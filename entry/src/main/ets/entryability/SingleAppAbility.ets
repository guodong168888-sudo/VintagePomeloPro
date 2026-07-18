import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import testNapi from 'libentry.so';
import { InputRouter } from '../service/InputRouter';
import { WineWindowManager } from '../service/WineWindowManager';
import { GamepadManager } from '../service/GamepadManager';

const DOMAIN = 0x0000;
const TAG = 'SingleAppAbility';

export default class SingleAppAbility extends UIAbility {
  private toplevelId: number = 0;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.applyWant(want);
    WineWindowManager.getInstance().registerAbility(this.toplevelId, this.context);
  }

  private applyWant(want: Want): void {
    this.toplevelId = Number(want.parameters?.toplevelId) || 0;
    AppStorage.setOrCreate('singleAppToplevelId', this.toplevelId);
    AppStorage.setOrCreate('singleAppSessionId', String(want.parameters?.sessionId ?? ''));
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
  }

  onNewWant(want: Want): void {
    this.applyWant(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    testNapi.setPendingToplevel(this.toplevelId);
    const mainWindow = windowStage.getMainWindowSync();
    WineWindowManager.getInstance().registerWindow(this.toplevelId, mainWindow);
    windowStage.loadContent('pages/SingleAppWindow', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(error));
        return;
      }
      try {
        mainWindow.setWindowDecorVisible(false);
        mainWindow.setWindowLayoutFullScreen(true).catch((_error: BusinessError) => {});
        mainWindow.setSpecificSystemBarEnabled('status', false).catch((_error: BusinessError) => {});
        mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false).catch((_error: BusinessError) => {});
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'immersive setup failed: %{public}s', JSON.stringify(error));
      }
    });
  }

  onForeground(): void {
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
    try { testNapi.setToplevelVisible(this.toplevelId, true); } catch (_) {}
  }

  onBackground(): void {
    GamepadManager.getInstance().releaseAll();
    InputRouter.getInstance().releaseAllKeys();
    try { testNapi.setToplevelVisible(this.toplevelId, false); } catch (_) {}
  }

  onDestroy(): void {
    GamepadManager.getInstance().releaseAll();
    InputRouter.getInstance().releaseAllKeys();
    WineWindowManager.getInstance().unregisterAbility(this.toplevelId);
  }
}
