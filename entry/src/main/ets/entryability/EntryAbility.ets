import { AbilityConstant, UIAbility, Want, bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { WineWindowManager } from '../service/WineWindowManager';

const DOMAIN = 0x0000;
export default class EntryAbility extends UIAbility {
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
        mainWin.setWindowDecorVisible(false);
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
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
