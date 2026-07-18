import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  AppDescriptor,
  AppSettings as StoredAppSettings,
  DisplayMode,
  createDefaultAppSettings
} from '../model/AppModels';
import { AppCatalogService } from '../service/AppCatalogService';
import { AppSettingsStore } from '../service/AppSettingsStore';

@Entry
@Component
struct AppSettingsPage {
  @State private app: AppDescriptor | null = null;
  @State private value: StoredAppSettings = createDefaultAppSettings('');
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    const appId = params.appId ?? '';
    this.app = AppCatalogService.getInstance().getApps().find((item: AppDescriptor) => item.id === appId) ?? null;
    this.value = AppSettingsStore.getInstance().getAppSettings(appId);
    if (this.app) {
      this.value = {
        appId: appId,
        customTitle: this.value.customTitle || this.app.title,
        customCover: this.value.customCover,
        executable: this.value.executable || this.app.launchTarget.executable,
        arguments: this.value.arguments,
        workingDirectory: this.value.workingDirectory || this.app.launchTarget.workingDirectory,
        displayModeOverride: this.value.displayModeOverride ?? this.app.displayModeOverride,
        inputProfileId: this.value.inputProfileId,
        prefixId: this.value.prefixId
      };
    }
  }

  private replace(title: string, cover: string, executable: string, workingDirectory: string,
    displayMode: DisplayMode | null): void {
    this.value = {
      appId: this.value.appId,
      customTitle: title,
      customCover: cover,
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

  private async selectExecutable(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['Windows 程序|.exe'];
      options.maxSelectNumber = 1;
      const result = await documentPicker.select(options);
      if (!result || result.length === 0) return;
      const executable = new fileUri.FileUri(result[0]).path;
      const separator = executable.lastIndexOf('/');
      const workingDirectory = separator > 0 ? executable.substring(0, separator) : this.value.workingDirectory;
      this.replace(this.value.customTitle, this.value.customCover, executable,
        workingDirectory, this.value.displayModeOverride);
    } catch (_) {
      promptAction.showToast({ message: '未选择可执行文件' });
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

  @Builder
  private Field(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 7 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value }).height(44).borderRadius(10).backgroundColor($r('app.color.search_background'))
        .onChange((text: string) => onChange(text))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Button('‹').type(ButtonType.Circle).width(38).height(38).backgroundColor('#00000000').onClick(() => router.back())
        Text(this.app ? this.app.title + ' 设置' : '应用设置').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('保存').borderRadius(20).onClick(() => this.save())
      }.width('100%').height(64)

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 16 }) {
            Text('卡片与启动').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            this.Field('显示名称', this.value.customTitle, (text: string): void => this.replace(text, this.value.customCover, this.value.executable, this.value.workingDirectory, this.value.displayModeOverride))
            this.Field('可执行文件路径（用于重新关联）', this.value.executable, (text: string): void => this.replace(this.value.customTitle, this.value.customCover, text, this.value.workingDirectory, this.value.displayModeOverride))
            Button('选择 EXE 文件').width('100%').backgroundColor($r('app.color.search_background'))
              .fontColor($r('app.color.text_primary')).onClick(() => this.selectExecutable())
            this.Field('工作目录', this.value.workingDirectory, (text: string): void => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, text, this.value.displayModeOverride))
            this.Field('自定义封面路径', this.value.customCover, (text: string): void => this.replace(this.value.customTitle, text, this.value.executable, this.value.workingDirectory, this.value.displayModeOverride))
            Button('选择封面图片').width('100%').backgroundColor($r('app.color.search_background'))
              .fontColor($r('app.color.text_primary')).onClick(() => this.selectCover())
          }.width('100%').padding(20).backgroundColor($r('app.color.card_background')).borderRadius(16)

          Column({ space: 13 }) {
            Text('显示模式').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 8 }) {
              Button('跟随全局').layoutWeight(1).backgroundColor(this.value.displayModeOverride === null ? $r('app.color.accent') : $r('app.color.search_background')).onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, null))
              Button('桌面模式').layoutWeight(1).backgroundColor(this.value.displayModeOverride === DisplayMode.DESKTOP ? $r('app.color.accent') : $r('app.color.search_background')).onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, DisplayMode.DESKTOP))
              Button('单应用').layoutWeight(1).backgroundColor(this.value.displayModeOverride === DisplayMode.SINGLE_APP ? $r('app.color.accent') : $r('app.color.search_background')).onClick(() => this.replace(this.value.customTitle, this.value.customCover, this.value.executable, this.value.workingDirectory, DisplayMode.SINGLE_APP))
            }.width('100%')
          }.width('100%').padding(20).backgroundColor($r('app.color.card_background')).borderRadius(16)

          if (this.app && !this.app.available) {
            Button('删除不可用卡片').fontColor('#D94848').backgroundColor($r('app.color.card_background')).onClick(() => this.removeUnavailable())
          }
        }.width('100%').padding({ bottom: 30 })
      }.layoutWeight(1).scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').padding({ left: 24, right: 24, top: 8 })
    .backgroundColor($r('app.color.page_background'))
  }
}
