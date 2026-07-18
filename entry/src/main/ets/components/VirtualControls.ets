import {
  InputProfile,
  VirtualControlDescriptor,
  VirtualControlKind,
  createDefaultInputProfile
} from '../model/AppModels';
import { InputRouter } from '../service/InputRouter';
import { VirtualKeyboard } from './VirtualKeyboard';

interface TouchOrigin {
  x: number;
  y: number;
  startX: number;
  startY: number;
  moved: boolean;
}

@Component
export struct VirtualControls {
  @Prop opacityValue: number = 72;
  @Prop profile: InputProfile = createDefaultInputProfile();
  @State private keyboardVisible: boolean = false;
  private origins: Map<string, TouchOrigin> = new Map<string, TouchOrigin>();
  private stickKeys: Map<string, Set<number>> = new Map<string, Set<number>>();

  private sendKey(code: number, pressed: boolean): void {
    InputRouter.getInstance().sendKey(code, pressed);
  }

  private handleTouchPad(control: VirtualControlDescriptor, event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (!point) return;
    const x = vp2px(point.x);
    const y = vp2px(point.y);
    const previous = this.origins.get(control.id);
    if (event.type === TouchType.Down) {
      this.origins.set(control.id, { x: x, y: y, startX: x, startY: y, moved: false });
    } else if (event.type === TouchType.Move && previous) {
      const dx = x - previous.x;
      const dy = y - previous.y;
      const moved = previous.moved || Math.abs(dx) + Math.abs(dy) > 3;
      InputRouter.getInstance().sendPointerDelta(dx, dy);
      this.origins.set(control.id, { x: x, y: y, startX: previous.startX, startY: previous.startY, moved: moved });
    } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && previous) {
      if (event.type === TouchType.Up && !previous.moved) {
        InputRouter.getInstance().sendPointerButton(MouseAction.Press, 272);
        InputRouter.getInstance().sendPointerButton(MouseAction.Release, 272);
      }
      this.origins.delete(control.id);
    }
  }

  private handleScroll(control: VirtualControlDescriptor, event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (!point) return;
    const y = vp2px(point.y);
    const previous = this.origins.get(control.id);
    if (event.type === TouchType.Down) {
      this.origins.set(control.id, { x: 0, y: y, startX: 0, startY: y, moved: false });
    } else if (event.type === TouchType.Move && previous) {
      const delta = previous.y - y;
      if (Math.abs(delta) >= 12) {
        InputRouter.getInstance().sendScrollAtPointer(0, delta > 0 ? 1 : -1);
        this.origins.set(control.id, { x: 0, y: y, startX: 0, startY: previous.startY, moved: true });
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.origins.delete(control.id);
    }
  }

  private setStickKey(controlId: string, code: number, pressed: boolean): void {
    let active = this.stickKeys.get(controlId);
    if (!active) {
      active = new Set<number>();
      this.stickKeys.set(controlId, active);
    }
    if (pressed === active.has(code)) return;
    if (pressed) active.add(code); else active.delete(code);
    this.sendKey(code, pressed);
  }

  private releaseStick(controlId: string): void {
    const active = this.stickKeys.get(controlId);
    if (!active) return;
    active.forEach((code: number): void => this.sendKey(code, false));
    active.clear();
    this.stickKeys.delete(controlId);
  }

  private handleStick(control: VirtualControlDescriptor, event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (!point) return;
    const x = vp2px(point.x);
    const y = vp2px(point.y);
    const previous = this.origins.get(control.id);
    if (event.type === TouchType.Down) {
      this.origins.set(control.id, { x: x, y: y, startX: x, startY: y, moved: false });
    } else if (event.type === TouchType.Move && previous) {
      if (control.evdevCode === 1) {
        InputRouter.getInstance().sendPointerDelta((x - previous.x) * 0.7, (y - previous.y) * 0.7);
      } else {
        const threshold = vp2px(control.size * 0.12);
        const deltaX = x - previous.startX;
        const deltaY = y - previous.startY;
        this.setStickKey(control.id, 30, deltaX < -threshold);
        this.setStickKey(control.id, 32, deltaX > threshold);
        this.setStickKey(control.id, 17, deltaY < -threshold);
        this.setStickKey(control.id, 31, deltaY > threshold);
      }
      this.origins.set(control.id, { x: x, y: y, startX: previous.startX, startY: previous.startY, moved: true });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.releaseStick(control.id);
      this.origins.delete(control.id);
    }
  }

  @Builder
  private Control(control: VirtualControlDescriptor) {
    if (control.kind === VirtualControlKind.STICK) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: control.size * 0.46, height: control.size * 0.46 })
          .fill('#88FFFFFF')
        Text(control.label).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
      }
      .width(control.size).height(control.size)
      .backgroundColor('#66282D38').borderRadius(control.size / 2)
      .border({ width: 2, color: '#66FFFFFF' })
      .hitTestBehavior(HitTestMode.Block)
      .opacity(control.opacity / 100)
      .position({ x: control.xPercent + '%', y: control.yPercent + '%' })
      .onTouch((event: TouchEvent) => this.handleStick(control, event))
    } else if (control.kind === VirtualControlKind.TOUCHPAD) {
      Column({ space: 5 }) {
        Text('⌁').fontSize(22).fontColor('#FFFFFFFF')
        Text(control.label).fontSize(10).fontColor('#DFFFFFFF')
      }
      .width(control.size * 1.45).height(control.size)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#80282D38').borderRadius(18)
      .border({ width: 1, color: '#55FFFFFF' })
      .hitTestBehavior(HitTestMode.Block)
      .opacity(control.opacity / 100)
      .position({ x: control.xPercent + '%', y: control.yPercent + '%' })
      .onTouch((event: TouchEvent) => this.handleTouchPad(control, event))
    } else if (control.kind === VirtualControlKind.SCROLL) {
      Column({ space: 4 }) {
        Text('↕').fontSize(22).fontColor('#FFFFFFFF')
        Text(control.label).fontSize(10).fontColor('#DFFFFFFF')
      }
      .width(control.size).height(control.size * 1.5)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#80282D38').borderRadius(18)
      .border({ width: 1, color: '#55FFFFFF' })
      .hitTestBehavior(HitTestMode.Block)
      .opacity(control.opacity / 100)
      .position({ x: control.xPercent + '%', y: control.yPercent + '%' })
      .onTouch((event: TouchEvent) => this.handleScroll(control, event))
    } else {
      Button(control.label)
        .type(ButtonType.Circle)
        .width(control.size).height(control.size)
        .fontSize(control.label.length > 2 ? 11 : 16)
        .fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
        .backgroundColor('#B5282D38')
        .border({ width: 1, color: '#66FFFFFF' })
        .hitTestBehavior(HitTestMode.Block)
        .opacity(control.opacity / 100)
        .position({ x: control.xPercent + '%', y: control.yPercent + '%' })
        .onTouch((event: TouchEvent) => {
          if (control.kind === VirtualControlKind.MOUSE_BUTTON) {
            if (event.type === TouchType.Down) InputRouter.getInstance().sendPointerButton(MouseAction.Press, control.evdevCode);
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) InputRouter.getInstance().sendPointerButton(MouseAction.Release, control.evdevCode);
          } else {
            if (event.type === TouchType.Down) this.sendKey(control.evdevCode, true);
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.sendKey(control.evdevCode, false);
          }
        })
    }
  }

  build() {
    Stack() {
      ForEach(this.profile.controls, (control: VirtualControlDescriptor) => {
        this.Control(control)
      }, (control: VirtualControlDescriptor) => control.id)
      if (this.keyboardVisible) {
        VirtualKeyboard({
          opacityValue: Math.max(82, this.opacityValue),
          onClose: (): void => { this.keyboardVisible = false; }
        })
      } else {
        Button('⌨')
          .type(ButtonType.Circle)
          .width(44).height(44)
          .fontSize(20).fontColor('#FFFFFFFF')
          .backgroundColor('#B5282D38')
          .border({ width: 1, color: '#66FFFFFF' })
          .hitTestBehavior(HitTestMode.Block)
          .position({ x: '92%', y: '3%' })
          .onClick(() => this.keyboardVisible = true)
      }
    }
    .width('100%').height('100%')
    .opacity(this.opacityValue / 100)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
