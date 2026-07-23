import { AbilityConstant, UIAbility, Want, bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import deviceInfo from '@ohos.deviceInfo';
import { WineWindowManager } from '../service/WineWindowManager';

const DOMAIN = 0x0000;
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private titleButtonRectCallback: ((rect: window.TitleButtonRect) => void) | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 与 VintagePomelo 相同，使用 docs FileUri 而非 Environment 的可选能力。
    // 这会在冷启动就创建 Download/包名/games，不依赖扫描或目录授权。
    this.ensureDownloadGamesDirectory();
  }

  private ensureDirectoryExists(path: string): void {
    try {
      if (fs.statSync(path).isDirectory()) return;
    } catch (_) {
      try {
        fs.mkdirSync(path);
      } catch (error) {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to create %{public}s: %{public}s', path, JSON.stringify(error));
      }
    }
  }

  private ensureDownloadGamesDirectory(): void {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const libraryUri = 'file://docs/storage/Users/currentUser/Download/' + bundleInfo.name;
      const libraryPath = new fileUri.FileUri(libraryUri).path;
      this.ensureDirectoryExists(libraryPath);
      this.ensureDirectoryExists(libraryPath + '/games');
      hilog.info(DOMAIN, 'EntryAbility', 'Download games directory ready: %{public}s', libraryPath + '/games');
    } catch (error) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to resolve Download games directory: %{public}s', JSON.stringify(error));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want): void {
    const parameters = want.parameters ?? {};
    if (parameters.overlayRoute === 'input-layout' || parameters.overlayRoute === 'key-mapping') {
      // 覆盖层属于 Desktop/SingleApp Ability，不能直接把它的子窗口替换为
      // 编辑器。回到应用库主窗口再进入编辑页，Wine 会话则保持后台可恢复。
      AppStorage.setOrCreate('overlayEditorRequest', JSON.stringify({
        route: String(parameters.overlayRoute),
        profileId: String(parameters.profileId ?? 'default'),
        profileName: String(parameters.profileName ?? '默认键鼠手柄'),
        appId: String(parameters.appId ?? ''),
        baseProfileId: String(parameters.baseProfileId ?? 'default'),
        returnAbilityName: String(parameters.returnAbilityName ?? ''),
        returnSessionId: String(parameters.returnSessionId ?? ''),
        returnToplevelId: String(parameters.returnToplevelId ?? '0')
      }));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化多窗口管理器
    WineWindowManager.getInstance().init(windowStage, this.context);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // loadContent 成功后隐藏窗口装饰
      let mainWin = windowStage.getMainWindowSync();
      if (mainWin) {
        this.mainWindow = mainWin;
        mainWin.setWindowDecorVisible(false);
        if (this.isPcWindowHost()) {
          // A 2-in-1 keeps the system three-button area even when the visual
          // title decoration is hidden. Re-enable that area's native drag and
          // double-click handling so the borderless library window still
          // behaves like a normal PC window.
          try {
            mainWin.setWindowDecorHeight(48);
            mainWin.setWindowTitleMoveEnabled(true);
          } catch (error) {
            hilog.warn(DOMAIN, 'EntryAbility', 'PC title drag unavailable: %{public}s', JSON.stringify(error));
          }
        }
        // The gesture navigation indicator otherwise reserves a light strip
        // below every routed page. Gesture navigation remains available.
        mainWin.setSpecificSystemBarEnabled('navigationIndicator', false).catch(() => {});
        this.observeTitleButtonInset(mainWin);
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  private isPcWindowHost(): boolean {
    return deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc';
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    if (this.mainWindow && this.titleButtonRectCallback) {
      try {
        this.mainWindow.off('windowTitleButtonRectChange', this.titleButtonRectCallback);
      } catch (_) {
      }
    }
    this.titleButtonRectCallback = null;
    this.mainWindow = null;
    AppStorage.setOrCreate('libraryTitleButtonInsetVp', 0);
  }

  private observeTitleButtonInset(mainWindow: window.Window): void {
    AppStorage.setOrCreate('libraryTitleButtonInsetVp', 0);
    this.titleButtonRectCallback = (rect: window.TitleButtonRect): void => {
      this.updateTitleButtonInset(rect);
    };
    try {
      this.updateTitleButtonInset(mainWindow.getTitleButtonRect());
      mainWindow.on('windowTitleButtonRectChange', this.titleButtonRectCallback);
    } catch (error) {
      AppStorage.setOrCreate('libraryTitleButtonInsetVp', 0);
      hilog.warn(DOMAIN, 'EntryAbility', 'Title button safe area unavailable: %{public}s', JSON.stringify(error));
    }
  }

  private updateTitleButtonInset(rect: window.TitleButtonRect): void {
    try {
      if (rect.width <= 0) {
        AppStorage.setOrCreate('libraryTitleButtonInsetVp', 0);
        return;
      }
      const density = Math.max(1, display.getDefaultDisplaySync().densityPixels);
      const insetVp = Math.ceil((Math.max(0, rect.right) + Math.max(0, rect.width)) / density) + 12;
      AppStorage.setOrCreate('libraryTitleButtonInsetVp', insetVp);
    } catch (_) {
      AppStorage.setOrCreate('libraryTitleButtonInsetVp', 0);
    }
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
