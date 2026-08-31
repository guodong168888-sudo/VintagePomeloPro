/* Diagnostic-only --wrap bridge for the cached x86_64 Guest Mesa library.
 * Counts encoded packets (not API draw calls); keeps all protocol calls intact.
 * Busy timing includes the complete Guest socket roundtrip, not just Host work.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dlfcn.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifndef WINEHUA_GUEST_STAGE_TEST_TYPES
#include "virgl_vtest_winsys.h"
struct gl_context;
struct gl_pixelstore_attrib;
struct gl_texture_image;
#include "main/formats.h"
#include "state_tracker/st_cb_readpixels.h"
#include "state_tracker/st_cb_texture.h"
#endif
#include "virtio-gpu/virgl_protocol.h"

#ifndef WINEHUA_GUEST_STAGE_CLOCK
#define WINEHUA_GUEST_STAGE_CLOCK clock_gettime
#endif
#define DECLARE_WRAP(name) \
    extern __typeof__(name) __real_##name; \
    extern __typeof__(name) __wrap_##name
#define GUEST_CONTEXT_LIMIT 8
#define GUEST_CALLER_LIMIT 8
enum metric_id { SUBMIT, BUSY_CHECK, BUSY_WAIT, GET, PUT, PRESENT, READ_PIXELS, GET_TEXTURE, METRIC_COUNT };
static const char *const metric_names[] = {
    "submit", "busy_check", "busy_wait", "get", "put", "present", "read_pixels", "get_texture"
};
struct metric { uint64_t calls, wall, cpu, max, positive, negative, invalid; };
struct stamp { uint64_t wall, cpu; };
struct caller_metric { uintptr_t address; struct metric time; };
struct guest_count {
    struct virgl_vtest_winsys *key;
    int fd, ready;
    uint32_t surface, width, height;
    uint64_t generation, started, frames, ok, failed;
    struct metric time[METRIC_COUNT];
    struct caller_metric callers[GUEST_CALLER_LIMIT];
    uint64_t caller_overflow;
    uint64_t words, packets, draw, inline_words, transfer, query, malformed;
    uint64_t get_bytes, get_full_size, get_max_width, get_max_height;
    uint32_t read_spec[4], texture_spec[4];
};
static _Thread_local struct guest_count counts[GUEST_CONTEXT_LIMIT];
static _Thread_local uint64_t generation;
static _Thread_local int overflow_reported;
static _Thread_local struct guest_count *active;

static uint64_t now_ns(clockid_t id)
{
    struct timespec t;
    return WINEHUA_GUEST_STAGE_CLOCK(id, &t) ? 0 :
        (uint64_t)t.tv_sec * UINT64_C(1000000000) + t.tv_nsec;
}
static struct stamp begin(void)
{
    const uint64_t wall = now_ns(CLOCK_MONOTONIC);
    const uint64_t cpu = now_ns(CLOCK_THREAD_CPUTIME_ID);
    return (struct stamp){wall, cpu};
}
static void add_metric(struct metric *m, struct stamp a, struct stamp b, int result)
{
    ++m->calls;
    m->positive += result > 0;
    m->negative += result < 0;
    if (!a.wall || !a.cpu || !b.wall || !b.cpu || b.wall < a.wall || b.cpu < a.cpu) {
        ++m->invalid;
        return;
    }
    const uint64_t elapsed = b.wall - a.wall;
    m->wall += elapsed;
    m->cpu += b.cpu - a.cpu;
    if (elapsed > m->max) m->max = elapsed;
}
static void print_metric(FILE *f, const char *name, const struct metric *m)
{
    fprintf(f, " %s=%" PRIu64 "/%" PRIu64 "/%" PRIu64 "/%" PRIu64
        "/%" PRIu64 "/%" PRIu64 "/%" PRIu64, name, m->calls,
        m->wall / 1000, m->cpu / 1000, m->max / 1000,
        m->positive, m->negative, m->invalid);
}
static void reset_window(struct guest_count *c, uint64_t now)
{
    struct guest_count next = {0};
    next.key = c->key; next.fd = c->fd; next.ready = c->ready;
    next.generation = c->generation;
    next.surface = c->surface; next.width = c->width; next.height = c->height;
    next.started = now;
    *c = next;
}
static void report(struct guest_count *c, const char *reason)
{
    const uint64_t now = now_ns(CLOCK_MONOTONIC);
    if (!c->ready || !c->frames) return;
#ifdef WINEHUA_GUEST_STAGE_OUTPUT
    FILE *f = WINEHUA_GUEST_STAGE_OUTPUT;
#else
    const char *path = getenv("WINEHUA_VTEST_FRONTBUFFER_LOG");
    FILE *f = path && path[0] == '/' ? fopen(path, "a") : NULL;
    if (!f) f = stderr;
#endif
    fprintf(f, "[GUEST-STAGE] v=2 scope=thread-winsys pid=%u tid=%u generation=%" PRIu64
        " surface=%u size=%ux%u reason=%s frames=%" PRIu64 " ok=%" PRIu64
        " failed=%" PRIu64 " interval_us=%" PRIu64 " end_ns=%" PRIu64
        " clock_valid=%d words=%" PRIu64 " packets=%" PRIu64
        " draw_packets=%" PRIu64 " inline_words=%" PRIu64
        " transfer_packets=%" PRIu64 " query_packets=%" PRIu64
        " malformed=%" PRIu64 " get_bytes=%" PRIu64 " get_full_size=%" PRIu64
        " get_max_box=%" PRIu64 "x%" PRIu64 " caller_overflow=%" PRIu64,
        (unsigned)getpid(), (unsigned)gettid(), c->generation, c->surface, c->width, c->height, reason,
        c->frames, c->ok, c->failed, now >= c->started ? (now - c->started) / 1000 : 0,
        now, now && c->started && now >= c->started, c->words, c->packets, c->draw,
        c->inline_words, c->transfer, c->query, c->malformed, c->get_bytes,
        c->get_full_size, c->get_max_width, c->get_max_height, c->caller_overflow);
    fprintf(f, " api_nested=1 read_spec=%ux%u/0x%x/0x%x texture_spec=%ux%u/0x%x/0x%x",
        c->read_spec[0], c->read_spec[1], c->read_spec[2], c->read_spec[3],
        c->texture_spec[0], c->texture_spec[1], c->texture_spec[2], c->texture_spec[3]);
    for (unsigned i = 0; i < METRIC_COUNT; ++i) print_metric(f, metric_names[i], &c->time[i]);
    for (unsigned i = 0; i < GUEST_CALLER_LIMIT; ++i) {
        if (!c->callers[i].address) continue;
        Dl_info info = {0};
        const int mapped = dladdr((void *)c->callers[i].address, &info) && info.dli_fbase;
        fprintf(f, " caller%u_%s=0x%" PRIxPTR, i, mapped ? "rva" : "unmapped",
            mapped ? c->callers[i].address - (uintptr_t)info.dli_fbase : 0);
        char name[24];
        snprintf(name, sizeof(name), "caller%u", i);
        print_metric(f, name, &c->callers[i].time);
    }
    fputc('\n', f);
#ifndef WINEHUA_GUEST_STAGE_OUTPUT
    if (f != stderr) fclose(f);
#endif
    reset_window(c, now); /* Log overhead remains in the next wall interval. */
}
static struct guest_count *lookup(struct virgl_vtest_winsys *key)
{
    struct guest_count *empty = NULL;
    active = NULL;
    if (!key) return NULL;
    for (unsigned i = 0; i < GUEST_CONTEXT_LIMIT; ++i) {
        if (counts[i].key == key) return active = &counts[i];
        if (!counts[i].key && !empty) empty = &counts[i];
    }
    if (!empty) {
        if (!overflow_reported) {
            fputs("[GUEST-STAGE] context_limit=8 untracked=1\n", stderr);
            overflow_reported = 1;
        }
        return NULL;
    }
    empty->key = key; empty->fd = key->sock_fd;
    empty->generation = ++generation;
    return active = empty;
}
static void packets(struct guest_count *c, const uint32_t *buf, uint32_t words)
{
    if (!c || !c->ready) return;
    c->words += words;
    if (!buf && words) { ++c->malformed; return; }
    for (uint32_t at = 0; at < words;) {
        const uint32_t size = (buf[at] >> 16) + 1;
        const unsigned op = buf[at] & 255;
        if (size > words - at) { ++c->malformed; return; }
        ++c->packets;
        if (op == VIRGL_CCMD_DRAW_VBO) ++c->draw;
        if (op == VIRGL_CCMD_RESOURCE_INLINE_WRITE) {
            if (size < VIRGL_RESOURCE_IW_DATA_START) ++c->malformed;
            else c->inline_words += size - VIRGL_RESOURCE_IW_DATA_START;
        }
        if (op == VIRGL_CCMD_TRANSFER3D || op == VIRGL_CCMD_COPY_TRANSFER3D) ++c->transfer;
        if (op == VIRGL_CCMD_BEGIN_QUERY || op == VIRGL_CCMD_END_QUERY ||
            op == VIRGL_CCMD_GET_QUERY_RESULT || op == VIRGL_CCMD_GET_QUERY_RESULT_QBO) ++c->query;
        if (op >= VIRGL_MAX_COMMANDS) ++c->malformed;
        at += size;
    }
}
static void record(struct guest_count *c, enum metric_id id, struct stamp a,
                   struct stamp b, int result)
{
    if (c && c->ready) add_metric(&c->time[id], a, b, result);
}

DECLARE_WRAP(st_ReadPixels);
void __wrap_st_ReadPixels(struct gl_context *ctx, GLint x, GLint y,
    GLsizei width, GLsizei height, GLenum format, GLenum type,
    const struct gl_pixelstore_attrib *pack, void *pixels)
{
    struct guest_count *c = active;
    const struct stamp a = begin();
    __real_st_ReadPixels(ctx, x, y, width, height, format, type, pack, pixels);
    record(c, READ_PIXELS, a, begin(), 0);
    if (c && c->ready) {
        c->read_spec[0] = width; c->read_spec[1] = height;
        c->read_spec[2] = format; c->read_spec[3] = type;
    }
}
DECLARE_WRAP(st_GetTexSubImage);
void __wrap_st_GetTexSubImage(struct gl_context *ctx, GLint x, GLint y, GLint z,
    GLsizei width, GLsizei height, GLint depth, GLenum format, GLenum type,
    void *pixels, struct gl_texture_image *image)
{
    struct guest_count *c = active;
    const struct stamp a = begin();
    __real_st_GetTexSubImage(ctx, x, y, z, width, height, depth, format, type, pixels, image);
    record(c, GET_TEXTURE, a, begin(), 0);
    if (c && c->ready) {
        c->texture_spec[0] = width; c->texture_spec[1] = height;
        c->texture_spec[2] = format; c->texture_spec[3] = type;
    }
}

DECLARE_WRAP(virgl_vtest_connect);
int __wrap_virgl_vtest_connect(struct virgl_vtest_winsys *vws)
{
    const int result = __real_virgl_vtest_connect(vws);
    struct guest_count *c = lookup(vws);
    if (c) {
        report(c, "reconnect");
        memset(c, 0, sizeof(*c));
        c->key = vws; c->fd = vws->sock_fd; c->generation = ++generation;
    }
    return result;
}
DECLARE_WRAP(virgl_vtest_busy_wait);
int __wrap_virgl_vtest_busy_wait(struct virgl_vtest_winsys *vws, int handle, int flags)
{
    struct guest_count *c = lookup(vws);
    const uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    struct stamp a = begin();
    const int result = __real_virgl_vtest_busy_wait(vws, handle, flags);
    struct stamp b = begin();
    record(c, flags & VCMD_BUSY_WAIT_FLAG_WAIT ? BUSY_WAIT : BUSY_CHECK, a, b, result);
    if (c && c->ready) {
        unsigned i;
        for (i = 0; i < GUEST_CALLER_LIMIT; ++i) {
            if (!c->callers[i].address || c->callers[i].address == caller) {
                c->callers[i].address = caller;
                add_metric(&c->callers[i].time, a, b, result);
                break;
            }
        }
        if (i == GUEST_CALLER_LIMIT) ++c->caller_overflow;
    }
    return result;
}
DECLARE_WRAP(virgl_vtest_submit_cmd);
int __wrap_virgl_vtest_submit_cmd(struct virgl_vtest_winsys *vws, uint32_t *buf, uint32_t length)
{
    struct guest_count *c = lookup(vws);
    packets(c, buf, length);
    struct stamp a = begin();
    const int result = __real_virgl_vtest_submit_cmd(vws, buf, length);
    record(c, SUBMIT, a, begin(), result);
    return result;
}
#define TRANSFER_WRAP(name, id) \
    DECLARE_WRAP(name); \
    int __wrap_##name(struct virgl_vtest_winsys *vws, uint32_t handle, uint32_t level, \
        uint32_t stride, uint32_t layer_stride, const struct pipe_box *box, \
        uint32_t size, uint32_t offset) \
    { \
        struct guest_count *c = lookup(vws); \
        struct stamp a = begin(); \
        const int result = __real_##name(vws, handle, level, stride, layer_stride, box, size, offset); \
        record(c, id, a, begin(), result); \
        if (id == GET && c && c->ready) { \
            c->get_bytes += size; \
            if (box && box->width > 0 && box->height > 0) { \
                if ((uint32_t)box->width > c->get_max_width) c->get_max_width = box->width; \
                if ((uint32_t)box->height > c->get_max_height) c->get_max_height = box->height; \
                c->get_full_size += (uint32_t)box->width == c->width && \
                    (uint32_t)box->height == c->height && box->depth == 1; \
            } \
        } \
        return result; \
    }
TRANSFER_WRAP(virgl_vtest_send_transfer_get, GET)
TRANSFER_WRAP(virgl_vtest_send_transfer_put, PUT)
DECLARE_WRAP(virgl_vtest_send_winehua_present);
int __wrap_virgl_vtest_send_winehua_present(struct virgl_vtest_winsys *vws,
    uint32_t handle, uint32_t level, uint32_t layer, uint32_t format, uint32_t bind,
    uint32_t width, uint32_t height, uintptr_t drawable, uint32_t serial, uint32_t surface)
{
    struct guest_count *c = lookup(vws);
    struct stamp a = begin();
    const int result = __real_virgl_vtest_send_winehua_present(vws, handle, level, layer,
        format, bind, width, height, drawable, serial, surface);
    struct stamp b = begin();
    if (!c) return result;
    if (!c->ready || c->surface != surface || c->width != width || c->height != height) {
        report(c, "identity_changed");
        c->ready = 1; c->surface = surface; c->width = width; c->height = height;
        reset_window(c, b.wall);
        return result;
    }
    record(c, PRESENT, a, b, result);
    ++c->frames; c->ok += result == 0; c->failed += result != 0;
    if (c->frames >= 120) report(c, "interval");
    return result;
}
