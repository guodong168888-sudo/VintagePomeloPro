# Vintage Pomelo Pro 主工程架构

本分支把 Wine 从首页启动流程拆成按需使用的兼容引擎。应用库扫描和浏览不会启动 Wine；只有 `wine-exe`、`wine-system` 或 `wine-desktop` 启动适配器需要运行时。

## 分层

- `AppCatalogService`：读取安装包内建清单，扫描应用专用 `games` 目录，并保留不可用卡片缓存。
- `LauncherAdapterRegistry`：按 `LaunchKind` 分发启动；首期提供 Wine 和 Harmony Ability 适配器，预留预编译工具/其他引擎适配器。
- `WineEngineService`：管理 `STOPPED / PREPARING / READY / SWITCHING / ERROR` 状态和运行时准备。
- `AppSessionService`：管理路径单例、PID、sessionId、toplevelId、后台恢复及模式冲突。
- `WineWindowManager`：选择桌面或单应用合成 Ability，并接收 Wayland toplevel 生命周期。
- `InputRouter`：把虚拟控件、实体键鼠和 Game Controller Kit 输入路由到活动 toplevel；失焦和切换时释放按键。

## 显示模式

桌面模式保持 Explorer desktop 作为合成 root，允许多程序和多窗口。同一路径重复启动时复用原 PID，会话层将已存在窗口提升到前台。

单应用模式在 Wine 引擎准备阶段不启动 Explorer。启动选定 EXE 前启用原有桌面合成器，并把该程序的首个 toplevel 标记为合成 root，因此主窗口、子进程窗口、对话框和弹窗仍走同一个全屏 XComponent。`SingleAppAbility` 为 singleton；进入后台只释放输入和隐藏 surface，不终止 Windows 进程。

## 程序目录规则

授权根目录为应用专用 Download 目录，其下固定扫描 `games`：一级目录一张卡，根目录 EXE 各一张卡。目录程序按“用户设置、目录同名、排除安装/卸载/运行库/崩溃工具后的唯一候选”选择；仍有歧义时生成不可用卡片，由用户在应用设置中关联 EXE。

扫描缓存与用户设置分别保存在 preferences。用户封面高于目录中的 `cover.*` 和 `folder.*`，没有封面时使用内建渐变默认封面。

## 后续边界

首期默认经 Controller Hub → WHGP → `winebus bus_ohos` 以 DirectInput / XInput 虚拟手柄进入 Wine，并将游戏 rumble 转发到实体手柄马达；可选 `keyboard_legacy` 回退到 Game Controller Kit → 键鼠/evdev 映射。多玩家热插拔不在本阶段。
