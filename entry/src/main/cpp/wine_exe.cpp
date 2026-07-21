#include <napi/native_api.h>
#include "wine_env.h"
#include "wine_process.h"
#include "broker.h"
#include "graphics_broker.h"
#include "wayland_server.h"

#include <unistd.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <cctype>

#undef LOG_TAG
#define LOG_TAG "WL_NAPI"
#include <hilog/log.h>

extern napi_threadsafe_function gStateTsfn;

static napi_value MakeLaunchResult(napi_env env, int32_t pid,
                                   const std::string& sessionId, bool reused) {
    napi_value result, pidValue, sessionValue, reusedValue;
    napi_create_object(env, &result);
    napi_create_int32(env, pid, &pidValue);
    napi_create_string_utf8(env, sessionId.c_str(), NAPI_AUTO_LENGTH, &sessionValue);
    napi_get_boolean(env, reused, &reusedValue);
    napi_set_named_property(env, result, "pid", pidValue);
    napi_set_named_property(env, result, "sessionId", sessionValue);
    napi_set_named_property(env, result, "reused", reusedValue);
    return result;
}

napi_value RunWineExe(napi_env env, napi_callback_info info) {
    size_t argc = 7;
    napi_value args[7] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 4) return MakeLaunchResult(env, -1, "", false);

    char binDir[512] = {}, sockPath[512] = {}, libPath[2048] = {}, wineExe[1024] = {}, homePath[1024] = {};
    napi_get_value_string_utf8(env, args[0], binDir, sizeof(binDir), nullptr);
    napi_get_value_string_utf8(env, args[1], sockPath, sizeof(sockPath), nullptr);
    napi_get_value_string_utf8(env, args[2], libPath, sizeof(libPath), nullptr);
    napi_get_value_string_utf8(env, args[3], wineExe, sizeof(wineExe), nullptr);
    if (argc >= 5) {
        napi_get_value_string_utf8(env, args[4], homePath, sizeof(homePath), nullptr);
    }
    std::vector<std::string> launchArguments;
    bool argumentArray = false;
    if (argc >= 6) napi_is_array(env, args[5], &argumentArray);
    if (argumentArray) {
        uint32_t length = 0;
        napi_get_array_length(env, args[5], &length);
        for (uint32_t index = 0; index < length; index++) {
            napi_value item;
            napi_get_element(env, args[5], index, &item);
            size_t size = 0;
            napi_get_value_string_utf8(env, item, nullptr, 0, &size);
            std::string value(size + 1, '\0');
            napi_get_value_string_utf8(env, item, value.data(), value.size(), &size);
            value.resize(size);
            launchArguments.push_back(value);
        }
    }
    bool singleAppRoot = false;
    if (argc >= 7) napi_get_value_bool(env, args[6], &singleAppRoot);

    std::string homeDir(homePath);
    if (homeDir.empty()) homeDir = gBrokerHomeDir;
    if (homeDir.empty()) homeDir = "/storage/Users/currentUser/Download/com.vintage.pomelopro";

    std::string exePath(wineExe);
    {
        std::string lower = exePath;
        for (auto& c : lower) c = tolower(c);
        if (lower.find("/drive_c/") != std::string::npos) {
            auto slash = exePath.find_last_of('/');
            if (slash != std::string::npos) exePath = exePath.substr(slash + 1);
        }
    }

    const pid_t existingPid = FindRunningProcessByPath(wineExe);
    if (existingPid > 0) {
        const std::string existingSession = FindSessionIdForClientPid(existingPid);
        OH_LOG_INFO(LOG_APP, "[Wine] singleton reuse pid=%{public}d exe=%{public}s",
                    existingPid, wineExe);
        return MakeLaunchResult(env, existingPid, existingSession, true);
    }

    OH_LOG_INFO(LOG_APP, "[Wine] runWineExe bin=%{public}s exe=%{public}s (final=%{public}s) home=%{public}s",
                binDir, wineExe, exePath.c_str(), homeDir.c_str());

    std::string sockStr(sockPath);
    auto pos = sockStr.find_last_of('/');
    std::string sockDir = (pos == std::string::npos) ? "/tmp" : sockStr.substr(0, pos);
    std::string sockName = (pos == std::string::npos) ? sockStr : sockStr.substr(pos + 1);

    int audioBootstrapFd = -1;  // broker 会为每个子进程创建 audio fd, 此处无需传递

    std::vector<std::string> wineEnv = BuildWineEnv(sockDir, sockName, libPath, binDir, audioBootstrapFd, homeDir);

    {
#ifdef __aarch64__
        std::string entryParams = std::string(binDir) + "|" +
            (singleAppRoot ? "__winehua_desktop__|" : "") + exePath;
#else
        std::string entryParams = std::string(binDir) + "|" +
            (singleAppRoot ? "__winehua_desktop__|" : "") + "wine|" + exePath;
#endif
        for (const auto& argument : launchArguments) entryParams += "|" + argument;
        entryParams += SerializeEnvToEntryParams(wineEnv);
        OH_LOG_INFO(LOG_APP, "[Wine] runWineExe via broker: %{public}s", entryParams.c_str());

        int broker_fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (broker_fd < 0) {
            OH_LOG_ERROR(LOG_APP, "[Wine] broker socket failed: %{public}s", strerror(errno));
            if (gStateTsfn) napi_call_threadsafe_function(gStateTsfn, strdup("-1:wine-failed"), napi_tsfn_blocking);
            return MakeLaunchResult(env, -1, "", false);
        }
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strcpy(addr.sun_path, getenv("PROCESSBROKER"));
        if (connect(broker_fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
            OH_LOG_ERROR(LOG_APP, "[Wine] broker connect failed: %{public}s", strerror(errno));
            close(broker_fd);
            if (gStateTsfn) napi_call_threadsafe_function(gStateTsfn, strdup("-1:wine-failed"), napi_tsfn_blocking);
            return MakeLaunchResult(env, -1, "", false);
        }

        char req_hdr[32];
        int hdr_len = snprintf(req_hdr, sizeof(req_hdr), "SPAWN\n");
        size_t ep_len = entryParams.size();
        struct iovec iov[3] = {
            {req_hdr, (size_t)hdr_len},
            {(void*)entryParams.c_str(), ep_len},
            {(void*)"\n", 1}
        };
        struct msghdr msg = {};
        msg.msg_iov = iov;
        msg.msg_iovlen = 3;

        if (sendmsg(broker_fd, &msg, MSG_NOSIGNAL) < 0) {
            OH_LOG_ERROR(LOG_APP, "[Wine] broker sendmsg failed: %{public}s", strerror(errno));
            close(broker_fd);
            if (gStateTsfn) napi_call_threadsafe_function(gStateTsfn, strdup("-1:wine-failed"), napi_tsfn_blocking);
            return MakeLaunchResult(env, -1, "", false);
        }

        int32_t response[2] = {-1, -1};
        ssize_t n = recv(broker_fd, response, sizeof(response), MSG_WAITALL);
        close(broker_fd);
        if (n != sizeof(response) || response[1] != 0 || response[0] <= 0) {
            OH_LOG_ERROR(LOG_APP, "[Wine] broker spawn failed pid=%{public}d status=%{public}d", response[0], response[1]);
            if (gStateTsfn) napi_call_threadsafe_function(gStateTsfn, strdup("-1:wine-failed"), napi_tsfn_blocking);
            return MakeLaunchResult(env, -1, "", false);
        }

        pid_t pid = response[0];
        const std::string sessionId = "wine-" + std::to_string(pid);
        AddProcess(pid, wineExe, -1, sessionId);
        OH_LOG_INFO(LOG_APP, "[Wine] wine pid=%{public}d exe=%{public}s (via broker)", pid, wineExe);
        if (gStateTsfn) {
            char msg[64];
            snprintf(msg, sizeof(msg), "%d:wine-running", pid);
            napi_call_threadsafe_function(gStateTsfn, strdup(msg), napi_tsfn_blocking);
        }
        return MakeLaunchResult(env, pid, sessionId, false);
    }
}

napi_value RunWineExeLegacy(napi_env env, napi_callback_info info) {
    napi_value result = RunWineExe(env, info);
    napi_value pid;
    if (napi_get_named_property(env, result, "pid", &pid) != napi_ok) {
        napi_create_int32(env, -1, &pid);
    }
    return pid;
}
