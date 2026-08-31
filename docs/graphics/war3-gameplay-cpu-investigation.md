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

## 15:19–15:49：进一步排除节流，并识别线程职责

这一轮仍用同一已验证 HAP，没有安装包/运行库/产品参数变化。

- 旧局内 2,400 帧原始间隔的 120 帧窗口为 16.86–35.64 FPS；240 个间隔短于
  30 ms，只有 418 个落在 33.33 ms ±1 ms 内。不支持“整个路径固定锁 30 帧”。
- 原会话 `frontbuffer.log` 的 calls=14,160 至 18,240，`paced_waits=127`、
  `paced_wait_us=265168` 均未增加。不能将这段局内低帧归因于 Host 返回的
  deadline 节流；这不排除其他资源/驱动等待。
- 15:47 前台局内同一 surface 的主消费者 frame=3840→3960 耗时约 7.966 秒，
  对应约 15.06 FPS；signals 同样只增加 120，update failures 保持 0。
  主合成另一组 120 帧统计为 16.79 FPS，total CPU P95 8.141 ms；之后依次
  回升至 21.62、24.81，并在 15:48 多个窗口约 25–26 FPS。两组窗口边界不同，
  不能视为逐帧对齐，也不能把此次短暂低谷称为持续十几帧。
- 这段前台样本 source 仍为 800×600，`upload_bytes=0`、`failed_swaps=0`。
  当前会话 calls=7,200→8,520 的 paced_waits=342、paced_wait_us=760363 均不变。
  后续线程短测主线程约 94%、另一繁忙线程约 65%；截图为人类前哨战役、
  25 FPS、应用 CPU 213%、系统 CPU 38%、电池 40.0℃。这些不是低谷瞬间的 CPU
  或 GPU 计时，不据此断言着色器编译、降频或某个 Guest 函数是根因。

硬件计数器验证被拒作性能证据：5 秒 `hiperf stat --per-thread` 报告出现单线程
task-clock 大于 5 秒、异常 GHz/CPI 注释及硬件事件仅 1% coverage。不能使用
这些数值推导 IPC、核心频率或调度瓶颈。

新增独立的 `smoke/winehua_guest_inspect.c`，只在现有容器执行
`make guest-inspect` 构建小型 Windows 诊断程序；不依赖 `wine/native/hap`
目标，不默认打包。通过原应用启动环境读取 Toolhelp 进程/模块、线程描述、
GetThreadTimes 和线程启动地址，不注入、不暂停、不调整目标进程。

- 正常 Wine 入口的进程快照确认实际游戏进程名为 **war3.exe**，不是启动器
  Frozen Throne.exe。Guest PID 与 Linux PID 不可混用。
- 真机线程描述确认第二个忙线程为 **wined3d_cs**，而非凭地址猜测。
  该诊断时段读到主线程约 95.5%、wined3d_cs 约 64.5%，但附近存在主合成
  `paused=yes`，只用于线程职责识别，不能当作前台性能 A/B。
- 对目标游戏的跨进程模块快照返回 `ERROR_ACCESS_DENIED (5)`。工具如实输出
  部分失败，未绕过权限；实际 D3D8/D3D9 模块仍未验证。启动地址仅为线程角色
  辅助信息，绝不是执行热点。
- 第一版一次自检遇到 Box64/Wine 异常，已经关闭该诊断会话、确认相关进程退出；
  新版增加无缓冲阶段记录和 10 秒仅终止自身的看门狗。后续顺序启动的真机
  自检通过，但原异常根因未确认，不能宣称看门狗修复了 Wine。
- 主机测试覆盖 JSONL、精确进程名、缺失进程、CPU 边界、启动地址非热点标记、
  时长限制及拒绝覆盖已有证据。命令：
  `automation/Test-GuestInspector.ps1 -Executable <构建产物的 Windows 路径>`。

证据位于忽略目录 `.hvigor/outputs/war3-critical-path-20260831`；工具使用 HDC
`file send/recv -b com.vintage.pomelopro` 的调试应用通道与 `/data/storage/el2/base/`
逻辑沙箱路径，普通 shell 对物理路径的权限不能等同于该通道。Want 中程序路径
使用正斜杠，参数用现有 URI 编码 JSON，不再用未转义反斜杠。

现有 `winehua.mode=game` 自动化入口会应用全局渲染设置并登记游戏会话，不是
无副作用的采样入口。后续需为已就绪会话提供不改设置、不调用 ensureReady、
不登记/切换游戏会话的受限诊断入口，再做前台同场景的线程采样。不要用这个
工具替代尚缺失的每帧绘制提交、资源锁定及 Host finish/fence 阶段统计。

## 16:04 后的负载变化与 Host 计时缺口

同一会话 16:04 的两个窗口回升至 34.99 / 35.54 FPS。用户明确说明此时已经
没有兵，渲染目标减少。因此这是场景负载变化，不能当作代码优化收益，也不能
用它与之前密集单位场景做 A/B。单位数量同时影响模拟、可见性、绘制提交和
GPU 工作量；“主线程接近一核”也可能包含忙等待，仍不能直接锁定 CPU 根因。

检查当前 `vtest_resource_busy_wait` 实现发现，在
`VTEST_SYNC_GL_FINISH` 生效时，`virgl_renderer_context_finish` **先执行**，
原 `busy wait begin/end` 日志随后才覆盖隐式 fence 的轮询。原日志中没有长等待，
并不能排除前面的 finish 阶段有成本。本轮没有关闭该同步机制。

已新增独立 Host 计时桥，见 [诊断库说明](host-stage-timing-diagnostic.md)。只编译
主仓库的一份 C 文件，再使用原生构建缓存重新链接；没有修改 Wine/Mesa/
VirGLRenderer 子模块或原缓存库。独立 library 目标不部署，后续显式 HAP 目标仅
临时替换 `entry/libs`，打包后已恢复并校验生产库。
主机模拟测试、ARM64 交叉编译和重复构建无操作检查通过；反汇编确认原 submit、
finish 和 callback 注册确实经过计时桥。这是诊断工具，不是性能优化成果。

图形契约应针对 Windows 主仓库检查：本轮容器镜像目录的父仓库 Git 元数据仍
引用旧 Wine gitlink，直接在那里运行会失败；其 Wine 子模块实际 HEAD 和主仓库
均为 `3fc36c426830211751248ae3f5e7485a2295c323`，字体修改仍在。未为消除此
检查失败而重置镜像 Git 元数据。Windows 主仓库完整契约检查已通过。

已验证的 HUD/导航栏 HAP 已备份到忽略目录
`.hvigor/outputs/host-stage-baseline-20260831/hud-nav-baseline-1.3.2-arm64.hap`，
SHA-256 仍为 `64a8fc96ebedda8c28be4234b20f83a9596b56a4157e4e9cafe622ed160fc154`。
用户随后授权不必保存，诊断 HAP 已通过原增量打包流程生成并覆盖安装，嵌套 Wine
数据不变、原生产库已恢复。最初启动被系统锁屏错误 10106102 拒绝，用户解锁后
启动成功。第一版 stderr 没进入 Host 文件日志，第二版修正日志接入后已采集到
阶段数据；具体产物哈希与回退状态见诊断库说明。

## 16:28–16:46：第二版 Host 诊断与实际低帧段

第一版安装末期曾捕获兽族/巨魔雨林剧情约 11–15 FPS，主合成无上传、无交换
失败；但没有 Host 阶段日志，不能拿它补全 Host/GPU 根因。第二版经正常入口启动，
加载现有 `sss` 存档后实际是暗夜精灵 Rise of the Naga；与之前兽族场景不同。
后续用户操作场景、视角和单位状态也有变化，以下是负载敏感性诊断，不是优化 A/B。

同一进程、surface 52、context generation 6、source 800×600：

- 前台较轻局内段：53 个完整窗口，6,360 帧 / 207.676353 秒，30.62 FPS。
  `end_ns` 范围 206811324604226–207015017582351。Host RPC 每帧 wall 均值：
  submit 1.859 ms、get 0.966 ms、busy 2.700 ms、present 0.530 ms。
  submit 3 次/帧、busy 查询 28.414 次/帧、finish 3 次/帧；finish wall 2.329 ms/帧。
- 16:40:39 后出现 `paused=yes`，后台期间 callback 失败，不纳入前台性能分析。
  一次 `gl=0x505` blit 错误在后台切换后发生；恢复后重新产生有效帧，不能用它
  解释此前稳定低帧，也不能据此宣称前后台完整回归已经通过。
- 16:43 恢复前台后，精灵门附近截图约 28 FPS、应用 CPU 212%、系统 CPU 38%、
  电池 38℃。短时出现 CPU 图层上传；16:44:11 起多个窗口恢复为零。
- 随后场景继续变化，16:44:28 后持续降至约 19–21 FPS。16:45:57 附近截图为
  精灵门前多个单位，HUD 20 FPS、应用 CPU 228%、系统 CPU 37%、电池 39℃。
  同期 `top` 主线程 95%、第二个忙线程 71%；后者当前 Linux TID 为 33027，
  未用旧进程的线程号或线程描述替代本会话的职责验证。
- 低帧稳态选取 7 个完整窗口（排除前一窗口约 198.6 ms 的单次 submit 尖峰）：
  840 帧 / 41.387110 秒，20.30 FPS；`end_ns` 为
  207313121693289–207348480281726。全部 presented=120、deferred=0、failed=0，
  阶段时钟有效且无非零返回。每帧 Host RPC wall 均值为 submit 3.514 ms、
  get 0.950 ms、busy 2.624 ms、present 0.528 ms；对应 CPU 均值分别为
  3.490 / 0.499 / 0.708 / 0.513 ms。
- 低帧时 submit 4 次/帧，busy 查询 60.337 次/帧；finish 仍为 3 次/帧，
  wall 1.881 ms、CPU 0.043 ms/帧。driver submit 3.081 ms wall、3.062 ms CPU/帧；
  每帧约 72,766 个提交 DWORD，约为较轻段约 24,700 DWORD 的三倍，
  **不是三倍 draw call 或三倍纹理上传**。
- 16:44:40–16:44:58 的主合成窗口约 19.3–21.0 FPS，upload_bytes=0、failed_swaps=0，
  total CPU P95 约 6.3–6.8 ms。当前 producer calls=27120→27480 的
  paced_waits=184、paced_wait_us=257862 均未增加。后续 source/几何不变，
  consumer update failures 仍为 0。Host 与主合成窗口不作逐帧强行对齐。

低帧段整帧约 49.27 ms，已计入的 Host RPC 合计约 7.62 ms，且呈现与 finish
没有随降帧增长。证据更支持继续追 Guest 绘制准备、资源检查和同步提交链路，
不支持把当前差距主要归因于全屏放大/末端 swap 或 Host deadline 节流。
但未测的 socket header/调度、Guest CPU 和异步 GPU 工作不能从差值自动分配；
GPU 时间仍未测，游戏主线程高 CPU 也可能包含 Wine 命令队列忙等待。

源码复核找到可区分的查询来源，而非已经确认的热函数：

1. `virgl_vtest_busy_wait` 每次使用两次写、两次读完成一次同步往返；Host 端
   resource handle 当前不参与 busy 判断，依据上下文的 implicit fence 状态。
2. Guest 的资源缓存复用检查、discard/map 检查、query result 和有限超时 fence
   轮询都可能调用此路径；仅凭 60 次/帧不能称为 60 次 `glFinish` 或无效轮询。
3. `virgl_resource.c` 的读回路径可能在传输前、传输内部以及传输后等待，符合
   当前“一次 get、三次 finish”的计数形态，但尚未确认具体资源及调用链。
4. Wine `wined3d_cs_mt_finish` 存在队列清空等待，`wined3d_cs_run` 也会轮询查询；
   因而不能将主线程接近一核直接解释成全部用于游戏 AI/逻辑。

下一步优先补充实际绘制/inline transfer 的命令分类、读回资源范围，以及 Guest
查询调用来源与往返耗时，区分“更多必要工作”和“重复检查”。确认冗余后才做
有提交代次失效规则的查询复用或更窄同步候选；不得固定返回 idle、关掉 finish，
或修改 `batchMappedFlush`。本轮没有安装新的性能候选，也没有改变运行环境。

原始证据保存在忽略目录 `.hvigor/outputs/host-stage-baseline-20260831`：
`v2-host-stages-1642.log`、`v2-resumed-host-1645.log`、`v2-resumed-graphics-1645.log`、
`v2-lowfps-host-1646.log`、`v2-lowfps-top-1646.log` 及对应游戏截图。

## 16:57–17:18：Guest 查询来源与完整彩色纹理下载

新增 [Guest 诊断桥](guest-stage-timing-diagnostic.md)，只重用原缓存重新链接，
未更改产品默认路径。以下是不同场景负载下的诊断，不是优化前后对照。

Guest v1：兽族雨中 Thrall 剧情（证据图片误命名为 `menu.jpeg`，实际不是菜单），
约 13–15 FPS。一个完整窗口 120 帧 / 9.003997 秒 = 13.327 FPS：

- 每帧约 1,012.7 个编码绘制包、80.5 个 transfer 包；没有 query 包或 inline 数据。
- 非阻塞 busy 检查 74.08 次/帧，wall 3.688 ms/帧；WAIT 三次/帧，wall 9.227 ms/帧。
- 每帧一次 800×600 下载，960,000 字节；present wall 0.830 ms/帧。
- `virgl_vtest_resource_is_busy` 调用点贡献 8,160/8,890 次非阻塞检查，
  全部返回 idle；资源缓存约 604 次、fence wait 约 126 次。
- 三次 WAIT 的直接调用位置确认是 transfer map 的传输前等待、vtest
  transfer-get 内部等待，以及 map 的传输后等待。不能仅凭三次就全部删除。

Guest v2：直接测得 `st_GetTexSubImage` 每帧一次，参数为
`800x600/GL_RGB/GL_UNSIGNED_SHORT_5_6_5`，恰为 800×600×2 字节。
稳态 `st_ReadPixels` 为零。由此确认是 **RGB565 彩色纹理下载，不是深度缓冲**；
主合成 `upload_bytes=0` 也不代表整个 Guest 没有资源读回。

17:18 捕获文件最后 20 个完整窗口（同 PID、线程、generation、surface）：
2,400 帧 / 87.667690 秒 = 27.376 FPS，`end_ns` 范围
209158766493445–209242137420945。平均每帧 370.70 个绘制包、25.16 次非阻塞
busy 查询，后者 wall 1.329 ms；WAIT wall 5.782 ms；取纹理 API wall 5.991 ms、
CPU 0.284 ms；present wall 0.733 ms。API 包含 WAIT，二者不得相加。
当前游戏主线程短采样约 93%、Guest 图形线程约 63%；没有据此认定主线程全部
在执行游戏逻辑。所有这些窗口依旧每帧下载 960,000 字节。

源码表明该 GL 下载既可能由 Wine 的 CPU 目标 blit 触发，也可能由纹理加载到
SYSMEM/BUFFER 触发；尚未找到游戏/Wine 的确切上层调用者。因而不能称为
“已确认无用下载”，更不能跳过下载后把黑屏/旧帧当性能收益。

目前可区分三部分：绘制工作量明显随场景增长；资源查询跨进程往返可累计数毫秒；
整张纹理下载带来同步等待。末端 GPU 呈现的 wall 没有同幅增长，不支持优先修改
全屏缩放或直接关闭同步。接下来先选不改变同步语义的传输优化候选，再继续追
下载触发源。缓存 idle 结果需要涵盖所有写入/提交、连接重用和跨线程失效规则；
仅在 submit 时清空 TLS 缓存不够安全，不能直接作为产品改动。

原始证据：`.hvigor/outputs/guest-stage-20260831/` 中的
`orc-guest-stage.log`、`orc-host-stage.log`、`v2-gameplay-1718.log` 和
`v2-host-1718.log`。隔离 Guest 覆盖状态及回退见上述诊断说明。

## 17:40–17:53：定位到 D3D8 后缓冲 LockRect

[WineD3D 隔离探针](wined3d-readback-diagnostic.md)补全了上节缺失的调用来源：
本次 War3 为 32 位 D3D8，每次 present 前同一后缓冲出现
READONLY | NOSYSLOCK map；60 次 v2 抽样请求均为完整 800×600，而非小范围锁定。
前后缓冲尺寸/格式相同。栈可定位到 Wine 的 D3D8 LockRect，尚未解出游戏函数。
这是正面调用证据，不是从缺少颜色转换日志作出的推断。

17:53 前后兽族基地约 24–26 FPS，主合成仍无 CPU 上传/交换失败。20 次 map
抽样耗时约 4.9–7.0 ms，但不是完整逐帧覆盖，不能据此给出帧时间 P95。
额外全帧读回是已确认的成本之一，尚不足以解释所有低帧差距。

产品 DXVK 选择目前仅强制接管 D3D11/DXGI；不能以“选了 2.6”认定 War3
D3D8 也走 Vulkan。保留 D3D8/VirGL 默认，另用经典 War3 自身 OpenGL 做正常
入口的临时路径区分实验，比盲目跳过读回更容易验证是否能避开 WineD3D 的开销。
不增加产品 profile/持久化环境变量，也不把这个游戏特例当作通用重构完成。

## 用户调整后的处理边界

本轮按“明确问题、明确收益，否则架构/CPU 专项暂放”收口。已确认每帧完整
后缓冲读回及同步成本，但没有证明数据无用；短包 I/O 候选也未证明 FPS 改善。
暂不为 War3 继续深入 CPU/转译栈或改写同步；不宣称 CPU 已解释全部差距。
首轮临时 OpenGL 仅验证菜单出帧并消除稳态 get；后续局内短测记录见下节，
仍不算同场景性能验收。
WineD3D、Guest Mesa 和 Host HAP 已还原到生产基线；细节见隔离探针说明。

以下 War3 专项顺序保留作将来的恢复入口，当前不继续执行。公共重构/跨后端
正确性验收可以独立推进，不能让本游戏未量化的架构优化拖住稳定成果。

### 后续局内 GL 短测已完成，专项继续暂放

2026-08-31 18:14–18:29，原 HAP/运行库下 D3D8 参考 28.10 FPS；游戏自身
`-opengl` 局内用户观察约 +10 FPS，60 秒完整窗口的描述性均值为 41.47 FPS。
两边视角、单位数和温度不一致，不是受控 A/B。GL 采样发生一次
`gl=0x505` 丢帧后恢复，严格工具状态为 `INCONCLUSIVE`；早期 EGL 基线已出现
同类错误，不能武断认定是 GL 参数引入。第一次 GL 尝试的用户报告卡住也保留。
完整条件、百分位与证据目录见 [最终短测记录](wined3d-readback-diagnostic.md)。

这支持继续将差距分解为 API/转译/资源读回与场景工作量，而非仅归咎全屏缩放。
没有证据证明 CPU 已解释全部低帧，GPU 执行耗时仍未测。按用户要求到此停止
扩大 War3 专项，公共重构/回归不受它阻塞；不默认替换其他游戏后端。

## 专项恢复时的优先顺序

1. War3 当前入口无法切换窗口/分辨率，不再将它们列为前置条件。固定同一
   存档/地图、视角与单位数量，对基线和候选做三组交替、预热 30 秒/采样 90 秒。
   空地/基地/密集单位只用于负载敏感性诊断，不混入同场景性能 A/B。
2. 同步观察生产端间隔、主消费者间隔、合成/交换耗时、上传量、CPU 与温度；
   GPU 指标不可用时标为未测，电池温度不得当作芯片温度。
3. CPU 短采样独立于性能 A/B；补齐匹配构建的 JIT 地址归属。若仍无法可信
   映射，改用分阶段计数/耗时缩小范围，不盲改某个 Box64 入口。
4. 按证据选择一个独立候选：Guest 提交/同步，或主合成中被完全覆盖的底图
   绘制。后者必须保留 CPU 视频周边 UI、弹窗层序、尺寸/输入同源几何和新鲜
   SHM 回退，不能根据 `fullscreen` 一个布尔值就跳过 CPU 图层。
5. 功能与性能门槛通过才考虑默认启用；当前 UI 修复已独立提交，不与后续
   性能实验捆绑。更改运行库子模块需另行检查保存的字体/构建补丁。
