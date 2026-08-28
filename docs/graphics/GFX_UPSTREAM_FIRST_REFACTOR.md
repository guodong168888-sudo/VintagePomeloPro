# 图形栈上游优先重构计划

## 目标与边界

目标是在保持当前生产行为的前提下，把图形栈从“跨层字符串和 workaround 的集合”重构为可测试、可观测、可回滚的配置管线；正常产品控制面只保留 VirGL 与 Vulkan 两条主 route。

本轮包含：文档收敛、契约锁、只读校验脚本和后续代码重构计划。本轮不包含：切换默认 profile、更新图形子模块、合入 Direct Present、删除设备 workaround 或发布新包。

## 必须保持的约束

- WHIP 协议版本和 Host 配置字符串数量必须由单一协议头定义，Host/Guest 同步升级。
- 正常产品只使用 `product-virgl` / `product-vulkan`；DXVK/VKD3D 的实现差异不得扩展成产品 profile。
- DXVK 仍保持 precise-dirty + inline upload + coverage sort，VKD3D 仍保持 precise + 限定同步语义，但这些成为后端策略字段而不是公开名称。
- `runGuestProgram` / `SpawnGuestProgram` 当前只由 `SmokeRunner` 使用，属于 LAB/SMOKE 入口，不是第二个生产配置生产者。
- 图形子模块升级按单个组件、单个假设推进；不以“更新到最新”替代设备验证。
- 不把日志无报错当作正确性结论。至少需要图像、帧推进和稳定性三类证据。

## 目标架构

配置流收敛为五层：

1. **用户意图**：ArkTS 只表达后端、显示模式和公开质量选项。
2. **能力与策略**：一个 resolver 根据 GPU 能力、后端和应用类型产生不可变 `GraphicsProfile`。
3. **协议 DTO**：一个 serializer 把 profile 映射为 WHIP 字段，显式携带 schema/version。
4. **执行适配器**：Host VirGL、Guest Venus、DXVK/VKD3D 和 Box64 各自只消费自己的强类型配置。
5. **观测与测试**：输出 profile id、配置摘要、阶段耗时和错误码，不回显敏感路径或用户数据。

生产入口只选择 product route；Smoke 可以显式选择 LAB experiment。两者复用同一强类型策略和 serializer 基础设施，但产品 resolver 不得查询 LAB 实验。诊断 trace 只能出现在 LAB 会话，不能隐式改变生产默认值。

## 分阶段执行

### Phase 0：锁定现状（已完成文档与脚本）

- 记录已验证版本、子模块 gitlink、WHIP 常量和两条生产 route。
- 将 workaround 逐条登记，补齐 owner、风险和删除条件。
- 把契约校验接入 `make test` 的前置门禁。

退出条件：`make graphics-contract-check` 通过；文档不存在互相冲突的“当前默认”。

### Phase 1：建立单一配置模型（代码与 ARM64 HAP 已通过，待设备门禁）

- 在 Native 层定义 `GraphicsProfileId`、`GraphicsCapabilities`、`GraphicsProfile` 和 `ResolveGraphicsProfile()`。
- 先以 characterization tests 固定现有字符串到环境变量的映射，再迁移逻辑。
- ArkTS 传递公开意图和显式 LAB override，不再拼接底层环境变量集合。

当前进度：`graphics_profile.h/.cpp` 已成为 product route、LAB experiment 与 DXVK runtime 的唯一解析器；ArkTS 生产入口只传 D3D backend。WineD3D/OpenGL 解析为 `product-virgl`，DXVK 1.10/2.6 与 VKD3D 解析为 `product-vulkan`；VKD3D 固定配套 DXVK 2.6.2 DXGI。产品策略不查询 LAB 实验。历史 32 个组合 profile 已删除，替换为 5 个从产品策略派生的观察/单变量实验；未知 backend/experiment fail closed。

集成状态：相同源码已通过 ARM64/x86_64 Native 严格链接；API 23 ARM64 1.2.9 HAP 已完成 Native、ArkTS、资源打包、Release 签名和签名块验证。包内只有 ARM64 Native ABI，同时携带 x86_64 Guest Vulkan、DXVK 1.10/2.6 x64/x86 和 VKD3D limited-500K。设备安装与运行时 characterization 尚未完成，因此这里仍不是性能结论。

退出条件：同一输入在生产启动和 Smoke 启动中得到相同基础配置；旧路径和新 resolver 的快照完全一致。

### Phase 2：分离策略、协议和执行

- 将 `napi_init.cpp` 中 profile 字符串解析迁到 resolver。
- 将 `wine_env.cpp` / `wine_launch.cpp` 降为 serializer 与进程环境适配器。
- 为 WHIP HostConfig 增加编解码 round-trip、字段数量和版本拒绝测试。
- 未知 profile 必须 fail closed，并记录稳定错误码。

当前进度：`napi_init.cpp` 的字符串条件树已迁到 resolver；配置写入逐项检查，并在失败时拒绝启动。产品使用 `ProductGraphicsPolicy` / `BuildProductGuestGraphicsEnvironment`；游戏自动化和 Smoke 使用显式 `ResolveLabGraphicsExperiment` / `BuildLab*` API。已应用的 Host experiment id 会由 `WineEngineService` 随每个 `runWineExe` 子进程传递，Native 在拼 Guest 环境前重新通过同一 resolver 校验，防止 Host/Guest 策略分裂。DXVK runtime 差异由窄 capability 字段表达，调用方不再按 1.10/2.6 名称复制条件树。

Presenter 控制面已进一步收敛：产品与现有五个 LAB 实验都不会选择 mailbox、异步释放或轮询释放，因此这三套不可达分支及两个 present-mode 环境键已删除，VirGL/Venus 固定使用 FIFO + 同步 fence 释放。帧周期归一化和 dispatch lead 迁入共用 `present_pacing.h`。WHIP 第 8 字段由废弃的 present mode 改为二值 Host `perfSummary`，协议升至 10；这样 `observe-product-summary` 可原子驱动 Host renderer、Presenter、日志转发与 Guest，而不增加第 12 个字段或新的公开开关。

退出条件：两条生产 route 只有一个定义点且不能引用 LAB id；协议 mismatch 可在启动渲染前被明确拒绝。

### Phase 3：可观测性与回归矩阵

- 增加每帧 dirty range 数、upload 字节、Host wait、Guest submit、present 完成和丢帧计数。
- 默认仅输出周期摘要；逐帧 trace 只允许 LAB 构建或显式诊断会话。
- 固定最小矩阵：WineD3D/OpenGL、DXVK 1.10、DXVK 2.6、VKD3D；每项覆盖冷启动、窗口缩放、前后台和 10 分钟稳定性。

退出条件：能够从一次设备采样区分 CPU upload、同步等待与 present 三类瓶颈，并能与 `v1.2.8` 证据对比。

### Phase 4：逐项上游化与性能实验

- 先重放每条 workaround 的最小复现，再检查 Mesa/VirGL/DXVK/VKD3D 上游是否已有等价修复。
- 每次只替换一条 workaround 或一个子模块 gitlink，保留 A/B 构建和单步回滚点。
- Direct Present/零拷贝必须重新基于当前 `main` 做接口审计；历史 SHA 和 cherry-pick 顺序只作线索，不作执行配方。
- Direct Present 参考分支审计与当前语义移植记录见 `DIRECT_PRESENT_REFERENCE_AUDIT.md`。
- `103ad12` 的 VKD3D Map/Execute Width flush 已按相同子模块基线移植并由补丁哈希门禁锁定；0001..0019 已以 `fuzz=0` 完整应用并完成 limited-500K x64 编译，设备 D3D12 动画仍是退出门禁。

退出条件：正确性矩阵不退化，P50/P95 帧时间和卡顿指标有可复现实测收益，且新增代码拥有明确 upstream/removal 路径。

### Phase 5：删除兼容层

- 只有在上游版本、设备矩阵和回滚版本都已记录时才能删除 workaround。
- 删除同时更新 ledger、机器锁、测试和用户可见兼容性说明。

## 测试门禁

每个图形行为变更至少通过：

- 静态门禁：契约校验、格式/编译、环境变量 allowlist。
- Host 测试：profile resolver、WHIP round-trip、geometry/blit。
- Guest smoke：VirGL、Venus、DXVK 1.10/2.6、VKD3D 的最小样例。
- 设备正确性：无黑屏/花屏，帧持续推进，窗口 resize/旋转/前后台恢复正常。
- 性能对比：相同设备、分辨率、场景、采样时长和温控条件，保存 P50/P95/P99 与原始日志。
- 稳定性：至少 10 分钟循环；候选发布再做长稳测试。

## 回滚原则

- profile 重构用兼容适配层和显式 feature gate 回滚，不改用户持久化数据格式。
- 子模块变更只回滚对应 gitlink，不整仓 reset，也不混入无关上游提交。
- 协议升级必须保留清晰的版本拒绝错误；禁止在字段不匹配时静默降级。
- 每次设备实验记录构建 commit、机器锁摘要、设备/GPU、场景和结果；没有这些信息的结论不进入生产默认。

## 本轮已完成的首个代码变更

已实现两条 product route、产品派生式 LAB resolver 与 characterization tests，并把 Host/Guest 语义集中到 Native。产品启动不借用实验名称；LAB NAPI 与 `SmokeRunner` 走显式 LAB API；自动化脚本不再复制 profile allowlist，未知名称统一在 Native 边界 fail closed。Host characterization 还覆盖 WHIP v10 摘要位的验证、fingerprint 变化和旧 present-mode 值拒绝。
