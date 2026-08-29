#pragma once

#include "controller_types.h"

#include <mutex>
#include <string>
#include <thread>

namespace winehua {
namespace controller {

// AF_UNIX WHGP server. Hub state listener pushes snapshots to connected winebus clients.
class GamepadBridge {
public:
    static GamepadBridge& Instance();

    bool Start(const std::string& socketPath);
    void Stop();
    bool IsRunning() const;
    std::string SocketPath() const;
    void PublishState(uint32_t slot, const LogicalGamepadState& state);
    void AttachToHub();

private:
    GamepadBridge() = default;
    void AcceptLoop();
    void WriteState(int fd, uint32_t slot, const LogicalGamepadState& state);

    mutable std::mutex mutex_;
    std::string path_;
    int listenFd_ = -1;
    int clientFd_ = -1;
    bool running_ = false;
    std::thread acceptThread_;
};

}  // namespace controller
}  // namespace winehua
