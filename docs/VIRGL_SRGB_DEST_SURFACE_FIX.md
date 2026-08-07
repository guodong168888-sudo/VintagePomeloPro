# VirGL sRGB 偏色修复：dest_surface_srgb_control 组合的硬件编码

本文档记录旧柚Pro（VintagePomeloPro）在 Maleoon 920/935 等 GPU 上
VirGL（vrend/GLES 路径）画面偏黑的根因与修复，供其他代码线参照移植。
修复原则：**按能力（扩展/格式组合）切换实现，不写死 GPU 型号**。

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

## 4. 修复内容

全部改动位于 `thirdparty/virglrenderer/src/vrend/`，能力驱动，不依赖 GPU 型号。

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

## 5. 验证结果

9020（Maleoon 920）修复后 framebuffer 状态日志：

```
use_srgb=1  surf_fmt=R8G8B8X8_UNORM  res_fmt=R8G8B8X8_SRGB  supports_view=1
use_srgb=0  surf_fmt=B8G8R8A8_UNORM  res_fmt=B8G8R8A8_UNORM  supports_view=1
```

- 第一行：dest_srgb_control 组合 → `GL_FRAMEBUFFER_SRGB_EXT` 硬件编码生效。
- 第二行：纯 UNORM 组合 → 不需要编码，`use_srgb=0`，行为正确。

游戏画面颜色恢复正常，且走的是 **GPU 硬件 sRGB 编码路径**（无 shader 软件
编码、无性能回退）。

## 6. 移植注意事项

- 修复逻辑以 `feat_srgb_write_control` 和格式组合为条件，**不要**按
  `GL_RENDERER`/`GL_VENDOR` 字符串或 GPU 型号分支。
- 未来更强的新 GPU 若同时支持 `GL_EXT_sRGB_write_control` 与
  `EGL_EXT_image_gl_colorspace`，会自动走硬件编码；只有扩展确实缺失时才
  回落软件路径。
- 若其他代码线不包含 EGL image 导入路径，第 4.3 节可只保留
  `feat_srgb_write_control` 的格式组合判断（4.1/4.2），EGL 相关条件按
  `#ifdef HAVE_EPOXY_EGL_H` 保护。
- 若 guest 侧 Mesa 版本不同，请确认 `VIRGL_CAP_SRGB_WRITE_CONTROL` 上报后
  guest 确实会创建 UNORM surface + SRGB 资源（可用 framebuffer 状态日志核对
  `surf_fmt/res_fmt`），再决定是否需要同样处理反向组合
  （SRGB surface + UNORM 资源，该组合现有代码已由 SRGB view + use_srgb 覆盖）。
