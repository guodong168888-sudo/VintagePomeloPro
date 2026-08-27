#include "wine_launch.h"
#include "wine_process.h"
#include "wine_env.h"
#include "env_profiles.h"
#include "spawner.h"
#include "wine_constants.h"
#include "wayland_server.h"
#include "audio_ipc_protocol.h"
#include "graphics_broker.h"
#include "phone_adapter/phone_adapter.h"

#include <unistd.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cerrno>
#include <string>
#include <strings.h>
#include <thread>
#include <vector>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000
#define LOG_TAG "WL_NAPI"
#include <hilog/log.h>

#include "broker.h"
#include "wait_utils.h"

// NCP 直启细节已收口到 spawner.cpp (重构第 4 步), 本文件不再直接触碰
// AbilityKit NCP 接口。

// -- prefix 初始化检测辅助函数 --
static bool FileHasData(const char* path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0;
}

static bool DirExists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

bool IsWinePrefixInitialized(const std::string& prefixDir) {
    const std::string prefix = prefixDir.empty() ? WINE_PREFIX : prefixDir;
    return FileHasData((prefix + "/system.reg").c_str()) &&
           FileHasData((prefix + "/user.reg").c_str()) &&
           DirExists((prefix + "/drive_c/windows/system32").c_str()) &&
           DirExists((prefix + "/drive_c/windows/temp").c_str()) &&
           DirExists((prefix + "/drive_c/users").c_str());
}

bool IsWinePrefixInitialized() {
    return IsWinePrefixInitialized(WINE_PREFIX);
}

// fork 模式下子进程退出先变僵尸、/proc/<pid> 不消失（NCP 模式由 appspawn 立即 reap）。
// 存活检测必须识别僵尸，否则 wineboot 等待会白等到 kWinebootHangMs 超时。
//
// 后端分流: fork 后端 (手机) /proc 可靠 → 保留 /proc/<pid>/stat 僵尸检测;
// NCP 后端 (平板/2in1/PC) appspawn 子进程可能不在主进程 /proc 可见范围
// (命名空间/hidepid/SELinux), fopen 必失败 → 改查进程注册表 (running 状态
// 由系统 NCP 退出回调维护), 避免把活着的 explorer/wineserver 误判为死亡
// 导致 "explorer died before registering desktop root" 启动失败。
static bool IsProcessAliveNotZombie(pid_t pid) {
    if (!PhoneAdapter_IsPhoneMode()) {
        return IsProcessRegisteredRunning(pid);
    }
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/stat", (int)pid);
    FILE* f = fopen(path, "r");
    if (!f) {
        // 诊断 (限频): fork 后端 /proc 读不到是异常 — ENOENT=进程真退出或
        // 命名空间不可见; EPERM/EACCES=进程在但权限/沙箱禁止读取。
        static uint32_t sOpenFailLogN = 0;
        if (++sOpenFailLogN <= 5) {
            OH_LOG_WARN(LOG_APP, "[Launch-Async] /proc/%d/stat open failed errno=%d (%s)",
                        (int)pid, errno, strerror(errno));
        }
        return false;                       // /proc 消失 = 已退出
    }
    char buf[512];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    char* rp = strrchr(buf, ')');               // state 字段在最后一个 ')' 之后
    return !(rp && rp[2] == 'Z');               // 僵尸 = 已退出
}

// -- WoW64 syswow64 预填充辅助 --
static bool EnsureDir(const std::string& path, mode_t mode)
{
    if (DirExists(path.c_str())) return true;
    if (mkdir(path.c_str(), mode) == 0 || errno == EEXIST) return DirExists(path.c_str());
    OH_LOG_ERROR(LOG_APP, "[Launch-Async] mkdir %{public}s failed: %{public}s",
                 path.c_str(), strerror(errno));
    return false;
}

static bool EnsureDirRecursive(const std::string& path, mode_t mode)
{
    if (path.empty() || path == "/") return true;
    if (DirExists(path.c_str())) return true;

    size_t slash = path.find_last_of('/');
    if (slash != std::string::npos && slash > 0)
    {
        if (!EnsureDirRecursive(path.substr(0, slash), mode)) return false;
    }
    return EnsureDir(path, mode);
}

static bool EnsureExternalPePrefixSkeleton(const std::string& prefixDir)
{
    // The external-PE runtime resolves 64-bit Windows binaries from
    // x86_64-windows instead of copying them into drive_c.  wineboot therefore
    // does not necessarily materialize directories which Windows services and
    // diagnostics still use as working/output directories.
    static const char* const suffixes[] = {
        "/drive_c/windows/system32",
        "/drive_c/windows/system32/drivers",
        "/drive_c/windows/system32/spool",
        "/drive_c/windows/system32/tasks",
        "/drive_c/windows/temp",
    };

    bool ok = true;
    for (const char* suffix : suffixes)
        ok = EnsureDirRecursive(prefixDir + suffix, 0777) && ok;

    OH_LOG_INFO(LOG_APP, "[Launch-Async] external-PE prefix skeleton %{public}s",
                ok ? "ready" : "failed");
    return ok;
}

static bool HasRuntimeFileExtension(const char* name)
{
    const char* dot = strrchr(name, '.');
    if (!dot) return false;
    return !strcasecmp(dot, ".dll") ||
           !strcasecmp(dot, ".drv") ||
           !strcasecmp(dot, ".sys") ||
           !strcasecmp(dot, ".exe");
}

static bool CopyFileIfNeeded(const std::string& src, const std::string& dst)
{
    struct stat srcSt;
    struct stat dstSt;
    if (stat(src.c_str(), &srcSt) != 0 || !S_ISREG(srcSt.st_mode)) return false;
    if (stat(dst.c_str(), &dstSt) == 0 && S_ISREG(dstSt.st_mode) &&
        dstSt.st_size == srcSt.st_size && dstSt.st_mtime >= srcSt.st_mtime)
        return true;

    int inFd = open(src.c_str(), O_RDONLY);
    if (inFd < 0)
    {
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] open src %{public}s failed: %{public}s",
                     src.c_str(), strerror(errno));
        return false;
    }

    std::string temporaryTemplate = dst + ".winehua.tmp.XXXXXX";
    std::vector<char> temporary(temporaryTemplate.begin(), temporaryTemplate.end());
    temporary.push_back('\0');
    int outFd = mkstemp(temporary.data());
    if (outFd < 0)
    {
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] create temporary for %{public}s failed: %{public}s",
                     dst.c_str(), strerror(errno));
        close(inFd);
        return false;
    }
    fchmod(outFd, 0666);

    char buffer[64 * 1024];
    bool ok = true;
    ssize_t n;
    while ((n = read(inFd, buffer, sizeof(buffer))) > 0)
    {
        char* p = buffer;
        ssize_t remaining = n;
        while (remaining > 0)
        {
            ssize_t w = write(outFd, p, remaining);
            if (w < 0)
            {
                ok = false;
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] write dst %{public}s failed: %{public}s",
                             dst.c_str(), strerror(errno));
                break;
            }
            p += w;
            remaining -= w;
        }
        if (!ok) break;
    }
    if (n < 0)
    {
        ok = false;
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] read src %{public}s failed: %{public}s",
                     src.c_str(), strerror(errno));
    }

    if (ok && fsync(outFd) != 0)
    {
        ok = false;
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] fsync dst %{public}s failed: %{public}s",
                     dst.c_str(), strerror(errno));
    }
    close(outFd);
    close(inFd);
    if (ok && rename(temporary.data(), dst.c_str()) != 0)
    {
        ok = false;
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] replace dst %{public}s failed: %{public}s",
                     dst.c_str(), strerror(errno));
    }
    if (!ok) unlink(temporary.data());
    return ok;
}

static bool EnsureWow64Files(const std::string& binDir, const std::string& prefixDir)
{
    const std::string srcDir = binDir + "/i386-windows";
    const std::string dstDir = prefixDir + "/drive_c/windows/syswow64";

    DIR* src = opendir(srcDir.c_str());
    if (!src)
    {
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] wow64 source missing %{public}s: %{public}s",
                     srcDir.c_str(), strerror(errno));
        return false;
    }
    if (!EnsureDirRecursive(dstDir, 0777))
    {
        closedir(src);
        return false;
    }

    int total = 0;
    int copied = 0;
    int failed = 0;
    while (dirent* entry = readdir(src))
    {
        if (entry->d_name[0] == '.' || !HasRuntimeFileExtension(entry->d_name)) continue;
        total++;
        std::string srcPath = srcDir + "/" + entry->d_name;
        std::string dstPath = dstDir + "/" + entry->d_name;
        if (CopyFileIfNeeded(srcPath, dstPath)) copied++;
        else failed++;
    }
    closedir(src);

    OH_LOG_INFO(LOG_APP, "[Launch-Async] wow64 syswow64 total=%{public}d ok=%{public}d failed=%{public}d",
                total, copied, failed);
    return total > 0 && failed == 0;
}
static bool IsWineserverSocketReady(const std::string& prefix) {
    char sockDir[512];
    snprintf(sockDir, sizeof(sockDir), "%s/.wineserver", prefix.c_str());
    DIR* d = opendir(sockDir);
    if (!d) return false;
    bool found = false;
    struct dirent* de;
    while ((de = readdir(d))) {
        if (de->d_name[0] == '.') continue;
        char sockPath[1024];
        snprintf(sockPath, sizeof(sockPath), "%s/%s/socket", sockDir, de->d_name);
        struct stat st;
        if (stat(sockPath, &st) == 0 && S_ISSOCK(st.st_mode)) { found = true; break; }
    }
    closedir(d);
    return found;
}

static void PrepareDesktopSessionGraphicsEnv(const LaunchParams& params)
{
    OH_LOG_INFO(LOG_APP, "[Launch-Async] preparing graphics env for child processes");
    auto& gb = winehua::GraphicsBroker::GetInstance();
    gb.SetWineRuntimeBinaryDir(params.winehuaBin);
    gb.SetRequestedBackend(winehua::GraphicsBackend::Virgl);
    gb.SetVulkanPresentMode(params.d3dBackend.rfind("dxvk_", 0) == 0);
    gb.EnsureStarted(params.sockDir);

    winehua::GraphicsBackendState state = gb.GetState();
    if (state.active != winehua::GraphicsBackend::Virgl) {
        OH_LOG_ERROR(LOG_APP,
                     "[Launch-Async] GL env unavailable: requested=%{public}s active=%{public}s error=%{public}s",
                     winehua::GraphicsBroker::BackendName(state.requested),
                     winehua::GraphicsBroker::BackendName(state.active),
                     state.lastError.c_str());
        return;
    }

    /* env 组装统一走 BuildSessionEnv (env_profiles.cpp); 此处只确保
     * graphics broker 就绪并记录状态。 */
    LogGraphicsBackendStateForLaunch("DesktopSession");
}

static winehua::SessionEnvPolicy SessionPolicyFromLaunch(const LaunchParams& p, int audioFd)
{
    winehua::SessionEnvPolicy s;
    s.sockDir = p.sockDir;
    s.sockName = p.sockName;
    s.libPath = p.libPath;
    s.binDir = p.winehuaBin;
    s.homeDir = p.homeDir;
    s.prefixDir = p.prefixDir;
    s.audioBootstrapFd = audioFd;
    s.d3dBackend = p.d3dBackend;
    s.compatEnvStr = p.compatEnvStr;
    s.automationMode = p.automationMode;
    return s;
}

// -- 引擎阶段/失败事件 (单一协调者 -> ArkTS 观察者) --
// 事件通道复用 gStateTsfn 单字符串; 语法:
//   phase:<name>    进入某个初始化阶段 (graphics/wineserver/wineboot/explorer/ready)
//   fail:<reason>   致命失败并带结构化原因
//   wine-ready      终态成功 (保留)
//   <pid>:wine-*    进程级事件 (游戏启动结果, 保留)
static void EmitEngineEvent(const char* event)
{
    if (gStateTsfn)
        napi_call_threadsafe_function(gStateTsfn, strdup(event), napi_tsfn_blocking);
}

static void EmitEnginePhase(const char* phase)
{
    std::string event = "phase:";
    event += phase;
    EmitEngineEvent(event.c_str());
}

static void EmitEngineFail(const char* reason)
{
    std::string event = "fail:";
    event += reason;
    EmitEngineEvent(event.c_str());
}

static bool LaunchPadMode(LaunchParams* p, int audioBootstrapFd) {
    winehua::Spawner::ConfigureSession(p->homeDir, p->winehuaBin, p->prefixDir);

    // Prefix registry and user data survive runtime upgrades, while the
    // syswow64 PE files are managed copies. Validate them before wineserver
    // starts so an interrupted prior refresh cannot leave a zero-length DLL.
    if (!EnsureExternalPePrefixSkeleton(p->prefixDir) ||
        !EnsureWow64Files(p->winehuaBin, p->prefixDir)) {
        OH_LOG_ERROR(LOG_APP, "[Launch-Async] external-PE prefix preparation failed");
        EmitEngineFail("prefix-prepare");
        return false;
    }

    // 图形栈必须是真实前置条件：VirGL receiver 未激活时继续启动只会得到一个
    // 无法渲染的桌面/窗口。直接报告具体原因，而不是在 SHM 回退里带病运行。
    // EnsureStarted 已同步等待 vtest socket（上限 4s），因此 GetState 的结果
    // 就是当前真实条件：Virgl=就绪，Shm+lastError=具体缺失项。
    {
        auto& gb = winehua::GraphicsBroker::GetInstance();
        const winehua::GraphicsBackendState gfxState = gb.GetState();
        if (gfxState.active != winehua::GraphicsBackend::Virgl) {
            OH_LOG_ERROR(LOG_APP,
                         "[Launch-Async] graphics backend unavailable: active=%{public}s error=%{public}s",
                         winehua::GraphicsBroker::BackendName(gfxState.active),
                         gfxState.lastError.c_str());
            EmitEngineFail("graphics-unavailable");
            return false;
        }
    }

    // -- wineserver via NCP (Spawner kind 推导入口符号与 token) --
    pid_t wsChildPid = -1;
    {
        winehua::SpawnRequest wsReq{winehua::SpawnKind::Wineserver};
#ifdef __aarch64__
        winehua::AppendCompatEnvLines(wsReq.env, p->compatEnvStr, p->automationMode);
#endif
        wsChildPid = winehua::Spawner::Spawn(wsReq);
        if (wsChildPid <= 0) {
            OH_LOG_ERROR(LOG_APP, "[Launch-Async] wineserver spawn FAILED");
            EmitEngineFail("wineserver-spawn");
            return false;
        }
        OH_LOG_INFO(LOG_APP, "[Launch-Async] wineserver pid=%{public}d (via NCP)", (int)wsChildPid);
        // 登记引擎核心进程: 用户应用全部退出/被杀后注册表仍非空,
        // 避免 handleNativeState('exited') 误判引擎 STOPPED 而拆掉桌面连接。
        AddProcess(wsChildPid, "@engine/wineserver", -1, "@engine/wineserver");
        if (!WaitFor("wineserver socket", [p]() { return IsWineserverSocketReady(p->prefixDir); }, 5000, 100)) {
            OH_LOG_WARN(LOG_APP, "[Launch-Async] wineserver socket not detected, "
                        "wineboot will recover via server_connect retry+start_server");
        }
    }

    EmitEnginePhase("wineboot");

    gBrokerHomeDir = p->homeDir;
    StartBrokerServer();
    setenv("PROCESSBROKER", WINE_BROKER_SOCKET, 1);

    // -- wineboot --init --
    const std::string initMarker = p->prefixDir + "/.winehua-init-in-progress";
    bool prefixReady = IsWinePrefixInitialized(p->prefixDir)
        && access(initMarker.c_str(), F_OK) != 0;

    if (!prefixReady) {
        OH_LOG_INFO(LOG_APP, "[Launch-Async] prefix not initialized, preparing WoW64 and running wineboot --init...");
        auto* ws = WaylandServer::GetInstance();
        ws->SetDesktopRootRecognitionEnabled(false);
        // wineboot creates shell-owned helper windows while initializing a fresh
        // prefix.  Keep those helpers on the desktop path even when the smoke
        // suite itself uses managed windows; otherwise the first clean-prefix
        // session can leave Wayland/audio/graphics services half initialized.
        const bool desktopSurface = ws->IsDesktopMode() || p->automationMode;
        // 注意: wineboot --init 只需要初始化 prefix, 不传完整环境变量以节省 entryParams 长度
        // (argv/兼容档位由 Spawner 按 kind 注入; aarch64 归一为不带 wine 加载器
        // token — Main 的 box64 路径自注 binDir/wine ELF)
        // 首启 wineboot 失败允许从标记重跑一次 (慢设备/瞬时崩溃), 避免一次失败
        // 就把整条启动链打回; 只有重试耗尽才发 fail:。
        constexpr int kMaxWinebootAttempts = 2;
        constexpr int kWinebootRetryBackoffMs = 2000;
        bool winebootOk = false;
        int winebootWaitMs = 0;
        for (int attempt = 1; attempt <= kMaxWinebootAttempts && !winebootOk; attempt++) {
            if (attempt > 1) {
                OH_LOG_WARN(LOG_APP, "[Launch-Async] retrying wineboot --init (attempt %d/%d)",
                            attempt, kMaxWinebootAttempts);
                usleep(kWinebootRetryBackoffMs * 1000);
            }
            if (FILE* marker = fopen(initMarker.c_str(), "w")) {
                fputs("wineboot\n", marker);
                fclose(marker);
            } else {
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] cannot create prefix init marker: %{public}s",
                             initMarker.c_str());
                EmitEngineFail("wineboot-failed");
                return false;
            }
            winehua::SpawnRequest wbReq{winehua::SpawnKind::Wineboot};
            wbReq.desktopSurface = desktopSurface;
#ifdef __aarch64__
            winehua::AppendCompatEnvLines(wbReq.env, p->compatEnvStr, p->automationMode);
#endif
            const pid_t childPid = winehua::Spawner::Spawn(wbReq);
            if (childPid <= 0) {
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] wineboot spawn FAILED (attempt %{public}d)",
                             attempt);
                if (attempt >= kMaxWinebootAttempts) {
                    EmitEngineFail("wineboot-spawn");
                    return false;
                }
                continue;
            }
            OH_LOG_INFO(LOG_APP, "[Launch-Async] wineboot started, pid=%{public}d (attempt %{public}d)",
                        childPid, attempt);
            // 登记 wineboot 到进程注册表: NCP 模式下存活判定依赖注册表
            // (IsProcessRegisteredRunning)。未登记会使下方 wineboot 等待循环
            // 0ms 立即结束 (done 0 ms) → ready 提前发出 → PC 首启时 Wine 服务
            // 栈尚未就绪, 应用作为首个 GUI 进程 attach VirGL surface 失败 → 白屏。
            // wineboot 退出时 NCP 退出回调 RemoveProcess 置 running=false, 等待自然结束。
            AddProcess(childPid, "@engine/wineboot", -1, "@engine/wineboot");
        /* 首次初始化 (wine.inf 的 PreInstall/DefaultInstall/Wow64Install + 可选 Mono)
         * 耗时与设备性能强相关, 模拟器上可超过 30s — 固定死线会把仍在正常初始化的
         * wineboot 误判为失败。改为"进展驱动"看门狗: prefix 关键路径的 mtime 持续
         * 变化就视为仍在推进并继续等待; 进程活着但长时间零进展才判死; 绝对上限只
         * 作挂死安全网, 正常情况下不会触发。 */
            constexpr int kWinebootPollMs = 1000;
            constexpr int kWinebootNoProgressGraceMs = 90 * 1000;
            constexpr int kWinebootAbsoluteCapMs = 5 * 60 * 1000;
            const std::string winebootProgressPaths[] = {
                p->prefixDir + "/drive_c/windows",
                p->prefixDir + "/drive_c/windows/mono",
                p->prefixDir + "/drive_c/windows/system32",
                p->prefixDir + "/system.reg",
                p->prefixDir + "/user.reg",
            };
            auto winebootProgressStamp = [&winebootProgressPaths]() -> int64_t {
                int64_t latest = 0;
                for (const auto& path : winebootProgressPaths) {
                    struct stat st;
                    if (stat(path.c_str(), &st) == 0 && (int64_t)st.st_mtime > latest)
                        latest = (int64_t)st.st_mtime;
                }
                return latest;
            };
            int64_t lastStamp = winebootProgressStamp();
            int waitedMs = 0;
            int lastProgressMs = 0;
            while (IsProcessAliveNotZombie(childPid) && waitedMs < kWinebootAbsoluteCapMs) {
                usleep(kWinebootPollMs * 1000);
                waitedMs += kWinebootPollMs;
                const int64_t nowStamp = winebootProgressStamp();
                if (nowStamp != lastStamp) {
                    lastStamp = nowStamp;
                    lastProgressMs = waitedMs;
                }
                if (waitedMs % 10000 == 0)
                    OH_LOG_INFO(LOG_APP, "[Launch-Async] wineboot still initializing (%{public}d s)",
                                waitedMs / 1000);
                if (waitedMs - lastProgressMs >= kWinebootNoProgressGraceMs) {
                    OH_LOG_ERROR(LOG_APP,
                                 "[Launch-Async] wineboot alive but no prefix progress for %{public}d s, abort (attempt %{public}d)",
                                 kWinebootNoProgressGraceMs / 1000, attempt);
                    winebootWaitMs = waitedMs;
                    if (attempt >= kMaxWinebootAttempts) {
                        EmitEngineFail("wineboot-no-progress");
                        return false;
                    }
                    continue;
                }
            }
            if (waitedMs >= kWinebootAbsoluteCapMs) {
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] wineboot exceeded %{public}d s absolute cap, abort (attempt %{public}d)",
                             kWinebootAbsoluteCapMs / 1000, attempt);
                winebootWaitMs = waitedMs;
                if (attempt >= kMaxWinebootAttempts) {
                    EmitEngineFail("wineboot-cap");
                    return false;
                }
                continue;
            }
            winebootWaitMs = waitedMs;
        /* wineboot 已退出: registry 仍在 wineserver flush 途中 (实测落盘延迟
         * 稳定 ~13s), 宽限窗口等文件就绪 — 文件到位即通过, 不会满等 */
            if (!WaitFor("wine prefix",
                         [&p]() { return IsWinePrefixInitialized(p->prefixDir); },
                         60000, 200)) {
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] wineboot exited but prefix incomplete, abort (attempt %{public}d)",
                             attempt);
                if (attempt >= kMaxWinebootAttempts) {
                    EmitEngineFail("wineboot-failed");
                    return false;
                }
                continue;
            }
            winebootOk = true;
        }
        OH_LOG_INFO(LOG_APP, "[Launch-Async] wineboot completed (%{public}d s)", winebootWaitMs / 1000);
        unlink(initMarker.c_str());
        // wineboot 退出仅代表 prefix 初始化结束; wineserver socket 才是 Wine
        // 服务栈对外的就绪信号。未就绪时若直接放行, 首个 GUI 进程可能抢跑
        // 建立渲染 surface 失败 (PC 首启白屏的竞态来源之一)。非致命: socket
        // 就绪后由 explorer/应用自身的 server_connect 重试收敛。
        if (!WaitFor("wineserver socket after wineboot",
                     [p]() { return IsWineserverSocketReady(p->prefixDir); }, 5000, 100)) {
            OH_LOG_WARN(LOG_APP, "[Launch-Async] wineserver socket not ready after wineboot");
        }
        ws->SetDesktopRootRecognitionEnabled(true);
        ws->PromotePendingDesktopRoot();
    } else {
        /* 二启 (prefix 已初始化): 显式播种 wineboot boot 事件。
         * 每个新 wineserver 会话的内核对象全空, 第一个客户端 (explorer) 会
         * 在 ntdll run_wineboot 里触发 wineboot --init——该路径继承 appspawn
         * 环境 (LD_PRELOAD=libappspawn_helper.z.so 等), 实测 wineboot 卡死
         * (注册表已写但 .update-timestamp 不更新), SetEvent 永不执行, 之后
         * 所有 Wine 进程都卡在 boot 事件等待, 窗口全部出不来。这里用与首启
         * 相同的 NCP 干净环境显式跑一次 wineboot: 正常完成后事件 signaled,
         * explorer 的 run_wineboot 检查事件已存在, 立即放行。
         * 参数必须用 --init: wineboot.c 的 wWinMain 传 update_wineprefix(update),
         * 而 update_wineprefix 的参数名就是 force——--update 会让 force=true,
         * 无条件重装 wine.inf 并弹出 "Setting up Wine" 等待窗; --init 传
         * force=false, 仅当 wine.inf 时间戳变化 (升级) 才重装。 */
        OH_LOG_INFO(LOG_APP, "[Launch-Async] prefix ready; seeding wineboot boot event (--init)...");
        winehua::SpawnRequest wbReq{winehua::SpawnKind::Wineboot};
#ifdef __aarch64__
        winehua::AppendCompatEnvLines(wbReq.env, p->compatEnvStr, p->automationMode);
#endif
        const pid_t childPid = winehua::Spawner::Spawn(wbReq);
        if (childPid <= 0) {
            OH_LOG_ERROR(LOG_APP, "[Launch-Async] wineboot --init spawn FAILED");
        } else {
            OH_LOG_INFO(LOG_APP, "[Launch-Async] wineboot --init pid=%{public}d", childPid);
            // 登记 wineboot: NCP 模式存活判定依赖注册表, 未登记会 0ms 放行
            // (done 0 ms) → ready 提前 → PC 首启白屏 (与首启登记同理)。
            AddProcess(childPid, "@engine/wineboot", -1, "@engine/wineboot");
            /* 与首启相同的等待纪律: wineboot 活着就继续等, 大超时仅作挂死
             * 安全网。wineboot 退出即 SetEvent, explorer 即可放行。 */
            char procPath[64];
            snprintf(procPath, sizeof(procPath), "/proc/%d", childPid);
            constexpr int kWinebootHangMs = 3 * 60 * 1000;
            int aliveMs = 0;
            while (IsProcessAliveNotZombie(childPid) && aliveMs < kWinebootHangMs) {
                usleep(500000);
                aliveMs += 500;
            }
            OH_LOG_INFO(LOG_APP, "[Launch-Async] wineboot --init done (%{public}d ms)",
                        aliveMs);
            if (!WaitFor("wineserver socket after wineboot seed",
                         [p]() { return IsWineserverSocketReady(p->prefixDir); }, 5000, 100)) {
                OH_LOG_WARN(LOG_APP, "[Launch-Async] wineserver socket not ready after wineboot seed");
            }
        }
    }

    // -- explorer desktop shell (仅 desktop 模式) --
    PrepareDesktopSessionGraphicsEnv(*p);

    if (p->automationMode)
    {
        OH_LOG_INFO(LOG_APP, "[Launch-Async] automation session ready; Explorer intentionally skipped");
    }
    else if (WaylandServer::GetInstance()->IsDesktopMode())
    // -- explorer (Desktop 或 Pad 模式均启动) --
    {
        auto* ws = WaylandServer::GetInstance();
        ws->SetDesktopRootRecognitionEnabled(true);
        int dw = ws->outputW_ > 0 ? ws->outputW_ : 1280;
        int dh = ws->outputH_ > 0 ? ws->outputH_ : 720;
        OH_LOG_INFO(LOG_APP, "[Launch-Async] explorer desktop size: outputW=%{public}d outputH=%{public}d → %{public}dx%{public}d",
                    ws->outputW_, ws->outputH_, dw, dh);
        char desktopSize[64];
        EmitEnginePhase("explorer");
        constexpr int kExplorerMaxAttempts = 3;
        constexpr int kExplorerRetryBackoffMs = 2000;
        int explorerAttempt = 0;
        /* 附带 winehua_keep.exe: 加入 shell desktop 并持久运行,
         * 避免最后一个用户应用退出后 wineserver 自动关闭桌面.
         * 仅 Pad 桌面模式需要, Phone 模式走单窗口, 无需此逻辑. */
        snprintf(desktopSize, sizeof(desktopSize), "/desktop=shell,%dx%d", dw, dh);
        winehua::SessionEnvPolicy explorerPolicy = SessionPolicyFromLaunch(*p, audioBootstrapFd);
        explorerPolicy.stableDesktopOverlay = true;
        std::vector<std::string> explorerEnv = winehua::BuildSessionEnv(explorerPolicy);
        winehua::SpawnRequest exReq{winehua::SpawnKind::DesktopShell};
        exReq.argv = {desktopSize, "winehua_keep.exe"};
        exReq.env = std::move(explorerEnv);
        bool explorerRootReady = false;
        while (!explorerRootReady && explorerAttempt < kExplorerMaxAttempts) {
            explorerAttempt++;
            const pid_t exPid = winehua::Spawner::Spawn(exReq);
            OH_LOG_INFO(LOG_APP, "[Launch-Async] explorer desktop attempt=%{public}d/%{public}d pid=%{public}d (via broker)",
                        explorerAttempt, kExplorerMaxAttempts, (int)exPid);
            if (exPid > 0) {
                // 桌面壳进程登记为引擎核心进程: 保证用户程序停止后桌面保持存活,
                // 且"关闭运行中的程序"不会把桌面一起带走。
                AddProcess(exPid, "@engine/explorer", -1, "@engine/explorer");
            }
            ws->PromotePendingDesktopRoot();
            if (exPid <= 0) {
                OH_LOG_ERROR(LOG_APP, "[Launch-Async] explorer desktop spawn failed (attempt %{public}d)",
                             explorerAttempt);
                if (explorerAttempt >= kExplorerMaxAttempts) {
                    EmitEngineFail("explorer-spawn");
                    return false;
                }
                usleep(kExplorerRetryBackoffMs * 1000);
                continue;
            }
            /* 桌面根是 wine-ready 的真实前置条件:
             * - root toplevel 注册 → 条件满足, 立即放行;
             * - explorer 死亡 → 自动重试 (慢设备/内存压力下 explorer 可能瞬崩);
             * - wineserver 死亡 → 明确失败;
             * 仅"进程活着但 root 永不注册"的挂死由看门狗兜底。 */
            constexpr int kRootCheckIntervalMs = 100;
            constexpr int kRootWatchdogMs = 10 * 60 * 1000;
            int waitedMs = 0;
            bool attemptFailed = false;
            while (ws->GetDesktopRootToplevelId() == 0) {
                if (!IsProcessAliveNotZombie(exPid)) {
                    OH_LOG_ERROR(LOG_APP,
                                 "[Launch-Async] explorer desktop died before registering desktop root (attempt %{public}d/%{public}d)",
                                 explorerAttempt, kExplorerMaxAttempts);
                    attemptFailed = true;
                    break;
                }
                if (wsChildPid > 0 && !IsProcessAliveNotZombie(wsChildPid)) {
                    OH_LOG_ERROR(LOG_APP,
                                 "[Launch-Async] wineserver died before explorer registered desktop root");
                    EmitEngineFail("wineserver-died");
                    return false;
                }
                if (waitedMs >= kRootWatchdogMs) {
                    OH_LOG_ERROR(LOG_APP,
                                 "[Launch-Async] explorer alive but desktop root never registered (%d s), abort",
                                 waitedMs / 1000);
                    EmitEngineFail("explorer-root-timeout");
                    return false;
                }
                usleep(kRootCheckIntervalMs * 1000);
                waitedMs += kRootCheckIntervalMs;
            }
            if (attemptFailed) {
                if (explorerAttempt >= kExplorerMaxAttempts) {
                    EmitEngineFail("explorer-died");
                    return false;
                }
                usleep(kExplorerRetryBackoffMs * 1000);
                continue;
            }
            explorerRootReady = ws->GetDesktopRootToplevelId() != 0;
        }
        OH_LOG_INFO(LOG_APP, "[Launch-Async] explorer desktop root ready tl=%{public}d",
                    ws->GetDesktopRootToplevelId());
    }
    else
    {
        // 非桌面模式 (PC/受管窗口/单窗口): 不自动启动 explorer 文件管理器窗口。
        // master phase-2 合并曾在此自动弹出 explorer, 导致 PC 上每次引擎启动
        // 都多弹一个 explorer 窗口; 用户需要文件管理时用"文件资源管理器"卡片
        // 手动打开 (Index.ets 手动启动走相同的 broker 路径)。
        OH_LOG_INFO(LOG_APP,
                    "[Launch-Async] non-desktop engine ready; explorer window intentionally not auto-started");
    }
    return true;
}

void LaunchThreadFunc(LaunchParams* p) {
    OH_LOG_INFO(LOG_APP, "[Launch-Async] wineserver + wineboot + wine starting in background");
    OH_LOG_INFO(LOG_APP, "[Launch-Async] XKB_CONFIG_ROOT=%{public}s",
                (p->winehuaBin + "/../share/X11/xkb").c_str());

    auto& graphicsBroker = winehua::GraphicsBroker::GetInstance();
    graphicsBroker.SetWineRuntimeBinaryDir(p->winehuaBin);
    graphicsBroker.SetVulkanPresentMode(p->d3dBackend.rfind("dxvk_", 0) == 0);
    EmitEnginePhase("graphics");
    graphicsBroker.EnsureStarted(p->sockDir);

    int audioBootstrapFd = CreateAudioBootstrapFd(p->sockDir);
    // Resolve VirGL/backend state before the explorer session env is built so
    // NCP children inherit the active receiver rather than an early SHM snapshot.
    PrepareDesktopSessionGraphicsEnv(*p);
    // 会话 env 不再预先构建: 唯一消费者是 explorer 桌面链, 它在 LaunchPadMode
    // 内用 BuildSessionEnv 现取现建, 图形状态更新鲜。

    mkdir(p->prefixDir.c_str(), 0755);

    EmitEnginePhase("wineserver");

    bool ok = false;
    ok = LaunchPadMode(p, audioBootstrapFd);

    if (ok) {
        EmitEnginePhase("ready");
        EmitEngineEvent("wine-ready");
    }

    delete p;
}
