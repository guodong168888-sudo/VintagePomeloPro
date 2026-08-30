import testNapi from 'libentry.so';
import { GlobalSettings } from '../model/AppModels';
import { ThemeSettingsListener, ThemeSettingsService } from '../service/ThemeSettingsService';

const HUD_INTERVAL_MS: number = 500;

@Component
export struct FpsHud {
  /** Renderer toplevel; 0 表示按桌面根 / 当前最高活跃值查询。 */
  @Prop toplevelId: number = 0;
  /** 浮窗缩略等场景隐藏，避免小窗挤数字。 */
  @Prop @Watch('onHideChanged') hide: boolean = false;
  @State private hudEnabled: boolean = false;
  @State private fpsText: string = '0';
  private timerId: number = -1;
  private settingsListener: ThemeSettingsListener | null = null;

  aboutToAppear(): void {
    this.hudEnabled = ThemeSettingsService.getInstance().getSettings().showFpsHud;
    this.settingsListener = (settings: GlobalSettings): void => {
      this.hudEnabled = settings.showFpsHud;
      this.syncTimer();
    };
    ThemeSettingsService.getInstance().subscribe(this.settingsListener);
    this.syncTimer();
  }

  aboutToDisappear(): void {
    this.clearTimer();
    if (this.settingsListener) {
      ThemeSettingsService.getInstance().unsubscribe(this.settingsListener);
      this.settingsListener = null;
    }
  }

  onHideChanged(): void {
    this.syncTimer();
  }

  private active(): boolean {
    return this.hudEnabled && !this.hide;
  }

  private syncTimer(): void {
    if (this.active()) {
      this.refreshFps();
      if (this.timerId < 0) {
        this.timerId = setInterval((): void => {
          this.refreshFps();
        }, HUD_INTERVAL_MS);
      }
    } else {
      this.clearTimer();
    }
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refreshFps(): void {
    if (!this.active()) return;
    let id = this.toplevelId;
    if (id <= 0) {
      try {
        id = testNapi.getDesktopRootId() as number;
      } catch (_) {
        id = 0;
      }
    }
    let fps = 0;
    try {
      fps = testNapi.getDisplayFps(id) as number;
    } catch (_) {
      fps = 0;
    }
    if (!(fps >= 0) || fps > 1000) fps = 0;
    this.fpsText = Math.round(fps).toString();
  }

  build() {
    if (this.active()) {
      Text(this.fpsText + ' FPS')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FF76FF03')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#99000000')
        .borderRadius(6)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}
