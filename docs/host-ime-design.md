# 宿主输入法 (HarmonyOS IME) → Wine 文本输入设计方案

目标：在 Wine 窗口获得键盘焦点时，能唤起 HarmonyOS 系统输入法，把输入
（重点是中文拼音组合与提交）正确地送进 Wine 应用；同时保证不干扰桌面
的日常操作稳定性。

## 0. 结论先行

- Wine 侧**不需要改**：`winewayland.drv/wayland_text_input.c` 是上游成熟
  代码，完整实现了 `zwp_text_input_v3` 的 client 端（enter/leave 时自动
  enable/disable，preedit/commit 经 `post_ime_update` → `WM_IME_*` 进入
  聚焦控件）。Winlator 与桌面 Linux Wine 的中文输入都走同一机制。
- 缺失的是**本应用 compositor 的 text-input 服务端**。此前做过一版快速
  实现，因不稳定已整体回退（未入库），原因是 surface 悬空指针、
  enter/leave 在每次触摸时重复发送、以及未经事件循环线程封送协议消息。
- 中文不需要“逐字按键映射”：拼音组合走 `preedit_string`，选字提交走
  `commit_string`，Wine 的标准 IME 消息链会把任意 Unicode 文本插入聚焦
  编辑控件。

## 1. 协议模型（以 Wine 打包的 draft 为准）

`zwp_text_input_manager_v3`：`get_text_input(id, seat)` 创建输入对象。

`zwp_text_input_v3`（注意这是较老的 draft，`enable` **不带 surface 参数**，
surface 由 `enter` 事件指定）：

- 请求（client→server）：`destroy`、`enable`、`disable`、
  `set_surrounding_text`、`set_text_change_cause`、`set_content_type`、
  `set_cursor_rectangle`、`commit`。
- 事件（server→client）：`enter(surface)`、`leave(surface)`、
  `preedit_string(text, begin, end)`、`commit_string(text)`、
  `delete_surrounding_text(before, after)`、`done(serial)`。

关键语义：

- compositor 决定焦点：键盘焦点进入某 surface 时对其所属 client 的所有
  text-input 对象发 `enter(surface)`；离开时发 `leave(surface)`。
- `done.serial` 必须等于该对象收到的 `commit` 请求数量（spec 要求），
  不能使用自增的本地计数器。
- 同一 seat 只允许一个 text-input 处于 enable；新对象 enable 时应先对旧
  对象发 `leave`。

## 2. 上一次实现为什么不稳定（教训）

1. **surface 悬空指针（use-after-free）**：窗口关闭后 entry 仍保存旧
   `wl_resource*`，后续 `leave/enter` 用它发事件 → 释放后使用 → Wine 进程
   崩溃（日志里 `BOX64 Signal 3/11` + 垃圾 `si_addr` 即此类）。必须给
   surface 挂 `wl_resource_add_destroy_listener`，销毁时清引用。
2. **enter/leave 风暴**：把“焦点跟随”挂在每次触摸的 `resolveToplevel`
   上，没做去重。手指每次按下都触发 enter/leave → Wine 反复
   enable/disable + `post_ime_update`，桌面随之卡顿/卡死。正确做法：只有
   焦点表面真正切换时才发，且最初可以用“输入法打开时才激活”作为隔离。
3. **跨线程封送**：`zwp_*_send_*` 从 NAPI/UI 线程直接调用。应统一走
   wl event loop 线程（经 `wl_event_loop_add_idle` 或 pipe 唤醒），避免与
   client 请求处理并发。
4. **焦点目标错误**：曾把 `enter` 发给桌面根窗口（explorer），提交文本
   全部落到 explorer 句柄。必须发给当前键盘焦点窗口的 surface。
5. **序列语义**：`done.serial` 用自增计数器不合 spec，会让部分客户端
   （严格校验 serial 的）拒绝应用状态。

## 3. 服务端正确实现要点

1. 在 compositor 内维护“键盘焦点 surface”：
   - 复用现有 toplevel 焦点（`InputRouter.setActiveToplevel` 的 tl 映射到
     surface），并做去重；
   - 焦点变化时：对旧 surface 的 client 发 `leave`，对新 surface 的 client
     发 `enter`。
2. 生命周期：每个被 enter 的 surface 挂 destroy listener；text-input 对象
   的 destroy 也要从表里移除。
3. 事件封送：所有 `send_*` 在 wl event loop 线程执行；NAPI 只入队。
4. serial：per-object 记录 client `commit` 次数，`done` 用它。
5. 唯一 enable：收到新对象 `enable` 时，向当前已 enable 的对象补发
   `leave`。
6. 稳定性隔离：宿主输入法关闭时协议路径完全静默（不发 enter/leave），
   桌面操作零影响；打开时激活，关闭时 deactivate + `leave` 清理。

## 4. 宿主 IME 桥（ArkTS 侧，已验证可行）

- 隐藏 `TextInput` + `FocusController.requestFocus` 能正常唤起系统输入法，
  `onChange(value, previewText)` 能拿到拼音组合与中文提交文本（此前实测
  “这个好像是…” 等提交已到达 ArkTS 层）。
- `onChange` 分段处理：
  - `previewText.value` 非空 → 组合态 → `preedit_string`（Wine 内显示候选）；
  - `preview` 为空 → 与上次已提交基线比较，新增部分 → `commit_string`，
    减少部分 → `delete_surrounding_text`；
  - Wine 无 text-input（游戏等非编辑控件）→ 回退逐字符 ASCII 按键注入。
- 输入法弹出时窗口压缩（avoidArea）需要重新实现：**去重 + 状态机**，
  只在“隐藏→显示”与“显示→隐藏”各执行一次 resize，且不在回调内同步
  resize 递归触发。

## 5. 中文适配要点

- **拼音候选**：IME preview → `preedit_string`，Wine 按 `WM_IME_COMPOSITION`
  显示下划线候选；**选字**：IME commit → `commit_string` → Wine 的
  `GCS_RESULTSTR` 插入完整汉字。全链路无需字符映射，天然支持中文。
- **中英切换**：由用户在系统输入法内切换；`TextInput` 保持
  `InputType.Normal` 即可。密码类场景以后可用 `inputFilter` 强制 ASCII。
- **候选窗口定位**：把 Wine 的 `set_cursor_rectangle` 转发给输入法
  （`TextInput` 光标几何由系统处理），v1 可先不做。
- **局限（与 Winlator 一致）**：只有聚焦了可编辑控件的 Wine 应用能收
  中文；游戏等纯键控界面只能走 ASCII 按键注入。

## 6. 验证计划

1. 记事本/编辑器输入中英文（拼音组合、候选、退格、回车）。
2. 输入法开着时在多个 Wine 窗口间切换焦点，确认 enter/leave 只随焦点
   切换各发一次。
3. 稳定性 soak：不打开输入法时桌面连续开/关窗口、点击、拖拽，日志中
   不得出现 text-input 事件；打开/收起输入法反复 20 次。
4. 关闭窗口/结束进程时无 `Signal 3/11` 崩溃增量。
