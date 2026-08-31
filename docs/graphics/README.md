# 图形栈优化入口

本目录是 VintagePomeloPro 图形栈的规划与约束入口。目标不是继续叠加实验开关，而是先固定当前可工作的契约，再逐步收敛配置所有权、补足回归测试，最后推进可量化的性能改造。

## 当前实施状态（2026-08-31）

- 当前本地验证基线为 `7d5e787`，产品版本 `1.3.2` / API 23；原分支
  `codex/graphics-refactor-performance` 保留，包含全屏显示与鼠标几何统一修复。
- GLES 候选在英文分支 `refact/gl-optimization` 开发；EGL 仍为默认路径，
  不能将候选代码存在或编译成功视为性能验收完成。
- Legacy/Modern 的 `batchMappedFlush` 保持产品开启策略，不跑 off 对照。
- 性能监控在系统设置中独立分区，采用小字号顶部横条；指标含义、
  采样边界和测试入口见 [performance-hud.md](performance-hud.md)。
- 局内低帧率仍在定位；原 FP 采样不能直接作函数热点结论，新 DWARF 短采样、
  数据可信度检查和下一轮对照见 [war3-gameplay-cpu-investigation.md](war3-gameplay-cpu-investigation.md)。
- Host/Guest 阶段计时已分项提交，确认 War3 每帧还有完整 RGB565 纹理下载。
  [短包 I/O 候选](guest-busy-io-candidate.md)降低了部分查询 CPU 开销，但未证明
  FPS 改善，不进入默认路径；[Guest 诊断与回退](guest-stage-timing-diagnostic.md)
  明确提取库覆盖不能仅靠重装 HAP 清理。
- [WineD3D 调用探针](wined3d-readback-diagnostic.md)已确认额外下载来自
  32 位 D3D8 后缓冲的整帧 READONLY LockRect；不能当作无用读回删除。
  DXVK 2.6 当前没有接管这条 D3D8 路线，后续分开评估原同步链与游戏自身 GL。
- 最新回退包、测量入口、真机能力门禁与未完成项见
  [gles-direct-validation.md](gles-direct-validation.md)。历史 1.2.8/1.2.9
  记录仅作为历史证据，不再代表当前安装包或设备连接状态。
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

1. 优先补“同一游戏实际对局”的性能定位。用户反馈局内仍约 20 多帧，
   不可用菜单或窗口测试的收益代替。固定地图、视角、分辨率并区分游戏全屏
   与应用铺满屏幕，采集 Guest 提交、Host 呈现、主合成和帧间隔。
2. GLES Direct 只做 Host 尾段候选；能力不足时固定回退 EGL，默认启用仍需
   正确性和三组交替性能门槛。不要为得到 Direct 路径而绕过驱动能力检查。
3. 分别验证 CPU UI/视频、GL 32/64 位、两代 DXVK、生命周期及长稳；
   菜单稳定不代表局内瓶颈解决。已完成稳定修复与性能候选分开评审。
4. 保留既有内容寻址构建校验和原容器增量构建。GPU 能力门控去重、
   Host 同步/上传、scanout 去拷贝、PC/x86_64 完整设备矩阵与 D3D12 专项后置。

## 本地校验

校验只读取 Git 对象和源码，不访问网络，也不要求子模块工作区已初始化：

```bash
make graphics-contract-check
```

宿主机单元测试 `make test` 也会先执行这项契约校验。
