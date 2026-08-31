# GL 后台失败重试：明确问题与有限修复

2026-08-31 真机回归发现。英文分支 `refact/gl-optimization`，保持产品
`batchMappedFlush` 开启、EGL 默认；不修改 Wine/Mesa/VirGLRenderer 子模块、
Vulkan target、WHIP 字段或启动环境。

## 原因和边界

`DesktopAbility.onBackground` 已经调用 `setToplevelVisible(false)`，使
`EglRenderer` 暂停消费 NativeImage；生产端的 EGL window target 仍绑定。
返回应用库会让整个应用再次活跃，但 Wine 桌面仍隐藏。日志显示此时反复
返回 `GL_OUT_OF_MEMORY (0x505)`，与停止消费的时段吻合；这尚不能证明
该错误一定只由队列满引起。原先失败路径返回 `-6`，
`nextPresentDeadlineNs` 保持零；Guest 在下一次 present 清空了限速，造成
高频错误循环。不是游戏必须渲染这么多帧，也不是帧率提高。

证据：基线 `.hvigor/outputs/gl-lifecycle-x64-20260831-1907/` 中，
19:09:46.595 的 Desktop background、renderer paused 后，drop 从
19:09:46.802 的 120 增至 19:12:00.975 的 44160，约 **328.2 次/秒**。
已主动停止负载，不能把这轮标记为五次生命周期或十分钟稳定性通过。
进程数为 14，采样 RSS 合计约 235 万 KiB（含共享页重复计算），没有据此证明
显存泄漏或实际物理内存占用；`0x505` 也不能单独证明系统内存耗尽。

## 本次小改

Native 本地提交 `8de093d`；测试入口修正独立提交 `d1086eb`、`6be307e`。

仅 GL target 使用 `GlPresentFailureBackoff`：首次失败至少等待一帧，连续
失败指数退避至 50 ms；被处理的 fence/init/make-current/present 失败仍返回
原错误，原有 present drop 日志继续保留。下次请求早于
deadline 时直接返回 deferred，不进行 GPU 提交，不在锁内睡眠。成功或新
target 会清空退避状态。50 ms 与现有 Guest vtest 的 deadline 上限一致，
因此不需要改 Guest 库或 IPC。

这是一项错误路径防止忙循环的修复，**不是完整的后台生产暂停**，不保证后台
零 GPU 工作，也不声称修好了冷启动/resize 的偶发 `0x505`。后续需单独设计
consumer/producer 生命周期协调，保持 surface 分类、新鲜 SHM 与恢复几何契约。

## 产物和验证

候选：`.hvigor/outputs/gl-failure-backoff-20260831/gl-failure-backoff-1.3.2-arm64.hap`

- 1.3.2 / 1003002，ARM64，API 23，debug；467411434 bytes。
- SHA-256 `adb0639e91fa81d30b7623714eec8f20524c6b39bca62a77dbb6b30f2463a4fb`。
- SDK `verify-app` 通过；覆盖安装成功，未卸载。
- 与基线相比 Native/ArkTS/runtime 载荷中仅 `libvirgl_child.so` 不同；
  内嵌 runtime 仍为 `2f9b5730da6b1013a7c9f268ef1cd20e8241bd38c7963408f35d5e3a47c00a0d`。
- 现有 `vp-build` 容器中增量 Hvigor 构建约 6 秒。没有新镜像、源码镜像或
  Wine/Mesa/DXVK 重建。Wine 字体和 GStreamer 既有补丁保留。
- Host 测试与 ARM64/x86_64 API 23 GLES syntax 通过。新增退避的到期、
  1000 次连续失败上限、成功重置、零 period 与整数溢出检查。
- 原静态契约还要求已删除的 batch-off 测试矩阵；已改为校验公共 product
  矩阵、正常 game 入口及 off 拒绝规则，完整契约重新通过。

首次候选恢复证据 `first-recovery-hilog.log`：同类隐藏桌面状态下，
19:23:20.331 的 240 drops 到 19:23:57.412 的 960 drops，约 **19.4 次/秒**，
比上述基线窗口减少 **94.1%**。通过应用库中的运行中 Wine 桌面卡片恢复后，
画面可见且重新呈现约 120 FPS。这里只量化错误尝试次数，不把它换算为
整机 CPU/功耗下降，也不作为正常前台游戏 FPS 性能门槛的数据。

`candidate-x64-final/` 已完成五轮 maximize/restore-size、Home → 应用库 →
Wine 桌面恢复。每轮主 PID 保持不变、14 个同名进程，恢复后 probe 帧数递增，
记录的显示速率为 117–120 FPS；首轮和末轮截图均能看到 3D cube。
这证明了该次恢复功能，不是 GPU 性能基准。隐藏期间的 `displayFps` 是缓存值，
不能当作后台真实显示帧率。五轮中隐藏期间仍有受限的 `0x505` 重试，不能
声称无错误稳定性通过。

`candidate-x86-final/` 也完成相同五轮，恢复后 probe 帧数递增、约 117–119 FPS，
首轮及末轮画面可见。主 PID 未变，同名进程数从初始 14 变为首轮后的 15，
随后四轮保持 15；不能据此声称完全无资源增长。两种 Guest 位数都出现过
隐藏期间的受限错误。此次只有几分钟的重复恢复观察，尚未完成十分钟连续
运行和可用内存/句柄增长门槛，也未通过 GL 画面帧序的专用检测。

候选安装后的交叉回归（同目录下 `dxvk-regression/` 和 `candidate-media/`）：

- Legacy `193604`、Modern `193731` 的 D3D11 cube 各 40/40 有效帧，
  0 重复、0 倒退，`direct-native-buffer` 动作契约通过，均继承 product batching。
- Modern 会话的 x86 Quartz/GStreamer probe 播放相同 `mv000.pak`，
  `frame-12.jpeg` 至 `frame-15.jpeg` 可见逐渐完成的 Leaf 动画及周围 Wine 窗口。
  本次追加日志只有一次 `EC_COMPLETE`，没有 media FAIL 或捕获到的 GL drop。
  不将播放器标题栏/桌面等同于完整游戏 CPU UI 验收，也未核验真人听感。
- progress 墙钟约 15 s，结束 PTS 30440 ms；两者不一致保留为独立媒体时间问题，
  不声称此次墙钟播放了 30.4 s。

## 测试入口注意事项

`EntryAbility` 是应用库，不是 Wine 桌面；`DesktopAbility` 未导出，不应通过
外部 aa 强行启动。复测使用 Home → 正常 EntryAbility → 运行中 Wine 桌面卡片。
Appspawn/Wine 子进程可与主进程同名，`pidof` 返回多个 PID 不代表应用重启；
应依据进程树识别主 PID。PowerShell 函数转发 `ps -o` 时须将
`'PID,PPID,NAME'` 作为一个字符串，不能传成逗号数组。

本次实际 A/B 基线保留为
`.hvigor/outputs/host-stage-baseline-20260831/hud-nav-baseline-1.3.2-arm64.hap`，
SHA-256 `64a8fc96ebedda8c28be4234b20f83a9596b56a4157e4e9cafe622ed160fc154`。
这是带 HUD/导航修复的后续基线，不要与最早 `7d5e787` 的包混用。
可单独撤销本次 Native 小改并覆盖安装该基线，不与 GLES Direct 默认启用或
War3 专项优化绑定。HAP 与本次三个源码覆盖文件的哈希保存在候选 `artifact.json`。
