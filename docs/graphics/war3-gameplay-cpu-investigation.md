# War3 局内性能与 CPU 采样可信度 — 2026-08-31

## 已确认与尚未确认

用户反馈的“进入实际游戏只有 20 多 FPS”仍未解决，不能用约 55 FPS 的菜单
代替验收。当前 GLES Direct 没有通过本机导入能力检查，默认仍走 EGL；
Legacy/Modern `batchMappedFlush` 继续保持产品开启策略。

已有局内探索采样（`9ca71b8`，非固定存档/视角）为 26.32 FPS，Host presenter
CPU P95 634 us，主合成 CPU P95 约 3.3–7.4 ms，稳定窗口 `upload_bytes=0`。
这不足以支持“只缩短 presenter CPU 尾段就能让局内帧率接近翻倍”。GPU 执行、
Guest/WineD3D 提交、同步等待和游戏逻辑仍需区分，不能仅凭 CPU 忙就断言具体原因。
原始场景、温度与测量限制见 [GLES 验证记录](gles-direct-validation.md)。

## 本轮推进：修正函数热点采样方法

原 FP 模式记录 5,184 条样本、无报告丢失；其中 5,179 条原始 `ip` 为
`ffffff0000000fff`。报告的两个主要叶地址经匹配的本地 Box64 符号解析，分别为
`pthread_routine` 与 `my___libc_start_main`，并不是可信的游戏/Wine 热函数。
这说明原回溯主要到达了线程入口，不能把报告中约 58.67% 和 30.96% 的权重
解释为这两个入口函数实际消耗了对应时间。

随后对正常应用入口已启动的 War3 做了 5 秒、99 Hz、用户态周期事件的
`dwarf,8192` 短采样，并请求 `--disable-callstack-expand`：

- 2,639 条样本，无报告丢失；这是菜单期间的**采样方式检查**，不是局内性能对照。
- 2,637 条原始 `ip` 仍为相同占位值，但调用链已经包含分散的用户地址候选。
  因而不能单凭原始 IP 占位就把整个记录判为没有可分析数据。
- 前两个线程占该记录的采样周期权重约 64.63% / 29.72%。这是进程内
  **硬件周期采样权重**，不是 HUD 的 CPU 利用率，也不是运行时间占比。
- 最大单地址权重约 4.67%，不再主要停在线程入口；地址仍没有可靠映射到
  Guest/JIT 函数，因此没有据此修改 Box64、Wine 或 Mesa。
- 两条样本仍含 `<expand callstack>` 标记。即使命令请求禁用扩展，也必须记录
  这个事实，而不是宣称回溯完整可靠。工具不从扩展片段恢复候选叶地址。

Hiperf 对原始 IP、调用链、unwind/expand 标记分别输出，参见
[官方 DumpCallchain 实现](https://github.com/openharmony/developtools_hiperf/blob/master/src/perf_event_record.cpp)。
本机系统行为以设备记录为准，不推断占位值背后的私有内核机制。

## 可复用的附加采样工具

`automation/Measure-WineHuaCpuProfile.ps1` 只附加到已通过应用正常入口启动的
同 UID 进程，不执行 shell Wine、不修改环境变量、不创建产品 profile，也不
重新安装或编译运行库。显式传实际游戏 PID；启动器根 PID 可能已经退出，
本轮曾因此被 Hiperf 拒绝，不能只沿用启动返回的 PID。

```powershell
# 先通过当前 toplevel/clientPid 日志和 ps 确认实际游戏 PID，再替换 12345。
./automation/Measure-WineHuaCpuProfile.ps1 -TargetPid 12345 `
  -RunLabel war3-fixed-save-fullscreen -SceneLabel '固定存档、固定视角、800x600，全屏' `
  -SampleSeconds 10 -HapSha256 '<当前已安装 HAP 的 SHA-256>'
```

时间限制 5–30 秒，默认用户态周期事件、99 Hz、DWARF 8 KiB 栈。
记录、dump、报告和质量摘要保存在忽略目录 `.hvigor/outputs/cpu-performance`；
设备端文件使用本次唯一的 `/data/local/tmp/winehua-cpu-*` 名称，未自动删除。
不要把采样期间的 FPS 当性能门槛数据，采样自身会扰动执行。

纯解析器 `HiperfSampleQuality.ps1` 检查记录数、PID、调用链完整性、占位 IP、
扩展标记与未解析符号，按 `period` 加权而不是按样本条数计算线程/地址权重。
它始终保留 `ATTRIBUTION_REVIEW_REQUIRED`；“有地址”不等于“热点归因已通过”。

验证：

```powershell
./automation/Test-HiperfSampleQuality.ps1
./automation/Test-GlTiming.ps1
```

解析器通过合成数据及上述两份真机 dump；采样器的模拟测试覆盖 UID 隔离、
固定参数、丢样拒绝、绝对路径传输和结果来源记录。组装工具后设备一度断开，
连接检查正确停止；重连时旧游戏 PID 已退出，PID 检查也正确拒绝继续。

重连后恢复不息屏，通过正常游戏入口重新启动（仍为 WineD3D、产品 batch
策略），自动采样器 `30280d8` 已完成两次真机端到端记录与质量摘要：

- `war3-dwarf-toolcheck-20260831-142824-047`：5 秒、2,337 条样本，无报告
  丢失。覆盖启动后的过渡阶段，只作为工具检查。
- `war3-cinematic-cpu-20260831-142934-865`：10 秒、4,397 条样本，无报告
  丢失。采样前截图是雨中海岸/Thrall 的引擎内剧情，HUD 约 15 FPS、应用 CPU
  203%、系统 CPU 43%、电池 38.0℃；这些是瞬时显示，不是平均值。
  前两个线程占采样周期权重约 69.10% / 25.16%；仍有 4,396 条占位原始 IP、
  1 条扩展标记，Guest/JIT 函数归属依然未完成。

两轮使用已经验证的 HUD/导航栏 HAP（SHA-256
`64a8fc96ebedda8c28be4234b20f83a9596b56a4157e4e9cafe622ed160fc154`），
没有重新构建或修改运行库。后一轮场景会变化，不能拿 15 FPS 与之前另一段
剧情的 26.32 FPS 直接推断退化，更不能与菜单对比宣称优化收益。

## 下一轮的优先顺序

1. 固定同一存档/地图、视角与单位数量；先测窗口/全屏各一个短样本确认
   分辨率与场景一致，再按原计划做三组交替、预热 30 秒/采样 90 秒。
   区分游戏全屏与应用沉浸布局，不把菜单与实际对局混为一组。
2. 同步观察生产端间隔、主消费者间隔、合成/交换耗时、上传量、CPU 与温度；
   GPU 指标不可用时标为未测，电池温度不得当作芯片温度。
3. CPU 短采样独立于性能 A/B；补齐匹配构建的 JIT 地址归属。若仍无法可信
   映射，改用分阶段计数/耗时缩小范围，不盲改某个 Box64 入口。
4. 按证据选择一个独立候选：Guest 提交/同步，或主合成中被完全覆盖的底图
   绘制。后者必须保留 CPU 视频周边 UI、弹窗层序、尺寸/输入同源几何和新鲜
   SHM 回退，不能根据 `fullscreen` 一个布尔值就跳过 CPU 图层。
5. 功能与性能门槛通过才考虑默认启用；当前 UI 修复已独立提交，不与后续
   性能实验捆绑。更改运行库子模块需另行检查保存的字体/构建补丁。
