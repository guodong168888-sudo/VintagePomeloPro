# 图形配置与开关清单

## 清单规则

本文件按所有权分类，不把仓库里出现的每个环境变量都视为产品 API。新增开关时必须指定类别、生产默认、owner、消费方、测试和删除条件；否则只能进入临时实验分支。

类别定义：

- **ABI/协议**：跨进程或跨组件的兼容契约，必须版本化。
- **PRODUCT**：用户或产品策略可选择的稳定行为。
- **PLATFORM**：由设备能力和传输约束推导，不直接暴露给用户。
- **LAB**：诊断、A/B 和 smoke 专用，不得成为持久化产品设置。
- **STATUS**：只读状态和观测输出，不参与策略选择。

## ABI 与正确性契约

- `WHIP magic`：`0x57484950`，owner 为 `virgl_ipc_protocol.h`。
- `WHIP protocol version`：当前 `10`。任何字段语义、顺序或数量变化都要升级版本并增加拒绝测试。
- `HostConfig string count`：当前 `11`。第 8 字段从已废弃的 present mode 改为二值 `perfSummary`；字段数不变但语义变化，因此协议从 9 升到 10，Host/Guest 必须用同一个协议头或生成物。
- 子模块 gitlink：VirGL、Mesa、DXVK、DXVK Modern、VKD3D-Proton、Wine 的精确 SHA 由 `graphics-stack.lock.yaml` 锁定。

这些值不能被命令行、ArkTS 设置或环境变量覆盖。

## PRODUCT：产品级意图

产品层只应保留以下意图，不直接暴露底层 workaround：

- D3D 后端：`auto`、DXVK 1.10、DXVK 2.6，以及已有的 WineD3D/VKD3D 场景选择。
- 展示模式：由 `WinePresentationMode` / display mode 表达。
- 应用级 renderer preference：由模型和 `AppSettingsStore` 归一化。
- 兼容性 preset：如 Box64 preset，必须是命名 preset，不是任意环境变量文本。

正常运行只有两条 Native route：`product-virgl` 与 `product-vulkan`。WineD3D/OpenGL 进入 VirGL route；DXVK 1.10、DXVK 2.6 与 VKD3D 进入 Vulkan route，版本差异和 VKD3D 的限定同步要求由后端适配器补齐，不再借用 LAB experiment 名称触发。ArkTS 生产入口只传 backend；DXVK 1.10/2.6 的目录、版本与窄 capability 由同一 resolver 产生，VKD3D 固定配套 DXVK 2.6.2 DXGI。

## PLATFORM：能力与传输策略

以下值应由 resolver 根据 GPU、后端和宿主能力产生：

- `WINEHUA_VIRGL_HOST_SHADOW_MODE`
- `WINEHUA_VIRGL_HOST_SHADOW_SELECTOR`
- `WINEHUA_VIRGL_HOST_SHADOW_MERGE_RANGES`
- `WINEHUA_VIRGL_HOST_GPU_UPLOAD_WAIT`
- `WINEHUA_VIRGL_HOST_DESCRIPTOR_UPDATE_SERIALIZE`
- `WINEHUA_VIRGL_HOST_PERF_SUMMARY`：仅由 resolver 写入的内部观测位，经 WHIP 第 8 字段同时驱动 Host renderer、Presenter 和摘要日志转发。
- `VKR_WINEHUA_*` Host renderer 派生配置
- `VN_PERF` 与 `VN_WINEHUA_*` Guest Venus 同步配置
- `DXVK_WINEHUA_EMULATE_RGBA8_SNORM_RT`
- 图形相关的 `BOX64_DYNAREC_*` 兼容 preset

要求：产品入口不能逐项拼这些值；Host 和 Guest 的成对约束必须由 product route policy 同时生成。未知值不得静默落到“看似可用”的默认组合。

## LAB：实验与诊断

以下属于实验面，默认关闭或仅由自动化设置：

- `WINEHUA_GRAPHICS_PROFILE`：Host 与 Guest 共用的只读策略标识；记录 product route 或显式 LAB experiment，不是第二个产品选择入口。
- `setHostGraphicsExperimentForLab(experimentId, backend)`：唯一 Host LAB experiment 入口；backend 与 Guest resolver 使用同一输入，产品启动不得调用。
- `VKR_WINEHUA_SHADOW_TRACE` 及 frame timeline、present image、frame association、GPU frame profile 等 trace。
- 当前仅保留 `observe-product-summary`、`observe-frame-timeline`、`trace-frame-association`、`trace-present-image`、`isolate-transport-neutral` 五个有界实验；展示队列和释放策略不再作为 LAB 组合维度。
- `automation/Invoke-WineHuaAutomation.ps1`、`Measure-WineHuaFrameOrder.ps1`、`Start-WineHuaGameTest.ps1` 暴露的 `GraphicsExperiment` 参数。
- `SmokeRunner.ets` 为 smoke case 组装的环境变量覆盖。

`runGuestProgram` / `SpawnGuestProgram` 当前仅从 `SmokeRunner` 调用，所以它是 LAB/SMOKE 执行入口。它应复用生产 resolver 的基础配置，但不能被计为第二个产品配置 owner。

LAB 开关的生命周期：提出假设 → 自动化复现 → A/B 数据 → 合并为命名策略或删除。禁止把一次有效的实验字符串直接提升为产品默认。

## STATUS：只读观测

应稳定输出但不影响策略：

- 选中的 profile id 与配置摘要 hash。
- WHIP 协议版本、Host/Guest ready 状态和拒绝原因。
- GPU device name 与能力判定结果。
- submit、Host wait、upload、present 的计数和阶段耗时。
- fallback/compatibility reason code。

状态日志不得包含签名材料、完整用户路径或任意环境变量值。

## 当前所有权状态与剩余债务

已完成：

- `graphics_profile.h/.cpp`：唯一 backend/route/LAB resolver 和生产策略 owner；产品只暴露 VirGL/Vulkan 两条 route。
- `WineEngineService.ets`：只传 backend intent，不再持有 shadow profile 字符串。
- `napi_init.cpp`：只应用 resolver 结果；未知值 fail closed。
- `wine_env.cpp` / `wine_launch.cpp`：通过 resolver 查询默认，不再重建 profile 条件树。
- `present_policy.h`：在 NativeWindow attach 时一次性解析只读诊断策略；VirGL/Venus 每帧不再重复读取环境开关。产品展示固定为 FIFO + 同步 fence 释放，旧 mailbox/async/poll 分支及两个 present-mode 环境键已删除。
- VKD3D `0001`/`0019`：按资源 Width 刷新持久映射 UPLOAD，补丁来源和规范化哈希由契约锁固定。
- 游戏自动化的 `winehua.graphics_experiment`：由 `EntryAbility` 显式转交 `setHostGraphicsExperimentForLab`，并在 VirGL 启动前经同一 resolver 校验/应用；`WineEngineService` 再把已经实际应用的 experiment id 随每次 `runWineExe` 启动传给 Native，Native 用同一 resolver 生成 Guest overlay，避免 Host 已切实验而应用子进程仍跑产品默认。自动化不持有第二份实验 allowlist。
- `ProductGraphicsPolicy` / `BuildProductGuestGraphicsEnvironment`：正常 Host/Guest 行为由两条 product route 生成，完全绕开 LAB 注册表。
- `ResolveLabGraphicsExperiment` / `BuildLabGuestGraphicsEnvironment`：仅保留 5 个有明确目的的 LAB 实验，全部从所选 `product-virgl` / `product-vulkan` 基础策略派生；32 个历史组合 profile 已删除。summary/timeline 观察可复用于两条 route，Venus trace 与 transport 负向控制会按 backend fail closed，不复制 Host/Guest 全量配置。
- `present_pacing.h`：统一 VirGL/Venus 的显示周期归一化、4–33.333 ms 边界和 0.5 ms dispatch lead，消除两条 presenter 对 100 ms 输入与最小周期的不同解释。
- WHIP v10：复用已失效的第 8 个 present-mode 字段承载二值 Host summary，不增加配置字段或产品开关；`observe-product-summary` 现在会同时打开 Host、Presenter 与 Guest 摘要。

剩余债务：

- `automation/*.ps1`：profile id allowlist 已删除，合法性统一由 Native resolver fail closed；脚本只保留与测试 suite/场景本身有关的参数枚举。
- 历史 LAB profile 清理已经完成；后续新增实验必须由产品策略加单一差量表达，并同时增加退出条件。
- Guest Venus/DXVK/VKD3D 的稳定运行时目录与后端专属变量仍由适配器生成；共通 product/LAB serializer 均有 characterization。

期望所有权：

- ArkTS：只拥有用户意图与 LAB override 请求。
- `GraphicsProfileResolver`：两条 product route 与 LAB 实验的唯一策略 owner。
- WHIP serializer：唯一协议映射 owner。
- Host/Guest adapters：只消费强类型结果。
- 自动化：只引用稳定的 profile id，不复制环境变量组合。

## 变更检查清单

新增或修改图形开关前确认：

1. 类别和 owner 是否明确。
2. 是否能由已有 profile/能力位表达，避免新增布尔量。
3. Host/Guest 是否需要原子联动。
4. 默认值、非法值和降级行为是否有测试。
5. 是否影响 WHIP ABI 或机器锁。
6. 是否有设备复现、性能指标和删除条件。
7. 文档、ledger 与自动化契约是否在同一变更中更新。
