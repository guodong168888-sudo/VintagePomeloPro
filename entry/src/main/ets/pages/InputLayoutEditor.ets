import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import {
  InputProfile,
  GamepadButtonMapping,
  VirtualControlDescriptor,
  VirtualControlKind,
  createDefaultInputProfile
} from '../model/AppModels';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { InputProfileService } from '../service/InputProfileService';

@Entry
@Component
struct InputLayoutEditor {
  @State private profile: InputProfile = createDefaultInputProfile();
  @State private profileId: string = 'default';
  @State private profileName: string = '默认键鼠手柄';
  @State private appId: string = '';
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private resetToDefault(): void {
    const defaults = createDefaultInputProfile();
    this.profile = {
      id: this.profileId,
      name: this.profileName,
      buttonOpacity: defaults.buttonOpacity,
      stickDeadzone: defaults.stickDeadzone,
      gamepadMappings: defaults.gamepadMappings.map((mapping: GamepadButtonMapping): GamepadButtonMapping => ({
        id: mapping.id,
        label: mapping.label,
        buttonCode: mapping.buttonCode,
        evdevCode: mapping.evdevCode
      })),
      controls: defaults.controls.map((control: VirtualControlDescriptor): VirtualControlDescriptor => ({
        id: control.id,
        label: control.label,
        kind: control.kind,
        evdevCode: control.evdevCode,
        xPercent: control.xPercent,
        yPercent: control.yPercent,
        size: control.size,
        opacity: control.opacity
      }))
    };
  }

  aboutToAppear(): void {
    const params = (router.getParams() as Record<string, string> | undefined) ?? {};
    this.profileId = params.profileId ?? 'default';
    this.profileName = params.profileName ?? (this.profileId === 'default' ? '默认键鼠手柄' : '应用专用布局');
    this.appId = params.appId ?? '';
    InputProfileService.getInstance().initialize(this.context).then(() => {
      this.profile = InputProfileService.getInstance().ensureProfile(this.profileId, this.profileName);
      this.profileName = this.profile.name;
    });
  }

  private updateControl(index: number, x: number, y: number, size: number,
    opacity: number, keyCode: number): void {
    const controls: VirtualControlDescriptor[] = this.profile.controls.slice();
    const current = controls[index];
    controls[index] = {
      id: current.id,
      label: current.label,
      kind: current.kind,
      evdevCode: keyCode,
      xPercent: x,
      yPercent: y,
      size: size,
      opacity: opacity
    };
    this.profile = {
      id: this.profile.id,
      name: this.profile.name,
      buttonOpacity: this.profile.buttonOpacity,
      stickDeadzone: this.profile.stickDeadzone,
      gamepadMappings: this.profile.gamepadMappings,
      controls: controls
    };
  }

  private updateGamepadMapping(index: number, evdevCode: number): void {
    const mappings: GamepadButtonMapping[] = this.profile.gamepadMappings.slice();
    const current = mappings[index];
    mappings[index] = {
      id: current.id,
      label: current.label,
      buttonCode: current.buttonCode,
      evdevCode: evdevCode
    };
    this.profile = {
      id: this.profile.id,
      name: this.profile.name,
      buttonOpacity: this.profile.buttonOpacity,
      stickDeadzone: this.profile.stickDeadzone,
      gamepadMappings: mappings,
      controls: this.profile.controls
    };
  }

  private async save(): Promise<void> {
    await InputProfileService.getInstance().saveProfile(this.profile);
    if (this.appId) {
      const current = AppSettingsStore.getInstance().getAppSettings(this.appId);
      await AppSettingsStore.getInstance().saveAppSettings({
        appId: current.appId,
        customTitle: current.customTitle,
        customCover: current.customCover,
        executable: current.executable,
        arguments: current.arguments,
        workingDirectory: current.workingDirectory,
        displayModeOverride: current.displayModeOverride,
        inputProfileId: this.profile.id,
        prefixId: current.prefixId
      });
    }
    promptAction.showToast({ message: '虚拟按键布局已保存' });
    router.back();
  }

  build() {
    Column() {
      Row() {
        Button('‹').type(ButtonType.Circle).width(38).height(38).backgroundColor('#00000000').onClick(() => router.back())
        Column({ space: 2 }) {
          Text(this.profileName).fontSize(24).fontWeight(FontWeight.Bold)
          Text('位置、大小、透明度与 evdev 映射').fontSize(11).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('恢复默认').backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary')).onClick(() => this.resetToDefault())
        Button('保存').onClick(() => this.save())
      }.height(68).width('100%')

      Scroll() {
        Column({ space: 12 }) {
          Text('实体手柄映射').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
          Text('手柄按键会转换为 Wine 可识别的 evdev 键码；摇杆与十字键继续按死区设置处理。')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          ForEach(this.profile.gamepadMappings, (mapping: GamepadButtonMapping, index: number) => {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(mapping.label).fontSize(15).fontWeight(FontWeight.Medium)
                Text('物理代码 ' + mapping.buttonCode).fontSize(11).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              TextInput({ text: mapping.evdevCode.toString() })
                .width(94).height(40).type(InputType.Number)
                .onChange((value: string) => this.updateGamepadMapping(index, Number(value) || 0))
            }
            .width('100%').padding(14).backgroundColor($r('app.color.card_background')).borderRadius(14)
          }, (mapping: GamepadButtonMapping) => mapping.id)

          Text('虚拟按键与鼠标布局').fontSize(18).fontWeight(FontWeight.Medium).width('100%').margin({ top: 12 })
          ForEach(this.profile.controls, (control: VirtualControlDescriptor, index: number) => {
            Column({ space: 10 }) {
              Row() {
                Text(control.label + '  ·  ' + control.kind).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
                TextInput({ text: control.evdevCode.toString() })
                  .width(90).height(38).type(InputType.Number)
                  .onChange((value: string) => this.updateControl(index, control.xPercent, control.yPercent,
                    control.size, control.opacity, Number(value) || 0))
              }.width('100%')
              Text('横向位置 ' + Math.round(control.xPercent) + '%').fontSize(12).width('100%')
              Slider({ value: control.xPercent, min: 0, max: 92, step: 1 })
                .onChange((value: number) => this.updateControl(index, value, control.yPercent, control.size, control.opacity, control.evdevCode))
              Text('纵向位置 ' + Math.round(control.yPercent) + '%').fontSize(12).width('100%')
              Slider({ value: control.yPercent, min: 0, max: 92, step: 1 })
                .onChange((value: number) => this.updateControl(index, control.xPercent, value, control.size, control.opacity, control.evdevCode))
              Row({ space: 12 }) {
                Column() {
                  Text('大小 ' + Math.round(control.size) + 'vp').fontSize(12).width('100%')
                  Slider({ value: control.size, min: 32,
                    max: control.kind === VirtualControlKind.TOUCHPAD ? 180 : 120, step: 1 })
                    .onChange((value: number) => this.updateControl(index, control.xPercent, control.yPercent, value, control.opacity, control.evdevCode))
                }.layoutWeight(1)
                Column() {
                  Text('透明度 ' + Math.round(control.opacity) + '%').fontSize(12).width('100%')
                  Slider({ value: control.opacity, min: 20, max: 100, step: 1 })
                    .onChange((value: number) => this.updateControl(index, control.xPercent, control.yPercent, control.size, value, control.evdevCode))
                }.layoutWeight(1)
              }.width('100%')
            }
            .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)
          }, (control: VirtualControlDescriptor) => control.id)
        }.width('100%').padding({ bottom: 30 })
      }.layoutWeight(1).scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.page_background'))
  }
}
