# 图形兼容性 Workaround 台账

## 使用规则

每条 workaround 必须有稳定编号。状态只能是 `active`、`candidate-remove`、`removed`。没有复现、回归测试和删除条件的 workaround 不得进入生产默认。

### Q001 — Maleoon 映射显存可见性与 inline upload

- 状态：`active`
- Owner：Guest Venus / Host VirGL shadow bridge
- 影响：Maleoon + Venus + 映射资源更新，DXVK 2.6 场景最敏感
- 症状：资源已由 Guest 写入但 Host/GPU 看到旧内容，表现为静帧、贴图错误或间歇花屏
- 当前措施：使用 precise dirty ring、inline GPU upload 和 coverage sort 组合，将 dirty range 在提交/展示前显式上传
- 生产默认：`product-vulkan` route 中的 DXVK Host policy 使用 precise-dirty、inline GPU upload 与 coverage sort；不暴露组合 profile 名称
- 主要位置：`napi_init.cpp`、`virgl_host_config.cpp`、`wine_env.cpp`、`wine_launch.cpp`；实现位于锁定的 Mesa/VirGL gitlink
- 回归：映射 buffer/texture 重复更新；Heaven 连续帧推进；上传 coverage/alias 边界测试
- 上游路径：最小化为 Mesa Venus 或 VirGL 的可见性/flush 复现，优先采用上游同步语义修复
- 删除条件：锁定上游版本在目标 Maleoon 设备通过相同矩阵，关闭 inline upload 后图像与 P99 帧时间不退化

### Q002 — 无 fence/query feedback 的远端同步模式

- 状态：`active`
- Owner：Guest Venus transport
- 影响：OHOS transport 无法导出所需 dma-buf/opaque-fd 同步对象的路径
- 症状：等待反馈可能死锁、长时间停帧，或 query/fence 结果永远不完成
- 当前措施：设置 `VN_PERF=no_fence_feedback,no_query_feedback`；部分路径同时关闭 semaphore feedback 和 multi ring
- 生产默认：由后端/transport 策略派生，不是用户选项
- 主要位置：`wine_exe.cpp`、`wine_env.cpp`、`SmokeRunner.ets`
- 回归：fence/query smoke、长循环帧推进、进程退出和前后台恢复
- 上游路径：验证目标平台是否具备可上游表达的外部同步能力；否则把 transport capability 做成显式能力位
- 删除条件：Host/Guest 双方支持并验证反馈通道，打开 feedback 后无死锁且结果一致

### Q003 — Box64 强内存屏障与 ring 可见性

- 状态：`active`
- Owner：Box64/Venus 进程边界
- 影响：ARM64 设备上的 x86_64 Guest Vulkan/DXVK
- 症状：弱内存序导致 ring 元数据或 payload 观察顺序错误，表现为随机卡帧、命令损坏或只在压力下复现
- 当前措施：`VN_WINEHUA_STRONG_RING_BARRIER=1`，并由 Box64 preset 保持强屏障语义
- 生产默认：DXVK/VKD3D 相关 ARM64 路径启用
- 主要位置：`wine_env.cpp`、`SmokeRunner.ets`、Box64 preset 传递链
- 回归：多线程 ring 压力、连续 submit、10 分钟稳定性和退出清理
- 上游路径：用 acquire/release 最小复现定位 Box64 或 ring 实现中的缺失内存序
- 删除条件：上游或本地原子语义修复后，在弱屏障 A/B 下长期稳定且无性能/正确性回归

### Q004 — RGBA8 SNORM render-target 自动仿真

- 状态：`active`
- Owner：DXVK compatibility layer
- 影响：支持采样但不支持该格式 color attachment 的 GPU，Maleoon 为已知目标
- 症状：DXVK 创建 SNORM render target 失败，或相关游戏出现黑屏/缺失效果
- 当前措施：`DXVK_WINEHUA_EMULATE_RGBA8_SNORM_RT=auto`，优先原生格式，仅在能力不足时仿真
- 生产默认：`auto`
- 主要位置：`wine_env.cpp`、`wine_child.cpp`、锁定的 `thirdparty/dxvk-modern`
- 回归：格式能力探测、创建/清除/采样 round-trip、相关游戏 smoke
- 上游路径：评估 DXVK format fallback 的通用实现，避免设备名称特判
- 删除条件：目标 DXVK/driver 组合原生支持，或上游 fallback 在设备矩阵通过且本地变量不再被消费

### Q005 — VirGL sRGB 首帧 framebuffer 策略

- 状态：`active`
- Owner：VirGL renderer/context compatibility
- 影响：首个 framebuffer 的 sRGB/linear 状态与 Guest 预期不一致的 OpenGL/WineD3D 路径
- 症状：首帧颜色空间错误、过亮/过暗，后续 framebuffer 切换后才恢复
- 当前措施：保留锁定 VirGL gitlink 中的首 framebuffer sRGB 策略
- 生产默认：随当前 VirGL gitlink 生效，无用户开关
- 主要位置：`thirdparty/virglrenderer` gitlink；版本由机器锁固定
- 回归：首帧截图像素/直方图、sRGB FBO 切换、WineD3D 老游戏 smoke
- 上游路径：先在纯 VirGL GLES 测试中复现，再核对上游 framebuffer sRGB 状态管理
- 删除条件：上游提交覆盖首帧与切换测试，目标设备像素结果与基线一致

### Q006 — GPU 名称正则驱动的 DXVK 2.6 门控

- 状态：`active`
- Owner：产品能力策略
- 影响：`Maleoon N` / `Mali-GN` 命名的 GPU；当前阈值为 920
- 症状：低于阈值的设备选择 DXVK 2.6 后不兼容；未知名称可能被误判
- 当前措施：通过 `getHostGpuName()` 和 `/(?:Maleoon|Mali-?G)\s*(\d+)/i` 判定，920 以下回退 DXVK 1.10
- 生产默认：`auto` 模式按此门控；显式选择仍必须经过能力约束
- 主要位置：`SystemSettings.ets`、`WineEngineService.ets`、`host_vulkan_probe.cpp`
- 回归：GPU 名称解析单测、空/未知/变体名称、低于/等于/高于 920 的后端选择测试
- 上游路径：用 Vulkan feature/format/extension probe 替代营销名称；GPU 名称只保留为诊断信息
- 删除条件：能力 probe 能稳定预测 DXVK 2.6 必要条件，并在目标设备矩阵与当前门控结果一致或更准确

### Q007 — VKD3D 持久映射 UPLOAD 按资源 Width 刷新

- 状态：`active`
- Owner：VKD3D-Proton / Guest Venus 映射可见性
- 影响：VKD3D 2.6 limited-500K profile 中长期保持 Map 的 D3D12 UPLOAD buffer
- 症状：只在 Map 时刷新 1 字节会留下旧常量数据；刷新整个 8–16 MiB 父 slab 又造成明显带宽和帧时间回退
- 当前措施：Map 时按 `resource->desc.Width` 标记写入；`ExecuteCommandLists` 前批量刷新仍处于映射状态且不超过 4 MiB 的 UPLOAD buffer
- 生产默认：仅由 `product-vulkan` 的 VKD3D 后端适配器启用 `VKD3D_WINEHUA_FORCE_COHERENT_MAP_SYNC=1`，不增加独立产品开关
- 主要位置：`patches/vkd3d-proton/0001-*`、`0019-vkd3d-flush-mapped-upload-width-on-execute.patch`
- 回归：gears 小常量 buffer、D3D12SingleGpu 2.5 MiB persistent CB、映射/取消映射/销毁竞态、96 MiB 父分配带宽回归
- 上游路径：将 OHOS/Venus 非同址 coherent 映射语义最小化后提交到 VKD3D/Venus；若 transport 获得正确 coherent 可见性则删除显式 flush
- 删除条件：目标设备关闭强制同步后仍逐帧更新正确，且 P95/P99 不劣于 Width flush 路径

## 新增记录模板

新增条目需包含：状态、Owner、影响范围、可见症状、当前措施、生产默认、代码位置、回归测试、上游路径和可验证的删除条件。
