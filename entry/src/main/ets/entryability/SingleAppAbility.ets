import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import testNapi from 'libentry.so';
import { InputRouter } from '../service/InputRouter';
import { InputDispatcher } from '../service/InputDispatcher';
import { WineWindowManager } from '../service/WineWindowManager';
import { GamepadManager } from '../service/GamepadManager';
import { InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { AppSessionService } from '../service/AppSessionService';
import { DisplayMode, resolveInputProfileId } from '../model/AppModels';
import { EngineState } from '../model/AppModels';
import { WineEngineService } from '../service/WineEngineService';
import { DeviceCapabilityPolicy } from '../common/DeviceCapabilityPolicy';

const DOMAIN = 0x0000;
const TAG = 'SingleAppAbility';

export default class SingleAppAbility extends UIAbility {
  private toplevelId: number = 0;
  private sessionId: string = '';
  private stage: window.WindowStage | null = null;
  private mainWindow: window.Window | null = null;
  private windowSizeCallback: ((size: window.Size) => void) | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.applyWant(want);
    WineWindowManager.getInstance().registerAbility(this.toplevelId, this.context);
  }

  private applyWant(want: Want): void {
    this.toplevelId = Number(want.parameters?.toplevelId) || 0;
    this.sessionId = String(want.parameters?.sessionId ?? '');
    AppStorage.setOrCreate('singleAppToplevelId', this.toplevelId);
    AppStorage.setOrCreate('singleAppSessionId', this.sessionId);
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
    this.attachInputOverlay();
  }

  onNewWant(want: Want): void {
    this.applyWant(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.stage = windowStage;
    testNapi.setPendingToplevel(this.toplevelId);
    const mainWindow = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;
    WineWindowManager.getInstance().registerWindow(this.toplevelId, mainWindow);
    windowStage.loadContent('pages/SingleAppWindow', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(error));
        return;
      }
      try {
        DeviceCapabilityPolicy.enableSensorRotation(mainWindow, TAG);
        if (DeviceCapabilityPolicy.usesForkNativeChildProcess()) {
          this.windowSizeCallback = (size: window.Size): void => {
            WineWindowManager.getInstance().syncOutputSize(size.width, size.height);
            InputOverlayWindowCoordinator.getInstance().syncBounds().catch(() => {});
          };
          mainWindow.on('windowSizeChange', this.windowSizeCallback);
        }
        mainWindow.setWindowDecorVisible(false);
        mainWindow.setWindowLayoutFullScreen(true).catch((_error: BusinessError) => {});
        mainWindow.setSpecificSystemBarEnabled('status', false).catch((_error: BusinessError) => {});
        mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false).catch((_error: BusinessError) => {});
        mainWindow.on('windowRectChange', () => {
          InputOverlayWindowCoordinator.getInstance().syncBounds().catch(() => {});
        });
        this.attachInputOverlay();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'immersive setup failed: %{public}s', JSON.stringify(error));
      }
    });
  }

  onForeground(): void {
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
    try { testNapi.setToplevelVisible(this.toplevelId, true); } catch (_) {}
    this.attachInputOverlay();
  }

  onBackground(): void {
    GamepadManager.getInstance().releaseAll();
    InputDispatcher.getInstance().releaseAll('single-app-background');
    InputRouter.getInstance().releaseAllKeys();
    try { testNapi.setToplevelVisible(this.toplevelId, false); } catch (_) {}
    InputOverlayWindowCoordinator.getInstance().setVisible(false).catch(() => {});
  }

  onDestroy(): void {
    if (this.mainWindow && this.windowSizeCallback) {
      this.mainWindow.off('windowSizeChange', this.windowSizeCallback);
    }
    this.windowSizeCallback = null;
    GamepadManager.getInstance().releaseAll();
    InputDispatcher.getInstance().releaseAll('single-app-destroy');
    InputRouter.getInstance().releaseAllKeys();
    WineWindowManager.getInstance().unregisterAbility(this.toplevelId);
    InputOverlayWindowCoordinator.getInstance().detach('single-app-ability-destroy').catch(() => {});
  }

  private attachInputOverlay(): void {
    if (!this.stage || !this.mainWindow) return;
    const session = AppSessionService.getInstance().getSession(this.sessionId);
    const settings = AppSettingsStore.getInstance().getGlobalSettings();
    const appProfileId = session ? AppSettingsStore.getInstance().getAppSettings(session.appId).inputProfileId : 'default';
    const profileId = resolveInputProfileId(appProfileId, settings.desktopInputProfileId);
    InputOverlayWindowCoordinator.getInstance().attach(
      this.stage, this.mainWindow, this.sessionId || ('single-' + this.toplevelId), DisplayMode.SINGLE_APP,
      this.toplevelId, profileId, settings.showVirtualControls, settings.controlOpacity,
      settings.virtualInputEnabled,
      true).catch(() => {});
  }
}
