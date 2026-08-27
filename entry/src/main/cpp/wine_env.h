#ifndef WINE_ENV_H
#define WINE_ENV_H

/**
 * wine_env.h — Wine 环境变量设置
 */

#include <cstdlib>
#include <string>
#include <vector>

#include "wine_constants.h"

/**
 * BOX64_EMULATED_LIBS 完整列表 (ARM64 真机)。
 *
 * 除图形/输入栈外, gnutls (schannel TLS) 与 gstreamer (winegstreamer)
 * 链的 guest 库都是 x86_64 ELF, 必须由 box64 模拟执行。若不列出,
 * box64 会按 native (arm64 dlopen) 加载, 对 x86_64 目标报
 * "Error initializing native lib...: No such file" — IE/网络走 schannel
 * 时 gnutls 加载失败, HTML 渲染则依赖 Wine Gecko (独立组件)。
 * 与运行时 wine/bin/x86_64-unix 下实际部署的 .so 保持一致。
 */
static inline std::string Box64EmulatedLibs()
{
    return "libvulkan.so:libvulkan.so.1:"
           "libEGL.so:libEGL.so.1:libGLESv2.so:libGLESv2.so.2:"
           "libGLESv1_CM.so:libGLESv1_CM.so.1:libGL.so:libGL.so.1:"
           "libwayland-client.so:libwayland-client.so.0:libwayland-server.so:"
           "libwayland-server.so.0:libwayland-egl.so:libwayland-egl.so.1:"
           "libdrm.so:libdrm.so.2:libffi.so:libffi.so.8:"
           // gnutls 链 (schannel TLS)
           "libgnutls.so:libgnutls.so.30:"
           "libnettle.so:libnettle.so.8:"
           "libhogweed.so:libhogweed.so.6:"
           "libgmp.so:libgmp.so.10:"
           "libtasn1.so:libtasn1.so.6:"
           "libunistring.so:libunistring.so.5:"
           // glib 链
           "libglib-2.0.so:libglib-2.0.so.0:"
           "libgobject-2.0.so:libgobject-2.0.so.0:"
           "libgio-2.0.so:libgio-2.0.so.0:"
           "libgmodule-2.0.so:libgmodule-2.0.so.0:"
           // gstreamer 链 (winegstreamer)
           "libgstreamer-1.0.so:libgstreamer-1.0.so.0:"
           "libgstbase-1.0.so:libgstbase-1.0.so.0:"
           "libgstvideo-1.0.so:libgstvideo-1.0.so.0:"
           "libgstaudio-1.0.so:libgstaudio-1.0.so.0:"
           "libgsttag-1.0.so:libgsttag-1.0.so.0:"
           "libgstpbutils-1.0.so:libgstpbutils-1.0.so.0:"
           "libgstallocators-1.0.so:libgstallocators-1.0.so.0:"
           "libgstapp-1.0.so:libgstapp-1.0.so.0:"
           "libgstcontroller-1.0.so:libgstcontroller-1.0.so.0:"
           "libgstfft-1.0.so:libgstfft-1.0.so.0:"
           "libgstnet-1.0.so:libgstnet-1.0.so.0:"
           "libgstriff-1.0.so:libgstriff-1.0.so.0:"
           "libgstrtp-1.0.so:libgstrtp-1.0.so.0:"
           "libgstrtsp-1.0.so:libgstrtsp-1.0.so.0:"
           "libgstsdp-1.0.so:libgstsdp-1.0.so.0:"
           // libgstcodecparsers: gst-plugins-bad videoparsersbad (h264parse 等)
           // 的依赖库; 不在列表时 box64 无法加载插件, GStreamer 报
           // "Failed to load plugin libgstvideoparsersbad.so"。
           "libgstcodecparsers-1.0.so:libgstcodecparsers-1.0.so.0:"
           // libgstmpegts: libgstmpegtsdemux (MPEG-TS) 的依赖库。
           "libgstmpegts-1.0.so:libgstmpegts-1.0.so.0:"
           // libxml2/libz: gst-plugins-bad 类插件 (libgstadaptivedemux2 等) 依赖。
           // 不在列表时 box64 重定位其版本化符号 (LIBXML2_2.9.0) 失败,
           // 插件 dlopen 失败, GStreamer 报 "Failed to load plugin"。
           "libxml2.so:libxml2.so.2:"
           "libz.so:libz.so.1";
}

// -- Box64 性能调优 (static inline, 供 napi_init / wine_child 共用) --
#ifdef __aarch64__
static inline void SetBox64PerfEnv() {
    setenv("BOX64_LOG", "0", 1);
    setenv("BOX64_NOBANNER", "1", 1);
    setenv("BOX64_SHOWSEGV", "1", 1);
    // Keep Box64's compatibility default. Forcing 0 breaks code that observes
    // x86 flags across translated blocks, including protected startup code.
    setenv("BOX64_DYNAREC_SAFEFLAGS", "1", 1);
    setenv("BOX64_DYNAREC_BIGBLOCK", "3", 1);
    setenv("BOX64_DYNAREC_CALLRET", "2", 1);
    setenv("BOX64_DYNAREC_FORWARD", "1024", 1);
    setenv("BOX64_DYNAREC_WEAKBARRIER", "2", 1);
    setenv("BOX64_AVX", "0", 1);
    // Box64 0.4.3 的 dynarec 对 AES-NI/PCLMULQDQ (GnuTLS AES-GCM 加速路径)
    // 的翻译有误: 解密得到乱码 (HTTPS 12152/400) 或 access violation。
    // 关闭模拟 cpuid 中的这两个特性位后, GnuTLS/nettle 回退纯 C 实现,
    // dynarec 对普通标量代码翻译正确, TLS 即恢复正常 (2026-08 实测)。
    setenv("BOX64_AES", "0", 1);
    setenv("BOX64_PCLMULQDQ", "0", 1);
    // 关闭 box64 的 PE Volatile Metadata 解析 (默认开启), 原因:
    // box64 的 my_mmap64 (wrappedlibc.c) 对 Wine 每个首次 mmap 的文件调用
    // ParseVolatileMetadata (src/tools/pe_tools.c), 该函数只校验 MZ 魔数、
    // 不校验 e_lfanew 边界。DOS/16位 MZ 可执行文件 (非 PE, 如仙剑 DOS 版的
    // PAL!.EXE / DJGPP 工具 exe) 的 0x3C 处是 DOS stub 文本 (" by "/"mail"),
    // 被当作 e_lfanew 偏移 → base+~545MB 越界解引用 → 宿主侧 SIGSEGV →
    // 被 Wine SEH 当客体异常恢复, 撕裂 my_mmap64 宿主调用栈 → explorer
    // 浏览含 DOS exe 的目录 (图标提取逐个 mmap) 连炸后挂死 (2026-07 实测)。
    // 副作用≈0: 本项目 STRONGMEM=0, 该元数据唯一生效消费点是给新 MSVC
    // (2019 16.10+) 编译的 PE 标注点额外加 DMB_ISHST 屏障 (正确性增强,
    // 非性能优化); 老游戏无此元数据, lock/原子指令走独立路径不受影响。
    // 若日后 fork 内给 pe_tools.c 补上边界检查, 可移除此行重新启用。
    setenv("BOX64_DYNAREC_VOLATILE_METADATA", "0", 1);
}

inline void AppendBox64PerfStrings(std::vector<std::string>& env) {
    env.push_back("BOX64_LOG=0");
    env.push_back("BOX64_NOBANNER=1");
    env.push_back("BOX64_SHOWSEGV=1");
    env.push_back("BOX64_DYNAREC_SAFEFLAGS=1");
    env.push_back("BOX64_DYNAREC_BIGBLOCK=3");
    env.push_back("BOX64_DYNAREC_CALLRET=2");
    env.push_back("BOX64_DYNAREC_FORWARD=1024");
    env.push_back("BOX64_DYNAREC_WEAKBARRIER=2");
    env.push_back("BOX64_AVX=0");
    // 与 SetBox64PerfEnv() 保持一致: 屏蔽模拟 cpuid 的 AES-NI/PCLMULQDQ,
    // 避免 Box64 dynarec 对 GnuTLS AES-GCM 加速路径的误译 (HTTPS 乱码/崩溃)。
    env.push_back("BOX64_AES=0");
    env.push_back("BOX64_PCLMULQDQ=0");
    // 关闭 Volatile Metadata 解析, 详细原因见上方 SetBox64PerfEnv() 注释
    // (box64 pe_tools.c 对 DOS MZ exe 无边界检查 → explorer 浏览目录挂死)
    env.push_back("BOX64_DYNAREC_VOLATILE_METADATA=0");
}
#else
static inline void SetBox64PerfEnv() {}
static inline void AppendBox64PerfStrings(std::vector<std::string>& env) { (void)env; }
#endif

// -- Wine 环境变量构建 --
std::vector<std::string> BuildWineEnv(const std::string& sockDir,
                                      const std::string& sockName,
                                      const std::string& libPath,
                                      const std::string& binDir,
                                      int audioBootstrapFd,
                                      const std::string& homeDir,
                                      const std::string& prefixDir = WINE_PREFIX);

// Add the managed product D3D backend overlay to a process environment. The
// caller selects the product backend once per Wine session; the default is
// dxvk_legacy, while wined3d remains an explicit compatibility fallback.
void AppendD3dBackendEnv(std::vector<std::string>& env,
                         const std::string& d3dBackend,
                         const std::string& binDir);

// C:\smoke gears/triangle only. Cube keeps the DXVK DIR0 overlay; these
// demos need vkd3d-first WINEDLLDIR plus the qualified D3D12 present path
// or Venus presents an empty (black) window.
bool IsVkd3dSmokeDemo(const std::string& exePath);
void AppendVkd3dDemoPresentEnv(std::vector<std::string>& env,
                               const std::string& d3dBackend,
                               const std::string& binDir);

// Add the stable production DXVK policy shared by Explorer descendants and
// applications launched directly from an Old Pomelo app card. Diagnostics
// may provide a specific performance profile; an empty profile selects the
// qualified product default.
void AppendProductDxvkEnv(std::vector<std::string>& env,
                          const std::string& d3dBackend,
                          const std::string& perfProfile = "");

// 覆盖式追加: 清理同 key 旧条目后追加新值 (graphics_broker 等跨文件使用)
void UpsertEnvLine(std::vector<std::string>& env, const std::string& line);

// -- Audio bootstrap --
int CreateAudioBootstrapFd(const std::string& runtimeDir);

// -- entryParams 序列化 (实现收口到 EnvSpec; AppendMissing 仍服务 explorer NCP 补键) --
size_t AppendMissingEntryParamsEnvOverrides(std::string& entryParams,
                                            const std::vector<std::string>& env);
std::string SerializeEnvToEntryParams(const std::vector<std::string>& env);

// -- Graphics 辅助 --
void LogGraphicsBackendStateForLaunch(const char* tag);

#endif // WINE_ENV_H
