#include "env_profiles.h"
#include "wine_env.h"

#include <cstdlib>
#include <cstring>

namespace winehua {

#ifdef __aarch64__
std::vector<std::string> FilterCompatLines(const std::string& compatEnvStr)
{
    std::vector<std::string> raw;
    std::string cur;
    for (const char c : compatEnvStr) {
        if (c == ';') {
            if (!cur.empty()) raw.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.empty()) raw.push_back(cur);
    std::vector<std::string> filtered;
    for (const std::string& line : raw) {
        if (line.rfind("BOX64_DYNAREC_", 0) != 0)
            continue;
        if (line.find('|') != std::string::npos || line.find('\n') != std::string::npos)
            continue;
        if (line.find('=') == std::string::npos)
            continue;
        filtered.push_back(line);
    }
    return filtered;
}

void AppendCompatEnvLines(std::vector<std::string>& env,
                          const std::string& compatEnvStr, bool automationMode)
{
    if (automationMode)
        return;
    for (const std::string& line : FilterCompatLines(compatEnvStr))
        UpsertEnvLine(env, line);
}

void AppendCompatEnvToEntryParams(std::string& entryParams,
                                  const std::string& compatEnvStr, bool automationMode)
{
    if (automationMode)
        return;
    for (const std::string& line : FilterCompatLines(compatEnvStr)) {
        entryParams += "|__env=";
        entryParams += line;
    }
}
#endif // __aarch64__

static std::string FindEnvValue(const std::vector<std::string>& probeBase, const char* key)
{
    const std::string prefix = std::string(key) + "=";
    for (auto it = probeBase.rbegin(); it != probeBase.rend(); ++it) {
        if (it->rfind(prefix, 0) == 0)
            return it->substr(prefix.size());
    }
    return {};
}

void AppendStableDesktopDxvkEnv(std::vector<std::string>& env,
                                const std::vector<std::string>& probeBase,
                                const std::string& d3dBackend)
{
    if (d3dBackend.rfind("dxvk_", 0) != 0) return;

    // 全部 probeBase / getenv 读取集中在写入之前 (允许 env 与 probeBase 别名)
    const char* shadowTrace = getenv("VKR_WINEHUA_SHADOW_TRACE");
    const char* hostShadowMode = getenv("WINEHUA_VIRGL_HOST_SHADOW_MODE");
    if (!hostShadowMode || !hostShadowMode[0])
        hostShadowMode = getenv("VKR_WINEHUA_SHADOW_FROM_HOST");
    const bool hostPrecise = hostShadowMode && !strcmp(hostShadowMode, "precise");
    const bool guestPerf = shadowTrace && !strcmp(shadowTrace, "perf");
    std::string selectedProfile = FindEnvValue(probeBase, "WINEHUA_PERF_PROFILE");
    if (selectedProfile.empty()) {
        if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload-frame-assoc-trace"))
            selectedProfile = "shadow-precise-dirty-ring-frame-assoc-trace";
        else if (shadowTrace && !strcmp(shadowTrace, "present-image-trace"))
            selectedProfile = "shadow-precise-dirty-ring-present-image-trace";
        else if (shadowTrace && !strcmp(shadowTrace, "gpu-frame-profile"))
            selectedProfile = "shadow-precise-dirty-ring-gpu-frame-profile";
        else if (shadowTrace && !strcmp(shadowTrace, "frame-timeline"))
            selectedProfile = "shadow-precise-dirty-ring-frame-timeline";
        else if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload-descriptor-serialized"))
            selectedProfile = "shadow-precise-dirty-ring-inline-upload-descriptor-serialized";
        else if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload-serialized"))
            selectedProfile = "shadow-precise-dirty-ring-inline-upload-serialized";
        else if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload-alias-cover"))
            selectedProfile = "shadow-precise-dirty-ring-inline-upload-alias-cover";
        else if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload-coverage-sort"))
            selectedProfile = "shadow-precise-dirty-ring-inline-upload-coverage-sort";
        else if (shadowTrace && !strcmp(shadowTrace, "inline-gpu-upload"))
            selectedProfile = "shadow-precise-dirty-ring-inline-upload";
        else if (shadowTrace && !strcmp(shadowTrace, "no-gpu-upload-fast"))
            selectedProfile = "shadow-precise-dirty-ring-no-upload-fast";
        else if (shadowTrace && !strcmp(shadowTrace, "no-gpu-upload"))
            selectedProfile = "shadow-precise-dirty-ring-no-upload";
        else if (hostPrecise)
            selectedProfile = "shadow-precise";
        else
            selectedProfile = guestPerf ? "shadow-precise-strong-ring-perf"
                                        : "shadow-precise-dirty-ring-inline-upload-coverage-sort";
    }

    AppendProductDxvkEnv(env, d3dBackend, selectedProfile);
    if (guestPerf) {
        env.push_back("VN_WINEHUA_PERF_SUMMARY=1");
        env.push_back("VN_WINEHUA_PERF_LOG=/storage/Users/currentUser/Download/app.hackeris.winehua/winehua_guest_ring_perf.log");
        env.push_back("MESA_LOG_LEVEL=debug");
    }
}

std::vector<std::string> BuildSessionEnv(const SessionEnvPolicy& p)
{
    std::vector<std::string> env = BuildWineEnv(p.sockDir, p.sockName, p.libPath,
                                                p.binDir, p.audioBootstrapFd, p.homeDir,
                                                p.prefixDir);
    if (!p.d3dBackend.empty())
        AppendD3dBackendEnv(env, p.d3dBackend, p.binDir);
#ifdef __aarch64__
    AppendCompatEnvLines(env, p.compatEnvStr, p.automationMode);
#endif
    if (p.stableDesktopOverlay)
        AppendStableDesktopDxvkEnv(env, env, p.d3dBackend);
    if (p.desktopShellFlag)
        UpsertEnvLine(env, "WINEHUA_DESKTOP=shell");
    for (const std::string& line : p.extraEnv)
        UpsertEnvLine(env, line);
    return env;
}

} // namespace winehua
