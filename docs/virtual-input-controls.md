# 虚拟输入控件（v6 元素化模型）

本文档描述旧柚Pro 输入控制重构后的设计。旧 v5“固定游戏手柄分组 +
自由按键预设”模型已直接替换，不再保留读取兼容。

## 设计来源

参考 Winlator 的 Input Controls 实现：

- 控件类型与形状抽象：`BUTTON / D_PAD / STICK / TRACKPAD / RANGE_BUTTON`
  与 `CIRCLE / RECT / ROUND_RECT / SQUARE`。
- 画布任意排布：元素中心使用归一化坐标 `x/y（0.0-1.0）`，与屏幕比例无关。
- 预设模板、`.icp` 导入导出、方案级透明度。
- 编辑器为全屏透明画布，叠在游戏上实时预览。

与 Winlator 的差异：

- 注入走本地 `InputDispatcher → InputRouter → testNapi`（evdev 键码 +
  指针按钮），不是 Android KeyEvent；`.icp` 的 `KEY_*/MOUSE_*` 绑定名
  通过 `common/EvdevKeyNames.ets` 映射表转换。
- 支持元素级透明度覆盖（Winlator 只有方案级）。
- `RANGE_BUTTON` 使用本地键码列表 `keyList` 实现。

## v6 Profile 结构

```ts
interface InputProfile {
  id: string;
  name: string;
  schemaVersion: 6;
  cursorSpeed: number;        // 触摸板指针速度倍率 0.1-5.0
  overlayOpacity: number;     // 方案级透明度 0-100
  gamepadMappings: GamepadButtonMapping[]; // 实体手柄映射（原样保留）
  elements: ControlElement[];    // 当前设备画面使用的元素集
  elementsTablet?: ControlElement[]; // 废弃兼容：旧三套数据回退读取
}

interface ControlElement {
  id: string;
  type: ControlElementType;
  shape: ControlElementShape;
  x: number;   // 归一化中心 0-1
  y: number;
  scale: number;  // 0.5-2.0
  opacity: number; // -1 继承方案，0-100 元素级
  bindings: InputBinding[]; // 多键组合
  toggleSwitch: boolean;
  text: string;
  iconId: number;  // 预留，v1 恒 0
  visible: boolean;
  keyList: number[]; // RANGE_BUTTON 可选键
}
```

## 断点形态适配

输入方案按屏幕宽度断点分成三种形态，与 `BreakpointSystem`
输入方案只有一套元素，元素中心使用归一化坐标，自动适配任意屏幕比例。
编辑器画布就是当前设备画面：在当前画面上直接排布控件，无需切换
手机/平板/PC 形态（普通用户只针对当前设备设定）。

绑定槽位语义：

- `BUTTON`：`bindings` 最多 4 个，按下时同时注入全部键/鼠标按钮。
- `D_PAD / STICK`：`bindings` 依次为 上/右/下/左 四个方向键。
- `TRACKPAD`：不发键；按住滑动注入指针增量，轻点发送左键。
- `RANGE_BUTTON`：`keyList` 为可选键列表，滑动选键、点按发送当前键。

## .icp 导入导出

导出为 Winlator 兼容子集（`id/name/cursorSpeed/elements[]`，
元素含 `type/shape/bindings[4]/scale/x/y/toggleSwitch/text/iconId`），
写入 `Download/com.vintage.pomelopro/input_profiles/<name>.icp`。
本项目扩展字段（元素级透明度、可见性、keyList）不导出。

导入接受纯 Winlator `.icp` 与本项目导出文件：未知元素类型跳过，
未知字段忽略；`KEY_* / MOUSE_* / NONE` 名称经 `EvdevKeyNames` 映射，
无法识别的绑定名转为 `NONE`。导入结果作为当前方案的元素集。

## 模板与方案管理

随包五个不可删除的模板（`AppModels.ets` 工厂），提供横屏友好的初始排布：

| 模板 | 内容 |
| --- | --- |
| 通用 | D-PAD(WASD) + 触摸板 + 左右键 + 空格/E/Esc/Shift/Ctrl |
| 全键盘 | 带键盘外框的紧凑物理键盘排列；半高、左右留边，含功能键区、方向键与修饰键 |
| RPG | 左侧菜单/背包/地图/角色/任务，右侧数字技能竖条、动作键与触摸板 |
| 射击 | D-PAD(WASD) + 视角触摸板 + 开火/瞄准 + R/跳/Shift/Ctrl + 武器滚动键 |
| 动作 | 移动摇杆 + 视角摇杆 + A/B/X/Y + L/R + Start + Shift/Ctrl |

系统设置页只显示当前方案摘要，通过弹出窗口选择模板或自定义方案，避免方案列表
长期占据页面。基于模板新建方案时必须命名；自定义方案支持重命名、编辑和删除，
内置模板不可删除。模板带 revision，升级后旧的内置默认布局会自动刷新，自定义
方案保持用户数据。

所有默认布局均使用归一化坐标，并针对手机和平板分别校准控件比例和间距；全键盘
限制在约 84% 宽、48% 高的外框内。工具栏可移动且最终不会出现在虚拟按键中，
不作为默认布局避让区。

Shift/Ctrl 可启用按住模式：第一次完整点按锁定并保持 key-down，第二次点按释放；
Touch Cancel、方案切换、页面销毁会清理状态并强制释放，避免持续跑步等场景留下
粘键。鼠标点击与触摸使用同一切换语义。

## 编辑器

全屏画布编辑器（`InputLayoutEditor.ets`）：

- 点按选中元素，单指拖动移动，双指捏合缩放；画布即当前设备画面，
  直接在当前画面上排布。
- 属性面板显示重叠警告：元素互相遮挡时提示，便于规避。
- 底部操作栏：添加 按钮/方向键/摇杆/触摸板/滚动键；保存/退出/重置/
  复制/删除。
- 属性面板：文字标签、形状、开关模式、缩放、透明度（继承/自定义）、
  绑定键编辑（按键列表 + 自定义键码 + 鼠标键）。
- 实时预览：编辑时元素直接按最终效果绘制，不注入按键。

## 旧数据声明

存储 key 改为 `profiles_v6`，`schemaVersion=6`。加载时非 v6 数据
直接丢弃，无数据则创建默认通用模板。升级到本分支后，用户需要
重新配置输入方案（可导入 `.icp` 或从模板新建）。
