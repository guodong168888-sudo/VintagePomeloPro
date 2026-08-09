# VirGL sRGB 兼容修复：按首个 render target 固化写入策略

本文记录 VintagePomeloPro 在 GLES/VirGL 路径上同时兼容 PAL4、PAL5 的
sRGB 方案。最终实现不按游戏名、进程路径、GPU 型号或设备型号分支，只依据
host 能力、render target 格式，以及同一 VirGL sub-context 首次出现的相关
framebuffer 状态。

## 最终结论（2026-08-09）

1. 恢复 v1.1.6 的 guest-visible 行为：host 具备 GL colorspace 时继续上报
   `VIRGL_CAP_SRGB_WRITE_CONTROL`，不强制把 UNORM surface 改成 sRGB view，
   不给 dma-buf import 追加 sRGB colorspace，也不全局改变 sampler decode。
2. 第一个相关 framebuffer 若包含 alpha-bearing
   `RGBA_UNORM surface -> RGBA_SRGB resource`，则一次性选择“保留 guest
   写入”，后续 XRGB attachment 不补编码。
3. 第一个相关 framebuffer 若是
   `XRGB_UNORM surface -> XRGB_SRGB resource`，则一次性选择“XRGB 软件编码”，
   在 fragment shader 写出和 `glClearColor` 路径做 linear-to-sRGB 转换。
4. 策略一经选定不再被后续无关 render target 改写。这样可避免启动时序、
   贴图创建顺序或另一个窗口改变已经正确的主画面。

ARM64 真机验证结果：PAL5 颜色与房屋材质正常；PAL4 颜色正常；灰色的果实
不再偏黑。三项均由用户在同一正式候选包上确认。临时 `[srgb-diag]` 日志已
从最终源码移除。

## 为什么以 v1.1.6 为基线

对比 v1.1.6 tag 与问题版本后确认：Mesa gitlink 没有变化；颜色相关差异只来自
VirGL 子模块的两次 sRGB 修改。v1.1.6 的 PAL5 已知正常，因此它是可靠的
PAL5 基线，而不是继续在阶段一/阶段二上叠加采样或 present 补偿。

历史实验矩阵：

| 路径 | PAL4 | PAL5 | 结论 |
| --- | --- | --- | --- |
| v1.1.6：cap 可见、host 不额外编码 | 偏暗 | 正常 | PAL5 基线 |
| sRGB view + framebuffer 硬件编码 | 正常 | 偏白 | PAL5 被过度转换 |
| 无条件隐藏 cap | 正常 | 偏白 | guest 仍产生格式错配，不能解决 |
| 全局 UNORM-view sampler decode | 正常 | 偏黑 | PAL5 过度解码 |
| v1.1.6 + 首个目标分类 + XRGB 软件编码（最终） | 正常 | 正常 | 通过 |

## 可区分的 render state

真机独立日志显示：

- PAL4 framebuffer 先出现且持续使用
  `R8G8B8X8_UNORM / R8G8B8X8_SRGB`；
- PAL5 同一 sub-context 先出现
  `R8G8B8A8_UNORM / R8G8B8A8_SRGB`，随后也可能出现 XRGB 组合。
- 灰色的果实先以独立的 1024×576 XRGB 资源建立主画面，约 18 秒后才出现
  另一个 1024×1024 RGBA 资源。旧实现会在 RGBA 出现后把整个 sub-context
  从“编码”永久改成“不编码”，导致已经正确的 XRGB 主画面整体偏黑。

因此既不能“见到 XRGB 就始终编码”，也不能“之后见到任意 RGBA 就反向关闭
编码”。正确的兼容启发式是由首个相关 framebuffer 一次性分类，后续附件只
执行已选策略。该状态来自真实的渲染格式与初始化顺序，不依赖游戏识别，同类
后续游戏会自动获得相同行为。实现同时覆盖 R8G8B8 与 B8G8R8 的 A8/X8
UNORM/SRGB view-compatible 组合。

## 实现位置

改动位于 `thirdparty/virglrenderer/src/vrend/vrend_renderer.c`：

- `vrend_is_unorm_surface_of_srgb_resource()`：识别 RGBA/BGRA 的 A8/X8
  UNORM-surface / sRGB-resource 配对；
- `vrend_classify_unorm_srgb_write_policy()`：只在策略为 `UNDECIDED` 时检查
  当前 framebuffer；alpha-bearing 优先选择 `PRESERVE`，否则 XRGB 选择
  `ENCODE_XRGB`；
- `vrend_hw_emit_framebuffer_state()`：
  - 在第一次相关绑定时固化 `unorm_srgb_write_policy`；
  - 仅在 GLES、host 具备 `feat_srgb_write_control`、策略为 `ENCODE_XRGB`、
    且当前为 X8 配对时设置 `needs_manual_srgb_encode_bitmask`；
- `vrend_clear_prepare()`：为相同 X8 配对转换 clear 的 RGB 分量；alpha 不转换；
- `vrend_renderer_init()`：恢复 v1.1.6 的能力判断，仅在 winsys 不具备 GL
  colorspace 时清除 `feat_srgb_write_control`。

阶段一加入的 sRGB texture view、`GL_FRAMEBUFFER_SRGB_EXT` 错配附件启用、
`EGL_EXT_image_gl_colorspace` dma-buf import 扩展均已撤销，避免硬件路径与
guest 的内容语义发生双重转换。

## 兼容边界与回归要求

- 9010 类不具备 `feat_srgb_write_control` 的 host 不进入新增 XRGB 软编码分支，
  保持既有行为。
- 9020/9030 类具备能力的 host 按 render state 自动分流；不允许增加
  `GL_RENDERER`、设备型号、游戏名或可执行文件路径白名单。
- 新增格式时，应扩展“view-compatible UNORM/sRGB 配对”识别，而不是增加
  应用特判。
- 发布前至少回归 PAL4、PAL5、灰色的果实；建议追加 9010/9030 硬件覆盖。

仍需注意：该策略解决的是当前 D3D/Wine guest 可观察到的两类写入语义。如果
未来 guest 协议能显式传递内容编码意图，应优先改为协议驱动，移除格式启发式。
