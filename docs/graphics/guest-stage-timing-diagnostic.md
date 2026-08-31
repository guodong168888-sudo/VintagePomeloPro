# Guest 阶段诊断库（非产品默认）

2026-08-31，在 `refact/gl-optimization` 上补充 Host 阶段计时的 Guest 对照。
通过 `make guest-stage-timing` 只编译主仓库的一份 C 文件，并重新链接现有
x86_64 Mesa 对象。没有修改 Wine/Mesa/VirGLRenderer 子模块、原构建缓存、
`entry/libs` 或 `wine-data.zip`；目标不会自动部署，也不是性能优化开关。

构建与测试均在既有 `vp-build` 容器执行：

```sh
make test-guest-stage-timing guest-stage-timing
```

输出位于 `build/guest-stage-timing/x86_64/`。脚本核对原编译命令、交叉对象的
未定义符号、链接后的 wrapper，并记录输入 SHA-256；输入未变化时无操作。
单元测试覆盖透传、正 busy/负错误、时钟失败、命令边界、嵌套计时、身份及容量。

## 指标边界

- 统计按线程、winsys、连接 generation 和最近 present 的 surface/尺寸隔离。
  第一次 present 只建立身份，不把之前的初始化成本归入第一帧。
- 每 120 次 present 输出一条 `[GUEST-STAGE] v=2`，复用已有
  `WINEHUA_VTEST_FRONTBUFFER_LOG`，没有增加启动环境变量或 WHIP 字段。
- 每项为 `calls/wall_us/cpu_us/max_wall_us/positive/negative/invalid_clock`。
  busy 返回正数表示仍忙，并非错误。CPU 是调用线程 CPU，不是全部游戏 CPU。
- submit/busy_check/busy_wait/get/put/present 计时保留真实协议调用；
  `get` 仅测发送请求，协议 2 之后的 WAIT 另计。
- `read_pixels`、`get_texture` 是上层 Mesa API，包含内部 RPC；
  `api_nested=1` 提醒不能与 busy/get 相加。规格字段仅为该窗口最后一次参数。
- `draw_packets` 是编码 DRAW_VBO 包数量，不等同于 Windows draw call，
  `words` 也不等同于顶点数或纹理上传量。解析不越过包边界或读取命令 payload。
- busy caller RVA 来自直接返回地址，用匹配 SHA 的库解析，只说明调用位置；
  不是可靠完整栈或函数热点采样。未映射地址明确标记，不猜 JIT 归属。
- TLS 最多跟踪八个 winsys；溢出透传不统计。没有析构 hook，尾部不足 120 帧
  可能不输出；身份变更可输出旧窗口。上层 API 使用该线程最近活动 winsys，
  多上下文 API 归属还需进一步验证，不能称为逐 surface 的完全准确追踪。
- 诊断本身有开销，未量化观察者影响；这里的 FPS 不是产品基线 A/B。

## 实机覆盖与回退

安装的是独立 Host 诊断 HAP v2，详见 [Host 说明](host-stage-timing-diagnostic.md)。
Guest 诊断使用应用调试传输通道，完整停止本应用进程后替换提取目录中的四个
等价 Gallium 文件；没有修改前缀、存档或重新打包 467 MB HAP。

逻辑沙箱相对 `/data/storage/el2/base/files/wine/bin/guest_gfx/lib/`：

- `libgallium-25.0.1.so`
- `dri/swrast_dri.so`
- `dri/kms_swrast_dri.so`
- `dri/virtio_gpu_dri.so`

原始四个文件均为 15,741,104 字节，SHA-256：
`28101aed4dd8256cafaff657b85d567e0dfed93fb6ae5682c1679ca491b840e4`。
仅备份一份到忽略目录 `.hvigor/outputs/guest-stage-20260831/libgallium.production.so`。

Guest v1 为 15,747,576 字节，SHA-256：
`48a92ae93e7d8371017eee353f6cba87d22d1061ef0215cc8a9676ccb1276d46`。
Guest v2 加入上层 API，为 15,748,992 字节，SHA-256：
`9bf62a1c4d36ba1de7ef98895cf0e53e2da0595518e1a9240c5816059807cb15`。

正常入口成功启动 War3，菜单和实际战役均产生有效帧和计时。此结果不代替
GL 32/64 位、最小化/恢复、视频、DXVK、长稳和固定场景性能验收。
`batchMappedFlush` 始终为 product/on，未移除任何 finish、读回或队列同步。

**结束实验或恢复产品时，必须先停止整棵应用进程，再恢复并校验上述四个文件。**
覆盖安装相同 `wine-data.zip` 的生产 HAP 不保证重新提取 Guest 库，不能单靠
重装 HAP 宣称回退完成。原始证据和逐次运行清单保存在同一忽略目录，勿提交。
