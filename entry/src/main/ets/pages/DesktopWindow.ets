import { DesktopLayer } from '../components/DesktopLayer';
import { WineWindowManager } from '../service/WineWindowManager';

// 桌面全屏窗口 (DesktopAbility 承载): 桌面全部逻辑 (renderer 生命周期 /
// 触控状态机 / 触控板 / 鼠标 / 键盘 / 滚轮 / 虚拟输入 overlay) 复用
// components/DesktopLayer (含 floating 态)。全屏态 floating=false 输入全直通。
// PC 虚拟桌面: 标题栏已隐藏, 顶部 hover 显示反色控制条 (最小化/退出全屏/关闭)。
@Entry
@Component
struct DesktopPage {
  // 顶部 hover 菜单态: 鼠标移入窗口顶部热区 → 显示控制条, 移出自动隐藏
  @State hoverMenu: boolean = false;

  build() {
    Stack() {
      DesktopLayer({ floating: false })

      // 顶部 hover 控制条 (反色: 白底黑字, 与黑色桌面形成反差):
      // 未 hover 只占 24vp 透明热区, hover 后展开半透明白控制条。
      Column() {
        Row({ space: 8 }) {
          Button('—')
            .height(28).borderRadius(6).fontSize(16).fontColor('#000000')
            .backgroundColor('#FFFFFF')
            .onClick(() => { WineWindowManager.getInstance().minimizeDesktopWindow(); })
          Button('还原')
            .height(28).borderRadius(6).fontSize(13).fontColor('#000000')
            .backgroundColor('#FFFFFF')
            .onClick(() => { WineWindowManager.getInstance().restoreDesktopWindow(); })
          Button('✕')
            .height(28).borderRadius(6).fontSize(14).fontColor('#FFFFFF')
            .backgroundColor('#D94848')
            .onClick(() => { WineWindowManager.getInstance().closeDesktopWindow(); })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, top: 6, bottom: 6 })
        .opacity(this.hoverMenu ? 1 : 0)
      }
      .width('100%')
      .height(this.hoverMenu ? 52 : 24)
      .backgroundColor(this.hoverMenu ? '#E6FFFFFF' : 'transparent')
      .align(Alignment.Top)
      .zIndex(10)
      .onHover((isHover: boolean) => { this.hoverMenu = isHover; })
    }
    .width('100%').height('100%')
  }
}
