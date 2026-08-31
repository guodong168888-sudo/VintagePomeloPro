# vtest 短包 I/O 候选：尚未达到默认启用门槛

2026-08-31，诊断检查点 `7df242c` 后的独立实验。

`make guest-busy-io` 在既有容器中只编译 Guest 计时桥并链接现有 Mesa 对象，
输出到 `build/guest-busy-io/x86_64/`；不修改子模块、生产缓存、Wine zip、HAP
或默认配置。它不是新增产品 profile、环境变量或 WHIP 字段。

## 范围及安全规则

原 BUSY_WAIT 的 8 字节 header + 8 字节参数合成一次写；12 字节回复合并读取。
SOCK_STREAM 仍可拆分，所以部分读写循环必须保留，不保证每次都是两次系统调用。
资源 handle、flags、顺序及返回值不变，所有查询和 WAIT 都实际执行。没有 idle
缓存、没有关闭 finish、没有移除传输或帧同步，也没有增加共享状态和锁。

EINTR 重试未完成部分；EOF、其他 I/O 错误和错误回复 header 终止 Guest，
绝不能把失败当 idle，也不能在可能部分发出的流上重试原事务。相比原实现的
失败读取 abort，写入和协议错误现在更早失败，不能称为异常路径完全相同。

主机测试涵盖 wire 字节、flags/结果、任意 DWORD 内拆分、EINTR、EOF、错误回复；
真实 socketpair 子进程按字节接收并回复，验证与旧 Host 的独立 header/body 兼容。
Guest 基线计时测试、x86_64 OHOS 交叉编译和重复构建 no-op 均通过。

## 实机结果

候选 15,748,904 字节，SHA-256：
`bf91686bb2b91fb78d12d7e27a943e4a208c158c8dc7f1ec05bba7654d6482ba`。
通过应用调试通道在整棵应用进程停止后替换四个已备份的提取库，全部核验哈希。
Host 诊断 HAP 未变。启动走正常游戏入口，`batchMappedFlush=product`，无环境覆盖。

正常进入 War3 菜单并显示约 54 FPS，随后兽族剧情和实际游戏继续渲染；
`io=packed` 确认候选激活。启动时允许既有一次 present 未就绪和少量 SHM 回退；
随后完整窗口 presented=120、failed=0，主合成 upload_bytes=0、failed_swaps=0，
没有观察到传输失败。读回仍为每帧 960,000 字节 RGB565，WAIT 仍为三次。

仅作工作量接近的单对诊断比较（不是三轮 A/B）：原 v2 窗口
`end_ns=208912177357664` 为 114,498 个绘制包、9,172 次查询、13.682 FPS；
候选 `209807039854539` 为 114,600 个绘制包、9,109 次查询、13.706 FPS。
每次查询 CPU 从约 24.47 us 降至 21.27 us，约 13%；但这不等于应用 CPU 降低 13%。
FPS 无实质提升，取纹理仍耗时约 9 ms/帧。场景、温度及调度未严格配平，
也没有帧时间 P95/P99 三组对照，不能报告已达到性能门槛。

结论：保留隔离候选，**不集成产品默认**。短包开销不是此次低帧的主要解释；
继续追完整彩色纹理下载触发源与 Guest 绘制/命令队列等待。

证据位于忽略目录 `.hvigor/outputs/guest-stage-20260831/`：
`packed-menu.jpeg`、`packed-menu.log`、`packed-gameplay.log`、`packed-host.log`、
`packed-graphics.log`。提取文件覆盖可跨 HAP 重装残留，恢复方法见
[Guest 诊断说明](guest-stage-timing-diagnostic.md)及同目录 `rollback.md`。
War3 三次冷启动、GL32/64、音频/视频、DXVK 和长稳回归仍未验收。
