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
- 参考分支与当前 `thirdparty/dxvk-modern` 都固定在同一个 `977a3d78`（DXVK 2.6.2 + WineHua
  compatibility + VKD3D 2.6 swapchain factory）提交。2.6 性能差距不是漏合参考分支的 Modern
  子模块提交；比较重点应放在该兼容层的实际动作和当前 Host/Present 反压。
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
- 当前 API 26 设备上安装的是 1.2.8 历史版本，而源码候选为 1.2.9；历史包只能提供旧基线，不能
  证明本轮 API-trace 编译移除、range 在线合并或 WHIP v10 的动作。必须先产出并安装当前候选。

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

各轮循环旋转顺序。它使用现有
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
且 batching 未关闭的轮次设置 stats，`result.json` 会把最后一个累计 marker 解析到
`modernMappedFlush`；正式 FPS 轮次仍应关闭该参数，避免统计原子与日志干扰稳定态。

设备测量至少读取：

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
`-Werror` 与 `--no-undefined` 链接；完整 HAP 与真机结果仍是进入候选的独立门禁，不能用静态
门禁代替。

### 5. 自动内部 runtime 选择，而不是增加用户线路

当正确性与性能矩阵成熟后，可由 app capability database 在 `product-vulkan` 内部选择 1.10 或
2.6：2.6 支持/性能达标则使用，特定应用或设备不达标则内部回退 1.10，并记录稳定 reason code。
这不是第三个产品 profile，也不能依赖模糊的全局 Auto 猜测。

### 6. 把性能证据变成发布门禁

每个候选保存版本、runtime SHA、设备类别、场景、分辨率、温控、P50/P95/P99、正确性结果和原始
日志。只有多轮改善超过噪声且没有正确性退化，才允许改变默认内部策略。

## 当前下一步

1. 当前 DP1 已通过现有 `winehua-dev` + API 23 ARM64 SDK 的目标文件语法检查；下一步仍须用当前
   源码产出完整 ARM64 候选，不能复用设备上的 1.2.8 冒充候选。
2. 安装候选后运行三轮 Legacy/Modern 产品基线，不带任何强制 on/off override。
3. 确认差距属于稳定态还是 cold path，并用改前/改后 DLL验证 API trace 与在线 range 合并净收益。
4. 再加入 Modern batch-off 单变量，验证当前产品 capability 的净收益。
5. 根据 Host/present 指标决定进入 Guest CPU、兼容功能或 Host uploader 分支。
6. 在原因没有被指标区分前，不修改产品默认 backend，不增加新的公开开关。
