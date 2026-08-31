/* Diagnostic-only --wrap bridge. No renderer implementation or protocol changes.
 * RPC times include body reads/replies; driver times are nested, NOT additive.
 * Wall minus thread CPU includes scheduling and all waits, not just GPU time.
 */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "vtest.h"
#include "virglrenderer.h"

#ifndef WINEHUA_STAGE_CLOCK
#define WINEHUA_STAGE_CLOCK clock_gettime
#endif

static FILE *open_stage_output(void)
{
#ifdef WINEHUA_STAGE_OUTPUT
    return WINEHUA_STAGE_OUTPUT;
#else
    /* OHOS does not forward this embedded server's stderr to its diagnostic
     * file. Use the existing Host log setting, not another launch environment.
     * Opening only per summary avoids a descriptor surviving server restarts. */
    const char *path = getenv("WINEHUA_VIRGL_LOG_PATH");
    FILE *output = path && path[0] == '/' ? fopen(path, "a") : NULL;
    return output ? output : stderr;
#endif
}

static void close_stage_output(FILE *output)
{
#ifdef WINEHUA_STAGE_OUTPUT
    (void)output;
#else
    if (output != stderr)
        fclose(output);
#endif
}

enum stage_id {
    RPC_SUBMIT, RPC_PUT, RPC_GET, RPC_BUSY, RPC_SYNC, RPC_PRESENT,
    DRIVER_SUBMIT, DRIVER_PUT, DRIVER_GET, DRIVER_FINISH, STAGE_COUNT
};
static const char *const stage_names[] = {
    "rpc_submit", "rpc_put", "rpc_get", "rpc_busy", "rpc_sync", "rpc_present",
    "driver_submit", "driver_put", "driver_get", "driver_finish"
};
struct stage_count {
    uint64_t calls, errors, invalid, wall_ns, cpu_ns, max_ns, words;
};
struct context_count {
    struct vtest_context *key;
    uint64_t generation, started_ns, frames, presented, deferred, failed;
    uint32_t pid, surface, width, height;
    int ready;
    struct stage_count stages[STAGE_COUNT];
};
struct stage_stamp { uint64_t wall, cpu; int active; };
#define CONTEXT_LIMIT 32
#define REPORT_FRAMES 120
static _Thread_local struct context_count contexts[CONTEXT_LIMIT];
static _Thread_local struct context_count *current;
static _Thread_local uint64_t next_generation;
static _Thread_local int overflow_reported;
static vtest_winehua_present_callback present_callback;
static void *present_userdata;

static uint64_t read_clock(clockid_t id)
{
    struct timespec value;
    if (WINEHUA_STAGE_CLOCK(id, &value) != 0)
        return 0;
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

static struct stage_stamp begin_stage(const struct context_count *ctx)
{
    struct stage_stamp stamp = {0, 0, 0};
    if (ctx && ctx->ready) {
        stamp.active = 1;
        stamp.wall = read_clock(CLOCK_MONOTONIC);
        stamp.cpu = read_clock(CLOCK_THREAD_CPUTIME_ID);
    }
    return stamp;
}

static void end_stage(struct context_count *ctx, enum stage_id id,
                      struct stage_stamp stamp, int result, uint64_t words)
{
    if (!ctx || !ctx->ready || !stamp.active)
        return;
    const uint64_t cpu = read_clock(CLOCK_THREAD_CPUTIME_ID);
    const uint64_t wall = read_clock(CLOCK_MONOTONIC);
    struct stage_count *count = &ctx->stages[id];
    ++count->calls;
    count->errors += result != 0;
    count->words += words;
    if (!stamp.wall || !stamp.cpu || !wall || !cpu || cpu < stamp.cpu || wall < stamp.wall) {
        ++count->invalid;
        return;
    }
    const uint64_t elapsed = wall - stamp.wall;
    count->wall_ns += elapsed;
    count->cpu_ns += cpu - stamp.cpu;
    if (elapsed > count->max_ns)
        count->max_ns = elapsed;
}

static void reset_window(struct context_count *ctx, uint64_t now)
{
    ctx->started_ns = now;
    ctx->frames = ctx->presented = ctx->deferred = ctx->failed = 0;
    memset(ctx->stages, 0, sizeof(ctx->stages));
}

static void report_window(struct context_count *ctx, const char *reason)
{
    const uint64_t now = read_clock(CLOCK_MONOTONIC);
    if (!ctx->ready || !ctx->frames)
        return;
    FILE *output = open_stage_output();
    fprintf(output,
        "[HOST-STAGE] v=1 scope=context generation=%" PRIu64
        " pid=%u surface=%u size=%ux%u reason=%s frames=%" PRIu64
        " presented=%" PRIu64 " deferred=%" PRIu64 " failed=%" PRIu64
        " interval_us=%" PRIu64 " end_ns=%" PRIu64
        " clock_valid=%d nested=1 gpu_time=unmeasured",
        ctx->generation, ctx->pid, ctx->surface, ctx->width, ctx->height,
        reason, ctx->frames, ctx->presented, ctx->deferred, ctx->failed,
        now >= ctx->started_ns ? (now - ctx->started_ns) / 1000 : 0,
        now,
        now != 0 && ctx->started_ns != 0 && now >= ctx->started_ns);
    for (unsigned i = 0; i < STAGE_COUNT; ++i) {
        const struct stage_count *c = &ctx->stages[i];
        fprintf(output,
            " %s=%" PRIu64 "/%" PRIu64 "/%" PRIu64 "/%" PRIu64
            "/%" PRIu64 "/%" PRIu64 "/%" PRIu64,
            stage_names[i], c->calls, c->wall_ns / 1000, c->cpu_ns / 1000,
            c->max_ns / 1000, c->errors, c->invalid, c->words);
    }
    fputc('\n', output);
    close_stage_output(output);
    /* Include logging overhead in the next interval, never hide it as a gain. */
    reset_window(ctx, now);
}

static struct context_count *find_context(struct vtest_context *key, int create)
{
    struct context_count *empty = NULL;
    if (!key)
        return NULL;
    for (unsigned i = 0; i < CONTEXT_LIMIT; ++i) {
        if (contexts[i].key == key)
            return &contexts[i];
        if (!contexts[i].key && !empty)
            empty = &contexts[i];
    }
    if (create && empty) {
        memset(empty, 0, sizeof(*empty));
        empty->key = key;
        empty->generation = ++next_generation;
        return empty;
    }
    if (create && !overflow_reported) {
        FILE *output = open_stage_output();
        fputs("[HOST-STAGE] context_limit=32 untracked=1\n", output);
        close_stage_output(output);
        overflow_reported = 1;
    }
    return NULL;
}

#define DECLARE_WRAP(name) \
    extern __typeof__(name) __real_##name; \
    extern __typeof__(name) __wrap_##name

DECLARE_WRAP(vtest_create_context);
int __wrap_vtest_create_context(struct vtest_input *input, int fd,
                                uint32_t length, struct vtest_context **out)
{
    const int result = __real_vtest_create_context(input, fd, length, out);
    if (result == 0 && out && *out) {
        struct context_count *ctx = find_context(*out, 1);
        if (ctx) {
            report_window(ctx, "context_reused");
            memset(ctx, 0, sizeof(*ctx));
            ctx->key = *out;
            ctx->generation = ++next_generation;
        }
    }
    return result;
}

DECLARE_WRAP(vtest_set_current_context);
void __wrap_vtest_set_current_context(struct vtest_context *ctx)
{
    __real_vtest_set_current_context(ctx);
    current = find_context(ctx, 1);
}

DECLARE_WRAP(vtest_destroy_context);
void __wrap_vtest_destroy_context(struct vtest_context *key)
{
    struct context_count *ctx = find_context(key, 0);
    if (ctx) {
        report_window(ctx, "destroy");
        if (current == ctx)
            current = NULL;
        memset(ctx, 0, sizeof(*ctx));
    }
    __real_vtest_destroy_context(key);
}

#define RPC_WRAP(name, stage) \
    DECLARE_WRAP(name); \
    int __wrap_##name(uint32_t length) \
    { \
        struct context_count *ctx = current; \
        const struct stage_stamp stamp = begin_stage(ctx); \
        const int result = __real_##name(length); \
        end_stage(ctx, stage, stamp, result, 0); \
        return result; \
    }
RPC_WRAP(vtest_submit_cmd, RPC_SUBMIT)
RPC_WRAP(vtest_submit_cmd2, RPC_SUBMIT)
RPC_WRAP(vtest_transfer_put, RPC_PUT)
RPC_WRAP(vtest_transfer_put2, RPC_PUT)
RPC_WRAP(vtest_transfer_get, RPC_GET)
RPC_WRAP(vtest_transfer_get2, RPC_GET)
RPC_WRAP(vtest_resource_busy_wait, RPC_BUSY)
RPC_WRAP(vtest_sync_wait, RPC_SYNC)

static int timing_present(uint32_t tex, uint32_t width, uint32_t height,
                          uint32_t format, uint32_t flags, uint64_t drawable,
                          uint32_t serial, uint32_t pid, uint32_t surface,
                          uint32_t present_flags, uint64_t *deadline, void *unused)
{
    (void)unused;
    const int result = present_callback(tex, width, height, format, flags,
        drawable, serial, pid, surface, present_flags, deadline, present_userdata);
    if (current) {
        if (!current->ready || current->pid != pid || current->surface != surface ||
            current->width != width || current->height != height) {
            report_window(current, "identity_changed");
            current->pid = pid;
            current->surface = surface;
            current->width = width;
            current->height = height;
            current->ready = 1;
            reset_window(current, read_clock(CLOCK_MONOTONIC));
        } else {
            ++current->frames;
            current->presented += result == 0;
            current->deferred += result > 0;
            current->failed += result < 0;
        }
    }
    return result;
}

DECLARE_WRAP(vtest_set_winehua_present_callback);
void __wrap_vtest_set_winehua_present_callback(vtest_winehua_present_callback cb,
                                               void *userdata)
{
    present_callback = cb;
    present_userdata = userdata;
    __real_vtest_set_winehua_present_callback(cb ? timing_present : NULL, cb ? NULL : userdata);
}

DECLARE_WRAP(vtest_winehua_present);
int __wrap_vtest_winehua_present(uint32_t length)
{
    struct context_count *ctx = current;
    const struct stage_stamp stamp = begin_stage(ctx);
    const int result = __real_vtest_winehua_present(length);
    /* Identity can change during the callback; discard that crossing sample. */
    if (ctx && stamp.wall >= ctx->started_ns)
        end_stage(ctx, RPC_PRESENT, stamp, result, 0);
    if (ctx && ctx->frames >= REPORT_FRAMES)
        report_window(ctx, "interval");
    return result;
}

DECLARE_WRAP(virgl_renderer_submit_cmd);
int __wrap_virgl_renderer_submit_cmd(void *buffer, int ctx_id, int ndw)
{
    struct context_count *ctx = current;
    const struct stage_stamp stamp = begin_stage(ctx);
    const int result = __real_virgl_renderer_submit_cmd(buffer, ctx_id, ndw);
    end_stage(ctx, DRIVER_SUBMIT, stamp, result, ndw > 0 ? (uint64_t)ndw : 0);
    return result;
}

DECLARE_WRAP(virgl_renderer_context_finish);
int __wrap_virgl_renderer_context_finish(uint32_t id)
{
    struct context_count *ctx = current;
    const struct stage_stamp stamp = begin_stage(ctx);
    const int result = __real_virgl_renderer_context_finish(id);
    end_stage(ctx, DRIVER_FINISH, stamp, result, 0);
    return result;
}

#define TRANSFER_WRAP(name, stage, level_type, count_type) \
    DECLARE_WRAP(name); \
    int __wrap_##name(uint32_t handle, uint32_t id, level_type level, \
        uint32_t stride, uint32_t layer_stride, struct virgl_box *box, \
        uint64_t offset, struct iovec *iov, count_type count) \
    { \
        struct context_count *ctx = current; \
        const struct stage_stamp stamp = begin_stage(ctx); \
        const int result = __real_##name(handle, id, level, stride, layer_stride, \
            box, offset, iov, count); \
        end_stage(ctx, stage, stamp, result, 0); \
        return result; \
    }
TRANSFER_WRAP(virgl_renderer_transfer_read_iov, DRIVER_GET, uint32_t, int)
TRANSFER_WRAP(virgl_renderer_transfer_write_iov, DRIVER_PUT, int, unsigned)
