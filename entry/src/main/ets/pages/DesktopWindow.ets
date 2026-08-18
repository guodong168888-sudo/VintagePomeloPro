import { DesktopLayer } from '../components/DesktopLayer';

// 桌面全屏窗口 (DesktopAbility 承载): 桌面全部逻辑 (renderer 生命周期 /
// 触控状态机 / 触控板 / 鼠标 / 键盘 / 滚轮 / 虚拟输入 overlay) 复用
// components/DesktopLayer (含 floating 态)。全屏态 floating=false 输入全直通。
@Entry
@Component
struct DesktopPage {
  build() {
    Stack() {
      DesktopLayer({ floating: false })
    }
    .width('100%').height('100%')
  }
}
