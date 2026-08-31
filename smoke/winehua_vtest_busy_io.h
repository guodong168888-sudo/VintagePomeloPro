/* Isolated candidate: same vtest BUSY_WAIT transaction, fewer short I/O calls.
 * No cached idle result, fence removal, batching of transactions or new state.
 * The caller must fail closed on transport/protocol failure: never replay a
 * partially sent transaction on this stream or report a failed query as idle.
 */
#ifndef WINEHUA_VTEST_BUSY_IO_H
#define WINEHUA_VTEST_BUSY_IO_H
#include <errno.h>
#include <stdint.h>
#include <unistd.h>
#include "vtest/vtest_protocol.h"

#ifndef WINEHUA_BUSY_WRITE
#define WINEHUA_BUSY_WRITE write
#endif
#ifndef WINEHUA_BUSY_READ
#define WINEHUA_BUSY_READ read
#endif

static int winehua_vtest_busy_io(int fd, int handle, int flags, uint32_t *result)
{
    _Static_assert(VTEST_HDR_SIZE == 2 && VCMD_BUSY_WAIT_SIZE == 2,
                   "Re-audit packed I/O if the wire layout changes");
    uint32_t request[VTEST_HDR_SIZE + VCMD_BUSY_WAIT_SIZE];
    uint32_t response[VTEST_HDR_SIZE + 1];
    request[VTEST_CMD_LEN] = VCMD_BUSY_WAIT_SIZE;
    request[VTEST_CMD_ID] = VCMD_RESOURCE_BUSY_WAIT;
    request[VTEST_HDR_SIZE + VCMD_BUSY_WAIT_HANDLE] = (uint32_t)handle;
    request[VTEST_HDR_SIZE + VCMD_BUSY_WAIT_FLAGS] = (uint32_t)flags;
    size_t offset = 0;
    while (offset < sizeof(request)) {
        const ssize_t n = WINEHUA_BUSY_WRITE(fd, (const char *)request + offset,
                                             sizeof(request) - offset);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -errno;
        }
        if (!n) return -EPIPE;
        offset += (size_t)n;
    }
    offset = 0;
    while (offset < sizeof(response)) {
        const ssize_t n = WINEHUA_BUSY_READ(fd, (char *)response + offset,
                                            sizeof(response) - offset);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -errno;
        }
        if (!n) return -ECONNRESET;
        offset += (size_t)n;
    }
    if (response[VTEST_CMD_LEN] != 1 || response[VTEST_CMD_ID] != VCMD_RESOURCE_BUSY_WAIT)
        return -EPROTO;
    *result = response[VTEST_HDR_SIZE];
    return 0;
}
#endif
