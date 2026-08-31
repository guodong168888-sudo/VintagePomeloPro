#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static uint8_t sent[16], incoming[12];
static size_t sent_bytes, read_bytes, chunk = 64;
static unsigned writes, reads, interrupt_write, interrupt_read;
static int fail_write, fail_read, zero_write, zero_read;
static int stream_fd = -1;

static ssize_t fake_write(int fd, const void *buf, size_t n)
{
    if (fd == stream_fd) return write(fd, buf, n);
    assert(fd == 33);
    if (++writes == interrupt_write) { errno = EINTR; return -1; }
    if (fail_write) { errno = fail_write; return -1; }
    if (zero_write) return 0;
    if (n > chunk) n = chunk;
    assert(sent_bytes + n <= sizeof(sent));
    memcpy(sent + sent_bytes, buf, n); sent_bytes += n;
    return (ssize_t)n;
}
static ssize_t fake_read(int fd, void *buf, size_t n)
{
    if (fd == stream_fd) return read(fd, buf, n);
    assert(fd == 33 && sent_bytes == sizeof(sent));
    if (++reads == interrupt_read) { errno = EINTR; return -1; }
    if (fail_read) { errno = fail_read; return -1; }
    if (zero_read) return 0;
    if (n > chunk) n = chunk;
    assert(read_bytes + n <= sizeof(incoming));
    memcpy(buf, incoming + read_bytes, n); read_bytes += n;
    return (ssize_t)n;
}
#define WINEHUA_BUSY_WRITE fake_write
#define WINEHUA_BUSY_READ fake_read
#include "../smoke/winehua_vtest_busy_io.h"

static void reset(uint32_t result)
{
    uint32_t reply[] = {1, VCMD_RESOURCE_BUSY_WAIT, result};
    memcpy(incoming, reply, sizeof(reply));
    memset(sent, 0, sizeof(sent));
    sent_bytes = read_bytes = writes = reads = 0;
    interrupt_write = interrupt_read = fail_write = fail_read = zero_write = zero_read = 0;
    chunk = 64;
}
static void check_request(int handle, int flags)
{
    uint32_t expected[] = {2, VCMD_RESOURCE_BUSY_WAIT, (uint32_t)handle, (uint32_t)flags};
    assert(sent_bytes == sizeof(expected) && read_bytes == sizeof(incoming));
    assert(!memcmp(sent, expected, sizeof(expected)));
}
static void test_stream(void)
{
    int pair[2];
    assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, pair));
    alarm(5); /* A broken stream test must not hang the build. */
    const pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(pair[0]);
        uint32_t request[4], reply[] = {1, VCMD_RESOURCE_BUSY_WAIT, 1};
        /* Old Host can read header/body separately and fragment its reply. */
        for (unsigned i = 0; i < sizeof(request); ++i)
            assert(read(pair[1], (char *)request + i, 1) == 1);
        assert(request[0] == 2 && request[1] == VCMD_RESOURCE_BUSY_WAIT);
        assert(request[2] == 765 && request[3] == 1);
        for (unsigned i = 0; i < sizeof(reply); ++i)
            assert(write(pair[1], (char *)reply + i, 1) == 1);
        close(pair[1]);
        _exit(0);
    }
    close(pair[1]); stream_fd = pair[0];
    uint32_t answer = 77;
    assert(!winehua_vtest_busy_io(stream_fd, 765, 1, &answer) && answer == 1);
    close(stream_fd); stream_fd = -1;
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    alarm(0);
}
int main(void)
{
    uint32_t answer;
    for (unsigned busy = 0; busy <= 1; ++busy) {
        for (unsigned wait = 0; wait <= 1; ++wait) {
            reset(busy);
            answer = 77;
            assert(!winehua_vtest_busy_io(33, 123, wait, &answer) && answer == busy);
            check_request(123, wait);
            assert(writes == 1 && reads == 1);
        }
    }
    /* SOCK_STREAM can fragment anywhere, including within a DWORD. */
    for (unsigned size = 1; size <= 16; ++size) {
        reset(9); chunk = size; interrupt_write = interrupt_read = 2;
        assert(!winehua_vtest_busy_io(33, -1, 0x4001, &answer) && answer == 9);
        check_request(-1, 0x4001);
    }
    reset(0); interrupt_write = interrupt_read = 1;
    assert(!winehua_vtest_busy_io(33, 0, 0, &answer)); check_request(0, 0);
    reset(0); fail_write = EIO; answer = 77;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -EIO && answer == 77 && !reads);
    reset(0); zero_write = 1;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -EPIPE && !reads);
    reset(0); fail_read = EAGAIN;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -EAGAIN && answer == 77);
    reset(0); zero_read = 1;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -ECONNRESET && answer == 77);
    reset(0); incoming[0] = 2;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -EPROTO && answer == 77);
    reset(0); incoming[4] = 255;
    assert(winehua_vtest_busy_io(33, 1, 0, &answer) == -EPROTO && answer == 77);
    test_stream();
    puts("Busy I/O tests passed: wire parity, flags/results, fragmentation, EINTR, EOF and fail-closed errors");
    return 0;
}
