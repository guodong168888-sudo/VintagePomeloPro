#define _GNU_SOURCE
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#define WINEHUA_GUEST_STAGE_TEST_TYPES
struct virgl_vtest_winsys { int sock_fd; };
struct pipe_box { int x, y, z, width, height, depth; };
typedef int GLint;
typedef int GLsizei;
typedef unsigned GLenum;
struct gl_context;
struct gl_pixelstore_attrib;
struct gl_texture_image;
void st_ReadPixels(struct gl_context *, GLint, GLint, GLsizei, GLsizei,
    GLenum, GLenum, const struct gl_pixelstore_attrib *, void *);
void st_GetTexSubImage(struct gl_context *, GLint, GLint, GLint, GLsizei, GLsizei,
    GLint, GLenum, GLenum, void *, struct gl_texture_image *);
#define VCMD_BUSY_WAIT_FLAG_WAIT 1
int virgl_vtest_connect(struct virgl_vtest_winsys *);
int virgl_vtest_busy_wait(struct virgl_vtest_winsys *, int, int);
int virgl_vtest_submit_cmd(struct virgl_vtest_winsys *, uint32_t *, uint32_t);
int virgl_vtest_send_transfer_get(struct virgl_vtest_winsys *, uint32_t, uint32_t,
    uint32_t, uint32_t, const struct pipe_box *, uint32_t, uint32_t);
int virgl_vtest_send_transfer_put(struct virgl_vtest_winsys *, uint32_t, uint32_t,
    uint32_t, uint32_t, const struct pipe_box *, uint32_t, uint32_t);
int virgl_vtest_send_winehua_present(struct virgl_vtest_winsys *, uint32_t, uint32_t,
    uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uintptr_t, uint32_t, uint32_t);
static FILE *test_output;
static int fake_clock(clockid_t, struct timespec *);
#define WINEHUA_GUEST_STAGE_CLOCK fake_clock
#define WINEHUA_GUEST_STAGE_OUTPUT test_output
#include "../smoke/winehua_guest_stage_timing.c"

static uint64_t fake_wall = 1000000, fake_cpu = 1000000;
static int clock_failure, present_result, other_result, busy_result = 1;
static struct virgl_vtest_winsys ws = {3};
static struct pipe_box full_box = {0, 0, 0, 800, 600, 1};
static uint32_t commands[45] = {
    [0] = VIRGL_CMD0(VIRGL_CCMD_DRAW_VBO, 0, 12),
    [13] = VIRGL_CMD0(VIRGL_CCMD_RESOURCE_INLINE_WRITE, 0, 15),
    [29] = VIRGL_CMD0(VIRGL_CCMD_TRANSFER3D, 0, 13),
    [43] = VIRGL_CMD0(VIRGL_CCMD_END_QUERY, 0, 1),
};
static int fake_clock(clockid_t id, struct timespec *t)
{
    if (clock_failure && id == CLOCK_THREAD_CPUTIME_ID) return -1;
    const uint64_t value = id == CLOCK_MONOTONIC ? fake_wall : fake_cpu;
    t->tv_sec = value / 1000000000; t->tv_nsec = value % 1000000000;
    return 0;
}
static void advance(uint64_t wall, uint64_t cpu)
{
    fake_wall += wall * 1000; fake_cpu += cpu * 1000;
}
int __real_virgl_vtest_connect(struct virgl_vtest_winsys *p)
{
    assert(p == &ws); p->sock_fd = 7; return other_result;
}
int __real_virgl_vtest_busy_wait(struct virgl_vtest_winsys *p, int handle, int flags)
{
    assert(p == &ws && handle == 123);
    assert(flags == 0 || flags == VCMD_BUSY_WAIT_FLAG_WAIT);
    advance(900, 20);
    return busy_result;
}
int __real_virgl_vtest_submit_cmd(struct virgl_vtest_winsys *p, uint32_t *buf, uint32_t length)
{
    assert(p == &ws && buf == commands && length == 45);
    advance(300, 150); return other_result;
}
#define REAL_TRANSFER(name) \
    int __real_##name(struct virgl_vtest_winsys *p, uint32_t h, uint32_t l, \
        uint32_t s, uint32_t ls, const struct pipe_box *b, uint32_t n, uint32_t off) \
    { \
        assert(p == &ws && h == 8 && l == 2 && s == 10 && ls == 11); \
        assert(b == &full_box && n == 1234 && off == 16); \
        advance(100, 40); return other_result; \
    }
REAL_TRANSFER(virgl_vtest_send_transfer_get)
REAL_TRANSFER(virgl_vtest_send_transfer_put)
void __real_st_ReadPixels(struct gl_context *ctx, GLint x, GLint y, GLsizei w, GLsizei h,
    GLenum format, GLenum type, const struct gl_pixelstore_attrib *pack, void *pixels)
{
    assert(!ctx && x == 1 && y == 2 && w == 800 && h == 600 && format == 0x1902 && type == 0x1403);
    assert(!pack && !pixels);
    __wrap_virgl_vtest_busy_wait(&ws, 123, 1);
    advance(200, 100);
}
void __real_st_GetTexSubImage(struct gl_context *ctx, GLint x, GLint y, GLint z,
    GLsizei w, GLsizei h, GLint depth, GLenum format, GLenum type,
    void *pixels, struct gl_texture_image *image)
{
    assert(!ctx && !x && !y && !z && w == 32 && h == 16 && depth == 1);
    assert(format == 0x1908 && type == 0x1401 && !pixels && !image);
    advance(400, 200);
}
int __real_virgl_vtest_send_winehua_present(struct virgl_vtest_winsys *p,
    uint32_t h, uint32_t l, uint32_t layer, uint32_t format, uint32_t bind,
    uint32_t w, uint32_t height, uintptr_t drawable, uint32_t serial, uint32_t surface)
{
    assert(p == &ws && h == 9 && l == 0 && layer == 0 && format == 54 && bind == 10);
    assert(w == 800 && height == 600 && drawable == 1234 && serial == 55 && surface);
    advance(200, 30); return present_result;
}
static int present_surface(uint32_t surface)
{
    return __wrap_virgl_vtest_send_winehua_present(&ws, 9, 0, 0, 54, 10, 800, 600, 1234, 55, surface);
}
int main(void)
{
    test_output = tmpfile(); assert(test_output);
    assert(__wrap_virgl_vtest_connect(&ws) == 0);
    struct guest_count *c = lookup(&ws);
    assert(c && !c->ready);
    assert(__wrap_virgl_vtest_submit_cmd(&ws, commands, 45) == 0);
    assert(c->words == 0); /* exclude startup before identity */
    present_surface(52);
    assert(c->ready && !c->frames);
    for (unsigned i = 0; i < 120; ++i) {
        assert(__wrap_virgl_vtest_submit_cmd(&ws, commands, 45) == 0);
        assert(__wrap_virgl_vtest_busy_wait(&ws, 123, 0) == 1);
        assert(__wrap_virgl_vtest_busy_wait(&ws, 123, 1) == 1);
        assert(__wrap_virgl_vtest_send_transfer_get(&ws, 8, 2, 10, 11, &full_box, 1234, 16) == 0);
        assert(present_surface(52) == 0);
        advance(20000, 100);
    }
    assert(!c->frames && !c->words);
    rewind(test_output);
    char line[8192]; assert(fgets(line, sizeof(line), test_output));
    assert(strstr(line, "frames=120 ok=120 failed=0"));
    assert(strstr(line, "words=5400 packets=480 draw_packets=120 inline_words=480"));
    assert(strstr(line, "transfer_packets=120 query_packets=120 malformed=0"));
    assert(strstr(line, "get_bytes=148080 get_full_size=120 get_max_box=800x600"));
    assert(strstr(line, "busy_check=120/108000/2400/900/120/0/0"));
    assert(strstr(line, "busy_wait=120/108000/2400/900/120/0/0"));
    assert(!fgets(line, sizeof(line), test_output));
    fseek(test_output, 0, SEEK_END);
    __wrap_st_ReadPixels(NULL, 1, 2, 800, 600, 0x1902, 0x1403, NULL, NULL);
    assert(c->time[READ_PIXELS].calls == 1 && c->time[READ_PIXELS].wall == 1100000);
    assert(c->time[BUSY_WAIT].wall == 900000 && c->read_spec[2] == 0x1902);
    __wrap_st_GetTexSubImage(NULL, 0, 0, 0, 32, 16, 1, 0x1908, 0x1401, NULL, NULL);
    assert(c->time[GET_TEXTURE].wall == 400000 && c->texture_spec[0] == 32);
    /* Classifier cannot read past a truncated buffer or treat payload as headers. */
    uint32_t truncated[] = {VIRGL_CMD0(VIRGL_CCMD_DRAW_VBO, 0, 65535)};
    packets(c, truncated, 1); assert(c->malformed == 1 && c->draw == 0);
    packets(c, NULL, 1); assert(c->malformed == 2);
    uint32_t short_inline = VIRGL_CMD0(VIRGL_CCMD_RESOURCE_INLINE_WRITE, 0, 0);
    packets(c, &short_inline, 1); assert(c->malformed == 3 && c->inline_words == 0);
    clock_failure = 1;
    __wrap_virgl_vtest_submit_cmd(&ws, commands, 45);
    assert(c->time[SUBMIT].invalid == 1 && !c->time[SUBMIT].wall);
    clock_failure = 0;
    busy_result = -9;
    assert(__wrap_virgl_vtest_busy_wait(&ws, 123, 0) == -9);
    assert(c->time[BUSY_CHECK].negative == 1);
    present_result = -6;
    assert(present_surface(52) == -6 && c->failed == 1);
    present_surface(53);
    assert(c->surface == 53 && !c->frames && !c->words);
    const uint64_t old_generation = c->generation;
    other_result = -2;
    assert(__wrap_virgl_vtest_connect(&ws) == -2);
    assert(c->generation > old_generation && !c->ready);
    assert(!lookup(NULL));
    struct virgl_vtest_winsys more[GUEST_CONTEXT_LIMIT] = {{0}};
    for (unsigned i = 0; i < GUEST_CONTEXT_LIMIT; ++i) lookup(&more[i]);
    assert(!lookup(&more[GUEST_CONTEXT_LIMIT - 1]) && overflow_reported);
    fclose(test_output);
    puts("Guest stage tests passed: protocol pass-through, packet bounds, clocks, identity, limits, summary");
    return 0;
}
