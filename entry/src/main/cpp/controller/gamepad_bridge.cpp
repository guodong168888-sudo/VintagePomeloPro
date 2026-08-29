#include "gamepad_bridge.h"

#include "controller_hub.h"
#include "gamepad_ipc_protocol.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#undef LOG_TAG
#define LOG_TAG "CtrlHub"
#include <hilog/log.h>

namespace winehua {
namespace controller {

GamepadBridge& GamepadBridge::Instance()
{
    static GamepadBridge bridge;
    return bridge;
}

std::string GamepadBridge::SocketPath() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return path_;
}

bool GamepadBridge::IsRunning() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return running_;
}

bool GamepadBridge::Start(const std::string& socketPath)
{
    std::string path = socketPath;
    if (path.empty()) {
        path = "/data/storage/el2/base/files/.wine/whgp.sock";
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (running_ && listenFd_ >= 0 && path_ == path) {
            OH_LOG_INFO(LOG_APP, "[WHGP] already listening on %{public}s", path.c_str());
            return true;
        }
    }
    Stop();

    unlink(path.c_str());
    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        OH_LOG_ERROR(LOG_APP, "[WHGP] socket failed errno=%{public}d", errno);
        return false;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (path.size() >= sizeof(addr.sun_path)) {
        close(fd);
        return false;
    }
    std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

    if (bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        OH_LOG_ERROR(LOG_APP, "[WHGP] bind %{public}s failed errno=%{public}d", path.c_str(), errno);
        close(fd);
        return false;
    }
    chmod(path.c_str(), 0666);
    if (listen(fd, 1) != 0) {
        close(fd);
        unlink(path.c_str());
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        listenFd_ = fd;
        path_ = path;
        running_ = true;
    }
    acceptThread_ = std::thread([this] { AcceptLoop(); });
    OH_LOG_INFO(LOG_APP, "[WHGP] listening on %{public}s", path.c_str());
    return true;
}

void GamepadBridge::Stop()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        running_ = false;
        if (listenFd_ >= 0) {
            shutdown(listenFd_, SHUT_RDWR);
            close(listenFd_);
            listenFd_ = -1;
        }
        if (clientFd_ >= 0) {
            close(clientFd_);
            clientFd_ = -1;
        }
        if (!path_.empty()) unlink(path_.c_str());
    }
    if (acceptThread_.joinable()) acceptThread_.join();
}

void GamepadBridge::AcceptLoop()
{
    while (true) {
        int listenFd = -1;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!running_) return;
            listenFd = listenFd_;
        }
        int client = accept4(listenFd, nullptr, nullptr, SOCK_CLOEXEC);
        if (client < 0 && (errno == ENOSYS || errno == EINVAL || errno == EOPNOTSUPP)) {
            client = accept(listenFd, nullptr, nullptr);
            if (client >= 0) fcntl(client, F_SETFD, FD_CLOEXEC);
        }
        if (client < 0) {
            if (errno == EINTR) continue;
            std::lock_guard<std::mutex> lock(mutex_);
            if (!running_) return;
            continue;
        }
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (clientFd_ >= 0) close(clientFd_);
            clientFd_ = client;
            OH_LOG_INFO(LOG_APP, "[WHGP] client connected fd=%{public}d", client);
        }
        // Push current slot0 state immediately.
        PublishState(0, ControllerHub::Instance().GetState(0));
    }
}

void GamepadBridge::WriteState(int fd, uint32_t slot, const LogicalGamepadState& state)
{
    whgp_header hdr{};
    hdr.magic = WHGP_MAGIC;
    hdr.version = WHGP_VERSION;
    hdr.msg_type = WHGP_MSG_STATE;
    hdr.slot = slot;
    hdr.payload_size = sizeof(whgp_state_v1);

    whgp_state_v1 body{};
    body.buttons = state.buttons;
    body.lx = state.lx;
    body.ly = state.ly;
    body.rx = state.rx;
    body.ry = state.ry;
    body.lt = state.lt;
    body.rt = state.rt;
    body.hat_x = state.hatX;
    body.hat_y = state.hatY;

    const ssize_t total = static_cast<ssize_t>(sizeof(hdr) + sizeof(body));
    iovec iov[2] = {
        {&hdr, sizeof(hdr)},
        {&body, sizeof(body)},
    };
    std::lock_guard<std::mutex> lock(mutex_);
    if (clientFd_ != fd) return;
    if (writev(fd, iov, 2) != total) {
        close(clientFd_);
        clientFd_ = -1;
    }
}

void GamepadBridge::PublishState(uint32_t slot, const LogicalGamepadState& state)
{
    int fd = -1;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        fd = clientFd_;
    }
    if (fd < 0) return;
    WriteState(fd, slot, state);
}

void GamepadBridge::AttachToHub()
{
    ControllerHub::Instance().SetEnabled(true);
    ControllerHub::Instance().SetStateListener(
        [this](uint32_t slot, const LogicalGamepadState& state) { PublishState(slot, state); });
}

}  // namespace controller
}  // namespace winehua
