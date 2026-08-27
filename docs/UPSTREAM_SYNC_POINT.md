# 上游同步基线标记

> 用途：标明本地产品线已合并到 WineHua 上游的哪个提交，避免重复合并/漏合并。
> 本地镜像分支：`mirror_master`（跟踪 `winehua/master`，只读对照，不 push）。
> 维护命令：`git fetch winehua && git branch -f mirror_master winehua/master`
> 下次同步前先执行：`git log d256317e..mirror_master --oneline`

| 项 | 值 |
| --- | --- |
| 上游仓库 | `https://github.com/winehua/WineHua` |
| 上游分支 | `master` |
| **最后核对的上游 SHA** | `d256317e`（2026-08-27，`winehua/master` 尖端） |
| 功能同步起点（用户指定） | `10a9e6caf33e0147363793947461417dd60a8372`（master 线等价 `189c27c`） |
| 合并方式 | 第 1–5 步已对齐 EnvSpec / 基线 / Profile / Spawner（全部 kind 走 broker）。不上游品牌/版本号/CI/README |
| 本地对应分支 | `feature/align-env-spawn-1-4`（叠在 `feature/host-fps-hud` 上） |
| 核对日期 | 2026-08-27 |

## 已对齐的上游架构（第 1–5 步）

WineHua `master` @ `d256317e` 的 EnvSpec / Profile / SpawnRequest 重构，本仓按第 1–5 步落地（`175ed930` `af871191` `3725dfb5` `d00df45b` + 第 5 步 `f9aaaaed` 适配）。wineserver/wineboot 经 broker 单一通道，`wine_child Main` 截获 wineserver 转入本体。

明细见 `docs/private-upstream-sync.md`「2026-08-27 对齐 WineHua master 启动/环境栈第 5 步」。

## 已核对的上游增量（90edaae..d256317e）

从上一基线 `90edaae` 到 `winehua/master` 尖端 `d256317e`。行为修复已在 `feature/host-fps-hud` 吸收；架构第 1–5 步见上一节。

明细见 `docs/private-upstream-sync.md`「2026-08-27 WineHua master 增量（90edaae..d256317e）」。

## 已核对的上游增量（e16d79b..90edaae）

从上一基线 `e16d79b` 到 `winehua/master` 尖端 `90edaae`。采纳 Box64 兼容档位 native 通道（`7cff882` `dcf3906` `90edaae`），跳过上游 `Box64Dynarec.ets` 与版本标签。

明细见 `docs/private-upstream-sync.md`「2026-08-25 WineHua master 增量（e16d79b..90edaae）」。

## 已核对的上游增量（10a9e6c..e16d79b）

从用户指定功能基线 `10a9e6c` 到 `winehua/master` 尖端 `e16d79b`。`98eaca5` 已在上一轮同步；本轮采纳 `189c27c`（光标门禁）、`15c53ee`（resize 强制重绘），跳过 `e16d79b`（CI mono）。

明细见 `docs/private-upstream-sync.md`「2026-08-24 WineHua master 增量（10a9e6c..e16d79b）」。

## 已核对的上游增量（ff76a8f..98eaca5）

从 `ff76a8f`（含）到 `winehua/master` 尖端 `98eaca5`。功能链已 cherry-pick 到
`feature/sync-winehua-ff76a8f`，并叠在 VintagePomeloPro `main` 的 UI 上
（浮窗桌面、PC 沉浸全屏、蓝牙键盘 XComponent 焦点、宿主 IME）。

明细与跳过项见 `docs/private-upstream-sync.md`「2026-08-23 WineHua master 输入/合成器同步」。

## 已核对的上游增量（d9c667e..1036ada，共 5 个提交）

连同先前暂缓的合成器 Layer 重构链（`76a2cd4`→`13cc583`）一并合入，明细见
`docs/private-upstream-sync.md`「2026-08-06 合成器 Layer 重构全链合并」。

## 已核对的上游增量（996aabb..d9c667e，共 11 个提交）

- 采纳（手动移植）：
  - `8fb8488`（wine 内部启动的进程登记到任务列表）→ broker.cpp 全量 AddProcess + ParseProcessName、wine_process.cpp basename 兼容反斜杠（私有 Index 已有 1.5s 轮询，未做 process-updated 推送）。
  - `e5cd7fa`（全屏游戏点击按 zIndex 命中上方窗口 + 菜单被全屏覆盖）→ 私有 input_resolver.cpp 全屏分支前置命中（z-order 高于全屏窗口的 toplevel/subsurface）。
  - `bb617a4` 的 UpsertEnvLine 去重语义（删全部同 key 再追加，避免 WEAKBARRIER 等重复 key）；整体重构（SpawnViaBroker 收敛）与私有启动链路差异大，维持私有实现。
  - `d9c667e`（explorer 登记名 desktop）：私有用 `@engine/explorer` 引擎标记体系，语义不同，未采用。
- 跳过：`7ed8ad2`（dinput_click_probe 已迁移进私有 wine 子模块）、`faf98af`（私有 CI 已装 curl、mono 下载成功）、`d3688e1`（BOX64 __aarch64__ 守卫私有已有）、`c5263a3`/`82ee3f3`/`1dc0283`（docs/清理）、`70abb0b`（上游版本号）。

## 已核对的上游增量（0ed802c..8089968，共 28 个提交）

- 结论：Aug 1-2 的输入/mono/字体/合成阶段修复与本地已有工作**等价**（另一条工作线已同步进上游），**未重复合并**；真正缺失的 **Aug 3 `8089968`**（zwp_relative_pointer_v1 取代 warp 补偿）已 cherry-pick（→ `0e2a86e`）。
- 真正缺失且暂缓：合成器 Layer 重构（阶段 1-4，`76a2cd4` `d5deed7` `6df338a` `c2bd0ee` 等）——大重构，与 1.1.2 修复无关，另行评估。
- 其余为文档/CI/清理类（`088fa6a` `1fba92d` `f817c12` `b40ef56` `a753d15` `8048b95` `1c778af` `8e022b4` `5fb8b86` `f9771a3` `7bd10c8`），按需选择性采纳，不阻塞产品修复。

## 已核对的上游增量（8089968..996aabb，共 5 个提交）

- 已合并：`996aabb`（warm-prefix 显式播种 wineboot boot 事件 + 自动 explorer 走 broker 通道）→ `f2f9cfe`；`build_deps.sh` 同步（BUILD_WINE_MONO 默认启用）。
- 暂缓：合成器 Layer 重构延续 `13cc583`（ToplevelState 封装）、`8ab97c3`（层序/全屏几何对象方法）——与私有 compositor 架构冲突，维持暂缓。
- 跳过：`82ee3f3`（README Contributors）、`c5263a3`（.gitignore，CI 侧）。
- 冲突处理：`.github/workflows/build.yml` 保留私有 CI 环境值（上游 GFX/Vulkan/Mono 全开，私有 workflow 不变）。
