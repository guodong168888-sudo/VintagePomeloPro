# 图形栈优化入口

本目录是 VintagePomeloPro 图形栈的规划与约束入口。目标不是继续叠加实验开关，而是先固定当前可工作的契约，再逐步收敛配置所有权、补足回归测试，最后推进可量化的性能改造。

## 当前审计基线

- 当前私有 `main`：`d73f299fbb7cca81ead0a947765fd93f9d0c3fec`，产品版本 `1.2.9`，标签 `rc-1.2.9`。
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

1. 在已初始化的 `3e5aab6` VKD3D 源上应用 0001..0019，完成 limited-500K 编译及 gears/SingleGpu Width-flush 正确性测试。
2. 完成 `GraphicsProfile`/Presenter policy 的 native/HAP 集成编译与设备 characterization；宿主纯函数测试已通过。
3. 用相同设备场景验证 Guest deadline pacing 的帧序、queue-full 和延迟指标。
4. 通过上述门禁后，A/B 评估参考分支 NativeBuffer import cache；不得沿用已漂移的旧 cherry-pick 配方。

## 本地校验

校验只读取 Git 对象和源码，不访问网络，也不要求子模块工作区已初始化：

```bash
make graphics-contract-check
```

宿主机单元测试 `make test` 也会先执行这项契约校验。
