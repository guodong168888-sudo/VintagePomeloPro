# 私有分支上游同步记录

目标分支：`private/wine-engine-app`

基线：WineHua `VintagePomeloMaster` @ `ba7218a`

> **同步基线标记**：最新合并到的上游 SHA 见 [UPSTREAM_SYNC_POINT.md](UPSTREAM_SYNC_POINT.md)（当前为 WineHua `master` @ `1036ada`）。下次同步先 `git log 1036ada..origin/master --oneline`，避免重复合并。

### 2026-08-09 版本 1.1.7：sRGB、游戏鼠标与虚拟输入方案

- 上游核对：`git fetch origin` 后 WineHua `master` 仍为 `1036ada`，本轮没有新的
  WineHua 主仓提交需要合并。
- VirGL：通用修复提交到 `winehua/virglrenderer`
  `fix/vrend-srgb-write-policy` @ `f49d7da6`；父仓 `a8c9d68` 更新 gitlink。
  策略由首个相关 framebuffer 一次性选择 RGBA preserve 或 XRGB 软件编码，后到
  的无关附件不能反向污染。无游戏、路径、GPU 或设备特判。
- 游戏鼠标：`b8167cf` 统一 overlay window 坐标；empty-input 呈现 subsurface
  穿透父 toplevel；relative-pointer 按 client/surface 路由并在坐标空间切换时
  首帧 rebase；fullscreen 取消/延迟系统窗口 raise。
- 虚拟输入：`7b1c391` 增加通用、全键盘、RPG、射击、动作五套模板；方案弹窗、
  新建命名、重命名/删除、自适应手机/平板布局，以及 Shift/Ctrl 锁定模式。
- 验证：输入模型测试通过；宿主几何 52 项通过；Docker ARM64 API 23 HAP 构建
  成功并覆盖安装；用户真机确认 PAL4、PAL5（含房屋材质）、灰色的果实、游戏内
  鼠标和新输入方案均正常。完整维护边界见
  `PRIVATE_1_1_7_RELEASE_AND_MERGE_MEMO.md`。

### 2026-08-06 合成器 Layer 重构全链合并（d9c667e..1036ada + 先前暂缓链）

- 分支：`feature/20260803-master-sync`（基于 1.1.5 前 `ac788e0`）。
- 背景：`d9c667e` 之后的 5 个提交（`94077be` 方案B 单一 Z 序命中、`2386c5f` 几何收敛、`7a59c00`/`c35ac03` 层序/blit 收敛、`1036ada` 文档）依赖此前两轮「暂缓」的合成器重构链，故本次把整条链按序 cherry-pick -x 合入：

  | 上游 SHA | 私有 SHA | 说明 |
  | --- | --- | --- |
  | `76a2cd4` | `810e632` | 阶段1 Layer 容器（合成/输入同源层序） |
  | `d5deed7` | `2024706` | 阶段2 ZC 入层（GL 画面可被遮挡） |
  | `6df338a` | `9b3a8ed` | 阶段3 PC 窗口内 Layer 收敛 + ZC 状态单一化 |
  | `c2bd0ee` | `ad12797` | 阶段4 全屏目标单一化（fs-pick 纯函数） |
  | `8ab97c3` | `fdf4c5e` | 层序跳过规则与全屏几何收敛到对象方法 |
  | `13cc583` | `fbe84d2` | ToplevelState 完整封装（字段私有 + 语义方法） |
  | `94077be` | `d63e63d` | 方案B 单一 Z 序命中循环统一输入命中 |
  | `2386c5f` | `a1218fe` | 几何收敛 FitMapLayerRect + ResolveRootSize |
  | `7a59c00` | `0443ea0` | ShouldSkipFullscreenCascade 谓词统一连带跳过 |
  | `c35ac03` | `88ff56b` | 像素 blit 收敛 BlitClipAlpha（阶段3a） |
  | `1036ada` | `6fdb30d` | 文档：固化全屏判定两套语义 |

- 冲突处理（2 处）：
  - `94077be`：私有线 2026-08-05 手移的 `e5cd7fa`「前置命中」分支被上游方案B 取代 → `input_resolver.cpp/.h` 直接采用上游版本（校验与上游逐字节一致），删除前置命中块。
  - `7a59c00`：`desktop_compositor.cpp` blitSubsurface 的连带 fullscreen 跳过条件改为统一的 `ShouldSkipFullscreenCascade` 谓词（与输入命中同源）。
- 跳过：链内 docs/checkpoint 提交（`c5e487e` `eaaeaeb` `6aaf6fd` `ea614cd` `4b82709` 及链外纯文档）不重复引入；`996aabb..d9c667e` 段已由上一轮同步覆盖。
- 私有保留：桌面全屏零拷贝、phone in-process VirGL、`@engine/` 核心进程登记、`desktop_root_manager` 语义均未受影响（本链只改合成/输入层内部）。
- 验证：`make hap`（winehua-dev 容器）构建成功，1.1.5/1001005 arm64 HAP 签名完成；`git diff --check` 通过；子模块 gitlink 无变化。

### 2026-08-05 增量同步（996aabb..d9c667e）

- 分支：`feature/20260803-master-sync`（基于 1.1.4 `acaf19e`）。
- 上游增量 11 个提交，采纳 3 项（手动移植）：
  - `8fb8488` → broker.cpp 对全部 SPAWN 请求统一 `AddProcess`（explorer 内双击的 exe 进入任务列表），`ParseProcessName` 兼容 homeDir/binDir/`__winehua_*` 标记段；wine_process.cpp basename 兼容 `\` 反斜杠路径。私有 Index 已有 1.5s 轮询刷新，未做 process-updated 推送节流（后续可加）。
  - `e5cd7fa` → 私有 `input_resolver.cpp` 全屏独占分支前加入前置命中：遍历 z-order 中高于全屏窗口的 toplevel 及其 subsurface（跳过连带 fullscreen 的旧窗口，与渲染侧对齐），修复"全屏游戏时新窗口/菜单显示在上方但点击回到游戏"。
  - `bb617a4` 部分 → `wine_env.cpp` 的 `UpsertEnvLine` 改为"删除全部同 key 再追加"，避免 AppendProductDxvkEnv 覆盖 WEAKBARRIER 等产生重复 key。
- 跳过并记录：`7ed8ad2`（dinput_click_probe 私有 wine 子模块已含）、`faf98af`（私有 CI 已装 curl，mono 下载成功）、`d3688e1`（BOX64 守卫私有已有）、`d9c667e`（私有 `@engine/explorer` 登记体系语义不同）、docs/版本号（`c5263a3` `82ee3f3` `1dc0283` `70abb0b`）。
- 验证：`make hap`（winehua-dev 容器）构建成功，1.1.4/1001004 arm64 HAP 签名完成。

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

### 2026-08-03/04 真机验证三项修复（平板 API 24）

- 装机方式：因签名不一致先卸载再安装 debug HAP（games 目录在共享 Download，不受影响；Wine prefix 重建）。
- Fix 1（卡片二次启动/唤起）：`created` 事件携带 `sessionId/clientPid` 后，运行中再点卡片正确唤起（`onNewWant` 指向新 toplevel）；杀死后重新启动正常，引擎全程 READY。
- Fix 2（切边/圆角避让，最终方案）：切边=沉浸全屏（隐藏系统栏）+ **只缩左右宽度、高度充满**，边距按设备自动估算（显示短边 5%，夹 40–100px；本机 2560×1600 → 80px）；explorer 启动前预置输出 1200×800，任务栏/开始按钮出生即在正确位置；XComponent 与输入覆盖层（InputOverlay）同步左右内缩，虚拟鼠标/触摸坐标与 surface 对齐（点开始按钮成功弹出开始菜单）。
- Fix 3（杀进程联动+桌面保活）：`KillProcessTree` 杀整树 + 立即触发 toplevel destroyed；wineserver/explorer 登记为 `@engine/` 核心进程，用户程序退出/被杀后注册表保持非空 → 引擎保持 READY、桌面不拆。
- 构建：`scripts/vpbuild.sh` 复用常驻容器 `vp-build`（不再每次 docker run 新建容器）；Docker `winehua-dev` ARM64 Debug HAP 验签通过。
- 产物：`F:\PomeloWin\artifacts\VintagePomeloPro-1.1.2-master-sync-20260803\旧柚Pro-1.1.2-master-sync-automargin.hap`。
- 结论：用户真机确认“好用”，本地提交当前版本（`644f6de`），未推送。

### 2026-08-04 二次 master 更新 + DXVK 方针对齐 + 版本 1.1.3

- 上游合并（996aabb..origin/master 共 6 提交，选 2 合 4 跳过）：
  - `d3688e1` → `fd98cbb`：所有 BOX64 环境变量加 `__aarch64__` 守卫（修复 x86_64 USE_LIBBOX64 导致 broker entryParams 错乱）；私有 `AppendProductDxvkEnv` 内的 BOX64 变量同步加守卫；
  - `7ed8ad2` → `5afcaaf`：dinput_click_probe 迁移到 wine 子模块，wine gitlink `3a69dcad` → `11e59500210`（线性后代，仅新增探针）；已重建 wine；
  - 跳过：`70abb0b`（上游版本号）、`1dc0283`（LGPL 文档）、`82ee3f3`/`c5263a3`（docs/.gitignore）。
- DXVK/VirGL 方针对齐（`1dbed33`）：DXVK override 从全 D3D native 改回 master 的 `d3d11=n;dxgi=n`。原因：Venus/Maleoon 栈上 DXVK 对 DX9/10 兼容性弱于 WineD3D→GL→VirGL，全 D3D 走 DXVK 会破坏 VirGL 驱动游戏；上游评估文档亦确认 Maleoon 910/920 达不到 DXVK 2.x 基线，Modern 仅作独立 profile 待能力门禁。真机回归：D3D11 立方体 dxvk_legacy 80+ FPS 正常。
- 版本：1.1.3（1001003）。
- 产物：`F:\PomeloWin\artifacts\VintagePomeloPro-1.1.3-20260804\`（debug HAP `74F18840…`、release APP `02A6599A…`、release entry HAP `EB159976…`，均验签 Verify success）。
