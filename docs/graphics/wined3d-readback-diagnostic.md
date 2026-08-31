# WineD3D 后缓冲回读诊断 — 2026-08-31

这是隔离诊断，不是性能修复，也不改变任何产品默认项。入口为
`make wined3d-readback`，只能在既有容器与 `build/wine-ohos` 缓存上运行。
不会 configure、构建完整 Wine、修改子模块或更新 staging/runtime zip/HAP。

## 实现与验证边界

`smoke/winehua_wined3d_readback.c` 复用真实 `wined3d_private.h` 与函数 ABI；
每种 PE 位宽只新增一个对象，链接原缓存对象。记录以下跨对象调用：

- `wined3d_device_context_emit_map`：请求区域、标志、位置与耗时。
- `wined3d_texture_load_location`：大纹理加载到 CPU 位置。
- `wined3d_texture_download_from_texture`：下载复制。
- `wined3d_device_context_emit_blt_sub_resource`：复制入队。
- `wined3d_cs_emit_present`：后缓冲与前缓冲身份、格式和尺寸。

真实调用的参数、返回值和同步语义不变。事件每进程先记录 6 次，再每 120 次
抽样一次，至 8,192 次后停止日志；不按纹理分别计数。计时为抽样 wall，
不是完整帧时间、GPU 时间或 P95/P99。栈只取可解出的本进程模块名/RVA，
不输出模块完整路径或猜测未映射地址。文件为
`C:\windows\temp\winehua_wined3d_readback.log`，不要求修改 `WINEDEBUG`。

GNU `--wrap` 无法覆盖同一对象内部已绑定的调用。尤其 texture.c 内部
map→load_location 可能不经过 load 包装；没有 load 日志不能排除该路径。
本轮正面证据来自 map 栈，不能用没有复制/颜色转换日志单独作排除判断。

构建工具确认调用引用可包装、实际 map/present 调用已重定向、输入指纹不变，
并比较原库、诊断库和去调试部署库的非空导出名/实际 ordinal 集。
8 项构建工具单元测试、i386/x64 PE 编译重链接及重复构建无操作检查通过。
它们不代替 64 位 GL、视频、音频或生命周期真机回归。

补充测试时发现新版 objdump 多了 `+base[ordinal] hint` 列；最初宽松解析会
把两边都解析为空列表，不能作为导出一致性的证明。已改为支持两种格式、
校验 ordinal base 并拒绝空表/未解析行，随后两种位宽重新通过实际导出检查。
同时修复 manifest 对原 link 参数列表的引用被重定向操作修改的问题。

## 真机确认

本轮原 Guest Mesa、正常应用入口、`WINEDEBUG=-all`，无实验环境覆盖，
Legacy/Modern `batchMappedFlush` 保持产品开启。已安装的是 Host 诊断 v2 HAP，
不是完整生产基线。War3 实际为 32 位 D3D8，不是根据 UI 后端标签推断：

1. `d3d8.dll+0xb805` 对应 `d3d8_surface_LockRect`，surface.c:247。
2. v2 `wined3d.dll+0x1f7df6` 对应 `wined3d_resource_map`，resource.c:317。
3. v2 `wined3d.dll+0x1d6942` 对应 `wined3d_device_context_map`，device.c:4648。
4. 随后同一后缓冲的 present 经 `d3d8.dll+0xc4a0`，即
   `d3d8_swapchain_Present`，swapchain.c:102。

RVA 使用当时匹配的未剥离 DLL 解析。栈在 D3D8 边界截断，没有拿到可靠的游戏
函数地址；尚不能区分引擎逻辑与游戏进程内第三方调用方。

v2 Wine PID 364/TID 368（不是 Linux PID）日志里 60 个 map 抽样均为
`box=0,0,800,600,0,1`、`flags=0x80000800`，即 READ | NOSYSLOCK。
这是整幅后缓冲范围，不是 1×1 请求被扩大；原始 NULL RECT 和显式全尺寸 RECT
在此处已规范化，无法区分。NOSYSLOCK 不表示可以跳过 GPU 同步。
map 前有效位置为 TEXTURE_RGB (0x10)，map 后 present 前为
TEXTURE_RGB | SYSMEM (0x12)。前后缓冲均为 800×600、相同格式编号 116。
结合此前 Guest 实测，下载为 RGB565，每次 960,000 字节。

序号 4,200–6,480 的 20 次 map 抽样为 4.911–6.975 ms，均值 5.9485 ms；
这不是完整时间窗口或性能对照。17:53 左右实际兽族基地截图为 24 FPS、
应用 CPU 203%、系统 CPU 54%、电池 39℃，不是菜单。相邻主合成窗口
25.59 FPS、upload_bytes=0、failed_swaps=0；源图与全屏几何保持不变。
Host 仍每 120 帧执行 120 次 get、360 次 finish，无 deferred/failed。

原始证据仅保留于忽略目录 `.hvigor/outputs/wined3d-readback-20260831/`：
`v1-readback.log`、`v2-readback.log`、`v2-current.jpeg`。v2 日志 SHA-256 为
`eac5f182e7b5dbea1dba128e9e0544d62ab7854edb6fc161e852fa703ea2dab7`。
后续重新取日志会增加内容，不能套用此哈希。

## 优化结论与下一步

已定位额外读回的 D3D8 API 来源和范围，但没有证明下载内容无人使用。
不能跳过读回、伪造 idle、把部分区域当整纹理有效，或直接去掉三次 WAIT。
全屏呈现尾段不是目前证据支持的主要放大因素；完整读回也不足以解释
所有 10 多 FPS 场景的整帧耗时，绘制准备/提交随单位数增长仍需继续优化。

当前 `wine_env.cpp` 在 DXVK 模式只强制 D3D11/DXGI 为 native，D3D8/9 保持
WineD3D 兼容路线，因此 DXVK 2.6 的 D3D11 改善不能直接应用于这次 War3。
现有 Modern 源码/缓存含 D3D8，但其入口要求同版本 DXVK D3D9 bridge；
不能仅复制一个 d3d8.dll，也不能无回归直接让全部旧游戏改走 Venus。

下一项成本更低的路径区分实验：经典 War3 自带 OpenGL，
[暴雪经典版 FAQ](https://classic.battle.net/war3/faq/features.shtml)确认两种 API。
可从正常游戏入口用临时游戏参数验证自身 GL 路线，仍复用现有 Mesa/VirGL，
不增加产品 profile、持久化环境变量或 WHIP 字段。该实验尚不构成通用优化，
必须核实真实加载路线、相同场景、全屏输入、画面与视频；不能比较 GL 菜单
和 D3D8 战役后宣称翻倍。原 D3D8 同步/提交优化继续保留为独立工作项。

## DLL 覆盖与回退

以下为数据采集时安装的 v2 DLL；改进构建校验后重链接产物仅留本地，没有再次部署。

- i386 v2：`9e292ed21c9f61b574a99f54d3904fd34ab38c117a8f21f879bacb60b19182ee`。
- x64 v2：`b4f1a3204e3d73fb293f5194fd9583ea2917b1af75fa1885e9e3fba8cb8446bf`。
- i386 原库：`84b9709aba9a24b66364423295d1481356716f288c1b580cf132f145c61b6a53`。
- x64 原库：`41b8e64aecb57bf2b41679569fb136ab9d7f0012ab9390dffe33b0e49e0359ac`。

原库备份为上述忽略目录的 `wined3d-i386-production.dll` 和
`wined3d-x64-production.dll`。回退前停止整个应用 UID 进程树，分别恢复：

1. `/data/storage/el2/base/files/wine/bin/i386-windows/wined3d.dll`
2. `/data/storage/el2/base/files/.wine/drive_c/windows/syswow64/wined3d.dll`
3. `/data/storage/el2/base/files/wine/bin/x86_64-windows/wined3d.dll`
4. `/data/storage/el2/base/files/.wine/drive_c/windows/system32/wined3d.dll`

使用 HDC debug bundle 文件传输，核对四个目标的哈希。runtime 和 prefix 均是
实际文件，不能只还原一组；重新安装 HAP 不保证清理这些覆盖。不要删除前缀
或存档。完整生产回退还需恢复 [Host 基线 HAP](host-stage-timing-diagnostic.md)。

## 本轮收口：暂停扩大 War3 专项

用户随后明确要求：有明确性能问题且可优化才尝试；若需要归结到架构/CPU，
则考虑暂放。因此不继续扩大同步改造、CPU 采样或 D3D8→DXVK 路由实验。
结论是“已定位强制回读成本，但没有已验证的低风险明显收益改动”，
不是“已证明全部低帧都由 CPU 引起”。游戏进程 CPU 包含 Wine/Mesa/Box64，
不能等同游戏 AI；GPU 执行时间仍未测。

收口前正常入口的临时 `-opengl` 已启动经典版动态菜单，约 52–60 FPS。
稳态 Host 每 120 帧 `rpc_get=0`、`driver_finish=120`、presented=120/failed=0；
初始窗口有 3 次 get 和 1 次 present 失败，未混入稳态。菜单仍有 Host
`Unhandled input/output semantic: 3` 告警，完整渲染正确性未验收。
没有同一战役场景的 A/B，不能与 D3D8 局内 24–26 FPS 对比宣称翻倍。
此项仅保留为将来有具体需求时可恢复的游戏自身 GL 选项，不默认启用。

已还原全部四个 WineD3D DLL，哈希与上节原库一致；Guest Mesa 原库保持不变。
随后使用已校验的 `hud-nav-baseline-1.3.2-arm64.hap` 覆盖安装成功
（SHA-256 `64a8fc96ebedda8c28be4234b20f83a9596b56a4157e4e9cafe622ed160fc154`），
撤掉 Host 诊断 HAP。正常入口重启时 Game argument count=0、无环境实验覆盖，
`batchMappedFlush` 仍为 product/on。未重建环境、未删除前缀/存档、未修改游戏文件。
源码诊断能力保留，不进入生产 payload；公共重构和跨后端验收另行收口。
