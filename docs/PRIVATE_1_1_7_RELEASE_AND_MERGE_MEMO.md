# VintagePomeloPro 1.1.7 私有差异与后续合并备忘

> 日期：2026-08-09
> 产品：旧柚Pro / `com.vintage.pomelopro`
> 版本：`1.1.7` / `1001007`
> 私有发布分支：`private/wine-engine-app` → `VintagePomeloPro:main`
> WineHua 上游核对基线：`origin/master` @ `1036ada`

本文只记录 1.1.7 发布时相对 WineHua master 必须保留的产品语义、容易在后续
合并中误删的修复，以及最小回归矩阵。完整历史仍见
`private-upstream-sync.md`、`UPSTREAM_SYNC_POINT.md`、
`virtual-input-controls.md` 和 `VIRGL_SRGB_DEST_SURFACE_FIX.md`。

本轮功能提交按可独立移植的边界拆分：

| 私有提交 | 作用 |
| --- | --- |
| `a8c9d68` | VirGL gitlink、首个 render target sRGB 写入策略与分析文档 |
| `b8167cf` | 游戏内鼠标坐标空间、relative-pointer 路由与全屏 raise 时序 |
| `7b1c391` | 五套输入模板、全键盘、方案弹窗/命名/删除和修饰键锁定 |

## 一、合并原则

1. 不要把 WineHua master 整体覆盖到私有分支，也不要用“冲突全部选 theirs”处理
   ArkTS 页面、Wine 启动链、窗口管理、输入或打包脚本。
2. 先 `git fetch origin`，从 `1036ada..origin/master` 逐提交审查；按 Wine/Box64、
   Wayland、图形、音频、输入、Harmony API、构建运行时分类选择性移植。
3. 子模块是独立仓库。先确认提交在其远端可获取，再更新父仓库 gitlink；禁止提交
   指向仅存在于本机的 SHA。
4. 合并后必须保持 API 23、`BUILD_GUEST_GFX=1`、HAP native ABI 与 x86_64 guest
   ABI 的架构分离，不能因为 ARM64 HAP 把 Wine/guest-gfx 误编成 ARM64。
5. 不得加入游戏名、路径、设备型号或 `GL_RENDERER` 白名单。兼容策略必须来自
   协议、能力、格式、窗口/坐标空间等可泛化状态。

## 二、VirGL sRGB：首个 framebuffer 一次性分类

VirGL 修复发布在 `winehua/virglrenderer` 分支
`fix/vrend-srgb-write-policy`，最终提交 `f49d7da6`。父工程必须保留该 gitlink，
直到修复被 VirGL master 线性包含后再前移。

必须保留的语义：

- host 有 GL colorspace 时继续暴露 guest sRGB write-control 能力，保持 1.1.6 中
  PAL5 已知正常的 guest 行为；
- sub-context 的第一个相关目标若为 RGBA/BGRA UNORM view of sRGB resource，
  固化为 `PRESERVE`；若为 XRGB/BGRX，固化为 `ENCODE_XRGB`；
- 固化后，后续无关 RGBA render target 不得反向关闭 XRGB 主画面的软件编码；
- shader 写出和 clear 路径必须使用相同策略；只转换 RGB，不转换 alpha；
- 禁止恢复已证明会双重转换的 sRGB texture view、错配附件硬件编码或 EGL image
  sRGB import。

实测分类：PAL5 为 RGBA-first；PAL4 为 XRGB-only；灰色的果实为 XRGB-first，
约 18 秒后才出现独立 RGBA 资源。旧的“任何时刻见到 RGBA 就永久 preserve”会让
灰果后半段偏黑。1.1.7 正式候选包中三款游戏均由用户确认颜色正常，PAL5 房屋
材质正常。

## 三、游戏内鼠标与全屏窗口时序

这些修改解决普通窗口正常、游戏客户区轻微向下偏移或相对鼠标漂移的问题：

- `input_resolver.cpp`：显式 empty input region 的呈现 subsurface 必须穿透到父
  toplevel，避免 compositor 与 Wine 对客户区/标题栏偏移各减一次；真实菜单
  subsurface 仍独立命中。
- `InputOverlay.ets`：直接触摸和物理鼠标统一使用 overlay window 坐标
  `windowX/windowY`，不能使用子控件局部的 `x/y`。
- `PointerExtras` / `InputManager`：relative-pointer 按 Wayland client 和当前
  surface 路由；toplevel、surface、relative-pointer 生命周期或坐标空间 epoch
  改变时，第一帧只重建基准，不把全屏/遮罩切换的跳变量当作鼠标移动。
- `WineWindowManager` / `wayland_server.cpp`：fullscreen 与 loadContent 分开
  记录；managed-window raise 延迟 250 ms 并在执行前重查 fullscreen。进入全屏
  会取消待提升，避免 `raiseToAppTop` 改变系统窗口几何后污染输入坐标。

回归必须同时覆盖普通 Wine 窗口点击、全屏游戏按钮命中、相对鼠标视角、窗口二次
打开，以及全屏/窗口切换后的第一下移动。

## 四、虚拟输入方案与默认布局

1. 内置模板共五个：通用、全键盘、RPG、射击、动作。选择入口是弹窗，不再把
   全列表铺在设置页。
2. 全键盘必须保持物理键盘分区、外框、约半高和左右留边；功能键、方向键不得
   越框。手机和平板均使用归一化布局和各自合理比例。
3. 自定义方案新建时必须命名，可重命名、编辑、删除；内置方案不可删除。内置
   revision 更新只刷新内置默认，不覆盖用户自定义方案。
4. Shift/Ctrl 的按住模式在完整 Touch Up 后切换：首次锁定 key-down，第二次
   释放；Cancel、切方案、销毁页面必须释放全部锁定键。
5. RPG 默认布局保持顶部菜单组、右侧紧凑数字技能竖条、左侧 Shift/Ctrl、右侧
   动作区和中右触摸板；evdev 2..11 的显示标签必须映射为 1..0。

模型测试入口：`scripts/run_input_controls_unit_tests.cjs`。修改模板时要同步更新
revision、手机/平板几何断言、命名/删除/持久化和锁定修饰键用例。

## 五、发布与产物规则

- 开发/真机验证：Docker `winehua-dev` + Makefile ARM64 HAP，API 23，guest ABI
  固定 x86_64；覆盖安装后必须 force-stop，确保新 native library 被加载。
- unsigned HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap` 是
  待签名载荷，适合交给侧载/企业签名流程；它本身不能在要求签名的量产系统上直接
  安装。日常 hdc 侧载应使用同批生成的 debug-signed HAP。
- 上线 APP：只使用 `proRelease` + `release` signing profile 运行
  `assembleApp -p product=proRelease -p buildMode=release`，禁止用 debug
  `sign.py` 冒充正式 APP。
- 每次发布检查 bundle、名称、版本、API、单一 ABI、外层 APP 中 entry HAP、
  ARM64 Box64/native 库、嵌套 x86_64 guest-gfx、签名工具结果、大小和 SHA-256。
- 密钥、口令、profile、证书内容、设备标识和本机日志不得进入 Git、memo 或产物
  归档。

## 六、1.1.7 真机回归结论

- PAL4：颜色正常。
- PAL5：整体颜色与房屋材质正常。
- 灰色的果实：单独启动不再偏黑；不依赖同时启动 PAL4。
- 普通窗口与游戏内鼠标命中正常。
- 新方案选择、五套模板、全键盘、RPG、命名/删除、Shift/Ctrl 锁定逻辑正常。

后续若任一结论回退，先按本文件定位语义边界，不要以游戏特判或全局颜色补偿绕过。
