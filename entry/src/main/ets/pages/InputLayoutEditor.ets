import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import {
  InputProfile,
  VirtualControlDescriptor,
  VirtualControlKind,
  createDefaultInputProfile
} from '../model/AppModels';
import { InputProfileService } from '../service/InputProfileService';

@Entry
@Component
struct InputLayoutEditor {
  @State private profile: InputProfile = createDefaultInputProfile();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    InputProfileService.getInstance().initialize(this.context).then(() => {
      this.profile = InputProfileService.getInstance().getProfile('default');
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
      controls: controls
    };
  }

  private async save(): Promise<void> {
    await InputProfileService.getInstance().saveProfile(this.profile);
    promptAction.showToast({ message: '虚拟按键布局已保存' });
    router.back();
  }

  build() {
    Column() {
      Row() {
        Button('‹').type(ButtonType.Circle).width(38).height(38).backgroundColor('#00000000').onClick(() => router.back())
        Column({ space: 2 }) {
          Text('虚拟按键布局').fontSize(24).fontWeight(FontWeight.Bold)
          Text('位置、大小、透明度与 evdev 映射').fontSize(11).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('恢复默认').backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary')).onClick(() => this.profile = createDefaultInputProfile())
        Button('保存').onClick(() => this.save())
      }.height(68).width('100%')

      Scroll() {
        Column({ space: 12 }) {
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
