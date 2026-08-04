# 上游同步基线标记

> 用途：标明本地产品线已合并到 WineHua 上游的哪个提交，避免重复合并/漏合并。
> 下次同步前先执行：`git fetch origin && git log LAST_MERGED_UPSTREAM_SHA..origin/master --oneline`

| 项 | 值 |
| --- | --- |
| 上游仓库 | `https://github.com/winehua/WineHua` |
| 上游分支 | `master` |
| **最后合并的上游 SHA** | `d9c667e4bdbc4792b83e6cd3d108a196efbf5bf8`（2026-08-05，explorer 桌面模式进程登记名） |
| 合并方式 | 选择性 cherry-pick / 手动移植 + 等价内容人工核对 |
| 本地对应分支 | `sync/master-dxvk-1103` → `private/wine-engine-app` |
| 本地对应提交 | `acaf19e`（feature/20260803-master-sync，1.1.4 / 1001004） |
| 核对日期 | 2026-08-05 |

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
