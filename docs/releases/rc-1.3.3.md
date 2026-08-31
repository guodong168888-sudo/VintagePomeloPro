# rc-1.3.3 用户测试候选

日期：2026-08-31。产品版本 `1.3.3` / `1003003`，API 23，ARM64。
目标为 `yifengling0/VintagePomeloPro` 的 `main` 与标签 `rc-1.3.3`；
这是已知限制公开的 RC，不代表全部图形优化计划完成。

## 本版包含

- 两条产品 route（VirGL/Vulkan）及共用 Native 策略、协议契约与环境适配。
- DXVK Legacy/Modern 保持 `batchMappedFlush` 开启；公共测试拒绝 off 实验。
- 全屏呈现和鼠标使用统一几何，保留逐 surface GL/Vulkan 分类与新鲜 SHM 回退。
- 性能 HUD 的独立设置区、顶部小字号横条及已验证可用的指标；底部导航高度/居中修复。
- GL 失败重试退避：隐藏桌面错误尝试从约 328 次/秒降至 19.4 次/秒。
  这是无效工作减少，不等同于正常游戏 FPS 提升。
- 测量工具改走正常游戏入口，修复同名子进程识别、GL 判图及帧序门禁。

## 已有验证及适用范围

原容器增量打包通过（Hvigor 9.845 s），SDK `verify-app` 通过。
与 1.3.2 限速候选的 30 个 Native/runtime/ArkTS 载荷条目逐一比对全部相同，
只更新产品版本元数据；226 个 Native/ArkTS/AppScope 源文件与现有构建树一致。

- HAP：`.hvigor/outputs/rc-1.3.3/VintagePomeloPro-rc-1.3.3-arm64.hap`
- 大小：467411450 bytes；ARM64/API 23/debug。
- SHA-256：`2bcc61e7124480810bdb03e4ce98321984e79972c856dfad6da84ab4e52a0bf2`。
- 内嵌 runtime：`2f9b5730da6b1013a7c9f268ef1cd20e8241bd38c7963408f35d5e3a47c00a0d`。
- 设备在 20:41 检查时未连接，因此 1.3.3 覆盖安装和正常入口检查仍待完成。
  下列真机结果属于字节相同的 1.3.2 候选，不冒充新版本安装结果。

- Host 测试、产品契约、ARM64/x86_64 API 23 GLES syntax 通过。
- GL x86/x64 各五轮缩放及后台恢复画面可见、帧数递增；不等同于完整帧序或长稳门槛。
- 两代 DXVK D3D11 cube 各 40/40 有效帧，未检出重复/倒退，Vulkan direct 动作契约通过。
- DXVK 2.6 会话中的 Quartz/GStreamer 动画可见并收到 `EC_COMPLETE`。
  只覆盖播放器周围 Wine 界面，不代表所有游戏 CPU UI 与真人听感验收。
- GL/音频 32/64 位功能短测已完成，基线 GL 的偶发 `0x505` 仍保留为问题。

原始证据与精确回退包见 [GLES 验证](../graphics/gles-direct-validation.md) 和
[GL 限速修复](../graphics/gl-background-backoff.md)。运行库诊断覆盖已撤回。

## 发布后仍须收口

1. 后台 consumer 暂停而 producer 仍工作的生命周期协调；现只限制错误重试。
2. 冷启动/缩放偶发 `0x505` 的进一步归因；不能把限速误称为根因已修好。
3. GL 32/64 位连续十分钟、资源增长及画面帧序；当前候选 War3 冷启动三次、
   动画到菜单、全屏鼠标和最小化恢复的完整重验。
4. 拆出 `syncManagedSmoke` 并清理已无启动调用者的旧 `SmokeRunner` 类与过期文档；
   生产环境已统一，但不能声称所有旧测试源码都已删除。
5. 媒体最后 PTS 与 progress 墙钟的差异需独立核对，不作为本次图形提速结论。

## 明确后置，不阻塞 EGL 默认 RC

- GLES Direct 已有实现但默认关闭；当前手机缺少 `EGL_OHOS_image_native_buffer`，
  未完成真实 Direct 矩阵和三组交替性能门槛，不做 EGL 对 EGL 的伪 A/B。
- War3 深度 CPU/转译优化按用户要求暂放；已知 D3D8 整帧 READONLY 回读不能直接删除。
- GPU 能力门控去重、Host 同步/上传、scanout 去拷贝、PC/x86_64 完整设备矩阵、D3D12 专项。

## 上游整合边界

本轮审计时 WineHua `master` 为 `74f2bfe`，包含合成器状态/输入/事件/零拷贝模块拆分，
以及 Native 顶层按八个功能域重排。它与本 RC 的本地实现已明显分叉。

先冻结并发布本 RC，再按上游语义移植用户功能与重构，不直接把当前整个工程合并过去。
每批分别验证全屏输入、surface 分类、SHM 新鲜度、生命周期和 batching；
保留产品身份、签名、游戏目录和运行库版本。对上游只提供通用且验证充分的变更，
性能候选与已稳定修复分开 PR，不能把 RC 标签当作上游合并完成。

## 发布可复现性检查

主仓库已补齐浅克隆历史，完整 HEAD 历史的 Gitleaks 扫描通过，签名文件未纳入跟踪。
DXVK Modern gitlink `ff2d6a2c3d26a3c3098f8a490e4e4adc5aa4704b` 已发布至
[`winehua/dxvk:codex/rc-1.3.3-mapped-flush`](https://github.com/winehua/dxvk/tree/codex/rc-1.3.3-mapped-flush)，
并从空白 Git 对象库按精确 SHA 成功拉取验证。原 `dxvk-modern-2.6` 分支未修改；
CI 使用递归 gitlink 检出，不执行 `submodule update --remote`。

CI 在编译前检查主库 SHA、RC 标签/产品版本及每级子模块实际 HEAD；
产物再次校验版本、ARM64 ELF/API 23，并上传源码/子模块/补丁版本清单与 HAP SHA-256。
手动发布按指定标签检出源码，工作流版本可来自修复后的 `main`；
构建 SHA、清单、产物和 Release 都必须对应标签提交，不能把当前分支产物挂到旧标签。
新增十项宿主回归测试覆盖版本错位、子模块缺失/错位及签名边界，已在原容器通过。

公开 CI 走明确的 `make hap-unsigned`，不读取私人签名，也不把 unsigned 文件冒充 signed。
GitHub Release 的无签名 HAP 与上方本地 debug 签名包是不同产物，哈希不能混用；
用户安装前须使用适当的签名证书/profile，单开开发者模式不足以完成签名。
本地签名预检和字体补丁反向校验通过。流水线最终结果以对应 GitHub Actions 运行为准。

首次标签 CI 已成功检出全部依赖，包括 Modern `ff2d6a2` 和 Wine `3fc36c4`；
重复拉取附注标签与浅检出的本地标签表示冲突，导致校验前停止。
修复仅写入 `FETCH_HEAD`，不移动或覆盖标签，并补充该场景回归测试（共十一项通过）。
`rc-1.3.3` 保留在 `358e3147`，后续 CI 修复单独提交至 `main`，再按既有标签手动构建。
