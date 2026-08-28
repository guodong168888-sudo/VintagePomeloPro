# 图形栈优化入口

本目录是 VintagePomeloPro 图形栈的规划与约束入口。目标不是继续叠加实验开关，而是先固定当前可工作的契约，再逐步收敛配置所有权、补足回归测试，最后推进可量化的性能改造。

## 当前审计基线

- 当前私有 `main`：`d73f299fbb7cca81ead0a947765fd93f9d0c3fec`，产品版本 `1.2.9`，标签 `rc-1.2.9`。
- 本轮本地集成候选：`317e45c`。它在上述 `main` 上收敛两条产品 route、移植 DP1、锁定
  DXVK/VKD3D 优化并补齐打包预检；尚未推送，也尚未成为新的设备性能基线。
- 已验证图形基线：`v1.2.8` / `5a92254f3d6732b8a3987dbeb72eab568247a308`。
- `1.2.9` 已包含输入与 Box64 兼容性更新；它不是一次新的图形性能结论。图形回归比较仍以 `v1.2.8` 的设备证据为起点。
- 机器可校验的协议、两条产品 route 与子模块 gitlink 记录在 [graphics-stack.lock.yaml](graphics-stack.lock.yaml)。

## 阅读顺序

1. [GFX_UPSTREAM_FIRST_REFACTOR.md](GFX_UPSTREAM_FIRST_REFACTOR.md)：重构目标、阶段、测试门禁和回滚原则。
2. [GFX_SWITCH_INVENTORY.md](GFX_SWITCH_INVENTORY.md)：生产配置、协议字段与实验开关的所有权边界。
3. [GFX_WORKAROUND_LEDGER.md](GFX_WORKAROUND_LEDGER.md)：当前 workaround 的原因、风险和删除条件。
4. [DIRECT_PRESENT_REFERENCE_AUDIT.md](DIRECT_PRESENT_REFERENCE_AUDIT.md)：参考分支核心提交、当前实现差异与移植门禁。
5. [DXVK_GENERATION_PERFORMANCE_PLAN.md](DXVK_GENERATION_PERFORMANCE_PLAN.md)：DXVK 1.10/2.6 性能差距假设、A/B 工具、优化批次与更大架构空间。
6. [graphics-stack.lock.yaml](graphics-stack.lock.yaml)：可由脚本读取的当前图形契约。

## 权威层级

发生冲突时按以下顺序处理：

1. 代码、设备日志和可复现测试结果。
2. `graphics-stack.lock.yaml` 中的机器锁。
3. 本目录的规划和说明。
4. 历史 handover、实验记录与命令行样例。

文档不能把尚未验证的实验分支写成生产事实。更新子模块、协议版本或产品 route 时，必须在同一个变更中更新机器锁、workaround 台账和验证证据。

## 下一步

当前优先级是“稳定与可维护”：

1. VKD3D 0001..0019 已在 `3e5aab6` 上以 `fuzz=0` 完整应用并完成 limited-500K x64 编译；下一门禁是设备 gears/SingleGpu 动画与 Width-flush 统计。
2. `GraphicsProfile`/DP1 已通过宿主测试、ARM64/x86_64 Native 严格链接和 API 23 ARM64 HAP 编译/Release 签名。候选版本为 1.2.9，签名 HAP SHA-256 为 `08920731b159f777edc93e72ba61ee0bba67da798f14c560a5a05d8dc852553b`。
3. 当前设备离线，尚未覆盖安装候选；设备恢复后先做正确性/帧序矩阵，再运行三轮 DXVK 1.10/2.6 同条件 Heaven 稳定态对照。
4. DXVK 1.10、DXVK 2.6、VKD3D、guest-gfx 与 guest Vulkan 的内容寻址构建校验已落地：输入 key 与整个对应输出树哈希同时命中才复用，不再依赖人工 touch stamp。
4. 通过上述门禁后再评估 GLES Direct 与 scanout backing；不得整分支合并或沿用已漂移的旧 cherry-pick 配方。

## 本地校验

校验只读取 Git 对象和源码，不访问网络，也不要求子模块工作区已初始化：

```bash
make graphics-contract-check
```

宿主机单元测试 `make test` 也会先执行这项契约校验。
