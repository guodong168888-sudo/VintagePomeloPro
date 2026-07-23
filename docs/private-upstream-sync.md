# 私有分支上游同步记录

目标分支：`private/wine-engine-app`

基线：WineHua `VintagePomeloMaster` @ `ba7218a`

## 2026-07-18 私有基线

- 来源：本地 `VintagePomeloMaster` @ `ba7218a`
- 纳入：1.0.5 配置与品牌图标、guest-gfx 修复、项目构建技能。
- 目的：在不移动现有分支的前提下建立 VintagePomeloPro 私有主工程。
- 验证：原工作区状态/diff、现有分支指针、`origin` 和 `.gitmodules` 均保持不变。

## 上游提交

### 2026-07-18 Wayland 窗口与图形修复

| 上游 SHA | 私有分支 SHA | 范围 | 选择原因 | 合并结果 |
| --- | --- | --- | --- | --- |
| `f5ad791` | `d998e83` | Wayland popup、ArkUI 子窗口 | 修复 PC 模式弹出菜单被窗口边缘裁剪 | 与双显示模式的 `DisplayMode` 导入合并，保留 popup 管理器和单应用模式 |
| `7f6b0ae` | `3548ae8` | Wayland/EGL alpha 合成 | 支持 Pad 端异型窗口透明混合 | 无冲突同步 |
| `4b0c3db` | `8effc60` | PC ARGB 子窗口、窗口 mask、NAPI | 支持分层/异型窗口并保留 popup 回退宿主 | 合并 `sessionId/clientPid` 归属；PC 窗口延迟到首帧分类，桌面/单应用合成继续携带完整会话信息 |
| `2afd8bf` | `133464e` | EGL overlay、Wayland z-order 与输入命中 | 修复桌面模式 zero-copy 内容错误置顶及点击命中 | 无冲突同步 |

- 跳过：品牌、发布、实验性首页和与 Wine 引擎化无关的提交。
- 子模块：未更新 gitlink，未修改 `.gitmodules` 或第三方 URL。
- 静态验证：冲突标记清除，`git diff --check` 通过。
- 构建验证：Docker 中 API 22 ARM64 `assembleHap` 成功，CMake/Ninja、ArkTS 和 HAP 打包均通过；包内仅含 `arm64-v8a` 原生库，并包含 Wine/Box64/guest gfx 运行时。
- 规则验证：目录与模型规则测试 15 项通过，覆盖 EXE 选择、封面优先级、路径规范化、稳定卡片 ID、显示模式和引擎状态转换。
- 签名验证：release HAP 使用 v3 签名块，官方 `hap-sign-tool verify-app` 验证 26 个 ARM64 原生库、证书链和 SHA-256 摘要通过。
- 真机状态：本轮 HDC 无在线目标，因此未执行安装与真机 UI/输入回归；产物已完成构建、release 签名和离线验签。

后续仍仅接受 Wine/Box64、Wayland、图形/音频/输入、HarmonyOS API 或构建运行时修复；每个提交继续在此记录来源 SHA、文件范围、选择原因和验证结果。

### 2026-07-23 PR #34 手机与 TV 运行后端

- 来源：WineHua PR #34，提交 `516c420`、`5c56bfc`、`3a80575`。
- 目标分支：`feature/phone_support`，基于私有 `main` 的 `2d0ceac`。
- 纳入：phone/TV 的 fork NativeChildProcess 后端、phone 横竖屏尺寸同步、TV 设备声明，以及设备能力分流。
- 设备范围：fork 后端仅在 `phone` 和 `tv` 启用；`tablet` 保持原桌面合成路径；`2in1` 和 `pc` 继续使用系统 NCP、Binder 和独立 Wine 窗口。
- 图形调整：未采用 `3a80575` 的 VirGL socketpair Surface relay 和 shm 降级。phone/TV 改为在应用进程的专用线程中运行 VirGL host，并通过窄 C 接口直接绑定现有 `OHNativeWindow`；帧仍提交到 SurfaceQueue/NativeBuffer。保留的 Unix socket 仅承载 x86_64 guest Mesa 与 VirGL/vtest host 之间的命令和资源协议。
- 隔离：Wine/wineserver 仍由 fork shim 在子进程运行；VirGL 不通过 fork shim。未修改任何子模块 URL、gitlink 或第三方源码。
- 静态验证：`git diff --check` 通过；ARM64 和 x86_64 的 `libvirgl_child.so` 均导出五个进程内控制符号，`libentry.so` 均不静态依赖 `libvirgl_child.so`。
- 规则验证：目录与模型规则测试 24 项通过。
- 构建验证：使用 `winehua-dev` 和 Makefile Docker 链路分别完成 API 23 x86_64 与 ARM64 Debug HAP；两者均启用 `BUILD_GUEST_GFX=1`，guest ABI 均为 x86_64。
- 包验证：两个 HAP 均为 `com.vintage.pomelopro` 1.0.8、单一目标 ABI，并包含 guest Mesa/VirGL 环境、`virtio_gpu_dri.so`、图形 smoke 和音频 smoke；官方签名工具验证通过。
- 未覆盖：phone/TV 真机上的 fork Wine、旋转、VirGL 重绘和触摸输入仍需设备回归，不能用 x86 模拟器或 ARM 平板结果替代。
