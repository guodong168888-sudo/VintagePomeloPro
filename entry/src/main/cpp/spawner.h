#ifndef WINE_SPAWNER_H
#define WINE_SPAWNER_H

/**
 * spawner.h — SpawnRequest/Spawner: 进程启动的意图与机制分离 (重构第 4 步)
 *
 * 调用方只声明 "启动什么 + 带什么 env 增量"; 机制细节由 kind 推导:
 *   - 路由: Wineserver/Wineboot → NCP 直启; 其余 → broker SPAWN (SpawnViaBroker)
 *   - 入口符号: NCP 路线 WineserverMain/Main
 *   - token 布局: homeDir 前缀 (NCP) / __winehua_desktop__ / guest|host elf 标记 /
 *     x86_64 的 wine 加载器前缀
 *   - 会话权威: NCP 路线尾部追加 WINEPREFIX=<session> (与 broker 服务端尾部
 *     追加同级语义); Wineserver 在 smoke prefix 下自动带退出遥测
 *
 * 第 5 步 (wineserver/wineboot 也走 broker、删 NCP 直启) 不在本轮。
 *
 * 刻意不在请求里的: homeDir/prefixDir (会话单例, ConfigureSession 设置;
 * broker 路线由 broker 服务端权威), fd (broker 自动挂 audio bootstrap)。
 * @engine/wineserver 等进程登记留在调用方拿到 pid 之后。
 */

#include <string>
#include <vector>
#include <sys/types.h>

namespace winehua {

enum class SpawnKind {
    Wineserver,    // NCP WineserverMain: argv 固定 "wineserver -f -p"
    Wineboot,      // NCP Main: argv 固定 "wineboot --init"
    DesktopShell,  // broker Main: explorer + argv (桌面 shell)
    WineExe,       // broker Main: argv = [exePath, args...]
    GuestElf,      // broker Main: __winehua_guest_elf__ + argv
    HostElf,       // broker Main: __winehua_host_elf__ + argv
};

struct SpawnRequest {
    SpawnKind kind;
    std::vector<std::string> argv;
    std::vector<std::string> env;
    bool desktopSurface = false;
    std::string binDir;
};

class Spawner {
public:
    static void ConfigureSession(std::string homeDir, std::string binDir, std::string prefixDir);
    static pid_t Spawn(const SpawnRequest& req);
};

} // namespace winehua

#endif // WINE_SPAWNER_H
