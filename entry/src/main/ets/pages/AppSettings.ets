import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  BOX64_PRESET_DEFAULT,
  BOX64_PRESET_IDS,
  AppDescriptor,
  AppSettings as StoredAppSettings,
  AppSource,
  DisplayMode,
  box64PresetDescription,
  box64PresetLabel,
  createDefaultAppSettings
} from '../model/AppModels';
import { AppCatalogService } from '../service/AppCatalogService';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { BreakpointSystem, BreakpointType } from '../common/BreakpointSystem';
import { DeviceCapabilityPolicy } from '../common/DeviceCapabilityPolicy';
import { LengthMetrics, window } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import {
  applyStatusOnlyImmersiveShell,
  getMiniTitleContentTopInset,
  getStatusOnlyWindowInsets,
  observeStatusOnlyWindowInsets
} from '../common/StatusOnlyImmersiveShell';
import {
  DividerShowType,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

const DEVICE_SDK_API_VERSION: number = (() => {
  try {
    return deviceInfo.sdkApiVersion as number;
  } catch (_) {
    return 0;
  }
})();
const SUPPORTS_HDS_FLOATING: boolean =
  canIUse('SystemCapability.UIDesign.HDSComponent.Core') && DEVICE_SDK_API_VERSION >= 23;
const HDS_MATERIAL_TYPE_IMMERSIVE: number = 101;
const HDS_MATERIAL_LEVEL_EXQUISITE: number = 0;

class ExecutableChoice {
  path: string;
  relativePath: string;

  constructor(path: string, relativePath: string) {
    this.path = path;
    this.relativePath = relativePath;
  }
}

@CustomDialog
struct WindowsExecutablePickerDialog {
  controller?: CustomDialogController;
  choices: ExecutableChoice[] = [];
  selectedPath: string = '';
  onSelect: (path: string) => void = (_path: string): void => {};

  build() {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text('选择 Windows 主程序').fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text('仅显示当前游戏目录及其子目录中的 EXE、COM、BAT、CMD。')
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.choices, (choice: ExecutableChoice) => {
            Button() {
              Column({ space: 3 }) {
                Text(choice.relativePath).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary')).width('100%').maxLines(2)
                Text(choice.path === this.selectedPath ? '当前已关联' : '选择为此卡片的主程序')
                  .fontSize(11)
                  .fontColor(choice.path === this.selectedPath ? $r('app.color.accent') : $r('app.color.text_secondary'))
                  .width('100%')
              }.width('100%').alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor(choice.path === this.selectedPath ? '#1F246BFD' : $r('app.color.search_background'))
            .onClick((): void => {
              if (this.controller) this.controller.close();
              this.onSelect(choice.path);
            })
          }, (choice: ExecutableChoice): string => choice.path)
        }.width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Auto)

      Button('取消').width('100%').height(46).backgroundColor($r('app.color.search_background'))
        .fontColor($r('app.color.text_primary')).onClick((): void => {
          if (this.controller) this.controller.close();
        })
    }
    .width('92%')
    .constraintSize({ maxWidth: 620 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }
}

@Entry
@Component
struct AppSettingsPage {
  @StorageLink('libraryTitleButtonInsetVp') private titleButtonInsetVp: number = 0;
  @State private app: AppDescriptor | null = null;
  @State private value: StoredAppSettings = createDefaultAppSettings('');
  @State private breakpoint: BreakpointType = 'lg';
  @State private titleContentTopInsetVp: number = 40;
  @State private navBarInsetVp: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private breakpointCallback: ((value: BreakpointType) => void) | null = null;
  private appSettingsScroller: Scroller = new Scroller();
  private disposeWindowInsetObserver: (() => void) | null = null;
  private executablePickerController: CustomDialogController | null = null;
  private openExecutablePickerOnShow: boolean = false;

  private isCompact(): boolean {
    return this.breakpoint === 'xs' || this.breakpoint === 'sm';
  }

  private isNarrowPhone(): boolean {
    return this.breakpoint === 'xs';
  }

  private usesDarkAppearance(): boolean {
    try {
      return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (_) {
      return false;
    }
  }

  private navigationTitleBackground(scrolled: boolean): string {
    if (this.usesDarkAppearance()) return scrolled ? '#80121821' : '#26121821';
    return scrolled ? '#99FFFFFF' : '#18FFFFFF';
  }

  private navigationControlBackground(): string {
    return this.usesDarkAppearance() ? '#30FFFFFF' : '#28FFFFFF';
  }

  private navigationTitleColor(): string {
    return this.usesDarkAppearance() ? '#F4F7FB' : '#182431';
  }

  private cardPadding(): number {
    return this.isCompact() ? 12 : 20;
  }

  private contentTopInset(): number {
    // Keep the HDS title clearance inside Scroll content so it moves away
    // together with the first settings card.
    return this.titleContentTopInsetVp;
  }

  private contentSidePadding(): number {
    if (this.isNarrowPhone()) return 10;
    if (this.breakpoint === 'sm') return 16;
    if (this.breakpoint === 'md') return 20;
    return 28;
  }

  private contentMaxWidth(): number {
    return this.breakpoint === 'xl' ? 1040 : 920;
  }

  private titleButtonMargin(): number {
    return this.titleButtonInsetVp > 0 ? this.titleButtonInsetVp + 44 : 0;
  }

  private currentProfileId(): string {
    return this.value.inputProfileId || 'default';
  }

  private profileEditorId(): string {
    return this.currentProfileId() === 'default' ? 'app-' + this.value.appId : this.currentProfileId();
  }

  private profileEditorName(): string {
    const title = this.value.customTitle || this.app?.title || '应用';
    return title + ' 键鼠手柄布局';
  }

  private globalProfileId(): string {
    return AppSettingsStore.getInstance().getGlobalSettings().desktopInputProfileId || 'default';
  }

  aboutToAppear(): void {
    BreakpointSystem.initialize();
    this.breakpointCallback = (value: BreakpointType): void => { this.breakpoint = value; };
    BreakpointSystem.subscribe(this.breakpointCallback);
    const params = (router.getParams() as Record<string, string> | undefined) ?? {};
    const appId = params.appId ?? '';
    this.openExecutablePickerOnShow = params.selectExecutable === 'true';
    this.app = AppCatalogService.getInstance().getApps().find((item: AppDescriptor) => item.id === appId) ?? null;
    this.value = AppSettingsStore.getInstance().getAppSettings(appId);
    if (this.app) {
      this.value = {
        appId: appId,
        customTitle: this.value.customTitle || this.app.title,
        customCover: this.value.customCover,
        favorite: this.value.favorite,
        box64Preset: this.value.box64Preset,
        executable: this.value.executable || this.app.launchTarget.executable,
        arguments: this.value.arguments,
        workingDirectory: this.value.workingDirectory || this.app.launchTarget.workingDirectory,
        displayModeOverride: this.value.displayModeOverride ?? this.app.displayModeOverride,
        inputProfileId: this.value.inputProfileId,
        prefixId: this.value.prefixId
      };
    }
  }

  aboutToDisappear(): void {
    if (this.breakpointCallback) BreakpointSystem.unsubscribe(this.breakpointCallback);
    this.stopWindowInsetObserver();
    if (this.executablePickerController) this.executablePickerController.close();
    this.executablePickerController = null;
  }

  onPageShow(): void {
    void this.applyPageWindowShell();
    if (this.openExecutablePickerOnShow) {
      this.openExecutablePickerOnShow = false;
      this.openExecutablePicker();
    }
  }

  onPageHide(): void {
    this.stopWindowInsetObserver();
  }

  private async applyPageWindowShell(): Promise<void> {
    try {
      const pageWindow = await window.getLastWindow(this.context);
      await applyStatusOnlyImmersiveShell(pageWindow);
      this.startWindowInsetObserver(pageWindow);
    } catch (_) {
    }
  }

  private refreshTitleContentInset(pageWindow: window.Window): void {
    this.titleContentTopInsetVp = getMiniTitleContentTopInset(pageWindow);
    this.navBarInsetVp = getStatusOnlyWindowInsets(pageWindow).bottom;
  }

  private startWindowInsetObserver(pageWindow: window.Window): void {
    this.stopWindowInsetObserver();
    this.disposeWindowInsetObserver = observeStatusOnlyWindowInsets(pageWindow, () => {
      this.refreshTitleContentInset(pageWindow);
    });
  }

  private stopWindowInsetObserver(): void {
    if (this.disposeWindowInsetObserver) {
      this.disposeWindowInsetObserver();
      this.disposeWindowInsetObserver = null;
    }
  }

  private replace(title: string, cover: string, executable: string, workingDirectory: string,
    displayMode: DisplayMode | null): void {
    this.value = {
      appId: this.value.appId,
      customTitle: title,
      customCover: cover,
      favorite: this.value.favorite,
      box64Preset: this.value.box64Preset,
      executable: executable,
      arguments: this.value.arguments,
      workingDirectory: workingDirectory,
      displayModeOverride: displayMode,
      inputProfileId: this.value.inputProfileId,
      prefixId: this.value.prefixId
    };
  }

  private async save(): Promise<void> {
    await AppSettingsStore.getInstance().saveAppSettings(this.value);
    await AppCatalogService.getInstance().scan();
    promptAction.showToast({ message: '应用设置已保存' });
    router.back();
  }

  private relativeExecutablePath(directory: string, executable: string): string {
    const root = directory.replace(/\\/g, '/').replace(/\/+$/, '');
    const target = executable.replace(/\\/g, '/');
    if (root && target.startsWith(root + '/')) return target.substring(root.length + 1);
    return target;
  }

  private selectExecutableCandidate(executable: string): void {
    const separator = executable.lastIndexOf('/');
    const workingDirectory = separator > 0 ? executable.substring(0, separator) : this.value.workingDirectory;
    this.replace(this.value.customTitle, this.value.customCover, executable,
      workingDirectory, this.value.displayModeOverride);
    this.executablePickerController = null;
    promptAction.showToast({ message: '已选择主程序，请点击右上角保存' });
  }

  private async openExecutablePicker(): Promise<void> {
    if (!this.app || this.app.source !== AppSource.DOWNLOAD) return;
    const candidates = await AppCatalogService.getInstance().getGameLaunchTargetCandidates(this.app.directory);
    if (candidates.length === 0) {
      AlertDialog.show({
        title: '未找到可启动的主程序',
        message: '已扫描当前游戏目录及两层子目录，未发现 EXE、COM、BAT 或 CMD。请确认游戏文件已完整放入此目录。',
        primaryButton: { value: '知道了', action: (): void => {} }
      });
      return;
    }
    const choices: ExecutableChoice[] = candidates.map((path: string) =>
      new ExecutableChoice(path, this.relativeExecutablePath(this.app?.directory ?? '', path)));
    this.executablePickerController = new CustomDialogController({
      builder: WindowsExecutablePickerDialog({
        choices: choices,
        selectedPath: this.value.executable,
        onSelect: (path: string): void => this.selectExecutableCandidate(path)
      }),
      cancel: (): void => { this.executablePickerController = null; },
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    try {
      this.executablePickerController.open();
    } catch (_) {
      this.executablePickerController = null;
      promptAction.showToast({ message: '无法打开主程序选择器' });
    }
  }

  private async selectCover(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['图片|.png,.jpg,.jpeg,.webp,.bmp'];
      options.maxSelectNumber = 1;
      const result = await documentPicker.select(options);
      if (!result || result.length === 0) return;
      const cover = new fileUri.FileUri(result[0]).path;
      this.replace(this.value.customTitle, cover, this.value.executable,
        this.value.workingDirectory, this.value.displayModeOverride);
    } catch (_) {
      promptAction.showToast({ message: '未选择封面' });
    }
  }

  private removeUnavailable(): void {
    if (!this.app || this.app.available) return;
    AlertDialog.show({
      title: '删除不可用卡片',
      message: '仅删除应用库记录，不会删除磁盘中的文件。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '删除', fontColor: '#D94848', action: (): void => {
          AppSettingsStore.getInstance().removeCachedApp(this.value.appId).then(() => router.back());
        }
      }
    });
  }

  private async editInputProfile(): Promise<void> {
    const profileId = this.profileEditorId();
    this.value = {
      appId: this.value.appId,
      customTitle: this.value.customTitle,
      customCover: this.value.customCover,
      favorite: this.value.favorite,
      box64Preset: this.value.box64Preset,
      executable: this.value.executable,
      arguments: this.value.arguments,
      workingDirectory: this.value.workingDirectory,
      displayModeOverride: this.value.displayModeOverride,
      inputProfileId: profileId,
      prefixId: this.value.prefixId
    };
    // Entering a child editor is an explicit choice to create a dedicated
    // profile. Persist it first so returning from the editor cannot restore
    // stale app settings and silently lose the association.
    await AppSettingsStore.getInstance().saveAppSettings(this.value);
    router.pushUrl({
      url: 'pages/InputLayoutEditor',
      params: {
        appId: this.value.appId,
        profileId: profileId,
        profileName: this.profileEditorName(),
        baseProfileId: this.globalProfileId()
      }
    });
  }

  private async openKeyMapping(): Promise<void> {
    const profileId = this.profileEditorId();
    this.value = {
      appId: this.value.appId,
      customTitle: this.value.customTitle,
      customCover: this.value.customCover,
      favorite: this.value.favorite,
      box64Preset: this.value.box64Preset,
      executable: this.value.executable,
      arguments: this.value.arguments,
      workingDirectory: this.value.workingDirectory,
      displayModeOverride: this.value.displayModeOverride,
      inputProfileId: profileId,
      prefixId: this.value.prefixId
    };
    await AppSettingsStore.getInstance().saveAppSettings(this.value);
    router.pushUrl({
      url: 'pages/AdvancedKeyMapping',
      params: {
        appId: this.value.appId,
        profileId: profileId,
        profileName: this.profileEditorName(),
        baseProfileId: this.globalProfileId()
      }
    });
  }

  private async useGlobalInputProfile(): Promise<void> {
    this.value = {
      appId: this.value.appId,
      customTitle: this.value.customTitle,
      customCover: this.value.customCover,
      favorite: this.value.favorite,
      box64Preset: this.value.box64Preset,
      executable: this.value.executable,
      arguments: this.value.arguments,
      workingDirectory: this.value.workingDirectory,
      displayModeOverride: this.value.displayModeOverride,
      inputProfileId: 'default',
      prefixId: this.value.prefixId
    };
    await AppSettingsStore.getInstance().saveAppSettings(this.value);
    promptAction.showToast({ message: '此应用已恢复使用全局输入方案' });
  }

  private setFavorite(value: boolean): void {
    this.value = {
      appId: this.value.appId,
      customTitle: this.value.customTitle,
      customCover: this.value.customCover,
      favorite: value,
      box64Preset: this.value.box64Preset,
      executable: this.value.executable,
      arguments: this.value.arguments,
      workingDirectory: this.value.workingDirectory,
      displayModeOverride: this.value.displayModeOverride,
      inputProfileId: this.value.inputProfileId,
      prefixId: this.value.prefixId
    };
  }

  private setBox64Preset(preset: string): void {
    if (preset === this.value.box64Preset) return;
    this.value = {
      appId: this.value.appId,
      customTitle: this.value.customTitle,
      customCover: this.value.customCover,
      favorite: this.value.favorite,
      box64Preset: preset,
      executable: this.value.executable,
      arguments: this.value.arguments,
      workingDirectory: this.value.workingDirectory,
      displayModeOverride: this.value.displayModeOverride,
      inputProfileId: this.value.inputProfileId,
      prefixId: this.value.prefixId
    };
  }

  @Builder
  private Field(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 7 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value }).height(48).borderRadius(14).backgroundColor($r('app.color.search_background'))
        .onChange((text: string) => onChange(text))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      HdsNavigation() {
        Scroll(this.appSettingsScroller) {
        Column({ space: 18 }) {
          Column({ space: 16 }) {
            Text('卡片与启动').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            this.Field('显示名称', this.value.customTitle, (text: string): void => this.replace(text, this.value.customCover, this.value.executable, this.value.workingDirectory, this.value.displayModeOverride))
            Row() {
              Column({ space: 4 }) {
                Text('收藏').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                Text('收藏后可从侧边栏快速访问').fontSize(11).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.value.favorite }).onChange((value: boolean): void => this.setFavorite(value))
            }.width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
            if (this.app && this.app.source === AppSource.DOWNLOAD) {
              Column({ space: 6 }) {
                Text('当前游戏目录').fontSize(13).fontColor($r('app.color.text_secondary'))
                Text(this.app.directory).fontSize(12).fontColor($r('app.color.text_primary')).maxLines(2)
                Text('从此目录及所有子目录选择 EXE、COM、BAT 或 CMD；不会打开系统文件框。')
                  .fontSize(11).fontColor($r('app.color.text_secondary'))
                Text(this.value.executable ? '当前主程序：' + this.relativeExecutablePath(this.app.directory, this.value.executable) : '尚未选择主程序')
                  .fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(2)
                if (!this.app.available && this.value.executable === this.app.launchTarget.executable) {
                  Text('未找到当前主程序，请重新选择。').fontSize(12).fontColor('#D94848')
                }
                Button('选择此游戏目录中的主程序').width('100%').height(48).backgroundColor($r('app.color.search_background'))
                  .fontColor($r('app.color.text_primary')).id('app-settings-select-exe').onClick(() => this.openExecutablePicker())
              }.width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14).alignItems(HorizontalAlign.Start)
            } else {
              Text('内建系统应用由 Wine 运行时提供，不能更换 EXE。').fontSize(12).fontColor($r('app.color.text_secondary'))
                .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
            }
            Button('选择封面图片').width('100%').height(48).backgroundColor($r('app.color.search_background'))
              .fontColor($r('app.color.text_primary')).id('app-settings-select-cover').onClick(() => this.selectCover())
          }.width('100%').padding(this.cardPadding()).backgroundColor($r('app.color.card_background')).borderRadius(16)

          Column({ space: 13 }) {
            Text('显示模式').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 8 }) {
              Button('跟随全局').layoutWeight(1).height(48).borderRadius(14)
                .fontSize(this.isCompact() ? 11 : 14)
                .backgroundColor(this.value.displayModeOverride === null ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.value.displayModeOverride === null ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .id('app-settings-mode-inherit')
                .onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, null))
              Button('桌面模式').layoutWeight(1).height(48).borderRadius(14)
                .fontSize(this.isCompact() ? 11 : 14)
                .backgroundColor(this.value.displayModeOverride === DisplayMode.DESKTOP ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.value.displayModeOverride === DisplayMode.DESKTOP ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .id('app-settings-mode-desktop')
                .onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, DisplayMode.DESKTOP))
              Button('单应用').layoutWeight(1).height(48).borderRadius(14)
                .fontSize(this.isCompact() ? 11 : 14)
                .backgroundColor(this.value.displayModeOverride === DisplayMode.SINGLE_APP ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.value.displayModeOverride === DisplayMode.SINGLE_APP ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .id('app-settings-mode-single')
                .onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, DisplayMode.SINGLE_APP))
            }.width('100%')
          }.width('100%').padding(this.cardPadding()).backgroundColor($r('app.color.card_background')).borderRadius(16)

          Column({ space: 12 }) {
            Text('兼容性').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            Text('Box64 兼容性预设').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            Text('影响程序在兼容模拟层上的稳定性与性能；跟随全局表示使用系统设置中的预设。')
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(BOX64_PRESET_IDS, (preset: string) => {
                Button(box64PresetLabel(preset))
                  .height(42)
                  .padding({ left: 12, right: 12 })
                  .margin({ right: 8, bottom: 8 })
                  .borderRadius(14)
                  .fontSize(12)
                  .fontColor(this.value.box64Preset === preset ?
                    '#FFFFFFFF' : $r('app.color.text_primary'))
                  .backgroundColor(this.value.box64Preset === preset ?
                    $r('app.color.accent') : $r('app.color.search_background'))
                  .id('app-settings-box64-' + preset)
                  .onClick(() => this.setBox64Preset(preset))
              }, (preset: string): string => preset)
            }.width('100%')
            Text(this.value.box64Preset === BOX64_PRESET_DEFAULT ?
              '此应用跟随全局兼容性预设。' : '此应用使用「' + box64PresetLabel(this.value.box64Preset) + '」。')
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          }.width('100%').padding(this.cardPadding()).backgroundColor($r('app.color.card_background')).borderRadius(16)

          Column({ space: 12 }) {
            Text('输入映射').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            Text('桌面模式始终使用系统设置中的桌面全局方案；这里的应用专用方案只在单应用模式启动时生效。')
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            Text(this.currentProfileId() === 'default' ? '当前跟随桌面全局输入方案' : '当前使用应用专用键鼠手柄布局')
              .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Button('编辑虚拟按键 / 虚拟鼠标 / 手柄映射')
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.search_background'))
              .fontColor($r('app.color.text_primary'))
              .id('app-settings-edit-input-profile')
              .onClick(() => this.editInputProfile())
            Button('编辑按键映射与自由按键')
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.search_background'))
              .fontColor($r('app.color.text_primary'))
              .id('app-settings-open-key-mapping')
              .onClick((): void => { this.openKeyMapping(); })
            if (this.currentProfileId() !== 'default') {
              Button('恢复使用全局输入方案')
                .width('100%')
                .height(48)
                .backgroundColor('#1F246BFD')
                .fontColor($r('app.color.accent'))
                .id('app-settings-use-global-input')
                .onClick((): void => { this.useGlobalInputProfile(); })
            }
          }.width('100%').padding(this.cardPadding()).backgroundColor($r('app.color.card_background')).borderRadius(16)

          if (this.app && !this.app.available) {
            Button('删除不可用卡片').height(48).fontColor('#D94848').backgroundColor($r('app.color.card_background')).onClick(() => this.removeUnavailable())
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%', maxWidth: this.contentMaxWidth() })
        .padding({
          left: this.contentSidePadding(), right: this.contentSidePadding(),
          top: this.contentTopInset(),
          bottom: Math.max(this.isCompact() ? 32 : 44, this.navBarInsetVp)
        })
        .alignSelf(ItemAlign.Start)
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        padding: { start: LengthMetrics.vp(14), end: LengthMetrics.vp(14 + this.titleButtonMargin()) },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: SUPPORTS_HDS_FLOATING ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR : ScrollEffectType.GRADUAL_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(SUPPORTS_HDS_FLOATING ? 96 : 68)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: this.navigationTitleBackground(false)
          },
          contentStyle: {
              titleStyle: {
                mainTitleColor: $r('app.color.text_primary'),
                subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.accent')
            },
            backIconStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
              }
            }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.navigationTitleBackground(true)
          },
          contentStyle: {
              titleStyle: {
                mainTitleColor: $r('app.color.text_primary'),
                subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.accent')
            },
            backIconStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
              }
            }
        },
        systemMaterialEffect: SUPPORTS_HDS_FLOATING ? {
          materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
          materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
        } : undefined
        },
        content: {
          title: {
            mainTitle: this.app ? this.app.title + ' 设置' : '应用设置',
            subTitle: this.isCompact() ? undefined : '封面、启动方式、显示模式和专用输入布局'
          },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.checkmark'),
                  action: (): void => { this.save(); }
                }
              }
            ],
            maxCount: 1
          } as HdsNavigationMenuContentOptions,
          divider: { showType: DividerShowType.OFF }
      },
        avoidLayoutSafeArea: true
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideToolBar(true)
      .systemBarStyle(
        { statusBarContentColor: this.navigationTitleColor() },
        { statusBarContentColor: this.navigationTitleColor() }
      )
      .bindToScrollable([this.appSettingsScroller])
      .width('100%').height('100%')
      .backgroundColor('#00FFFFFF')
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
