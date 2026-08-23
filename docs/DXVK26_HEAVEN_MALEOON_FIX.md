# DXVK 2.6 Heaven 黑屏修复与平移说明

## 适用范围

- Host：HarmonyOS / WineHua VirGL-Venus
- GPU：Huawei Maleoon，Vulkan `vendorID == 0x19e5`
- Guest：Wine + DXVK 2.6.2
- 已复现应用：Unigine Heaven 4.0 DX11

Cube 能正常运行并不能覆盖此问题。Heaven 高频更新动态 index、vertex、constant/UBO
以及纹理 staging 数据，因此会稳定触发 mapped-memory 可见性缺陷。

## 根因

VirGL/Venus 的 Host shadow mapped-memory 默认路径会先在 CPU 上把 guest 更新复制到
Host mapped pointer，再调用 `vkFlushMappedMemoryRanges`。Maleoon 920 上，这条路径返回成功，
Host 侧抽样和 CRC 也正确，但 GPU consumer 仍可能读取旧数据。结果是提交、Present 和
zero-copy 都在继续，画面却黑屏或出现错误几何。

决定性对照是在同一 command buffer 内使用 GPU update 携带同一批更新字节：Heaven 立即
正常出图。这排除了 DXVK shader profile、SPIR-V 版本、Wayland Present、guest memfd 和
批量 range 合并等方向。

## 最小产品修复

修改位置：

`thirdparty/virglrenderer/src/venus/vkr_physical_device.c`

函数：`vkr_physical_device_init_properties`

在 `__OHOS__` 构建中，仅对以下设备自动开启已有 inline shadow GPU uploader：

```c
physical_dev->winehua_shadow_gpu_upload_quirk =
   props->vendorID == 0x19e5 && strstr(props->deviceName, "Maleoon");
```

该 uploader 把 shadow 更新字节作为 command payload 放到 guest submit 之前执行，从而同时
建立数据传输和 GPU 顺序。非 Maleoon 设备的 `auto` 行为不变。

诊断覆盖仍保留：

- `VKR_WINEHUA_GPU_UPLOAD=0`：强制关闭，用于确认回归现象。
- `VKR_WINEHUA_GPU_UPLOAD=1`：强制开启，用于新设备资格验证。
- 未设置或 `auto`：使用上述设备 quirk。

## DXVK 自动选择

主仓库 `entry/src/main/ets/service/WineEngineService.ets` 的现有产品策略为：

- 支持的 Maleoon 920+：Auto 选择 `dxvk_modern_2_6`。
- Maleoon 920 以下：回退 `dxvk_legacy` 1.10.3。
- 显式 `dxvk_1_10` 和 `virgl` 选择保持有效。

不要把 shader 诊断 profile 或全局 uploader 强开带入产品默认配置。

## 已完成验证

- Modern x86/x64 D3D11 smoke：通过。
- Modern x86/x64 Cube：通过。
- Heaven 正常产品 Auto 路径：DXVK 2.6.2 正常显示。
- Heaven 长跑：VIRGL-ZC 12,840 帧、显示 24,360 帧，`failure=0`、
  `failed_swaps=0`，无 device lost。
- 签名测试包：
  `vintagepomelopro-1.2.8-arm64-v8a-v19-final-auto-modern-signed.hap`
- HAP SHA-256：
  `D2CF139CE5296A19CA2B1F7FA789EE0EB9809E06D74E6ADBE7111A2A842DA7FA`

## 平移检查清单

1. 以目标分支当前 VirGL gitlink 为基线，不要整棵替换子模块。
2. 平移 `vkr_physical_device_init_properties` 中的设备 quirk；确认目标分支已包含
   `winehua_shadow_gpu_upload_quirk` 和 inline uploader 实现。
3. 保留 `VKR_WINEHUA_GPU_UPLOAD=0/1/auto` 覆盖优先级。
4. 确认 Host 日志包含：
   `WineHua shadow GPU upload auto=1` 和
   `WineHua shadow GPU upload inline-submit enabled`。
5. 依次运行 D3D11 smoke、Cube、Heaven；Heaven 至少连续 300 帧。
6. 同时检查颜色/纹理、几何、HUD、`device lost`、uploader failure 和 swap failure；
   不能只以“有 Present”作为成功标准。

## 不应删除的边界

- 不要移除 CPU fallback；非 Maleoon 或 uploader 失败时仍需要它。
- 不要把 quirk 放宽为所有 Vulkan 设备。
- 不要用 `vkQueueWaitIdle`、每帧 `glFinish` 或强制 CPU readback 规避问题；它们会掩盖
  可见性缺陷并显著损害手机性能。
- 后续性能优化必须保持 SurfaceQueue zero-copy、fence 生命周期和 fallback 正确性。
