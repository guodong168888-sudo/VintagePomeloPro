import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { WineWindowManager } from '../service/WineWindowManager';
import { GamepadManager } from '../service/GamepadManager';
import { InputRouter } from '../service/InputRouter';
import { InputDispatcher } from '../service/InputDispatcher';
import { InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { DisplayMode } from '../model/AppModels';
import { EngineState } from '../model/AppModels';
import { WineEngineService } from '../service/WineEngineService';
import { DeviceCapabilityPolicy } from '../common/DeviceCapabilityPolicy';

const DOMAIN = 0x0000;
const TAG = 'DWA';

export default class DesktopAbility extends UIAbility {
  private toplevelId: number = 0;
  private stage: window.WindowStage | null = null;
  private mainWindow: window.Window | null = null;
  private windowSizeCallback: ((size: window.Size) => void) | null = null;
  private windowResizeGeneration: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      const params = want.parameters ?? {};
      this.toplevelId = Number(params.toplevelId) || 0;
      AppStorage.setOrCreate('desktopToplevelId', this.toplevelId);
      hilog.info(DOMAIN, TAG, '[DWA]  onCreate: tl=%{public}d', this.toplevelId);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '[DWA] ERR onCreate: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.stage = windowStage;
    hilog.info(DOMAIN, TAG, '[DWA] onWindowStageCreate tl=%{public}d', this.toplevelId);
    windowStage.loadContent('pages/DesktopWindow', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, '[DWA] loadContent FAILED: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '[DWA] loadContent OK tl=%{public}d', this.toplevelId);

      // 沉浸模式: 全屏 + 隐藏状态栏和导航栏
      try {
        const mw = windowStage.getMainWindowSync();
        if (mw) {
          this.mainWindow = mw;
          DeviceCapabilityPolicy.enableSensorRotation(mw, TAG);
          if (DeviceCapabilityPolicy.usesForkNativeChildProcess()) {
            this.windowSizeCallback = (size: window.Size): void => {
              this.synchronizeDesktopWindow(size.width, size.height);
            };
            mw.on('windowSizeChange', this.windowSizeCallback);
            const initialRect = mw.getWindowProperties().windowRect;
            this.synchronizeDesktopWindow(initialRect.width, initialRect.height);
          }
          mw.setWindowLayoutFullScreen(true).catch((e: BusinessError) => {
            hilog.error(DOMAIN, TAG, '[DWA] fullScreen failed: %{public}s', JSON.stringify(e));
          });
          mw.setSpecificSystemBarEnabled('status', false).catch((e: BusinessError) => {
            hilog.error(DOMAIN, TAG, '[DWA] statusBar failed: %{public}s', JSON.stringify(e));
          });
          mw.setSpecificSystemBarEnabled('navigationIndicator', false).catch((e: BusinessError) => {
            hilog.error(DOMAIN, TAG, '[DWA] navBar failed: %{public}s', JSON.stringify(e));
          });
          mw.on('windowRectChange', () => {
            InputOverlayWindowCoordinator.getInstance().syncBounds().catch(() => {});
          });
          this.attachInputOverlay();
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, '[DWA] immersive ERR: %{public}s', JSON.stringify(e));
      }
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '[DWA] onForeground tl=%{public}d', this.toplevelId);
    WineWindowManager.getInstance().markDesktopAbilityForeground(this.toplevelId);
    InputRouter.getInstance().setActiveToplevel(WineWindowManager.getInstance().getDesktopRootId());
    this.attachInputOverlay();
  }

  onNewWant(want: Want): void {
    const newId = Number(want.parameters?.toplevelId) || 0;
    hilog.info(DOMAIN, TAG, '[DWA] onNewWant tl: %{public}d -> %{public}d', this.toplevelId, newId);
    // 无参数的 activate 只是把 singleton Ability 带回前台，不能覆盖已知 root。
    if (newId > 0) {
      this.toplevelId = newId;
      AppStorage.setOrCreate('desktopToplevelId', newId);
    }
    this.attachInputOverlay();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '[DWA] onBackground tl=%{public}d', this.toplevelId);
    WineWindowManager.getInstance().markDesktopAbilityBackground(this.toplevelId);
    GamepadManager.getInstance().releaseAll();
    InputDispatcher.getInstance().releaseAll('desktop-background');
    InputRouter.getInstance().releaseAllKeys();
    InputOverlayWindowCoordinator.getInstance().setVisible(false).catch(() => {});
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '[DWA] onDestroy tl=%{public}d', this.toplevelId);
    try {
      if (this.mainWindow && this.windowSizeCallback) {
        this.mainWindow.off('windowSizeChange', this.windowSizeCallback);
      }
      this.windowResizeGeneration++;
      this.windowSizeCallback = null;
      GamepadManager.getInstance().releaseAll();
      InputDispatcher.getInstance().releaseAll('desktop-destroy');
      InputRouter.getInstance().releaseAllKeys();
      WineWindowManager.getInstance().markDesktopAbilityStopped(this.toplevelId);
      // 关闭 ArkTS 宿主并不等于关闭 Wine explorer。保留 desktop root 后，
      // 应用库中的“Wine 桌面”卡片可以重新拉起同一会话和渲染 surface。
      WineWindowManager.getInstance().unregisterAbility(this.toplevelId);
      InputOverlayWindowCoordinator.getInstance().detach('desktop-ability-destroy').catch(() => {});
    } catch (e) {
      hilog.error(DOMAIN, TAG, '[DWA] ERR onDestroy: %{public}s', JSON.stringify(e));
    }
  }

  private attachInputOverlay(): void {
    // PC/2-in-1 desktop mode is a multiton collection of native Harmony
    // windows. It relies on physical input and must not create a screen
    // overlay for every Wine window. SingleAppAbility remains opt-in capable.
    if (AppSettingsStore.getInstance().usesManagedWineWindows()) {
      InputOverlayWindowCoordinator.getInstance().detach('pc-desktop-uses-physical-input').catch(() => {});
      return;
    }
    if (!this.stage || !this.mainWindow) return;
    const settings = AppSettingsStore.getInstance().getGlobalSettings();
    const rootId = WineWindowManager.getInstance().getDesktopRootId() || this.toplevelId;
    InputOverlayWindowCoordinator.getInstance().attach(
      this.stage, this.mainWindow, 'desktop-' + rootId, DisplayMode.DESKTOP, rootId,
      settings.desktopInputProfileId || 'default', settings.showVirtualControls, settings.controlOpacity,
      settings.virtualInputEnabled,
      true).catch(() => {});
  }

  private synchronizeDesktopWindow(width: number, height: number): void {
    if (width <= 0 || height <= 0) return;
    WineWindowManager.getInstance().syncOutputSize(width, height);
    InputOverlayWindowCoordinator.getInstance().syncBounds().catch(() => {});
    const generation = ++this.windowResizeGeneration;
    // Rotation delivers several transient sizes. Re-sample the real window
    // after layout and animation settle so both the Wine root and overlay use
    // the final landscape/portrait rectangle.
    [160, 480].forEach((delay: number): void => {
      setTimeout((): void => {
        if (generation !== this.windowResizeGeneration || !this.mainWindow) return;
        const rect = this.mainWindow.getWindowProperties().windowRect;
        WineWindowManager.getInstance().syncOutputSize(rect.width, rect.height);
        InputOverlayWindowCoordinator.getInstance().syncBounds().catch(() => {});
      }, delay);
    });
  }
}
