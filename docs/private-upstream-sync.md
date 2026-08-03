# 私有分支上游同步记录

目标分支：`private/wine-engine-app`

基线：WineHua `VintagePomeloMaster` @ `ba7218a`

> **同步基线标记**：最新合并到的上游 SHA 见 [UPSTREAM_SYNC_POINT.md](UPSTREAM_SYNC_POINT.md)（当前为 WineHua `master` @ `996aabb`）。下次同步先 `git log 996aabb..origin/master --oneline`，避免重复合并。

### 2026-08-03 二次合并：warm-prefix explorer 恢复修复

- 上游 `996aabb` → 私有 `f2f9cfe`（cherry-pick -x，仅 CI workflow 冲突且保留私有侧）：
  - 温前缀（prefix 已初始化）时显式用干净 NCP 环境跑 `wineboot --init`，播种 boot 事件，避免 explorer 首客户端触发的 wineboot 卡死导致后续所有 Wine 进程阻塞在 boot-event 等待（与私有线"二次启动无窗口/所有卡片失效"现象同源）；
  - 非桌面模式自动 explorer 改为走 `SpawnWineProgram`（broker 通道），与手动启动路径一致；
  - `scripts/build_deps.sh`：BUILD_WINE_MONO 默认启用（`BUILD_WINE_MONO=0` 跳过），与私有打包约定一致。
- 暂缓/跳过：`13cc583` `8ab97c3`（合成器重构延续，私有 compositor 冲突）、`82ee3f3`（docs）、`c5263a3`（.gitignore）。

### 2026-08-03 三项修复 + 合并 Aug 3 输入提交

- 分支：`feature/20260803-master-sync`（基于 `private/wine-engine-app` `b66318b`）。
- 上游同步：合并 Aug 3 `8089968`（zwp_relative_pointer_v1 取代 warp 补偿，修红警2光标偏移/PAL2点击瞬移）→ 私有 `0e2a86e`，无冲突 cherry-pick（本地输入代码与上游父提交一致）。
- 排除记录：合成器 Layer 重构（阶段 1-4 `76a2cd4` `d5deed7` `6df338a` `c2bd0ee`）与本地私有 compositor 架构（桌面全屏零拷贝、phone in-process VirGL 直连）冲突大、与三项修复无关，维持暂缓；Aug 1-2 输入/mono/字体提交本地已有等价实现，不重复合并。
- 三项修复：
  - `e837ceb` Fix 1：删除 `RunWineExe` 的残留单例复用（进程退出后登记未清 → 二次启动返回死 pid）。对齐 master，每次经 broker 新建；ArkTS `result.reused` 分支恒 false 安全。
  - `10105b5` Fix 2：新增全局设置 `desktopWindowMode`（全屏/切边安全区）。圆角屏全屏遮挡开始菜单；平板默认切边，`DesktopAbility` 按设置应用 `setWindowLayoutFullScreen` + 系统栏显隐，并在窗口再次打开时重应用。
  - `ab4fdab` Fix 3：停止程序改为杀死整棵 wine/box64 进程树（`KillProcessTree`，后代先杀再杀根），并立即触发 Wayland toplevel `destroyed` 事件 + `pid:exited` 状态消息，使 ArkTS 关窗与运行状态即时联动，不依赖断连异步时序。
- 构建验证：目录/模型单测 34 项通过；Docker `winehua-dev` ARM64 Debug HAP（API 23、`com.vintage.pomelopro` 1.1.2/1001002、旧柚Pro、仅 arm64）打包+签名成功；包内 guest-gfx、图形/音频 smoke、wine-mono-11.1.0 msi、dxvk legacy x64/x86 全量 DLL 完整；`hap-sign-tool.jar verify-app` 验签通过。
- 产物：`F:\PomeloWin\artifacts\VintagePomeloPro-1.1.2-master-sync-20260803\旧柚Pro-1.1.2-master-sync.hap`，SHA-256 `021FB252CF69D420CDFCD09CA3F5299950DAB2D95B7F043519A0946695BB8A60`。
- 未覆盖：平板当前离线，未做真机回归（二次运行/切边显示/杀死联动三项仅代码与包级别验证）；合入 `private/wine-engine-app` 并推送 `VintagePomeloPro:main`。

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

### 2026-07-27 桌面全屏合成器与自动构建

| 上游 SHA | 私有分支 SHA | 范围 | 选择原因 | 合并结果 |
| --- | --- | --- | --- | --- |
| `c00efd8` | `ca10e8c` | Docker 构建配置与签名挂载 | 让自动/容器构建可导入用户配置 | 无冲突同步 |
| `954730e` | `2d5f754` | GitHub Actions 无签名 HAP 构建 | 提供上游自动构建 | 无冲突同步 |
| `a287fe5` | `df8d913` | 合成器模块化与 Wine OHOS 适配 | 是后续全屏渲染与输入修复的基础 | 采用新的桌面合成器；保留私有 NCP shim、应用内 VirGL、手柄桥接与旧柚桌面输入页 |
| `42eb250` | `ac75ed9` | app_id 语义与 ghost desktop-shell 过滤 | 防止 Explorer/桌面壳窗口参与错误命中 | 同步并更新 Wine gitlink |
| `68555ed` | `e352950` | 桌面全屏零拷贝、warp 与 pointer constraints | 修复全屏比例、黑边点击和 dinput 贴边 | 无冲突同步 |
| `ed8dcac` | `e747937` | 全屏前台优先级 | 修复旧窗口连带全屏抢输入 | 无冲突同步 |
| `65cc779` | `9581efd` | Wine shell32 desktop.ini CLSID 回退 | 修复 Explorer 文件夹处理回退 | 子模块无共同线性祖先，已明确切至已审查提交 |

- 跳过：`7d9c7ec` 的 wine32 构建改动已等价存在；`c8e94b3` 会将手机 VirGL 改为 fork/socket relay，违背私有分支保留的应用内直连 Surface 架构；`3331df7` 会把产品版本倒退到 1.0.3。
- 冲突处理：保留旧柚 Pro 的 ArkTS 页面、设备分流和 `ncp_shim`；采用新的桌面合成器、全屏输入/渲染栈和 Wine 适配。
- 验证：目录与模型单元测试 24 项通过；Docker/Makefile ARM64 Debug HAP 构建成功，目标/兼容 API 均为 23，guest ABI 为 x86_64。包内包含 ARM64 的 Box64、entry、wine child、VirGL/Wayland 运行库和 `wine-data.zip`；嵌套运行时包含 guest-gfx 环境、EGL、virtio GPU 驱动及图形/音频 smoke。官方签名工具验证通过。
- 兼容修复：私有 ArkTS 仍调用 `setDisplayScale`，上游合成器已从 `EglRenderer` 移除全局缩放。该 NAPI 导出保留为兼容空操作，实际渲染和输入变换由新合成器测量输出几何统一计算。
- 未覆盖：尚未在物理 ARM 设备上回归零拷贝全屏、pointer warp/constraints 与私有手机应用内 VirGL；不能由本次离线构建替代。

### 2026-08-02 dxvk 1.10.3 合并（版本 1.1.2 / 1001002）

- 来源：WineHua `origin/master` `0ed802c`，按时间序 cherry-pick 36 个提交（dxvk legacy 1.10.3 phase-2、Venus 呈现/阴影上传优化、wine/PE 修复、d3d8 兼容子模块指针、guest-gfx/guest-vulkan 打包等），2 个跳过（`86838e2`、`6d64109`，仅改上游 Index/DesktopWindow 页）。14 个子模块 gitlink 与上游一致（dxvk=`abe71bc` v1.10.3-28；wine/mesa/virglrenderer=d3d8 兼容分支提交）。
- 架构取舍：native 层对齐上游最终版；私有文件保留（`game_controller_bridge.*`、`ncp_shim/*`）；UI 与私有运行时 API 恢复自产品线（test 分支）——`runWineExe`（含 sessionId）、`checkWinePrefix`、`setForkNcpEnabled`、手柄回调等导出保留。
- 关键修复（均为设备实测驱动）：
  - 打包：DXVK Legacy 全量 DLL（d3d9/d3d10core/d3d10/d3d10_1/d3d11/dxgi ×x64/x86）、`bin/Alarm01.wav`、`bin/x86_64-windows` smoke 必须齐备，否则引擎初始化失败；
  - wine-mono 11.1.0 与 `appwiz.cpl` 必须同包（缺失时 wineboot 弹框阻塞前缀初始化，导致音频驱动/图标缓存缺失）；assemble 增加守卫；
  - DXVK 性能：启动前 `setHostShadowProfile('shadow-precise-dirty-ring-inline-upload-coverage-sort')`，立方体 4 FPS → 84 FPS；
  - games 目录：`bundleManager.getBundleInfoForSelfSync` 动态取包名 + 写探针，杜绝硬编码/假 ready；
  - 标题栏高度：`componentUtils.getRectangleById('HdsTitleBar')` 运行时实测，替代硬编码。
- 验证：ARM64 Debug HAP（API 23、`com.vintage.pomelopro` 1.1.2/1001002、旧柚Pro、仅 arm64、guest-gfx+dxvk+mono 载荷完整，官方签名工具验签通过）；平板上引擎 READY、桌面 100+ FPS、DXVK 立方体 84 FPS、干净安装后音频与 Wine 内 EXE 图标恢复。
- 发布：合入 `private/wine-engine-app` 并显式推送到 `VintagePomeloPro:main`（版本 1.1.2）。
