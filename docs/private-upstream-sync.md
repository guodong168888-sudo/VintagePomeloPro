# 私有分支上游同步记录

目标分支：`private/wine-engine-app`

基线：WineHua `VintagePomeloMaster` @ `ba7218a`

## 2026-07-18 私有基线

- 来源：本地 `VintagePomeloMaster` @ `ba7218a`
- 纳入：1.0.5 配置与品牌图标、guest-gfx 修复、项目构建技能。
- 目的：在不移动现有分支的前提下建立 VintagePomeloPro 私有主工程。
- 验证：原工作区状态/diff、现有分支指针、`origin` 和 `.gitmodules` 均保持不变。

## 上游提交

### 2026-07-18 Wayland 窗口与图形修复

| 上游 SHA | 私有分支 SHA | 范围 | 选择原因 | 合并结果 |
| --- | --- | --- | --- | --- |
| `f5ad791` | `d998e83` | Wayland popup、ArkUI 子窗口 | 修复 PC 模式弹出菜单被窗口边缘裁剪 | 与双显示模式的 `DisplayMode` 导入合并，保留 popup 管理器和单应用模式 |
| `7f6b0ae` | `3548ae8` | Wayland/EGL alpha 合成 | 支持 Pad 端异型窗口透明混合 | 无冲突同步 |
| `4b0c3db` | `8effc60` | PC ARGB 子窗口、窗口 mask、NAPI | 支持分层/异型窗口并保留 popup 回退宿主 | 合并 `sessionId/clientPid` 归属；PC 窗口延迟到首帧分类，桌面/单应用合成继续携带完整会话信息 |
| `2afd8bf` | `133464e` | EGL overlay、Wayland z-order 与输入命中 | 修复桌面模式 zero-copy 内容错误置顶及点击命中 | 无冲突同步 |

- 跳过：品牌、发布、实验性首页和与 Wine 引擎化无关的提交。
- 子模块：未更新 gitlink，未修改 `.gitmodules` 或第三方 URL。
- 静态验证：冲突标记清除，`git diff --check` 通过。
- 构建验证：Docker 中 API 22 ARM64 `assembleHap` 成功，CMake/Ninja、ArkTS 和 HAP 打包均通过；包内仅含 `arm64-v8a` 原生库，并包含 Wine/Box64/guest gfx 运行时。
- 规则验证：目录与模型规则测试 15 项通过，覆盖 EXE 选择、封面优先级、路径规范化、稳定卡片 ID、显示模式和引擎状态转换。
- 签名验证：release HAP 使用 v3 签名块，官方 `hap-sign-tool verify-app` 验证 26 个 ARM64 原生库、证书链和 SHA-256 摘要通过。
- 真机状态：本轮 HDC 无在线目标，因此未执行安装与真机 UI/输入回归；产物已完成构建、release 签名和离线验签。

后续仍仅接受 Wine/Box64、Wayland、图形/音频/输入、HarmonyOS API 或构建运行时修复；每个提交继续在此记录来源 SHA、文件范围、选择原因和验证结果。
