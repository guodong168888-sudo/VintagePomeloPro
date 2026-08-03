# 上游同步基线标记

> 用途：标明本地产品线已合并到 WineHua 上游的哪个提交，避免重复合并/漏合并。
> 下次同步前先执行：`git fetch origin && git log LAST_MERGED_UPSTREAM_SHA..origin/master --oneline`

| 项 | 值 |
| --- | --- |
| 上游仓库 | `https://github.com/winehua/WineHua` |
| 上游分支 | `master` |
| **最后合并的上游 SHA** | `8089968057e3b577799ed223c31bfbd00f69ce56`（2026-08-03，`0ed802c` 之后的 Aug 3 输入提交） |
| 合并方式 | 选择性 cherry-pick（36 个 dxvk 1.10.3 相关提交）+ 等价内容人工核对 |
| 本地对应分支 | `sync/master-dxvk-1103` → `private/wine-engine-app` |
| 本地对应提交 | `ab4fdab`（feature/20260803-master-sync，1.1.2 / 1001002） |
| 核对日期 | 2026-08-03 |

## 已核对的上游增量（0ed802c..8089968，共 28 个提交）

- 结论：Aug 1-2 的输入/mono/字体/合成阶段修复与本地已有工作**等价**（另一条工作线已同步进上游），**未重复合并**；真正缺失的 **Aug 3 `8089968`**（zwp_relative_pointer_v1 取代 warp 补偿）已 cherry-pick（→ `0e2a86e`）。
- 真正缺失且暂缓：合成器 Layer 重构（阶段 1-4，`76a2cd4` `d5deed7` `6df338a` `c2bd0ee` 等）——大重构，与 1.1.2 修复无关，另行评估。
- 其余为文档/CI/清理类（`088fa6a` `1fba92d` `f817c12` `b40ef56` `a753d15` `8048b95` `1c778af` `8e022b4` `5fb8b86` `f9771a3` `7bd10c8`），按需选择性采纳，不阻塞产品修复。
