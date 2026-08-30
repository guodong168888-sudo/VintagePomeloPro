# DXVK 1.10 / 2.6 性能差距分析与优化计划

## 问题定义

设备现象是 DXVK 2.6 在相同 Heaven 场景下低于 DXVK 1.10。当前不能把差距直接归因于
“DXVK 新版本更慢”，因为两代 runtime 共用 Wine、Box64、WineVulkan/Venus、Host
VirGLRenderer、NativeWindow 与系统合成路径，但会产生不同的命令流、动态资源更新、shader
和 pipeline 行为。

本项目的目标不是用一个新 profile 掩盖差距，而是回答三个问题：

1. 差距发生在 Guest DXVK CPU、Guest→Host transport、Host shadow GPU upload、GPU draw，
   还是最终 present。
2. 差距是稳定态吞吐、冷启动/pipeline 编译、卡顿尾延迟，还是温控/测试顺序偏差。
3. 能否用共通、可回滚的内部策略改善，而不增加产品线路和用户开关。

产品控制面继续只有 `product-virgl` 与 `product-vulkan`。DXVK 1.10/2.6 是 Vulkan route
内部 runtime adapter，不成为新的图形 profile。

## 当前已知事实

- 两代 DXVK 由同一个 `ResolveProductGraphicsPolicy()` 解析到 `product-vulkan`，Host 均使用
  precise-dirty、Maleoon inline GPU upload、coverage sort 与 FIFO present。
- 版本差异由 `ResolveDxvkRuntimeProfile()` 的窄 capability 字段集中表达：Legacy 1.10.3 使用
  relaxed-feature、command-query-reset 与 dynamic mapped-flush；Modern 2.6.2 使用 command-list
  mapped-flush batching 和 `no_semaphore_feedback`。调用方不再用版本名重建条件树。
- Heaven 2.6 黑屏的正式修复位于 Maleoon Host inline uploader。该修复证明 mapped resource
  publication 是正确性关键路径，也意味着它的 range 数、字节数和提交次数可能放大性能差距。
- Modern 2.6 的 WineHua compatibility layer 在 41 个文件中增加约 2267 行，覆盖 D3D11、
  DXBC、DXGI 和 DXVK hot path。它包含按需诊断、BC/custom-border/dual-source 兼容和 mapped
  flush 逻辑；必须逐项用运行时证据判断，不能整体删除或整体归罪。
- 参考分支与本轮优化起点的 `thirdparty/dxvk-modern` 都固定在同一个 `977a3d78`（DXVK 2.6.2 +
  WineHua compatibility + VKD3D 2.6 swapchain factory）提交；当前工作分支在其上增加 mapped-flush
  合并与 trace 热路径收敛提交 `ff2d6a2c`。2.6 性能差距不是漏合参考分支的 Modern 子模块提交；
  比较重点应放在该兼容层的实际动作和当前 Host/Present 反压。
- 当前 Legacy `f3436e1` 只比参考分支 Legacy `5058927` 多一个进程内 fake-shared-resource
  提交；两者 merge-base 就是 `5058927`。该路径要求显式 `DXVK_WINEHUA_FAKE_SHARED=1`，当前产品
  resolver没有设置它，因此正常 Heaven 性能差距也不是由两套 Legacy 基线漂移造成。
- 当前源码有 69 个 `WINEHUA_API_TRACE()` 调用点，分布在 7 个 Modern 源文件，包含每帧
  `Present` 以及高频 `Map/Unmap`、`GetData/Flush`。产品构建现默认把这些 scope 编译为空操作；只有
  显式以 `DXVK_WINEHUA_ENABLE_API_TRACE=1` 重编译诊断 DLL 时才保留运行时 trace。它消除了确定存在、
  与图形动作无关的 Box64 分支/RAII 固定开销，但不是已确认的主要瓶颈，净收益仍需同场景实测。
- mapped-flush 入队原先对每个 range 都访问一次仅为“首次日志”服务的全局 atomic；该 marker 与
  flush 语义、失败处理和 LAB stats 无关，现已从入队热路径完整移除。该改动不作为 2.6 已追平
  1.10 的证据，仍需用相同 Heaven 基线验证净收益。
- mapped-flush batching 现会在入队时先合并同一 allocation 上连续或重叠的 range，零长度 range
  直接忽略；只有不能在线合并的 range 才进入 command-list vector，并在提交前做全局排序/合并。
  这减少动态 buffer 顺序更新时的 vector 增长、排序输入和最终 Vulkan flush range，不改变
  allocation lifetime、non-coherent atom 对齐或失败处理。
- Modern 在 Maleoon 不支持 dual-source blend 且命中特定 blend 状态时，默认明确执行 secondary
  与 primary 两次 draw；Heaven 已确认命中过该兼容路径。它是比盲调 present 更高价值的 GPU/draw
  放大候选，但单 pass 替代可能改变 Alpha，必须先做像素正确性门禁。
- 当前 ARM64 候选已完成替换安装，保留既有应用数据；设备端启动、字体/音频、Direct NativeBuffer
  及帧序门禁均已复核。历史包的读数不再用于判断本轮优化。
- 当前候选在同一 HAP、同一 Heaven DX11 低画质参数、固定 10 s 预热 / 20 s 采样和交替顺序下完成
  两轮产品路线确认：Legacy 1.10 平均 presenter FPS 为 18.441（16.788--20.095），Modern 2.6
  为 48.087（48.017--48.157），两者均为 `direct-native-buffer` 且动作契约通过，Modern 相对
  Legacy 为 +160.76%。这推翻了“当前受控 D3D11 路线中 2.6 必然低于 1.10”的前提，但样本仍短，
  不代表所有游戏、冷启动、不同温度或 VirGL 工作负载；后续以更长时长、多轮与独立 VirGL 工作负载
  分别确认，而不据此修改产品默认 runtime。
- 随后的 Modern 单变量复测（同一 10 s / 20 s 窗口、两轮交错）显示：产品 batching 为
  48.114 FPS（48.103--48.125），显式 batch-off 为 17.904 FPS（17.831--17.978），两边均为
  `direct-native-buffer` 且两轮动作契约通过。也就是 batching 在该 Heaven 场景为约 2.687 倍
  （+168.73%）的确定性收益，应保留为 Modern 产品 capability，而非新的用户 profile。更早一次
  batch-off 冷启动未产出呈现帧并被标记为 `INFRA_ERROR`；其后的受控复测均成功，不能在未复现前
  把它归因于 batching。
- 诊断轮的本进程累计计数为 3,359,308 个 queued range、3,295,188 个 emitted range、16,170 次
  flush 调用、5.642 GB queued bytes、1.989 GB emitted bytes，失败为零。range 数下降 1.91%，
  而合并后的 byte 覆盖下降 64.75%，与“合并相邻/重叠 dirty range，减少 Venus 非 coherent flush
  及其 Host 处理”的预期一致；这解释了 A/B 方向，但不是其它游戏的性能承诺。

### 媒体播放与图形路由：已确认的边界

- WA2 Special Contents 的媒体窗口走 Wine 内建 `d3d9.dll` / `wined3d.dll`、Quartz 与
  GStreamer；它不是 DXVK D3D9 runtime 的基准。因此“该游戏的影片显示差异”不能用于比较
  DXVK 1.10 和 2.6 的 D3D11 性能，Heaven 的固定场景仍是代际性能结论的唯一基线。
- 2.6 会话仍可能同时存在 Venus/Vulkan 游戏 surface 与 Quartz/WineD3D 的 GL surface。此前
  `EglRenderer` 用会话级 `IsVulkanPresentMode()` 过滤 producer，错误地把 Quartz 的 GL source
  当成 Venus source 交给 NCP；GL presenter 随后拒绝这个类型不匹配的 target，表现为音频正常、
  画面黑。
- 现改为把 `surface.vulkan` 作为 producer 属性随 `AttachZeroCopyTarget()` 传到 NCP，绑定后也只
  与该 surface 自身的类型比较。一个 toplevel 仍只持有一个 NativeImage consumer；当旧绑定从未
  产出帧时，候选只可按 NCP 的“最近 present 优先”顺序、且在合成器可见和未被绑定的前提下提升，
  已产出帧的绑定绝不抖动切换。
- 真机受控验证使用同一 `mv000.pak`，在 `dxvk_modern_2_6` 路由上显示了实际影片帧并以
  `EC_COMPLETE` 结束（约 30.5 s）。这证明当前候选的 Quartz/GStreamer 解码和可视呈现可用。
  若 WA2 重启后仍停在黑屏，先检查该进程是否真的创建了 Quartz/GStreamer graph：本轮重启后的
  Legacy 与 Modern 都未创建 graph，属于游戏入口状态，不能归因到任一 DXVK runtime 或 presenter。

## 首轮瓶颈假设

### H1：Modern 产生更多或更碎的动态 mapped range

如果 2.6 每帧发布更多 dirty range，即使最终字节数相近，也会增加 Guest flush、协议序列化、
Host coverage sort 和 inline upload 命令数。command-list mapped-flush batching 当前已经是 Modern 产品
capability，因此首个单变量应当是保持真实产品基线，再显式关闭 batching，验证它究竟在改善还是放大开销。

当前候选在 batching 内增加了相邻 range 在线合并。诊断计数在合并前记录原始
`queued_ranges/queued_bytes`，`emitted_ranges/emitted_bytes` 则记录排序和两级合并后的 Vulkan
flush 输入；统计关闭时不做原子计数。正式判断仍要用同一 DLL 的 product/batch-off，以及改前/改后
DLL 单变量，避免把工作负载波动误判为合并收益。

在线与最终排序合并现共用 `dxvk_winehua_mapped_range.h`，其相邻、重叠、逆序、间隙、
`VK_WHOLE_SIZE` 和溢出语义有 27 个 host 断言。修改后的 `dxvk_cmdlist.cpp` 已通过项目
Meson/Ninja 的 MinGW x64/x86 单对象编译。现有 `winehua-dev` 不含真实 `glslangValidator`，因此该结果
不冒充完整 DXVK DLL 构建；完整 DLL/HAP/真机仍保留为候选门禁。

判据：Modern product 与 Modern batch-off 的 Host/Guest range 数、flush call、uploaded bytes、
present FPS 和 P95/P99 同时对比。

### H2：Guest/Box64 CPU hot path 成本

Modern compatibility layer 原先在大量 D3D11/DXGI 入口保留可关闭的 RAII trace scope；该固定
开销已在产品构建中编译期消除。DXVK 2.6 自身的 command recording、资源跟踪和 pipeline 路径
仍与 1.10 不同。在 ARM64 + Box64 上，原生 PC 上不明显的分支、TLS/static guard 和较大代码
工作集仍可能成为 CPU 瓶颈。

判据：若 presenter/Host upload 阶段接近、GPU present copy 接近，但应用 FPS 仍低，优先进入
Guest CPU 采样；API trace 改动用改前 DLL 与默认编译为空操作的候选 DLL做单变量对照，不能仅以
源码分析推断收益。

### H3：dual-source、custom-border 或 BC 兼容路径放大 GPU/CPU 工作

Modern 的默认 dual-source 模式是 two-pass；custom-border emulation 默认允许；Maleoon 不支持的
BC 格式需要兼容处理。它们可能分别影响稳定态 draw 数、shader 复杂度和资源加载。

dual-source 当前不是抽象猜测：命中时源码会提交 secondary/primary 两个 pipeline 和两组 draw，
并把两者都计入 `CmdDrawCalls`。因此下一轮应同时记录 draw/submission 计数，判断 Heaven 中该路径
占总帧成本的比例；不能因为它“确定多一次 draw”就直接切换到已知会改 Alpha 的单 pass。

判据：先从日志/计数证明场景确实命中，再做诊断 A/B。任何替换模式都必须通过截图、Heaven
运动、Alpha/阴影、BC 纹理和 smoke matrix；“FPS 上升但图像语义变化”不构成优化。

### H4：pipeline/shader cold path 与缓存

2.6 可能在首次运行编译更多 pipeline，导致冷启动和前几分钟低于已预热的 1.10。必须把冷启动、
同一 prefix 的第二次运行和稳定态分开，记录 pipeline cache 是否命中。

判据：相同 backend 连续两次的 warm/cold 差值。如果差距仅出现在首轮，优先修缓存所有权和
持久化，不改稳定态同步策略。

### H5：Host inline uploader 的工作量被 Modern 命令流放大

两代都使用相同 Host 策略，并不代表 Host 成本相同。Modern 如果写入更多 generation、alias 或
小 range，coverage sort 之后仍可能产生更多 GPU upload 命令。

判据：比较 Host queued/emitted ranges、bytes、coverage、upload command、wait 和失败计数。若字节
相同但命令数显著更高，正式方向是按 resource/generation 合并和按大小选择 inline/staging，
而不是回到不可靠的 CPU coherent 假设。

### H6：present/backpressure 是结果而不是根因

VirGL/Venus presenter 对两代相同。若 2.6 的 `wait_fence`、`acquire`、`queue_present` 和
`gpu_present_copy` 与 1.10 接近，present 可以降级为观察点；低 FPS 来自上游供帧不足。只有这些
指标明显恶化时，才继续检查 Guest submit 与 Host present 共用 queue 的反压。

### H7：温控、顺序和场景不一致造成假差距

每轮必须轮换 Legacy/Modern 顺序，固定分辨率、质量、持续时间、电源状态和温控窗口。一次 HUD
读数或不同时间段截图不能进入默认策略决策。

## 已落地的测量入口

`automation/Measure-WineHuaDxvkPerformance.ps1` 使用现有 HAP 和设备运行 Heaven，默认执行：

1. Legacy 1.10 产品基线。
2. Modern 2.6 产品基线（继承产品的 mapped-flush batching）。
3. 可选 Modern 2.6 batch-off 单变量。

各轮循环旋转顺序。启动后先等待 Presenter 至少提交 120 帧，再开始预热；预热结束时清空
hilog，避免首次 runtime 解压、Wine 初始化和 Heaven Loading 混入正式采样。正式 FPS 使用采样窗口内
同一 surface 的 Presenter 帧号增量/日志时间增量计算，不再使用从首帧起累计、会被加载阶段稀释的 FPS。
空 timeline 或 FPS 样本会将单轮标记为 `INCONCLUSIVE`，但不会中断整组 A/B 会话。它使用现有
`observe-frame-timeline` LAB 观察实验；该实验从产品策略派生，保持 precise-dirty、
inline GPU upload、coverage sort 和 FIFO 动作，只增加每 120 帧一次的阶段观测。产物仅包含每轮
一张截图、筛选后的图形日志和 JSON，不复制 HAP、runtime 或源码。

示例：

```powershell
& .\automation\Measure-WineHuaDxvkPerformance.ps1 `
  -Rounds 3 `
  -WarmupSeconds 30 `
  -SampleSeconds 90 `
  -CooldownSeconds 20 `
  -IncludeModernBatchMappedFlushOff
```

需要短时确认 Modern range 合并效率时，可另加 `-CollectModernMappedFlushStats`。它只在 Modern
且 batching 未关闭的轮次设置 stats；脚本在启动前记录 Wine stderr 行偏移，结束后仅解析本轮新增的
`WineHuaModernMappedFlushPerf` marker 并写入 `modernMappedFlush`，不会把旧运行的累计计数混入。
正式 FPS 轮次仍应关闭该参数，避免统计原子与日志干扰稳定态。
若产品代际基线已经完成，可用 `-ConditionSet modern-batch` 只运行 Modern 产品配置与
batch-off 单变量，避免重复消耗 Legacy 轮次；`-ConditionSet all` 则运行完整三条件矩阵。
终端只打印聚合摘要与归档路径，逐轮 timeline/perf marker 保留在 `comparison.json`。

设备测量至少读取：

固定 cube 的跨 route 回归可用 `Measure-WineHuaFrameOrder.ps1` 分别选择
`dxvk_legacy`、`dxvk_modern_2_6` 与 `wined3d`。其中 `wined3d` 必须观察到
`product-virgl`，DXVK 两代必须观察到 `product-vulkan`；三者使用相同的帧标记、截图采样
和 FPS 估算，不能把 cube 的结果与 Heaven 的结果直接横向比较。

当前手机上的 WineD3D 自动路径应使用 cube 的 `--d3d9` 参数：D3D9/WineD3D/VirGL 已在 40/40
有效截图中通过帧序门禁（无重复、无倒退），按采样时间还原的展示 FPS 为 123.996，P95 帧时间为
8.570 ms。默认 D3D11 变体在 WineD3D 路线于 `CreateVertexShader` 返回 `E_INVALIDARG`，它是
WineD3D D3D11 shader 能力缺口，不能被标记为 VirGL presenter、Direct Present 或 DXVK 代际回归。
为抵消 HDC 截图约 1.3 s 的采样成本，D3D9/D3D11 cube 的视觉 marker 每 8 个渲染帧推进一次，脚本
再按此倍率还原 FPS；读取区域也排除了 Wine 标题栏的蓝色，避免 UI chrome 污染 marker。

FurMark 若作为下一阶段 VirGL 真实负载，只能固定分辨率、预热时间、采样时长、温度/充电状态与
顺序，并同时保存画面正确性和帧时间；它不能替代 D3D9 帧序门禁，也不能用来推导 DXVK 1.10/2.6
的性能结论。

- Presenter FPS、frames、failure、throttled/deferred。
- present CPU、wait fence、acquire、submit、queue present 的平均值与稀疏 P50/P95/P99。
- GPU final present copy 时间。
- Host VirGL/Venus frame timeline、upload/range/perf markers。
- Backend 和实际 runtime 观测。
- 最终截图亮度/变化度提示；它只能发现明显空白，图像正确性仍需视觉或像素基准确认。

`Measure-WineHuaFrameOrder.ps1` 也已支持显式 `dxvk_legacy` / `dxvk_modern_2_6`，并输出根据
帧 marker 与真实采样时间估算的 FPS、P50/P95/P99。它用于固定 cube 的动作/帧序回归，不替代
Heaven 性能结论。

## 实验顺序与退出条件

### Phase A：建立可信基线

- 至少三轮，顺序轮换。
- 同一 HAP、设备、分辨率、Heaven 参数和 prefix。
- 每轮先 warmup，再采样稳定态。
- 保存应用 FPS、presenter FPS、阶段耗时、Host perf markers 和截图。

退出条件：2.6 相对 1.10 的差距在多轮仍稳定，且不是 backend 未切换、温控或旧日志污染。

### Phase B：mapped-flush batching 单变量

- 只比较 Modern product 与 Modern batch-off，不能把强制关闭的实验误标成产品 baseline。
- 如需 range/call 细目，另做短时 stats characterization；稳定性能轮次不打开 stats bookkeeping。
- 不同时改变 dual-source、border、pipeline 或 Host uploader。
- 重跑 Heaven、Modern x86/x64 smoke、Cube 和帧序门禁。

退出条件：正确性不变，flush call/range 或 CPU/present 指标有可重复改善。否则关闭候选。

### Phase C：定位 Guest CPU 或兼容功能成本

当 Host/present 指标不能解释差距时，依次测试：

1. 验证已编译期移除的 API trace scope 净收益。
2. cold/warm pipeline cache。
3. 已证明命中的 dual-source two-pass。
4. 已证明命中的 custom-border/BC 路径。

每次只改变一个因素，并保留视觉正确性证据。

### Phase D：Host uploader 分层

只有 Modern 的 dirty workload 明显更高时才进入：

- 按 memory/resource/generation 合并 range。
- 小范围继续 inline，大范围转 persistent staging + 单次 GPU copy。
- 设置每 submit 的 command/byte budget，超限时合并而不是退回 full copy。
- 继续保留 Maleoon 自动 quirk 和非 Maleoon 标准路径。

退出条件：Heaven/Cube/VKD3D 正确，Host upload 命令与尾延迟下降，10 分钟稳定且可回滚。

## 更大的架构优化空间

### 1. 从 profile 列表改成“产品策略 + 数据化实验”

产品继续两条 route。现有 LAB 名称逐步降级为数据化 ExperimentSpec：基线策略加少数正交 override、
适用后端、预期动作和退出门禁。这样不会再为每个组合增加一个 profile 名称，也能自动发现等价项。

### 2. 建立端到端阶段预算

一次帧需要拆成 Guest D3D/DXVK CPU、Guest submit/serialization、Host decode/publication、Host GPU
upload、scene GPU、final present copy 和系统队列。优化目标从“总 FPS”升级为每层预算和 P95/P99；
否则一个层的改善可能被另一层反压掩盖。

### 3. Host upload 做成统一资源更新器

VirGL/Venus/VKD3D 当前共享的是策略，下一步应共享 dirty-range normalization、generation/lifetime、
upload budget 和统计结构。后端 adapter 只产生规范化更新，不重复实现合并、排序和回退。

### 4. final present 分两阶段减少尾端成本

当前 Venus 把 source image copy/blit 到 NativeWindow swapchain，并在 `QueuePresent` 后同步等待
copy fence。参考分支的第一阶段 NativeBuffer import 仍然每帧 copy/blit，但用 SurfaceQueue
acquire/release fence 代替 WSI present 和 CPU release wait；它优化的是提交/回收，不是 zero-copy。
第二阶段才是让 Guest/renderer 直接写入轮换 NativeBuffer 的 scanout backing，从而跳过 copy。
参考实现默认关闭 Venus scanout backing，因为采样 backbuffer 的 DX11 游戏曾出现黑屏，所以两阶段
必须分开验证。它们能改善两代 DXVK 的共同尾端成本，但不会单独解释 2.6/1.10 的差距。

Phase DP1 现已进入源码：`product-vulkan` 内部优先探测 OHOS NativeBuffer Vulkan 扩展，成功后
固定使用 Direct queue，失败则在本次 attach/device 生命周期锁定 FIFO WSI reason code；没有新增
用户 profile 或运行时开关。Direct 成功路径把 GPU release fence交给 SurfaceQueue，去掉 WSI
acquire/present 与 Present 后 CPU wait，但仍保留 final copy。因此后续 Legacy/Modern 对比要同时
报告 transport 与 `post_present_cpu_wait`，把共同尾端收益与 DXVK 代际差距分开。
Direct 与 WSI 的 final copy 已收敛到同一个录制器；格式/尺寸判断、barrier 和 copy/blit 不再按
transport 复制实现，确保后续共同尾端优化会同时覆盖 DXVK 1.10、2.6 与 VKD3D。
frame slot 现在只在真实 submit 后进入 in-flight：WSI 已完成 post-present fence wait 的槽在复用时
不再重复等待，Direct 则只在无 CPU post-wait 后的实际槽复用点等待；异常 rebuild 对所有真实在途槽
做有界回收。该优化属于三种 Guest runtime 共用的 Host 尾链，不计入 2.6 相对 1.10 的独有收益。
该共享单元以及包含它的完整 `virgl_child` 源清单已在 API23 ARM64/x86_64 SDK 下通过
`-Werror` 与 `--no-undefined` 链接；API 23 ARM64 HAP 也已完成编译、Release 签名和签名块
验证。x86_64 完整 HAP 与真机结果仍是进入候选的独立门禁，不能用静态门禁代替。

### 5. 自动内部 runtime 选择，而不是增加用户线路

当正确性与性能矩阵成熟后，可由 app capability database 在 `product-vulkan` 内部选择 1.10 或
2.6：2.6 支持/性能达标则使用，特定应用或设备不达标则内部回退 1.10，并记录稳定 reason code。
这不是第三个产品 profile，也不能依赖模糊的全局 Auto 猜测。

### 6. 把性能证据变成发布门禁

每个候选保存版本、runtime SHA、设备类别、场景、分辨率、温控、P50/P95/P99、正确性结果和原始
日志。只有多轮改善超过噪声且没有正确性退化，才允许改变默认内部策略。

### 7. 构建与验证改成内容寻址的短反馈环

第一片已覆盖 DXVK 1.10、DXVK 2.6 和 VKD3D：`scripts/build_cache.sh` 将源码提交与工作区差异、
递归子模块状态、补丁/构建脚本、编译器/Meson/Ninja/glslang/widl 工具版本、架构和关键 Meson
选项合成 SHA-256 输入 key；每次
`make hap` 都会检查 key，并逐个复算将要打包的 DLL/EXE/manifest 的大小与 SHA-256。两边都命中
才跳过 Ninja，否则只重建对应组件并原子更新 `build/.cache-manifests/`。因此它不信任旧 mtime，
也不会把只有同名文件的旧产物当作有效缓存。

DXVK 2.6 的 Meson 目录还会校验其记录的源码路径与 `glslangValidator` 绝对路径；换挂载点后若旧
路径已失效，只清理并重配该架构的 Modern build 目录，不要求新镜像或清空共享输出。

VKD3D 的隔离源码刻意不复制 `.git`；上游 `vcs_tag` 在这种情况下会退回项目版本 `2.6`，与其
`0x@VCS_TAG@` 模板组合会生成非法的 `0x2.6`。构建脚本现在从已锁定 upstream commit 取 15 位
十六进制 build id，先确定性物化模板，并把同一 id 写进 runtime manifest 和缓存 key；不再依赖
父目录是否偶然处于另一个 Git worktree。

第二片已覆盖 guest-gfx/guest Vulkan：key 纳入 Mesa/libdrm/wayland/wayland-protocols、OHOS clang、
固定 Loader/Headers commit、Loader 补丁、目标 SDK，以及 smoke、shader、replay 和可选 Heaven
诊断输入。命中时校验 bundle/install/runtime 的整个文件树，不用最终 `manifest.json` 或 Mesa HEAD
代替完整输入边界。下一片再扩到 Wine、Box64 与 HAP。

签名流程已先按同一原则缩短失败路径：Hvigor 前验证 signing config 非空、三件材料存在、签名
profile 有效且 bundle 与 AppScope 一致；`sign.py` 也会拒绝把解密异常文本当成口令。它不改变
证书或发布策略，只把原先 2–3 分钟后的确定性失败前移到秒级。

## 当前下一步

1. 已完成替换安装与真机启动、视频、Direct NativeBuffer、DXVK Modern 帧序及 VirGL D3D9 帧序验证；
   不需重建镜像或创建额外容器。
2. 扩展 Legacy/Modern 到更长时长、冷热两次和温控窗口；保持产品默认 capability，不再重复做
   batch-off 的短窗口证明。
3. batch-off 已确认是主要回归来源；下一项在保留 batching 前提下，用改前/改后 DLL 隔离
   API-trace 编译移除和在线 range 合并各自的净收益。
4. 为 Heaven 增加 draw/submission 计数，再判断 Modern dual-source 两次 draw、custom-border 或 BC
   兼容是否值得做正确性受限的单变量实验。
5. 使用独立固定分辨率 VirGL 工作负载（例如固定设置的 FurMark）补足 WineD3D/VirGL；不能以
   WineD3D D3D11 `CreateVertexShader` 能力缺口代替 VirGL 性能结论。若共同
   Present 尾端下降但 2.6/1.10 差距不变，就停止把差距归因于 Direct Present。
6. DXVK/VKD3D 已保存首次登记及第二次全命中证据；在下一次 guest runtime 构建中保存 guest-gfx/
   guest Vulkan 的首次登记与第二次命中证据。旧 deps stamp 暂不删除，保证单步回滚。
7. 在原因没有被指标区分前，不修改产品默认 backend，不增加新的公开开关。
