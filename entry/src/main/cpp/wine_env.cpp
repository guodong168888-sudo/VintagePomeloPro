#include "wine_env.h"
#include "wine_constants.h"
#include "audio_broker.h"
#include "audio_ipc_protocol.h"
#include "graphics_broker.h"
#include "wayland_server.h"

#include <unistd.h>
#include <cstdlib>
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>
#include <unordered_set>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000
#define LOG_TAG "WL_NAPI"
#include <hilog/log.h>

#ifndef __aarch64__
namespace {
constexpr const char* X86_BUNDLED_GUEST_GFX_DIR = "/data/storage/el1/bundle/libs/x86_64";
}
#endif

int CreateAudioBootstrapFd(const std::string& runtimeDir) {
    if (!winehua::AudioBroker::GetInstance().EnsureStarted(runtimeDir)) {
        OH_LOG_ERROR(LOG_APP, "[AudioBroker] failed to start for runtimeDir=%{public}s", runtimeDir.c_str());
        return -1;
    }
    int fd = winehua::AudioBroker::GetInstance().CreateBootstrapHandle();
    if (fd < 0) {
        OH_LOG_ERROR(LOG_APP, "[AudioBroker] failed to create bootstrap FD for runtimeDir=%{public}s", runtimeDir.c_str());
        return -1;
    }
    OH_LOG_INFO(LOG_APP, "[AudioBroker] bootstrap ready runtimeDir=%{public}s", runtimeDir.c_str());
    return fd;
}

std::vector<std::string> BuildWineEnv(const std::string& sockDir,
                                      const std::string& sockName,
                                      const std::string& libPath,
                                      const std::string& binDir,
                                      int audioBootstrapFd,
                                      const std::string& homeDir,
                                      const std::string& prefixDir) {
    std::string shareDir = binDir + "/../share";
    std::string xkbDir = shareDir + "/X11/xkb";
    std::string midiSoundfontPath = binDir + "/../audio/winehua-gm.sf2";
    std::string runtimeLibPath = binDir + ":" + binDir + "/x86_64-unix:" + binDir + "/../lib/x86_64";
    winehua::GraphicsBackendState graphicsState = winehua::GraphicsBroker::GetInstance().GetState();
    std::string guestReceiverLibDir;
    bool useGuestReceiverRuntime = graphicsState.active == winehua::GraphicsBackend::Virgl;

    if (useGuestReceiverRuntime && graphicsState.guestReceiverPresent && !graphicsState.guestReceiverRuntimeDir.empty()) {
#ifdef __aarch64__
        guestReceiverLibDir = graphicsState.guestReceiverRuntimeDir + "/lib";
#else
        const std::string bundledGuestLibDir = X86_BUNDLED_GUEST_GFX_DIR;
        if (access((bundledGuestLibDir + "/libwinehua_guest_EGL.so").c_str(), R_OK) == 0 &&
            access((bundledGuestLibDir + "/libgallium-25.0.1.so").c_str(), R_OK) == 0) {
            guestReceiverLibDir = bundledGuestLibDir;
        } else {
            guestReceiverLibDir = graphicsState.guestReceiverRuntimeDir + "/lib";
        }
#endif
        if (access(guestReceiverLibDir.c_str(), F_OK) == 0) {
            runtimeLibPath = guestReceiverLibDir + ":" + runtimeLibPath;
        }
    }

    std::string dllPath = binDir + "/x86_64-windows:" + binDir + "/i386-windows:" + binDir;
#ifndef __aarch64__
    // x86_64: bundled libs 加入 WINEDLLPATH, load_unixlib_by_name() 从此搜索 .so
    dllPath += ":/data/storage/el1/bundle/libs/x86_64";
#endif

    std::vector<std::string> env = {
        "XDG_RUNTIME_DIR=" + sockDir,
        "WAYLAND_DISPLAY=" + sockName,
        "HOME=" + homeDir,
        "WINEPREFIX=" + (prefixDir.empty() ? std::string(WINE_PREFIX) : prefixDir),
        "WINEDATADIR=" + shareDir + "/wine",
        "WINEDLLDIR=" + binDir + "/x86_64-unix",
        "WINEDLLDIR0=" + binDir + "/x86_64-windows",
        "WINEDLLDIR1=" + binDir + "/i386-windows",
        "WINEDLLDIR2=" + binDir,
        "WINEDLLPATH=" + dllPath,
        "WINEDEBUG=-all",
        "LANG=zh_CN.UTF-8",
        "XKB_CONFIG_ROOT=" + xkbDir,
        "PATH=/usr/local/bin:/data/app/bin:/usr/bin:/vendor/bin:" + binDir + "/x86_64-windows:" + binDir + "/i386-windows:" + binDir,
        "TMPDIR=" WINE_TMPDIR,
        "MIDI_SOUNDFONT_PATH=" + midiSoundfontPath,
        // winegstreamer 运行时加载 GStreamer 插件 (gst-plugins-base/good/libav)
        "GST_PLUGIN_PATH=" + binDir + "/x86_64-unix/gstreamer-1.0",
        "GST_PLUGIN_SYSTEM_PATH=" + binDir + "/x86_64-unix/gstreamer-1.0",
    };
    AppendBox64PerfStrings(env);
#ifdef __aarch64__
    env.push_back("LD_LIBRARY_PATH=" + libPath);
    env.push_back("BOX64_LD_LIBRARY_PATH=" + runtimeLibPath);
#else
    env.push_back("LD_LIBRARY_PATH=" + runtimeLibPath);
#endif
    if (audioBootstrapFd >= 0) {
        env.push_back("WINE_OHOS_AUDIO_ENABLE=1");
        env.push_back("WINE_OHOS_AUDIO_BOOTSTRAP_FD=" + std::to_string(audioBootstrapFd));
        env.push_back("WINE_OHOS_AUDIO_PROTOCOL_VERSION=" + std::to_string(WINEHUA_AUDIO_PROTOCOL_VERSION));
    }
    winehua::GraphicsBroker::GetInstance().SetWineRuntimeBinaryDir(binDir);
    // 告知 winewayland.drv 当前是桌面模式还是独立窗口模式
    env.push_back(std::string("WINEHUA_DESKTOP_MODE=") +
                  (WaylandServer::GetInstance()->IsDesktopMode() ? "1" : "0"));
    // WINEHUA_SIMULATE_RESOLUTION: win32u per-process 模拟 ChangeDisplaySettings
    // (记录游戏主动 CDS 请求的分辨率, 查询时返回 — DDraw 全屏游戏依赖)。
    // 仅 PC 多窗口模式注入: Pad 模拟桌面 (RootCompositing) 由合成器缩放绘制,
    // 不需要分辨率模拟。
    if (!WaylandServer::GetInstance()->IsDesktopMode())
        env.push_back("WINEHUA_SIMULATE_RESOLUTION=1");
    // ==== Layer 5: 图形状态 ====
    // NOTE: BOX64_EMULATED_LIBS (ARM64) 在 DXVK 路径下会被 AppendD3dBackendEnv 覆盖
    winehua::GraphicsBroker::GetInstance().AppendWineEnv(env);

    OH_LOG_INFO(LOG_APP,
                "[WineEnv] backend=%{public}s guestMode=%{public}s guestLib=%{public}s runtimeLibPath=%{public}s",
                winehua::GraphicsBroker::BackendName(graphicsState.active),
                graphicsState.guestReceiverMode.empty() ? "stock-egl" : graphicsState.guestReceiverMode.c_str(),
                guestReceiverLibDir.empty() ? "(none)" : guestReceiverLibDir.c_str(),
                runtimeLibPath.c_str());
    return env;
}

void UpsertEnvLine(std::vector<std::string>& env, const std::string& line)
{
    const size_t sep = line.find('=');
    if (sep == std::string::npos || sep == 0) return;
    const std::string key = line.substr(0, sep);
    // 清理所有同 key 的旧条目, 然后追加新值 — 避免预填充 vector 上
    // push_back 路径 (如 AppendProductDxvkEnv 覆盖 WEAKBARRIER) 产生重复 key。
    // (与上游 bb617a4 收敛语义一致)
    env.erase(std::remove_if(env.begin(), env.end(), [&](const std::string& existing) {
        return existing.compare(0, key.size(), key) == 0 &&
               existing.size() > key.size() && existing[key.size()] == '=';
    }), env.end());
    env.push_back(line);
}

void AppendD3dBackendEnv(std::vector<std::string>& env,
                         const std::string& d3dBackend,
                         const std::string& binDir)
{
    if (d3dBackend == "wined3d") {
        const std::vector<std::string> managed = {
            "WINEHUA_D3D_BACKEND=wined3d",
            /* Compatibility mode must be deterministic even when a game
             * directory contains a copied DXVK DLL. Wine's built-in D3D
             * modules render through WineD3D -> OpenGL -> VirGL. */
            "WINEDLLOVERRIDES=d3d8=b;d3d9=b;d3d10core=b;d3d10=b;d3d10_1=b;d3d11=b;dxgi=b",
        };
        for (const std::string& line : managed) UpsertEnvLine(env, line);
        return;
    }
    if (d3dBackend.rfind("dxvk_", 0) != 0) return;

    std::string profile = d3dBackend.substr(strlen("dxvk_"));
    if (profile.empty()) profile = "legacy";
    const bool legacy = profile == "legacy";
    const bool modern26 = profile == "modern_2_6";
    if (!legacy && !modern26) return;
    // dxvk_modern_2_6 → 运行时目录 dxvk/modern-2.6 (与打包目录一致)
    const std::string runtimeProfile = modern26 ? "modern-2.6" : "legacy";
    const std::string overlayRoot = std::string(WINE_RUNTIME_ROOT) +
        "/dxvk/" + runtimeProfile;
    const std::string overlay64 = overlayRoot + "/x64";
    const std::string overlay86 = overlayRoot + "/x86";
    const std::string guestVulkanRoot = binDir + "/guest_vulkan";
    const std::string guestVulkanLib = guestVulkanRoot + "/lib";
    const std::string guestVulkanIcd = guestVulkanRoot +
        "/share/vulkan/icd.d/venus_icd.x86_64.json";
    const std::string box64LibraryPath = guestVulkanLib + ":" +
        binDir + "/guest_gfx/lib:" + binDir + ":" +
        binDir + "/x86_64-unix:" + std::string(WINE_RUNTIME_ROOT) + "/lib/x86_64";
    const std::string wineDllPath = overlay64 + ":" + overlay86 + ":" +
        binDir + "/x86_64-windows:" + binDir + "/i386-windows:" + binDir;

    const std::vector<std::string> managed = {
        "WINEHUA_D3D_BACKEND=" + d3dBackend,
        "WINEHUA_DXVK_ROOT=" + overlayRoot,
        "WINEHUA_DXVK_PROFILE=" + runtimeProfile,
        "WINEHUA_DXVK_VERSION=" + std::string(modern26 ? "2.6.2" : "1.10.3"),
        "WINEHUA_VULKAN_RUNTIME=1",
        "WINEHUA_VULKAN_LOADER_ARCH=x86_64",
        "WINEHUA_VENUS_ICD_ARCH=x86_64",
#ifdef __aarch64__
        "USE_LIBBOX64=1",
#endif
#ifdef __aarch64__
        "BOX64_LD_LIBRARY_PATH=" + box64LibraryPath,
        "BOX64_EMULATED_LIBS=" + Box64EmulatedLibs(),
#endif
        "VK_DRIVER_FILES=" + guestVulkanIcd,
        "VK_ICD_FILENAMES=" + guestVulkanIcd,
        "VN_DEBUG=vtest",
        /* Host GPU writes to Venus feedback buffers are not automatically
         * visible through WineHua's explicit Guest/Host shadow mapping.
         * Query the real Host objects instead of polling stale Guest words. */
        /* The Guest Mesa / host virglrenderer transport uses one shared
         * command ring. Multiple Venus rings can emit an invalid command
         * length to the host decoder and leave a D3D11 process black. */
        "VN_PERF=" + std::string(modern26
            ? "no_fence_feedback,no_query_feedback,no_semaphore_feedback,no_multi_ring"
            : "no_fence_feedback,no_query_feedback,no_multi_ring"),
        /* 与 master 方针一致: DXVK 只接管 D3D11。DX9/10/10.1 使用 Wine 内建
         * WineD3D → OpenGL → VirGL, 该路径在 Venus/Maleoon 栈上对老游戏更
         * 成熟稳定; 全 D3D 走 DXVK(Venus) 会破坏原本 VirGL 驱动的游戏。 */
        "WINEDLLOVERRIDES=d3d11=n;dxgi=n",
        /* This path is qualified by the command-list ownership and continuous
         * Heaven gates. Keep per-range statistics opt-in so production avoids
         * diagnostic bookkeeping and log I/O. */
        "DXVK_WINEHUA_BATCH_MAPPED_FLUSH=1",
        "VN_WINEHUA_REMOTE_MEMORY_SYNC=1",
        "WINEDLLPATH=" + wineDllPath,
        "WINEDLLDIR0=" + overlay64,
        "WINEDLLDIR1=" + overlay86,
        /* Keep the Wine PE directories contiguous after the DXVK overlays.
         * ntdll stops scanning at the first missing WINEDLLDIR index. */
        "WINEDLLDIR2=" + binDir + "/x86_64-windows",
        "WINEDLLDIR3=" + binDir + "/i386-windows",
        "WINEDLLDIR4=" + binDir,
    };
    for (const std::string& line : managed) UpsertEnvLine(env, line);

    /* Product DXVK sessions also expose VKD3D-Proton for D3D12. Keep the
     * existing 3-arg signature: there is no separate render-mode button.
     *
     * WINEDLLDIR0 stays the DXVK overlay (d3d11/dxgi). d3d12.dll is loaded
     * from WINEDLLPATH. Do not copy it into DIR0 (stray d3d12 next to d3d11
     * made cube's first present white) and do not set
     * VN_WINEHUA_DIRECT_FENCE_WAIT on the shared session — that flag
     * deadlocks Venus when cube and gears share one ring (cube 0.4 FPS,
     * gears white/stuck). GPU_UPLOAD=0 stays vkd3d-prefixed only. */
    const std::string vkd3dRoot = std::string(WINE_RUNTIME_ROOT) +
        "/vkd3d/limited-500k";
    const std::string vkd3d64 = vkd3dRoot + "/x64";
    if (access((vkd3d64 + "/d3d12.dll").c_str(), R_OK) == 0) {
        const std::string overlayD3d12 = overlay64 + "/d3d12.dll";
        if (access(overlayD3d12.c_str(), F_OK) == 0 &&
            unlink(overlayD3d12.c_str()) == 0) {
            OH_LOG_INFO(LOG_APP,
                "[D3D] removed staged d3d12.dll from DXVK overlay %{public}s",
                overlay64.c_str());
        }
        const std::string wineDllPathWithVkd3d = vkd3d64 + ":" + wineDllPath;
        const std::vector<std::string> vkd3dOverlay = {
            "WINEHUA_VKD3D_ROOT=" + vkd3dRoot,
            "WINEHUA_VKD3D_PROFILE=limited-500k",
            "WINEHUA_VKD3D_VERSION=2.6",
            "VKD3D_WINEHUA_GPU_UPLOAD=0",
            "WINEDLLOVERRIDES=d3d12=n;d3d11=n;dxgi=n",
            "WINEDLLPATH=" + wineDllPathWithVkd3d,
        };
        for (const std::string& line : vkd3dOverlay) UpsertEnvLine(env, line);
    }

    if (!legacy) return;
    // These compatibility relaxations are implemented only by the legacy
    // 1.10 fork; keep the modern 2.6 environment clean and diagnosable.
    const std::vector<std::string> legacyCompatibility = {
        "WINEHUA_DXVK_RELAXED_FEATURES=1",
        "DXVK_WINEHUA_COMMAND_QUERY_RESET=1",
        "DXVK_WINEHUA_FLUSH_DYNAMIC_MAPPED=1",
        /* Prefer the native RGBA8 SNORM render-target path. On devices such
         * as Maleoon where sampling is supported but color attachment usage
         * is not, DXVK may substitute its qualified RGBA16F backing image. */
        "DXVK_WINEHUA_EMULATE_RGBA8_SNORM_RT=auto",
    };
    for (const std::string& line : legacyCompatibility) UpsertEnvLine(env, line);
}

bool IsVkd3dSmokeDemo(const std::string& exePath)
{
    std::string lower = exePath;
    for (char& c : lower) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        if (c == '/') c = '\\';
    }
    const size_t slash = lower.find_last_of("\\/");
    const std::string name = slash == std::string::npos ? lower : lower.substr(slash + 1);
    if (name != "gears.exe" && name != "triangle.exe") return false;
    return lower.find("smoke") != std::string::npos || lower == name;
}

void AppendVkd3dDemoPresentEnv(std::vector<std::string>& env,
                               const std::string& d3dBackend,
                               const std::string& binDir)
{
    if (d3dBackend.rfind("dxvk_", 0) != 0) return;
    std::string profile = d3dBackend.substr(strlen("dxvk_"));
    if (profile.empty()) profile = "legacy";
    const bool modern26 = profile == "modern_2_6";
    const bool legacy = profile == "legacy";
    if (!legacy && !modern26) return;
    const std::string runtimeProfile = modern26 ? "modern-2.6" : "legacy";
    const std::string dxvk64 = std::string(WINE_RUNTIME_ROOT) + "/dxvk/" +
        runtimeProfile + "/x64";
    const std::string dxvk86 = std::string(WINE_RUNTIME_ROOT) + "/dxvk/" +
        runtimeProfile + "/x86";
    const std::string vkd3dRoot = std::string(WINE_RUNTIME_ROOT) +
        "/vkd3d/limited-500k";
    const std::string vkd3d64 = vkd3dRoot + "/x64";
    if (access((vkd3d64 + "/d3d12.dll").c_str(), R_OK) != 0) return;

    const std::string wineDllPath = vkd3d64 + ":" + dxvk64 + ":" + dxvk86 + ":" +
        binDir + "/x86_64-windows:" + binDir + "/i386-windows:" + binDir;
    /* Master 13236b5 vkd3d_limited_500k (qualified gears/triangle). Do not
     * copy b2437a3 explorer-inject (PERSISTENT_MAP_SYNC=0 / FORCE_COHERENT=0 /
     * GPU_UPLOAD=0): that presents a black rotating window. Cube stays on the
     * DXVK DIR0 session; these overrides apply only to this process. */
    env.erase(std::remove_if(env.begin(), env.end(), [](const std::string& existing) {
        return existing.rfind("VKD3D_WINEHUA_GPU_UPLOAD=", 0) == 0;
    }), env.end());
    const std::vector<std::string> demo = {
        "WINEDLLDIR0=" + vkd3d64,
        "WINEDLLDIR1=" + dxvk64,
        "WINEDLLDIR2=" + dxvk86,
        "WINEDLLDIR3=" + binDir + "/x86_64-windows",
        "WINEDLLDIR4=" + binDir + "/i386-windows",
        "WINEDLLDIR5=" + binDir,
        "WINEDLLPATH=" + wineDllPath,
        "WINEDLLOVERRIDES=d3d12=n;d3d11=n;dxgi=n",
        "WINEHUA_PERF_PROFILE=shadow-precise",
        "VN_WINEHUA_STRONG_RING_BARRIER=1",
        "VN_WINEHUA_REMOTE_MEMORY_SYNC=1",
        "VN_WINEHUA_PERSISTENT_MAP_SYNC=1",
        "VN_WINEHUA_DIRECT_FENCE_WAIT=1",
        "VKR_WINEHUA_SHADOW_FROM_HOST=precise",
        "VKD3D_WINEHUA_FORCE_COHERENT_MAP_SYNC=1",
    };
    for (const std::string& line : demo) UpsertEnvLine(env, line);
    OH_LOG_INFO(LOG_APP,
        "[D3D] vkd3d demo present DIR0=%{public}s profile=shadow-precise "
        "persistent=1 coherent=1 backend=%{public}s",
        vkd3d64.c_str(), d3dBackend.c_str());
}

void AppendProductDxvkEnv(std::vector<std::string>& env,
                          const std::string& d3dBackend,
                          const std::string& perfProfile)
{
    if (d3dBackend.rfind("dxvk_", 0) != 0) return;

    const std::string selectedProfile = perfProfile.empty()
        ? "shadow-precise-dirty-ring-inline-upload-coverage-sort"
        : perfProfile;
    const std::vector<std::string> managed = {
        // Retain actionable DXVK failures without filling a user's game
        // directory with the informational startup stream.
        "DXVK_LOG_LEVEL=warn",
        "DXVK_LOG_PATH=C:\\windows\\temp",
        "WINEHUA_PERF_PROFILE=" + selectedProfile,
        "DXVK_WINEHUA_PRECISE_SHADOW=1",
        "VN_WINEHUA_STRONG_RING_BARRIER=1",
    };
    for (const std::string& line : managed) UpsertEnvLine(env, line);
#ifdef __aarch64__
    // BOX64 变量仅在 ARM64 生效; x86_64 主机设置它会破坏 broker entryParams。
    UpsertEnvLine(env, "BOX64_DYNAREC_WEAKBARRIER=0");
#endif
    if (selectedProfile ==
        "shadow-precise-dirty-ring-inline-upload-descriptor-serialized")
        UpsertEnvLine(env, "VKR_WINEHUA_DESCRIPTOR_UPDATE_SERIALIZE=1");
    if (selectedProfile == "shadow-precise") {
        /* Master 13236b5 vkd3d_limited_500k session contract. Explorer and
         * gears must share these Guest Venus flags with the precise host. */
        env.erase(std::remove_if(env.begin(), env.end(), [](const std::string& existing) {
            return existing.rfind("VKD3D_WINEHUA_GPU_UPLOAD=", 0) == 0;
        }), env.end());
        const std::vector<std::string> precise = {
            "VN_WINEHUA_REMOTE_MEMORY_SYNC=1",
            "VN_WINEHUA_PERSISTENT_MAP_SYNC=1",
            "VN_WINEHUA_DIRECT_FENCE_WAIT=1",
            "VKR_WINEHUA_SHADOW_FROM_HOST=precise",
            "VKD3D_WINEHUA_FORCE_COHERENT_MAP_SYNC=1",
        };
        for (const std::string& line : precise) UpsertEnvLine(env, line);
    }
}

static bool ShouldSerializeEntryParamEnv(const std::string& envLine) {
    return envLine.rfind("WINE_OHOS_AUDIO_ENABLE=", 0) != 0 &&
           envLine.rfind("WINE_OHOS_AUDIO_BOOTSTRAP_FD=", 0) != 0 &&
           envLine.rfind("WINE_OHOS_AUDIO_PROTOCOL_VERSION=", 0) != 0 &&
           envLine.rfind("WINESERVERSOCKET=", 0) != 0;
}

static std::string EnvKey(const std::string& envLine) {
    size_t sep = envLine.find('=');
    return sep == std::string::npos ? envLine : envLine.substr(0, sep);
}

static bool IsBrokerSessionAuthoritativeKey(const std::string& key) {
    // Explorer may start before VirGL is ready. Replace its early Box64 path
    // with the finalized path, where guest graphics libraries are a fallback.
    return key == "BOX64_LD_LIBRARY_PATH";
}

size_t AppendMissingEntryParamsEnvOverrides(std::string& entryParams,
                                            const std::vector<std::string>& env) {
    std::unordered_set<std::string> existingKeys;
    size_t pos = 0;

    while ((pos = entryParams.find("|__env=", pos)) != std::string::npos) {
        pos += strlen("|__env=");
        size_t end = entryParams.find('|', pos);
        std::string key = EnvKey(entryParams.substr(pos, end == std::string::npos
                                                          ? std::string::npos
                                                          : end - pos));
        if (!key.empty()) existingKeys.insert(std::move(key));
        if (end == std::string::npos) break;
        pos = end;
    }

    size_t appended = 0;
    for (const std::string& envLine : env) {
        if (!ShouldSerializeEntryParamEnv(envLine) ||
            envLine.find('|') != std::string::npos ||
            envLine.find('\n') != std::string::npos)
            continue;
        // 过滤 per-process fd 变量: 子进程会从 fdList 拿到自己的值
        if (envLine.rfind("WINESERVERSOCKET=", 0) == 0 ||
            envLine.rfind("WINE_OHOS_AUDIO_ENABLE=", 0) == 0 ||
            envLine.rfind("WINE_OHOS_AUDIO_BOOTSTRAP_FD=", 0) == 0 ||
            envLine.rfind("WINE_OHOS_AUDIO_PROTOCOL_VERSION=", 0) == 0)
            continue;
        const std::string key = EnvKey(envLine);
        if (key.empty() ||
            (existingKeys.count(key) && !IsBrokerSessionAuthoritativeKey(key)))
            continue;
        entryParams += "|__env=";
        entryParams += envLine;
        existingKeys.insert(key);
        ++appended;
    }
    return appended;
}

std::string SerializeEnvToEntryParams(const std::vector<std::string>& env) {
    std::string result;
    for (const std::string& e : env) {
        if (e.find('|') != std::string::npos || e.find('\n') != std::string::npos)
            continue;
        if (e.rfind("WINESERVERSOCKET=", 0) == 0 ||
            e.rfind("WINE_OHOS_AUDIO_ENABLE=", 0) == 0 ||
            e.rfind("WINE_OHOS_AUDIO_BOOTSTRAP_FD=", 0) == 0 ||
            e.rfind("WINE_OHOS_AUDIO_PROTOCOL_VERSION=", 0) == 0)
            continue;
        result += "|__env=";
        result += e;
    }
    return result;
}

void LogGraphicsBackendStateForLaunch(const char* tag) {
    winehua::GraphicsBackendState state = winehua::GraphicsBroker::GetInstance().GetState();
    OH_LOG_INFO(LOG_APP,
                "[%{public}s] graphics requested=%{public}s active=%{public}s runtimeReady=%{public}s "
                "guestReceiver=%{public}s(%{public}s) virglSocketReady=%{public}s virglLibraryPresent=%{public}s",
                tag,
                winehua::GraphicsBroker::BackendName(state.requested),
                winehua::GraphicsBroker::BackendName(state.active),
                state.runtimeReady ? "true" : "false",
                state.guestReceiverPresent ? "true" : "false",
                state.guestReceiverMode.empty() ? "stock-egl" : state.guestReceiverMode.c_str(),
                state.virglSocketReady ? "true" : "false",
                state.virglLibraryPresent ? "true" : "false");
    if (!state.lastError.empty())
        OH_LOG_WARN(LOG_APP, "[%{public}s] graphics note: %{public}s", tag, state.lastError.c_str());
}
