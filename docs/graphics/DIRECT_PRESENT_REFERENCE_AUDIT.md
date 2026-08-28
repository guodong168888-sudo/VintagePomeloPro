# Direct Present 参考分支审计

## 参考范围

- 参考仓库：`winehua/WineHua`
- 参考分支：`opt/nativewindow-direct-present`
- 审计分支头：`3cb84963ef4f3ceae540ee8c0374e3819dfa048c`
- WineHua `master`：`90edaae3e3ec6f4a9201fd8f7e6d5ae04349d60f`
- 分叉基点：`e382b4d3c7bd0b1aac8c683fb409212ae009dd54`

该实验分支相对 `master` 有 82 个独有提交、落后 30 个提交，包含 VKD3D、cnc-ddraw、CI、UI 和大量 probe 代码。因此不能整分支合并，也不能把旧 cherry-pick 顺序当成当前 `main` 的移植配方。

## Direct Present 核心提交

- `e646e74`：为 VirGL 与 Venus 引入 NativeWindow Direct Render、Host probe、present timeline，并移动 Mesa/VirGL gitlink。
- `3c3c3f6`：修正 DX11 动画帧序与 direct queue 行为，避免成功 Present 被时钟门禁丢弃后出现运动回退。
- `0d4ed2c`：预热后使用非阻塞 NativeWindow acquire，由 Guest 在下一次 Present 前等待 Host deadline；避免 RequestBuffer 与 NativeImage consumer 共享 timeout 引发阻塞。
- `103ad12`：将 VKD3D 与 DXVK 2.6 DXGI 配对，并按 D3D12 resource width 刷新持久映射 UPLOAD。

## 精确源码结论

本轮已通过 `127.0.0.1:8080` 临时代理把参考分支主体取到当前对象库，并直接审计
`FETCH_HEAD=3cb84963`；没有新增 remote、源码镜像或工作树。主仓库 fetch 成功，随后自动递归
子模块因旧的本机路径映射失败，但不影响上述四个主仓库提交与源码内容。

1. `e646e74` 新增的 `native_window_direct.cpp/.h` 是独立 NativeBuffer target，不是现有
   presenter 的小补丁。Vulkan 使用 `vkGetNativeBufferPropertiesOHOS`、`vkAcquireImageOHOS` 和
   `vkQueueSignalReleaseImageOHOS`；GLES 使用 `EGL_NATIVE_BUFFER_OHOS` 与 native fence。
2. Vulkan Direct 默认仍把 Guest source image 每帧 copy/blit 到导入的 NativeBuffer。主要收益是
   去掉 `vkAcquireNextImageKHR`/`vkQueuePresentKHR` 的 WSI 链和 Present 后 CPU fence wait，并把
   GPU release fence直接交给 `OH_NativeWindow_NativeWindowFlushBuffer`。
3. 真正 skip-copy 依赖 renderer/Guest scanout backing。VirGL 分支做过该轮换；Venus 路径在参考
   头中仍默认关闭，因为替换 Guest swapchain image 会让采样 backbuffer 的 DX11 游戏黑屏。
4. `0d4ed2c` 的队列规则不可拆开：前 24 帧允许 100 ms 首 buffer 分配，稳定后 `SET_TIMEOUT=0`；
   queue-full 立即返回并发布未来 Guest deadline，不能在持有 present mutex 时轮询。
5. 参考 target 用固定 8 槽 cache，主要按 NativeBuffer `seq` 命中，依靠 Configure 变化时整体
   Reset。当前 main 的正式实现要把 window generation、seq、extent、format 和 device identity
   纳入 cache owner/key，避免 resize、重连或句柄复用命中旧 image/memory。
6. 参考头同时保留 Direct、VirGL scanout、Venus scanout、glFinish、NativeImage drop、uncap 等
   多个环境/文件开关。它们是实验分支的探针，不应进入当前产品控制面。
7. 当前 Mesa 锁定提交 `2939cbb8` 不再实现参考分支的
   `VN_WINEHUA_PRESENT_ROUNDTRIP_ONLY` 开关。它在私有 `vn_winehua_present` 内无条件执行
   `vn_ring_roundtrip(dev->primary_ring)` 与 `vn_ring_wait_all(dev->primary_ring)`，然后才经 vtest
   socket 发出 Host Present 回调。注释明确该 drain 只等 renderer decode 与 Host
   `QueueSubmit` 调用完成，不等待 GPU 完成。因此 DP1 依赖的是现有固定排序契约，不需要恢复旧
   环境变量或新增 profile。
8. 当前 VirGLRenderer 锁定提交 `670ff196` 用 `queue_guard.locked` 保护 Host queue mutex。Presenter
   可在最后一个 Host queue API 返回后主动调用 `release_queue` 缩短锁持有时间；无论 Presenter 以
   成功、deferred 或错误返回，`vkr_renderer_winehua_present` 都会再次调用
   `vkr_winehua_release_queue(&queue_guard)` 兜底，guard使第二次调用无副作用。因此 DP1 的
   RequestBuffer queue-full/导入失败早退不会泄漏 Host queue mutex，成功路径则在
   `vkQueueSignalReleaseImageOHOS` 返回后立即释放。

DXVK 2.6 方面，参考分支与本轮优化起点的 `thirdparty/dxvk-modern` 基线都是 `977a3d78`；当前
工作分支在该基线上增加 WineHua mapped-flush 合并与 trace 热路径收敛提交 `ff2d6a2c`。因此
Direct Present 合并与 2.6/1.10 性能差距是两个相交但独立的项目：前者减少共同尾端成本，后者
仍需定位 Modern compatibility、mapped update、Host upload 或 Guest CPU 差异。

## 当前私有 main 的对应状态

本轮优化起点 `d73f299` 已有：

- `virgl_surface_presenter.cpp`：VirGL 纹理直接提交到 NativeWindow EGL surface。
- `venus_surface_presenter.cpp`：Venus source image 经 Host Vulkan copy/blit 提交到 NativeWindow swapchain。
- `virgl_child.cpp`：向 Guest 返回 `nextPresentDeadlineNs`。
- `graphics_broker.cpp`：传递 NativeWindow、surface key、frame period 和 presenter 类型。
- `native_window_lease.h`：统一 NCP parcel window 与进程内引用的释放语义。

当前实现不是参考分支 `native_window_direct.cpp` 的逐文件副本，而是后来拆分的 presenter 架构。直接覆盖会丢失 phone in-process attach、device release、GPU timeline 和现有 WSI 恢复逻辑。

## 已吸收的设计与本轮修正

本轮按语义移植，不按文件移植：

1. `present_pacing.h` 成为 VirGL/Venus 共用 deadline 算法，使用饱和加法避免边界溢出。
2. VirGL 只在 `eglSwapBuffers` 成功后推进 `lastPresentNs`，失败帧不再制造假的下一帧门禁。
3. Venus 的 fence/acquire/release timeout 返回 `1` 时必须携带未来 deadline，避免 Guest 无上限自旋。
4. Venus 保留 24 帧预热；之后不再用时钟门禁预先丢弃已完成的 Guest frame。
5. 预热 acquire 最长 100 ms；进入稳定队列后 acquire timeout 为 0，由 Guest deadline 节拍，而不是阻塞 NCP present 线程。
6. DXVK 1.10 与 2.6 使用同一个 Native resolver 和 Direct Present 策略，版本差异只保留在 runtime overlay 与必要兼容项。
7. Venus summary 分拆记录 `clock_deferred`、`acquire_deferred`、`fence_deferred` 和 `guest_deadline_frames`，用于证明实际执行的是预期动作，而不是只看平均 FPS。
8. WineD3D 显式解析到中性的 `product-virgl` Host route；不再落入 DXVK 默认分支，切换到 VirGL 时会覆盖上一会话残留的 Venus shadow 设置。
9. `103ad12` 的 VKD3D 持久映射修复已按相同 `3e5aab6` 基线逐字节移植：Map 与 Execute 阶段都按 D3D12 buffer `Width` 刷新，Execute 批量路径上限 4 MiB，不刷新 8–16 MiB 父分配。该行为由补丁哈希契约锁定，不新增产品开关。
10. DXVK runtime 目录、版本和 legacy compatibility 由同一 resolver 产生；VKD3D limited-500K 固定复用 DXVK 2.6.2 DXGI/Venus 环境，不再跟随用户会话落到 1.10.3，也不会在 WineD3D 模式下跳过。
11. VirGL/Venus 共用 4–33.333 ms 显示周期归一化和不穿越 4 ms 下限的 0.5 ms dispatch lead，删除两条 presenter 互相矛盾的局部实现。
12. 产品展示队列固定为 Vulkan WSI 保证支持的 FIFO，source release 固定同步 fence wait；已不可达的 mailbox、async 与 poll 控制分支不再参与正常或 LAB 动作。
13. WHIP v10 用原 present-mode 槽位承载二值 Host summary，使 `observe-product-summary` 同时覆盖 renderer、Presenter、Host 日志转发与 Guest；字段数仍为 11，没有新增组合开关。
14. Phase DP1 已在当前 presenter 架构中实现：`native_window_vk_target` 只拥有一个
    surface/device generation 的 NativeBuffer import；`VenusSurfaceQueueTarget` 每个 attach/device
    只探测一次 Direct 能力，支持则固定 Direct，不支持则锁定 FIFO WSI reason code。成功 Direct
    帧保留每帧 source→NativeBuffer copy/blit，但用 `vkQueueSignalReleaseImageOHOS` 产生的 GPU
    release fence直接 `FlushBuffer`，不再执行 WSI acquire/present，也不做 Present 后 CPU fence wait。
15. 正式 DP1 不沿用参考实现的 8 槽淘汰。cache key/owner包含 surface key、seq、extent、native
    format、physical device 与 device；导入槽在 attach/device 生命周期内保留，超过 64 个唯一槽时
    失败并锁定回退，禁止在 consumer 可能仍持有 NativeBuffer 时销毁旧 VkImage/VkMemory。
16. Direct 与 WSI 只保留一个 `RecordPresentCopyLocked` 录制器，共用格式/尺寸判定、barrier、
    copy/blit 和可选 GPU timestamp。两条 transport 仅在 target acquire、release/present 与回收策略
    上分流，frame fence/command buffer reset 也由该录制器统一检查；契约测试要求 presenter 内只能
    各出现一个 `vkCmdCopyImage`/`vkCmdBlitImage`/`vkResetFences` 实现。
17. 每个 frame slot 显式记录是否真正提交：fence 只在命令录制成功后 reset，submit 成功后才标记
    在途。WSI resize/dirty 重建前只对真实在途槽执行 1 秒有界 `waitAll`；超时返回重试而不销毁仍被
    GPU 使用的 command/fence/swapchain 对象，也不会等待一次失败 submit 留下的未触发 fence。
    WSI 成功帧已在 publish 前完成 fence wait，后续槽复用会跳过原来的第二次空等；Direct 因不做
    Present 后 CPU wait，仍在实际槽复用时等待。
18. WSI acquire 与 QueuePresent 共用同一 target-loss 分类；`OUT_OF_DATE`、`SURFACE_LOST` 及已知
    Harmony transient `UNKNOWN` 都锁定为 swapchain rebuild，而不是只在 acquire 阶段恢复、在
    present 阶段误报为永久 I/O 失败。

## 参考提交的合并方式

- `e646e74`：不 cherry-pick。只抽取 NativeBuffer import、acquire/release fence 和 SurfaceQueue
  flush 语义，接入当前拆分后的 presenter 与 `NativeWindowLease` 生命周期。
- `3c3c3f6`：吸收“成功 Present 不得先时钟丢帧”和“等待精确 writer submit”的正确性约束；
  scanout-backing/remap 属于第二阶段，不连同大量 probe、Mesa/VirGL gitlink一起移植。
- `0d4ed2c`：其 24 帧预热、稳定态非阻塞 acquire、Guest future deadline 已进入共用
  `present_pacing.h`，继续作为 Direct target 的固定策略，不再新增运行时开关。
- `103ad12`：VKD3D Width flush 与 DXVK 2.6 DXGI 配对已按相同基线移植并由补丁哈希锁定。

这四项是语义依赖关系，不是 cherry-pick 队列。`e646e74` 的 Direct target 要重写到当前架构；
其余三项分别作为帧序、队列节拍和 mapped upload 的门禁。

## 预期内部架构

产品仍只有 `product-virgl` 和 `product-vulkan`。Presenter 内部按一次 attach/device 生命周期选择
transport，不向用户暴露 Direct/WSI/scanout profile：

1. `product-virgl`：现有 EGL surface 是稳定回退；NativeBuffer GLES target通过能力探测后可进入
   Direct queue，scanout backing 最后单独验证。
2. `product-vulkan`：现有 FIFO WSI 是稳定回退；第一候选是 NativeBuffer Direct queue +
   per-frame copy + GPU release fence；Venus scanout backing 不与第一候选绑定。
3. 能力探测只在 attach/device create执行一次。缺扩展、格式/usage不匹配、首次 import/acquire失败
   时，本次 attach锁定回退到稳定路径并记录单一 reason code，禁止每帧在两条路径间抖动。
4. Direct owner 持有 import cache 和未完成 acquire fd，但不拥有 `OHNativeWindow`；销毁顺序固定为
   abort current buffer → 关闭 fd → 等待/确认 device release → 销毁 image/memory/EGLImage →
   `NativeWindowLease::Reset()`。
5. A/B 使用工程候选的编译期默认差异，不添加产品 runtime 开关或新 profile；资格验证完成后删除
   临时选择点，只保留能力探测和自动回退。

### 分阶段落地

- Phase DP1：先实现 Vulkan Direct queue，保留 per-frame copy。目标是证明 WSI/release-wait成本下降，
  同时 DXVK 1.10、2.6 和 VKD3D 帧序/图像一致。
- Phase DP2：复用同一个 NativeBuffer owner实现 GLES Direct queue，不先接 scanout remap。
- Phase DP3：只有 DP1/DP2 稳定后才接 renderer scanout backing；VirGL 与 Venus分别资格验证，
  任何 backbuffer sampling不兼容都自动保留 copy路径。

## 暂不直接移植的部分

- 参考分支的 GLES NativeBuffer/EGLImage target（DP2）。Vulkan import 已按当前 owner/lifetime
  边界重写，不复制参考分支的固定 8 槽实现。
- Host NativeWindow 独立 smoke 页面和实验 UI。
- 参考分支的 Mesa、VirGL、VKD3D gitlink。
- cnc-ddraw 与 Direct Present 无关的构建/overlay 改动。

Vulkan DP1 目前通过了 API 23 ARM64/x86_64 SDK 真实头文件下的严格语法检查；完整
`virgl_child` 源清单也以 `--no-undefined` 链接到对应架构 CMake 声明的 SDK 库。该门禁同时发现并
修复了 x86_64 vtest 参数数组中字符串常量误放入 `char*` 的旧问题。随后 API 23 ARM64 HAP 已完成
Native/ArkTS 编译、资源打包、Release 签名与签名块验证；x86_64 完整 HAP 和真机运行仍未完成，
因此不能标记为候选完成。GLES Direct 与 scanout remap 继续后置，避免一次引入多层 ownership
变化后无法归因黑屏、释放竞态或 GPU hang。

## 下一验证门禁

Direct NativeBuffer import 进入生产候选前必须同时满足：

1. Host 单测：deadline、profile、geometry、blit 全通过。
2. Native/HAP：x86_64 与 ARM64 API 23 构建通过，HAP 含完整 guest-gfx。
3. VirGL：WineD3D/OpenGL 首帧、resize、旋转、前后台和 10 分钟动画正确。
4. DXVK 1.10/2.6：相同 Heaven 路径帧序单调，无黑屏/回退；记录 P50/P95/P99。
5. 队列证据：预热后 acquire timeout 为 0，queue-full 返回未来 deadline，不出现 NCP 250 ms watchdog。
6. A/B：当前 WSI/EGL direct path 与 NativeBuffer import path使用同一输入、设备、分辨率和时长；只有正确性相同且性能有稳定收益才切换默认。
