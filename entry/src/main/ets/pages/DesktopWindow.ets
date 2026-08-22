import { display } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { DesktopLayer } from '../components/DesktopLayer';
import { WineWindowManager } from '../service/WineWindowManager';

const EXIT_BTN_PREF_FILE = 'vd_exit_btn';
const EXIT_BTN_PREF_X = 'x';
const EXIT_BTN_PREF_Y = 'y';
const EXIT_BTN_SIZE = 48;
const EXIT_DRAG_THRESHOLD = 5;

// 桌面全屏窗口 (DesktopAbility 承载)。PC 虚拟桌面沉浸态不画系统关闭条,
// 只留可拖动的小圆形还原钮 (对齐 main-ui VirtualDesktop)。
@Entry
@Component
struct DesktopPage {
  @StorageProp('vdImmersive') immersive: boolean = false;
  @State btnX: number = 0;
  @State btnY: number = 0;
  private scrW: number = 0;
  private scrH: number = 0;
  private startX: number = 0;
  private startY: number = 0;
  private startBtnX: number = 0;
  private startBtnY: number = 0;
  private dragMoved: boolean = false;

  aboutToAppear(): void {
    const d = display.getDefaultDisplaySync();
    this.scrW = px2vp(d.width);
    this.scrH = px2vp(d.height);
    this.btnX = this.scrW * 0.84 - EXIT_BTN_SIZE;
    this.btnY = 20;
    this.loadBtnPos();
  }

  private loadBtnPos(): void {
    preferences.getPreferences(getContext(this), EXIT_BTN_PREF_FILE).then((prefs: preferences.Preferences) => {
      const x = prefs.getSync(EXIT_BTN_PREF_X, -1) as number;
      const y = prefs.getSync(EXIT_BTN_PREF_Y, -1) as number;
      if (x >= 0 && y >= 0) {
        this.btnX = Math.min(Math.max(0, x), this.scrW - EXIT_BTN_SIZE);
        this.btnY = Math.min(Math.max(0, y), this.scrH - EXIT_BTN_SIZE);
      }
    }).catch(() => {});
  }

  private saveBtnPos(): void {
    preferences.getPreferences(getContext(this), EXIT_BTN_PREF_FILE).then((prefs: preferences.Preferences) => {
      prefs.putSync(EXIT_BTN_PREF_X, this.btnX);
      prefs.putSync(EXIT_BTN_PREF_Y, this.btnY);
      prefs.flush();
    }).catch(() => {});
  }

  private onExitBtnTouch(ev: TouchEvent): void {
    if (ev.type === TouchType.Down) {
      const t = ev.touches[0];
      if (t) {
        this.startX = t.windowX;
        this.startY = t.windowY;
      }
      this.startBtnX = this.btnX;
      this.startBtnY = this.btnY;
      this.dragMoved = false;
    } else if (ev.type === TouchType.Move) {
      const t = ev.touches[0];
      if (t) {
        if (!this.dragMoved &&
          (Math.abs(t.windowX - this.startX) > EXIT_DRAG_THRESHOLD ||
            Math.abs(t.windowY - this.startY) > EXIT_DRAG_THRESHOLD)) {
          this.dragMoved = true;
        }
        if (this.dragMoved) {
          this.btnX = Math.min(Math.max(0, this.startBtnX + (t.windowX - this.startX)),
            this.scrW - EXIT_BTN_SIZE);
          this.btnY = Math.min(Math.max(0, this.startBtnY + (t.windowY - this.startY)),
            this.scrH - EXIT_BTN_SIZE);
        }
      }
    } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
      if (!this.dragMoved) {
        WineWindowManager.getInstance().recoverDesktopWindow();
      } else {
        this.saveBtnPos();
      }
      this.dragMoved = false;
    }
  }

  build() {
    Stack() {
      DesktopLayer({ floating: false })

      if (this.immersive) {
        Stack() {
          SymbolGlyph($r('sys.symbol.full_screen_fill'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(EXIT_BTN_SIZE)
        .height(EXIT_BTN_SIZE)
        .borderRadius(EXIT_BTN_SIZE / 2)
        .backgroundColor('#33000000')
        .border({ width: 1, color: '#66FFFFFF', style: BorderStyle.Solid })
        .position({ x: this.btnX, y: this.btnY })
        .onTouch((ev: TouchEvent) => this.onExitBtnTouch(ev))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
