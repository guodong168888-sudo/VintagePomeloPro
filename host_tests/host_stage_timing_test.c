#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <time.h>

static FILE *test_output;
static int test_clock(clockid_t id, struct timespec *value);
#define WINEHUA_STAGE_CLOCK test_clock
#define WINEHUA_STAGE_OUTPUT test_output
#include "../smoke/winehua_host_stage_timing.c"

static uint64_t wall_ns = 1000000, cpu_ns = 100000;
static int clock_error, callback_result, driver_result, destroys;
static uint32_t test_surface = 52;
static vtest_winehua_present_callback installed_callback;
static void *installed_userdata;
static struct vtest_context *real_current;

static int test_clock(clockid_t id, struct timespec *value)
{
    if (clock_error && id == CLOCK_THREAD_CPUTIME_ID)
        return -1;
    uint64_t ns = id == CLOCK_MONOTONIC ? wall_ns : cpu_ns;
    value->tv_sec = (time_t)(ns / 1000000000);
    value->tv_nsec = (long)(ns % 1000000000);
    return 0;
}
static void advance_us(uint64_t wall, uint64_t cpu)
{
    wall_ns += wall * 1000;
    cpu_ns += cpu * 1000;
}

int __real_vtest_create_context(struct vtest_input *input, int fd, uint32_t length,
                                struct vtest_context **out)
{
    (void)input;
    assert(fd == 7 && length == 4);
    *out = (struct vtest_context *)(uintptr_t)100;
    return 0;
}
void __real_vtest_set_current_context(struct vtest_context *ctx) { real_current = ctx; }
void __real_vtest_destroy_context(struct vtest_context *ctx)
{
    assert(ctx != NULL);
    ++destroys;
}
void __real_vtest_set_winehua_present_callback(vtest_winehua_present_callback cb, void *data)
{
    installed_callback = cb;
    installed_userdata = data;
}
static int callback(uint32_t tex, uint32_t width, uint32_t height, uint32_t format,
                    uint32_t flags, uint64_t drawable, uint32_t serial, uint32_t pid,
                    uint32_t surface, uint32_t present_flags, uint64_t *deadline, void *data)
{
    assert(tex == 9 && width == 800 && height == 600 && format == 1 && flags == 2);
    assert(drawable == 123 && serial == 777 && pid == 58561 && surface == test_surface);
    assert(present_flags == 3 && data == (void *)(uintptr_t)77);
    *deadline = 987654321;
    return callback_result;
}
int __real_vtest_winehua_present(uint32_t length)
{
    assert(length == 4);
    uint64_t deadline = 0;
    advance_us(100, 80);
    const int result = installed_callback(9, 800, 600, 1, 2, 123, 777, 58561,
        test_surface, 3, &deadline, installed_userdata);
    assert(deadline == 987654321);
    /* The protocol dispatcher can return success after a callback failure. */
    assert(result == callback_result);
    return 0;
}
int __real_virgl_renderer_submit_cmd(void *buffer, int id, int ndw)
{
    assert(buffer == (void *)(uintptr_t)8 && id == 3 && ndw == 256);
    advance_us(300, 250);
    return driver_result;
}
int __real_virgl_renderer_context_finish(uint32_t id)
{
    assert(id == 3);
    advance_us(5000, 300);
    return driver_result;
}
int __real_virgl_renderer_transfer_read_iov(uint32_t handle, uint32_t id,
    uint32_t level, uint32_t stride, uint32_t layer_stride, struct virgl_box *box,
    uint64_t offset, struct iovec *iov, int count)
{
    assert(handle == 1 && id == 3 && level == 2 && stride == 4 && layer_stride == 5);
    assert(box == NULL && offset == 6 && iov == NULL && count == 0);
    advance_us(700, 200);
    return driver_result;
}
int __real_virgl_renderer_transfer_write_iov(uint32_t handle, uint32_t id,
    int level, uint32_t stride, uint32_t layer_stride, struct virgl_box *box,
    uint64_t offset, struct iovec *iov, unsigned count)
{
    assert(handle == 1 && id == 3 && level == 2 && stride == 4 && layer_stride == 5);
    assert(box == NULL && offset == 6 && iov == NULL && count == 0);
    advance_us(800, 400);
    return driver_result;
}
#define REAL_RPC(name, call) \
    int __real_##name(uint32_t length) \
    { \
        assert(length == 4); \
        advance_us(100, 60); \
        return (call); \
    }
REAL_RPC(vtest_submit_cmd, __wrap_virgl_renderer_submit_cmd((void *)(uintptr_t)8, 3, 256))
REAL_RPC(vtest_submit_cmd2, __wrap_virgl_renderer_submit_cmd((void *)(uintptr_t)8, 3, 256))
REAL_RPC(vtest_resource_busy_wait, __wrap_virgl_renderer_context_finish(3))
REAL_RPC(vtest_transfer_put, __wrap_virgl_renderer_transfer_write_iov(1, 3, 2, 4, 5, NULL, 6, NULL, 0))
REAL_RPC(vtest_transfer_put2, __wrap_virgl_renderer_transfer_write_iov(1, 3, 2, 4, 5, NULL, 6, NULL, 0))
REAL_RPC(vtest_transfer_get, __wrap_virgl_renderer_transfer_read_iov(1, 3, 2, 4, 5, NULL, 6, NULL, 0))
REAL_RPC(vtest_transfer_get2, __wrap_virgl_renderer_transfer_read_iov(1, 3, 2, 4, 5, NULL, 6, NULL, 0))
REAL_RPC(vtest_sync_wait, driver_result)

int main(void)
{
    test_output = tmpfile();
    assert(test_output);
    /* Missing context never changes the original result. */
    driver_result = 17;
    assert(__wrap_vtest_resource_busy_wait(4) == 17);
    driver_result = 0;
    struct vtest_context *ctx = NULL;
    assert(__wrap_vtest_create_context(NULL, 7, 4, &ctx) == 0);
    __wrap_vtest_set_current_context(ctx);
    assert(real_current == ctx && current && !current->ready);
    __wrap_vtest_set_winehua_present_callback(callback, (void *)(uintptr_t)77);
    __wrap_vtest_winehua_present(4); /* establish identity; exclude startup */
    assert(current->ready && current->frames == 0);
    for (int i = 0; i < 120; ++i) {
        assert(__wrap_vtest_submit_cmd(4) == 0);
        assert(__wrap_vtest_resource_busy_wait(4) == 0);
        assert(__wrap_vtest_winehua_present(4) == 0);
        advance_us(20000, 0);
    }
    assert(current->frames == 0 && current->stages[DRIVER_FINISH].calls == 0);
    rewind(test_output);
    char line[4096];
    assert(fgets(line, sizeof(line), test_output));
    assert(strstr(line, "frames=120 presented=120 deferred=0 failed=0"));
    assert(strstr(line, "rpc_busy=120/612000/43200/5100/0/0/0"));
    assert(strstr(line, "driver_finish=120/600000/36000/5000/0/0/0"));
    assert(strstr(line, "driver_submit=120/36000/30000/300/0/0/30720"));
    assert(strstr(line, "nested=1 gpu_time=unmeasured"));
    assert(!fgets(line, sizeof(line), test_output)); /* bounded: no per-frame output */
    fseek(test_output, 0, SEEK_END);
    driver_result = -7;
    assert(__wrap_vtest_transfer_put2(4) == -7);
    assert(current->stages[DRIVER_PUT].errors == 1);
    assert(__wrap_vtest_transfer_get(4) == -7);
    driver_result = 0;
    clock_error = 1;
    assert(__wrap_vtest_submit_cmd2(4) == 0);
    assert(current->stages[DRIVER_SUBMIT].invalid == 1);
    assert(current->stages[DRIVER_SUBMIT].wall_ns == 0);
    clock_error = 0;
    callback_result = 1;
    __wrap_vtest_winehua_present(4);
    callback_result = -6;
    __wrap_vtest_winehua_present(4);
    assert(current->deferred == 1 && current->failed == 1);
    test_surface = 53;
    __wrap_vtest_winehua_present(4);
    assert(current->surface == 53 && current->frames == 0);
    assert(current->stages[DRIVER_PUT].calls == 0);
    uint64_t generation = current->generation;
    __wrap_vtest_destroy_context(ctx);
    assert(!current && destroys == 1);
    assert(__wrap_vtest_create_context(NULL, 7, 4, &ctx) == 0);
    __wrap_vtest_set_current_context(ctx);
    assert(current->generation > generation && !current->ready);
    /* Fixed capacity must not merge overflow into another context's statistics. */
    for (unsigned i = 1; i <= CONTEXT_LIMIT; ++i)
        __wrap_vtest_set_current_context((struct vtest_context *)(uintptr_t)i);
    assert(!current && overflow_reported);
    __wrap_vtest_set_current_context(ctx);
    assert(current && !current->ready);
    __wrap_vtest_set_winehua_present_callback(NULL, (void *)(uintptr_t)99);
    assert(!installed_callback && installed_userdata == (void *)(uintptr_t)99);
    fclose(test_output);
    puts("Host stage timing tests passed: nesting, identity, bounds, clocks, pass-through");
    return 0;
}
