# Host GL 分阶段诊断（非产品默认）

目的：补齐 WineD3D → Guest Mesa → vtest → Host VirGL 链路中的 Host 提交、
资源传输及 finish 等待计时。它不能直接测 GPU 利用率、GPU 执行时间或 Guest
游戏逻辑，更不是消除同步/拷贝的性能候选。

## 构建与隔离

在已经存在的 Docker 容器和 ext4 构建目录内执行：

```sh
make NATIVE_ARCH=arm64-v8a test-host-stage-timing
make NATIVE_ARCH=arm64-v8a host-stage-timing
```

`scripts/build_host_stage_timing.py` 读取原 Meson 编译数据库与 Ninja 的查询输出，
只编译 `smoke/winehua_host_stage_timing.c`，使用链接器 `--wrap` 桥接原缓存对象。
不执行 Ninja 构建、configure、clean、子模块修改或完整运行库重编译。

输出仅在 `build/host-stage-timing/<ABI>/`：诊断动态库、对象及含输入/输出哈希的
`manifest.json`。脚本核验外部符号引用、输出 hook、构建前后输入哈希；缓存缺失、
命令结构变化、输出符号链接或缓存归属不符时拒绝执行。不自动拷贝到 `entry/libs`，
不默认进入 HAP，不新增环境变量、产品 profile 或 WHIP 字段。重复执行指纹相同则
不编译、不重新链接。当前只验证 ARM64；CLI 接受 x86_64 不代表该 ABI 已验收。

正常产品完全不加载这份独立输出。诊断库自身总是计时，不能把它当成低开销的
正式性能候选。需要真机量化开销后，才能判断它对被测场景的扰动。

## 日志范围和口径

输出到既有 `WINEHUA_VIRGL_LOG_PATH` 文件，每个上下文约 120 次 GL present callback 一条
`[HOST-STAGE]`。固定最多 32 个线程局部上下文，无逐帧分配、无逐帧日志、无包围
真实驱动调用的锁。溢出只告警一次，未跟踪上下文不混入其他统计。

按 context generation 隔离；首个 GL callback 建立 PID、surface、尺寸身份。
身份/尺寸变化会结束旧窗口，跨界 present 样本不计；销毁输出有限的尾窗口并清除
状态。首次身份建立前的启动工作不计。日志 `scope=context` 明确它不是通用的
逐 surface GPU 性能数据：一个上下文轮流呈现多个 surface 会切成短窗口。

基本字段包括 `pid/surface/size`、窗口 callback 总数、成功/正值延迟/负值失败
计数、窗口实际经过时间、单调时钟 `end_ns` 及时间有效标记。callback 返回值与 deadline 原样传回，
没有替换原来的 acquire、finish、poll、提交或呈现策略。

每个阶段复合字段统一为：

```text
calls / wall_us / cpu_us / max_wall_us / nonzero_returns / invalid_clock / submit_words
```

- `rpc_submit/put/get/busy/sync/present`：vtest 调度函数，含命令体读取、原函数和
  回复时间，不含它之前的 socket header 等待或事件循环全部工作。
- `driver_submit/put/get/finish`：原 vtest 对相应 VirGL API 的调用；submit_words
  是提交的 32 位字数，不是 draw call 数，也不是资源上传字节数。
- `wall_us` 是累计实际经过时间，`cpu_us` 是当前 Host 线程累计 CPU 时间，
  `max_wall_us` 是单次调用最大值，不是 P95/P99。
- `nested=1`：driver 阶段位于 RPC 内部，**不能相加当作独占耗时**。高 wall、低 CPU
  只能提示等待或调度；不能把差值直接命名为 GPU 时间。
- `gpu_time=unmeasured`：异步 GPU 时间未测。低 Host CPU 不足以排除 GPU 瓶颈；
  高游戏线程 CPU 也不足以排除忙等待。
- 时钟失败/倒退单独计数，不纳入时长总和；有 invalid_clock 的阶段不得直接
  以 calls 做平均。日志输出开销保留在下一窗口的 interval 中，不伪装成收益。

## 验证与部署边界

主机模拟覆盖：嵌套阶段口径、120 帧有界输出、参数/返回值/deadline 保持、正负
callback 结果、时钟失败、上下文重用、surface 变化、32 上下文容量和空 callback。
原缓存 ARM64 交叉编译已通过，反汇编也确认原函数调用进入 bridge。

用户随后授权不必保存、直接开始。显式执行
`make NATIVE_ARCH=arm64-v8a host-stage-timing-hap` 完成诊断打包（约 17 秒），
仍走原 Makefile/package.sh/Hvigor，`-o assemble` 只复用已核验的原 Wine 数据。
脚本拒绝删除其他 ABI 目录，保留原生产库，退出时恢复其内容并刷新 mtime，确保
下一次普通 Hvigor 打包重新处理生产输入。原生产库 SHA-256 为
`4d7ae360e168f4290cfe28905b7dd60d325746fde128bbfc327cc787daa0fdfb`，恢复后已核对。

第一版 stderr 输出未被本机 OHOS 嵌入式服务收集，虽可启动游戏，但没有可用的
Host 阶段记录。第二版只修正输出接入既有 Host 日志路径，并增加 `end_ns`；
每次汇总打开、追加、关闭文件，不保留跨服务重启的 fd；打开失败才退回 stderr。
两版都没有改变原函数参数、返回值、同步或呈现策略。

当前第二版诊断 HAP 已覆盖安装成功，未卸载：

- HAP SHA-256：`60ba1efc042643b329aa9cb78828b92569306acadf0b587069f3428a5e25aa9f`。
- 467,420,463 字节，1.3.2 / 1003002，ARM64，API 23，开发调试签名。
- 第一版与基线的归档名称/大小/CRC 比较仅发现 vtest 库及二进制 `.pages.info` 改变；
  第二版另外核对了签名、嵌入的诊断库与未改变的 Wine zip。
- HAP 内 vtest 库哈希与 Hvigor stripped_native_libs 产物相同：
  `d22732b45f3251c9ec43c12c25c1a7890b2bbd887088f1031cc11626f55ae305`。
- HAP 内 Wine zip SHA-256 仍为
  `2f9b5730da6b1013a7c9f268ef1cd20e8241bd38c7963408f35d5e3a47c00a0d`。
- SDK `verify-app` 使用 `-outCertChain/-outProfile` 返回 0；当前工具不接受
  `-outFile`。未打印或提交验证导出的证书/profile。

用户解锁后正常入口启动成功，第二版已获得菜单与局内的有效 Host 阶段数据，
含连续约 20 FPS 的前台场景。结果见 [War3 调查记录](war3-gameplay-cpu-investigation.md)。
16:40:39 起进入后台的样本已排除；前台恢复后的过渡上传与稳定段分别记录。
手机和构建目录默认 signed HAP 输出仍是诊断包，`entry/libs` 已恢复生产库；
三者不能混淆。采样结束按需要恢复基线包，不能提交诊断二进制或默认启用它。

War3 对比固定相同存档、视角与单位数量。用户已经确认“兵没有了”的场景 FPS
会回升，该变化不能拿来判断优化收益。先用阶段数据确定可改方向，再单独实现
一个优化候选并运行原有正确性与性能门槛；不关闭 `batchMappedFlush`。
