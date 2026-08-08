# VirGL sRGB 偏色修复：统一回退（禁用硬件 sRGB 编码）

本文档记录旧柚Pro（VintagePomeloPro）在 Maleoon 920/935 等 GPU 上
VirGL（vrend/GLES 路径）画面偏黑/偏白的根因、两阶段修复与最终决策，
供其他代码线参照移植。

**最终决策（2026-08-08）**：无条件清除 `feat_srgb_write_control`，
统一回退到 Maleoon 910（无硬件 sRGB 编码）的行为，所有游戏颜色与 910
一致。代码中保留 FIXME 注释，未来再按 guest 采样语义实现硬件加速兼容
（见第 7 节 memo）。

## 1. 问题现象

- 部分游戏（如“灰色的果实”）通过 VirGL 渲染时，整幅画面明显偏暗/偏黑。
- 同一游戏在 Maleoon 910（9010 平板）颜色正常，在 Maleoon 920（9020 平板）
  与 935 偏黑。
- 非游戏桌面（explorer、窗口管理器）颜色正常，问题集中在 3D 渲染目标上。

## 2. 设备能力差异（实测）

| 设备 | GPU | `GL_EXT_sRGB_write_control` | `EGL_EXT_image_gl_colorspace` | 现象 |
| --- | --- | --- | --- | --- |
| 9010 | Maleoon 910 | 无 | 有 | 颜色正常 |
| 9020 | Maleoon 920 | 有 | 有 | 偏黑 |

> 注意：`GL_EXT_sRGB_write_control` 的有无只决定“host 是否把
> `VIRGL_CAP_SRGB_WRITE_CONTROL` 上报给 guest”，并不等于编码一定正确。
> 真正的差异在于 guest 拿到该 cap 后**改变了 surface/资源的格式组合**。

## 3. 根因分析

### 3.1 guest 侧行为

host 上报 `VIRGL_CAP_SRGB_WRITE_CONTROL` 后，guest Mesa 的 virgl 驱动会启用
`dest_surface_srgb_control`（见 mesa `virgl_screen.c` / `virgl_context.c`）：

```c
caps->dest_surface_srgb_control =
   (vscreen->caps.caps.v2.capability_bits & VIRGL_CAP_SRGB_WRITE_CONTROL) || ...;

/* virgl_create_surface 中允许格式不一致： */
assert(ctx->screen->caps.dest_surface_srgb_control ||
       (util_format_is_srgb(templ->format) ==
        util_format_is_srgb(resource->format)));
```

即 guest 可以创建 **UNORM surface 绑定 SRGB 资源**，并期望 host 在渲染时
自动完成线性→sRGB 编码（语义：surface 用 UNORM 视图，但存储是 sRGB）。

### 3.2 host（vrend）缺失的编码

实际抓到的 framebuffer 状态（修复前）：

```
surf_fmt=R8G8B8X8_UNORM  res_fmt=R8G8B8X8_SRGB  supports_view=1  use_srgb=0
```

问题链：

1. `vrend_create_surface` 检测到 surface 格式（UNORM）≠ 资源格式（SRGB），
   走 `glTextureView()` 创建 **UNORM 视图**（`internalformat` 用 surface 格式）。
2. `vrend_hw_emit_framebuffer_state` 的 `use_srgb` 只检查
   `util_format_is_srgb(surf->format)`，UNORM surface → `use_srgb=0`，
   **不执行 `glEnable(GL_FRAMEBUFFER_SRGB_EXT)`**。
3. 结果：渲染写入的像素被直接存进 sRGB 存储（未编码），呈现时又被当作
   sRGB 解码一次 → 画面偏暗。

910 上没有该 GL 扩展，cap 不上报，guest 全部用 UNORM/UNORM 组合，因此
“误打误撞”颜色正常；920/935 有扩展反而触发错误路径。

### 3.3 阶段一验证暴露的语义冲突（最终回退的原因）

阶段一（组合编码 + 硬件编码）在 9020 上：灰色的果实、仙剑4 颜色正常，
但**仙剑5 偏白**。对比两游戏 sampler view 完全一致：

```
SRGB 纹理 + UNORM view + GL_SKIP_DECODE_EXT
```

消费者语义却相反：

- 仙剑5：按线性 L 消费纹理内容，期望存储里是不编码的线性值 →
  组合编码后得到 f(L)，再被当作 L 使用 → 偏白。
- 仙剑4：在 sRGB 空间合成，期望存储里是编码值 f(L) →
  组合编码后正常。

vrend 无法从 view 格式区分两类游戏：全局 sampler DECODE 会让仙剑4 偏黑，
组合编码会让仙剑5 偏白；协议中现有 `srgb_decode` 只表达采样侧意图，
也表达不了“内容编码意图”。因此硬件编码与 guest wined3d 语义存在根本冲突，
最终选择统一回退。

## 4. 修复内容

全部改动位于 `thirdparty/virglrenderer/src/vrend/`。

> 阶段一（vrend f9c35d7，已放弃）：组合编码 + 硬件编码，见 4.1–4.3。
> 阶段二（最终）：无条件清除 `feat_srgb_write_control`，统一回退，见 4.4。
> 阶段一代码仍保留在源码中（因 feat 清除永不触发），关键位置已加
> `FIXME(硬件加速参考)` 注释，供未来恢复硬件加速时参考。

### 4.1 创建 sRGB 视图（`vrend_create_surface`）

`vrend_renderer.c` `vrend_create_surface()` 内，创建 texture view 时：
若 host 已启用 `feat_srgb_write_control`，且 surface 是 UNORM、资源是 SRGB
（dest_srgb_control 方向），则 `internalformat` 改用**资源的 SRGB 格式**，
使附件真正是 sRGB 格式：

```c
if (has_feature(feat_srgb_write_control) &&
    !util_format_is_srgb(surf->format) &&
    util_format_is_srgb(res->base.format))
   internalformat = tex_conv_table[res->base.format].internalformat;
```

### 4.2 framebuffer 状态启用硬件编码（`vrend_hw_emit_framebuffer_state`）

`use_srgb` 判断补充“UNORM surface + SRGB 资源”组合：

```c
if (util_format_is_srgb(surf->format)) {
   use_srgb = true;
   break;
}
if (!util_format_is_srgb(surf->format) &&
    util_format_is_srgb(surf->texture->base.format)) {
   use_srgb = true;
   break;
}
```

`use_srgb=true` → `glEnable(GL_FRAMEBUFFER_SRGB_EXT)`，由 GPU 硬件完成
线性→sRGB 编码（含 `glClear` 自动编码）。不触发 shader 手动编码位
（`needs_manual_srgb_encode_bitmask` 仍只对“surface 本身是 SRGB 且不支持
view”的场景设置），因此无软件编码、无双编码。

### 4.3 EGL image 导入声明 sRGB（能力驱动，配套）

`vrend_winsys_egl.c/.h`：

- 新增 `EGL_EXT_image_gl_colorspace` 检测（`virgl_has_egl_image_gl_colorspace`）。
- `virgl_egl_image_from_dmabuf()` 增加 `srgb` 参数；sRGB 资源导入时附加
  `EGL_GL_COLORSPACE_SRGB` 属性，使 EGL-backed sRGB 纹理真正以 sRGB 格式存在。

`vrend_renderer.c` `vrend_renderer_init()`：

```c
vrend_state.egl_image_srgb_import = virgl_has_egl_image_gl_colorspace(egl);
if (!vrend_state.egl_image_srgb_import)
   clear_feature(feat_srgb_write_control);
```

即：host 能以 sRGB 格式导入/创建纹理时才保留硬件 sRGB 路径；
无 `EGL_EXT_image_gl_colorspace`（部分 Maleoon 驱动）→ 清除 feat →
guest 回落格式匹配 + shader 编码路径（与 910 行为一致）。

配套修改：`vrend_hw_emit_framebuffer_state` 与 `vrend_clear_prepare` 中
shader 手动编码/手动 clear 转换在 `egl_image_srgb_import=true` 时跳过，
避免“硬件编码 + shader 编码”双编码偏黑。

### 4.4 最终方案：无条件清除 feat（阶段二）

`vrend_renderer_init()` 中无条件执行：

```c
/* FIXME: 硬件 sRGB 编码 (GL_EXT_sRGB_write_control) 在 Maleoon 920/935
 * 上与 guest (wined3d) 的 sRGB 语义冲突（详见本文档 3.3）。
 * 当前统一按 Maleoon 910 的行为处理：清除 feat，host 不编码，
 * SRGB 纹理内容保持线性 L，所有游戏与 910 一致（正常）。
 * 未来若要兼容硬件加速，需按 guest 采样语义精确决定内容编码，
 * 或扩展协议传递明确的 srgb_decode 意图。 */
clear_feature(feat_srgb_write_control);
```

效果：guest 不再启用 `dest_surface_srgb_control`，回到格式匹配 +
shader 手动编码路径，与 9010 行为完全一致。阶段一的 sRGB view /
framebuffer `use_srgb` / EGL sRGB import 代码全部保留但不会触发。

## 5. 验证结果

9020（Maleoon 920）统一回退后：

- 仙剑5：不再偏白，颜色正常；
- 仙剑4：不再偏黑，颜色正常；
- 灰色的果实：不再偏黑，颜色正常；
- 与 9010（Maleoon 910）行为一致。

代价：需要编码的内容走 shader 手动编码（与 910 相同），无硬件 sRGB 编码，
功能正确优先。

## 6. 移植注意事项

- **最终修复只有一处**：`vrend_renderer_init()` 无条件
  `clear_feature(feat_srgb_write_control)`（含 FIXME 注释）。不要按
  `GL_RENDERER`/`GL_VENDOR` 字符串或 GPU 型号分支。
- 阶段一 4.1–4.3 是已放弃的历史实现，可不移植；若保留，须同步保留
  `FIXME(硬件加速参考)` 注释，避免后续误以为硬件编码已启用。
- 若 guest 侧 Mesa 版本不同，请确认 `VIRGL_CAP_SRGB_WRITE_CONTROL` 上报后
  guest 会创建 UNORM surface + SRGB 资源；回退后该组合不再出现。

## 7. FIXME / 未来硬件加速兼容策略（memo）

当前统一禁用硬件 sRGB 编码，根因是 guest（wined3d）对同一
“SRGB 纹理 + UNORM view + SKIP_DECODE”组合存在两种相反的内容语义：
仙剑5 按线性 L 消费、仙剑4 在 sRGB 空间合成；vrend 无法从 view 格式区分，
现有 `srgb_decode` 只表达采样侧意图，表达不了内容编码意图。

未来若恢复硬件加速，可选方向：

1. 扩展协议：传递明确的“内容编码意图”（结合 view / 采样语义），host 据此
   决定 framebuffer 编码方式，只对语义明确的 draw 启用硬件编码。
2. host 侧按 draw 动态切换 `GL_FRAMEBUFFER_SRGB_EXT` 与 sampler
   `GL_SKIP_DECODE_EXT`/`GL_DECODE_EXT`，避免双编码。
3. 在上层（guest Mesa / wined3d）统一内容格式约定，避免同一纹理被两种
   语义消费。

启用条件（必须全部通过）：9010/9020/9030 全系回归 仙剑4、仙剑5、
灰色的果实 颜色正常；不能只按 GPU 型号开关。
