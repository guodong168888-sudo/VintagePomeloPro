import {
  DirectionControlMode,
  FreeButton,
  FreeButtonLayoutMode,
  InputProfile,
  VirtualKey,
  VirtualKeyColorScheme,
  computeGamepadPositions,
  computeRadialPositions,
  createDefaultInputProfile
} from '../model/AppModels';
import { InputDispatcher } from '../service/InputDispatcher';

type DirectionName = 'up' | 'down' | 'left' | 'right';

interface OverlayPoint {
  x: number;
  y: number;
}

/**
 * Wine adapter of VintagePomelo's VirtualGamepad overlay.  Its layout contract
 * is intentionally group based: direction, action and auxiliary.  Individual
 * control coordinates are not supported, so a d-pad and joystick cannot be
 * displayed together.
 */
@Component
export struct VirtualInputOverlay {
  @Prop profile: InputProfile = createDefaultInputProfile();
  @Prop opacityValue: number = 100;
  @Prop interactive: boolean = true;
  @Prop hideToolbar: boolean = false;
  onOpenLayoutEditor: () => void = (): void => {};
  onUnhandledTouch: (event: TouchEvent) => void = (_event: TouchEvent): void => {};
  onUnhandledMouse: (event: MouseEvent) => void = (_event: MouseEvent): void => {};
  onUnhandledAxis: (event?: AxisEvent) => void = (_event?: AxisEvent): void => {};

  @State private overlayW: number = 0;
  @State private overlayH: number = 0;
  @State private pressedKeys: string = '';
  @State private joystickActive: boolean = false;
  @State private joystickX: number = 0;
  @State private joystickY: number = 0;
  @State private dpadUp: boolean = false;
  @State private dpadDown: boolean = false;
  @State private dpadLeft: boolean = false;
  @State private dpadRight: boolean = false;
  @State private pressedFreeButtons: string = '';
  // Keep the ArkTS control bar alive when the gamepad itself is folded.  This
  // is the same split VintagePomelo uses: the control bar remains clickable,
  // while the actual virtual controls can be hidden and restored instantly.
  @State private controlsExpanded: boolean = true;
  private activeButtonTouches: Map<VirtualKey, number> = new Map<VirtualKey, number>();
  private joystickTouchId: number = -1;
  private joystickCenterX: number = 0;
  private joystickCenterY: number = 0;
  private dpadTouchId: number = -1;
  private activeFreeTouches: Map<string, number> = new Map<string, number>();
  private activeActionMouseKey: VirtualKey | null = null;
  private activeActionMouseFallback: number = 0;
  private lastActionTouchAt: number = 0;

  private config() {
    return this.profile.virtualKeyConfig;
  }

  private visibleOpacity(transparency: number): number {
    return Math.max(0.16, Math.min(1, (100 - transparency) / 100 * this.opacityValue / 100));
  }

  private strokeColor(): string {
    return this.config().colorScheme === VirtualKeyColorScheme.WHITE ? '#FFF2F6FF' : '#FF2196F3';
  }

  private outlineBackdropColor(): string {
    return this.config().colorScheme === VirtualKeyColorScheme.WHITE ? '#FF101820' : '#FFF4F8FF';
  }

  private fillColor(pressed: boolean): string {
    return pressed ? this.strokeColor() : '#8032323A';
  }

  private textColor(pressed: boolean, accent?: string): string {
    if (pressed) return '#FFFFFFFF';
    return accent ?? this.strokeColor();
  }

  private joystickRadius(): number {
    return 60 * this.config().joystickSize / 100;
  }

  private directionSize(): number {
    return this.joystickRadius() * 2 + 20;
  }

  private actionWidth(): number {
    return 140 * this.config().buttonSize / 100;
  }

  private actionHeight(): number {
    let height = 140;
    if (this.config().showButtonShift || this.config().showButtonCtrl) height += 41;
    if (this.config().showButtonL || this.config().showButtonR) height += 43;
    return height * this.config().buttonSize / 100;
  }

  private auxWidth(): number {
    return this.config().showButtonMenu ? 35 * this.config().buttonSize / 100 : 0;
  }

  private groupPosition(centerX: number, centerY: number, groupW: number, groupH: number): OverlayPoint {
    return { x: this.overlayW * centerX - groupW / 2, y: this.overlayH * centerY - groupH / 2 };
  }

  private layout() {
    return this.overlayH > this.overlayW ? this.profile.layoutPortrait : this.profile.layoutLandscape;
  }

  private mapping(key: VirtualKey, fallback: number): number {
    return this.profile.virtualKeyMappings.find((item) => item.virtualKey === key)?.evdevCode ?? fallback;
  }

  private freeButtonSize(): number {
    return 50 * this.config().buttonSize / 100;
  }

  private freeButtonPositions() {
    const free = this.profile.freeButtonsConfig;
    return free.layoutMode === FreeButtonLayoutMode.RADIAL ?
      computeRadialPositions(free.buttons.length, free.radialScale * 0.6) :
      computeGamepadPositions(free.buttons.length, free.gamepadSpacing);
  }

  private freeGroupSize(): number {
    return Math.max(240, this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.RADIAL ? this.profile.freeButtonsConfig.radialScale * 1.5 : 280);
  }

  private freePositionX(index: number): number {
    return this.freeGroupSize() / 2 + (this.freeButtonPositions()[index]?.offsetX ?? 0) - this.freeButtonSize() / 2;
  }

  private freePositionY(index: number): number {
    return this.freeGroupSize() / 2 + (this.freeButtonPositions()[index]?.offsetY ?? 0) - this.freeButtonSize() / 2;
  }

  private rectContains(x: number, y: number, left: number, top: number, width: number, height: number): boolean {
    return x >= left && x <= left + width && y >= top && y <= top + height;
  }

  private actionOrigin(): OverlayPoint {
    return this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
      this.actionWidth(), this.actionHeight());
  }

  private actionButtonAtLocal(localX: number, localY: number): [VirtualKey, number] | null {
    const scale = this.config().buttonSize / 100;
    const small = 35 * scale;
    const spacing = 16 * scale;
    const big = 50 * scale;
    let rowY = 0;
    if (this.config().showButtonShift || this.config().showButtonCtrl) {
      if (this.config().showButtonShift && this.rectContains(localX, localY, 0, rowY, small, small)) {
        return [VirtualKey.BUTTON_SHIFT, 42];
      }
      if (this.config().showButtonCtrl && this.rectContains(localX, localY, small + spacing, rowY, small, small)) {
        return [VirtualKey.BUTTON_CTRL, 29];
      }
      rowY += small + 6;
    }
    if (this.config().showButtonL || this.config().showButtonR) {
      if (this.config().showButtonL && this.rectContains(localX, localY, 0, rowY, small, small)) {
        return [VirtualKey.BUTTON_L, 16];
      }
      if (this.config().showButtonR && this.rectContains(localX, localY, small + spacing, rowY, small, small)) {
        return [VirtualKey.BUTTON_R, 17];
      }
      rowY += small + 8;
    }
    if (this.config().showButtonY && this.rectContains(localX, localY, 45 * scale, rowY, big, big)) {
      return [VirtualKey.BUTTON_Y, 31];
    }
    if (this.config().showButtonX && this.rectContains(localX, localY, 0, rowY + 45 * scale, big, big)) {
      return [VirtualKey.BUTTON_X, 30];
    }
    if (this.config().showButtonA && this.rectContains(localX, localY, 90 * scale, rowY + 45 * scale, big, big)) {
      return [VirtualKey.BUTTON_A, 57];
    }
    if (this.config().showButtonB && this.rectContains(localX, localY, 45 * scale, rowY + 90 * scale, big, big)) {
      return [VirtualKey.BUTTON_B, 45];
    }
    return null;
  }

  private activeButtonForTouch(touchId: number): [VirtualKey, number] | null {
    for (const entry of this.activeButtonTouches.entries()) {
      if (entry[1] === touchId) return [entry[0], this.fallbackForKey(entry[0])];
    }
    return null;
  }

  private fallbackForKey(key: VirtualKey): number {
    switch (key) {
      case VirtualKey.BUTTON_SHIFT: return 42;
      case VirtualKey.BUTTON_CTRL: return 29;
      case VirtualKey.BUTTON_L: return 16;
      case VirtualKey.BUTTON_R: return 17;
      case VirtualKey.BUTTON_Y: return 31;
      case VirtualKey.BUTTON_X: return 30;
      case VirtualKey.BUTTON_A: return 57;
      case VirtualKey.BUTTON_B: return 45;
      case VirtualKey.BUTTON_MENU: return 1;
      default: return 0;
    }
  }

  private handleActionOverlayTouch(event: TouchEvent, x: number, y: number): boolean {
    const touch = event.changedTouches[0];
    if (!touch) return false;
    const active = this.activeButtonForTouch(touch.id);
    if (active) {
      this.handleButtonTouch(event, active[0], active[1]);
      return true;
    }
    const origin = this.actionOrigin();
    const target = event.type === TouchType.Down ? this.actionButtonAtLocal(x - origin.x, y - origin.y) : null;
    if (target) {
      this.handleButtonTouch(event, target[0], target[1]);
      return true;
    }
    return this.rectContains(x, y, this.actionOrigin().x, this.actionOrigin().y,
      this.actionWidth(), this.actionHeight());
  }

  private handleActionGroupTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) return;
    this.lastActionTouchAt = Date.now();
    const touch = event.changedTouches[0];
    const active = this.activeButtonForTouch(touch.id);
    if (active) {
      this.handleButtonTouch(event, active[0], active[1]);
      return;
    }
    const target = event.type === TouchType.Down ?
      this.actionButtonAtLocal(Number(touch.x), Number(touch.y)) : null;
    if (target) this.handleButtonTouch(event, target[0], target[1]);
    else event.stopPropagation();
  }

  private handleActionGroupMouse(event: MouseEvent): void {
    event.stopPropagation();
    if (Date.now() - this.lastActionTouchAt <= 320) return;
    if (event.action === MouseAction.Press) {
      const target = this.actionButtonAtLocal(Number(event.x), Number(event.y));
      if (!target) return;
      this.activeActionMouseKey = target[0];
      this.activeActionMouseFallback = target[1];
      this.setPressed(target[0], true);
      this.pressVirtualKey(target[0], target[1], -100, 'action-mouse');
      return;
    }
    if (event.action === MouseAction.Release && this.activeActionMouseKey !== null) {
      const key = this.activeActionMouseKey;
      const fallback = this.activeActionMouseFallback;
      this.activeActionMouseKey = null;
      this.activeActionMouseFallback = 0;
      this.setPressed(key, false);
      this.releaseVirtualKey(key, fallback, -100, 'action-mouse');
    }
  }

  private handleFreeOverlayTouch(event: TouchEvent, x: number, y: number): boolean {
    const touch = event.changedTouches[0];
    if (!touch) return false;
    for (const button of this.profile.freeButtonsConfig.buttons) {
      if (this.activeFreeTouches.get(button.id) === touch.id) {
        this.handleFreeButtonTouch(event, button);
        return true;
      }
    }
    for (const button of this.profile.freeButtonsConfig.buttons) {
      const index = this.profile.freeButtonsConfig.buttons.indexOf(button);
      if (this.rectContains(x, y,
        this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
          this.freeGroupSize(), this.freeGroupSize()).x + this.freePositionX(index),
        this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
          this.freeGroupSize(), this.freeGroupSize()).y + this.freePositionY(index),
        this.freeButtonSize(), this.freeButtonSize())) {
        this.handleFreeButtonTouch(event, button);
        return true;
      }
    }
    return this.rectContains(x, y,
      this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
        this.freeGroupSize(), this.freeGroupSize()).x,
      this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
        this.freeGroupSize(), this.freeGroupSize()).y,
      this.freeGroupSize(), this.freeGroupSize());
  }

  private handleOverlayTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) return;
    if (!this.interactive || !this.controlsExpanded) {
      this.onUnhandledTouch(event);
      return;
    }
    const touch = event.changedTouches[0];
    const x = Number(touch.x);
    const y = Number(touch.y);
    const direction = this.groupPosition(this.layout().direction.centerX, this.layout().direction.centerY,
      this.directionSize(), this.directionSize());
    const aux = this.groupPosition(this.layout().aux.centerX, this.layout().aux.centerY,
      this.auxWidth(), 35 * this.config().buttonSize / 100);
    let claimed = false;
    if (this.dpadTouchId === touch.id) {
      this.handleDpadTouch(event);
      claimed = true;
    } else if (this.joystickTouchId === touch.id) {
      this.handleJoystickTouch(event);
      claimed = true;
    } else if (this.profile.freeButtonsConfig.enabled && this.profile.freeButtonsConfig.buttons.length > 0) {
      claimed = this.handleFreeOverlayTouch(event, x, y);
    } else if (this.rectContains(x, y, direction.x, direction.y, this.directionSize(), this.directionSize())) {
      if (this.config().dpadMode === DirectionControlMode.DPAD) this.handleDpadTouch(event);
      else this.handleJoystickTouch(event);
      claimed = true;
    } else {
      claimed = this.handleActionOverlayTouch(event, x, y);
      if (!claimed && this.auxWidth() > 0) {
        claimed = this.rectContains(x, y, aux.x, aux.y, this.auxWidth(), 35 * this.config().buttonSize / 100);
        if (claimed && this.config().showButtonMenu) this.handleButtonTouch(event, VirtualKey.BUTTON_MENU, 1);
      }
    }
    if (claimed) event.stopPropagation();
    else this.onUnhandledTouch(event);
  }

  private isFreePressed(button: FreeButton): boolean {
    return this.pressedFreeButtons.indexOf('|' + button.id + '|') >= 0;
  }

  private setFreePressed(button: FreeButton, pressed: boolean): void {
    const token = '|' + button.id + '|';
    if (pressed && !this.isFreePressed(button)) this.pressedFreeButtons += token;
    if (!pressed && this.isFreePressed(button)) this.pressedFreeButtons = this.pressedFreeButtons.replace(token, '');
  }

  private source(key: VirtualKey, touchId: number, section: string = 'button'): string {
    return 'vintage-' + section + '-' + key + '-' + touchId;
  }

  private isPressed(key: VirtualKey): boolean {
    return this.pressedKeys.indexOf('|' + key + '|') >= 0;
  }

  private setPressed(key: VirtualKey, pressed: boolean): void {
    const token = '|' + key + '|';
    if (pressed && !this.isPressed(key)) this.pressedKeys += token;
    if (!pressed && this.isPressed(key)) this.pressedKeys = this.pressedKeys.replace(token, '');
  }

  private pressVirtualKey(key: VirtualKey, fallback: number, touchId: number, section: string = 'button'): void {
    if (!this.interactive) return;
    InputDispatcher.getInstance().pressKey(this.source(key, touchId, section), this.mapping(key, fallback));
  }

  private releaseVirtualKey(key: VirtualKey, fallback: number, touchId: number, section: string = 'button'): void {
    if (!this.interactive) return;
    const source = this.source(key, touchId, section);
    InputDispatcher.getInstance().releaseKey(source, this.mapping(key, fallback));
    InputDispatcher.getInstance().releaseSource(source);
  }

  private handleButtonTouch(event: TouchEvent, key: VirtualKey, fallback: number): void {
    if (!this.interactive) return;
    event.stopPropagation();
    for (let index = 0; index < event.changedTouches.length; index++) {
      const touch = event.changedTouches[index];
      if (event.type === TouchType.Down && !this.activeButtonTouches.has(key)) {
        this.activeButtonTouches.set(key, touch.id);
        this.setPressed(key, true);
        this.pressVirtualKey(key, fallback, touch.id);
      } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) &&
        this.activeButtonTouches.get(key) === touch.id) {
        this.activeButtonTouches.delete(key);
        this.setPressed(key, false);
        this.releaseVirtualKey(key, fallback, touch.id);
      }
    }
  }

  private handleFreeButtonTouch(event: TouchEvent, button: FreeButton): void {
    if (!this.interactive) return;
    event.stopPropagation();
    for (let index = 0; index < event.changedTouches.length; index++) {
      const touch = event.changedTouches[index];
      const source = 'vintage-free-' + button.id + '-' + touch.id;
      if (event.type === TouchType.Down && !this.activeFreeTouches.has(button.id)) {
        this.activeFreeTouches.set(button.id, touch.id);
        this.setFreePressed(button, true);
        InputDispatcher.getInstance().pressKey(source, button.evdevCode);
      } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && this.activeFreeTouches.get(button.id) === touch.id) {
        this.activeFreeTouches.delete(button.id);
        this.setFreePressed(button, false);
        InputDispatcher.getInstance().releaseKey(source, button.evdevCode);
        InputDispatcher.getInstance().releaseSource(source);
      }
    }
  }

  private setDirection(key: VirtualKey, name: DirectionName, fallback: number, pressed: boolean, touchId: number, section: string): void {
    const previous = name === 'up' ? this.dpadUp : name === 'down' ? this.dpadDown : name === 'left' ? this.dpadLeft : this.dpadRight;
    if (previous === pressed) return;
    if (name === 'up') this.dpadUp = pressed;
    if (name === 'down') this.dpadDown = pressed;
    if (name === 'left') this.dpadLeft = pressed;
    if (name === 'right') this.dpadRight = pressed;
    this.setPressed(key, pressed);
    if (pressed) this.pressVirtualKey(key, fallback, touchId, section);
    else this.releaseVirtualKey(key, fallback, touchId, section);
  }

  private applyDirection(up: boolean, down: boolean, left: boolean, right: boolean, touchId: number, section: string): void {
    this.setDirection(VirtualKey.DPAD_UP, 'up', 103, up, touchId, section);
    this.setDirection(VirtualKey.DPAD_DOWN, 'down', 108, down, touchId, section);
    this.setDirection(VirtualKey.DPAD_LEFT, 'left', 105, left, touchId, section);
    this.setDirection(VirtualKey.DPAD_RIGHT, 'right', 106, right, touchId, section);
  }

  private releaseDirections(touchId: number, section: string): void {
    this.applyDirection(false, false, false, false, touchId, section);
  }

  private directionFor(dx: number, dy: number): [boolean, boolean, boolean, boolean] {
    const distance = Math.sqrt(dx * dx + dy * dy);
    if (distance < this.joystickRadius() * this.config().joystickDeadzone / 100) return [false, false, false, false];
    const angle = Math.atan2(dy, dx) * 180 / Math.PI;
    if (!this.config().eightDirectionJoystick) {
      if (angle >= -45 && angle < 45) return [false, false, false, true];
      if (angle >= 45 && angle < 135) return [false, true, false, false];
      if (angle >= 135 || angle < -135) return [false, false, true, false];
      return [true, false, false, false];
    }
    if (angle >= -22.5 && angle < 22.5) return [false, false, false, true];
    if (angle >= 22.5 && angle < 67.5) return [false, true, false, true];
    if (angle >= 67.5 && angle < 112.5) return [false, true, false, false];
    if (angle >= 112.5 && angle < 157.5) return [false, true, true, false];
    if (angle >= 157.5 || angle < -157.5) return [false, false, true, false];
    if (angle >= -157.5 && angle < -112.5) return [true, false, true, false];
    if (angle >= -112.5 && angle < -67.5) return [true, false, false, false];
    return [true, false, false, true];
  }

  private handleJoystickTouch(event: TouchEvent): void {
    if (!this.interactive) return;
    event.stopPropagation();
    if (event.type === TouchType.Down && event.changedTouches.length > 0) {
      const touch = event.changedTouches[0];
      this.joystickTouchId = touch.id;
      this.joystickCenterX = Number(touch.x);
      this.joystickCenterY = Number(touch.y);
      this.joystickActive = true;
      this.joystickX = 0;
      this.joystickY = 0;
      return;
    }
    if (event.type === TouchType.Move && this.joystickTouchId >= 0) {
      for (let index = 0; index < event.touches.length; index++) {
        const touch = event.touches[index];
        if (touch.id !== this.joystickTouchId) continue;
        let dx = Number(touch.x) - this.joystickCenterX;
        let dy = Number(touch.y) - this.joystickCenterY;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance > this.joystickRadius()) {
          dx = dx * this.joystickRadius() / distance;
          dy = dy * this.joystickRadius() / distance;
        }
        this.joystickX = dx;
        this.joystickY = dy;
        const direction = this.directionFor(dx, dy);
        this.applyDirection(direction[0], direction[1], direction[2], direction[3], this.joystickTouchId, 'joystick');
        break;
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      for (let index = 0; index < event.changedTouches.length; index++) {
        if (event.changedTouches[index].id === this.joystickTouchId) {
          this.releaseDirections(this.joystickTouchId, 'joystick');
          this.joystickTouchId = -1;
          this.joystickActive = false;
          this.joystickX = 0;
          this.joystickY = 0;
          break;
        }
      }
    }
  }

  private updateDpad(event: TouchEvent): void {
    for (let index = 0; index < event.touches.length; index++) {
      const touch = event.touches[index];
      if (touch.id !== this.dpadTouchId) continue;
      const center = this.directionSize() / 2;
      const direction = this.directionFor(Number(touch.x) - center, Number(touch.y) - center);
      this.applyDirection(direction[0], direction[1], direction[2], direction[3], this.dpadTouchId, 'dpad');
      break;
    }
  }

  private handleDpadTouch(event: TouchEvent): void {
    if (!this.interactive) return;
    event.stopPropagation();
    if (event.type === TouchType.Down && event.changedTouches.length > 0) {
      this.dpadTouchId = event.changedTouches[0].id;
      this.updateDpad(event);
      return;
    }
    if (event.type === TouchType.Move && this.dpadTouchId >= 0) {
      this.updateDpad(event);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      for (let index = 0; index < event.changedTouches.length; index++) {
        if (event.changedTouches[index].id === this.dpadTouchId) {
          this.releaseDirections(this.dpadTouchId, 'dpad');
          this.dpadTouchId = -1;
          break;
        }
      }
    }
  }

  @Builder
  private GameButton(label: string, key: VirtualKey, fallback: number, accent: string = this.strokeColor(), small: boolean = false) {
    Stack({ alignContent: Alignment.Center }) {
      Circle().width((small ? 35 : 50) * this.config().buttonSize / 100).height((small ? 35 : 50) * this.config().buttonSize / 100)
        .fill(this.isPressed(key) ? accent : this.fillColor(false)).stroke(accent).strokeWidth(small ? 1.5 : 2)
        .opacity(this.visibleOpacity(this.config().transparency)).shadow({ radius: this.isPressed(key) ? 2 : 4, color: '#66000000' })
      Text(label).fontSize((small ? 10 : 16) * this.config().buttonSize / 100).fontWeight(FontWeight.Bold)
        .fontColor(this.textColor(this.isPressed(key), accent))
    }
    .width((small ? 35 : 50) * this.config().buttonSize / 100).height((small ? 35 : 50) * this.config().buttonSize / 100)
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => this.handleButtonTouch(event, key, fallback))
  }

  @Builder
  private Dpad() {
    Stack() {
      // Keep the VintagePomelo circular base, but add a contrasting halo so
      // the blue outline does not disappear on Wine's blue desktop.
      Circle().width(this.directionSize()).height(this.directionSize()).fill('#16000000')
        .stroke(this.outlineBackdropColor()).strokeWidth(4)
        .opacity(this.visibleOpacity(this.config().joystickTransparency))
        .shadow({ radius: 5, color: '#88000000' })
      Circle().width(this.directionSize() - 4).height(this.directionSize() - 4).fill('#00000000')
        .stroke(this.strokeColor()).strokeWidth(2)
        .opacity(this.visibleOpacity(this.config().joystickTransparency))
      Rect().width(this.joystickRadius() * 0.6).height(this.joystickRadius() * 0.9).fill(this.fillColor(this.dpadUp)).borderRadius({ topLeft: this.joystickRadius() * 0.3, topRight: this.joystickRadius() * 0.3 })
        .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.dpadUp ? 1 : 0.5)).position({ x: this.directionSize() / 2 - this.joystickRadius() * 0.3, y: 10 })
      Rect().width(this.joystickRadius() * 0.6).height(this.joystickRadius() * 0.9).fill(this.fillColor(this.dpadDown)).borderRadius({ bottomLeft: this.joystickRadius() * 0.3, bottomRight: this.joystickRadius() * 0.3 })
        .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.dpadDown ? 1 : 0.5)).position({ x: this.directionSize() / 2 - this.joystickRadius() * 0.3, y: this.directionSize() - this.joystickRadius() * 0.9 - 10 })
      Rect().width(this.joystickRadius() * 0.9).height(this.joystickRadius() * 0.6).fill(this.fillColor(this.dpadLeft)).borderRadius({ topLeft: this.joystickRadius() * 0.3, bottomLeft: this.joystickRadius() * 0.3 })
        .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.dpadLeft ? 1 : 0.5)).position({ x: 10, y: this.directionSize() / 2 - this.joystickRadius() * 0.3 })
      Rect().width(this.joystickRadius() * 0.9).height(this.joystickRadius() * 0.6).fill(this.fillColor(this.dpadRight)).borderRadius({ topRight: this.joystickRadius() * 0.3, bottomRight: this.joystickRadius() * 0.3 })
        .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.dpadRight ? 1 : 0.5)).position({ x: this.directionSize() - this.joystickRadius() * 0.9 - 10, y: this.directionSize() / 2 - this.joystickRadius() * 0.3 })
      Circle().width(this.joystickRadius() * 0.4).height(this.joystickRadius() * 0.4).fill(this.fillColor(false)).opacity(this.visibleOpacity(this.config().joystickTransparency) * 0.7)
    }
    .width(this.directionSize()).height(this.directionSize()).hitTestBehavior(HitTestMode.Block).id('wine-vintage-direction-dpad')
    .onTouch((event: TouchEvent): void => this.handleDpadTouch(event))
  }

  @Builder
  private Joystick() {
    Stack() {
      Circle().width(this.directionSize()).height(this.directionSize()).fill('#16000000')
        .stroke(this.outlineBackdropColor()).strokeWidth(4)
        .opacity(this.visibleOpacity(this.config().joystickTransparency))
        .shadow({ radius: 5, color: '#88000000' })
      Circle().width(this.directionSize() - 4).height(this.directionSize() - 4).fill('#00000000')
        .stroke(this.strokeColor()).strokeWidth(2)
        .opacity(this.visibleOpacity(this.config().joystickTransparency))
      ForEach([0, 45, 90, 135, 180, 225, 270, 315], (angle: number): void => {
        Line().width(10).height(2).backgroundColor(this.strokeColor()).opacity(this.visibleOpacity(this.config().joystickTransparency) * 0.5)
          .rotate({ angle: angle }).position({ x: this.joystickRadius() + 10 + Math.cos(angle * Math.PI / 180) * (this.joystickRadius() - 5) - 5, y: this.joystickRadius() + 10 + Math.sin(angle * Math.PI / 180) * (this.joystickRadius() - 5) - 1 })
      }, (angle: number): string => angle.toString())
      Circle().width(50 * this.config().joystickSize / 100).height(50 * this.config().joystickSize / 100)
        .fill(this.fillColor(this.joystickActive)).stroke(this.strokeColor()).strokeWidth(2)
        .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.joystickActive ? 1 : 0.7)).translate({ x: this.joystickX, y: this.joystickY })
    }
    .width(this.directionSize()).height(this.directionSize()).hitTestBehavior(HitTestMode.Block).id('wine-vintage-direction-joystick')
    .onTouch((event: TouchEvent): void => this.handleJoystickTouch(event))
  }

  @Builder
  private DirectionGroup() {
    Column() {
      if (this.config().dpadMode === DirectionControlMode.DPAD) this.Dpad()
      else this.Joystick()
    }
    .width(this.directionSize()).height(this.directionSize())
    .hitTestBehavior(HitTestMode.Block)
    .position(this.groupPosition(this.layout().direction.centerX, this.layout().direction.centerY, this.directionSize(), this.directionSize()))
  }

  @Builder
  private ActionGroup() {
    Stack() {
      Column() {
        if (this.config().showButtonShift || this.config().showButtonCtrl) {
          Row({ space: 16 * this.config().buttonSize / 100 }) {
            if (this.config().showButtonShift) this.GameButton('LT', VirtualKey.BUTTON_SHIFT, 42, '#FFFFB74D', true)
            if (this.config().showButtonCtrl) this.GameButton('RT', VirtualKey.BUTTON_CTRL, 29, '#FF64B5F6', true)
          }.margin({ bottom: 6 }).hitTestBehavior(HitTestMode.Block)
        }
        if (this.config().showButtonL || this.config().showButtonR) {
          Row({ space: 16 * this.config().buttonSize / 100 }) {
            if (this.config().showButtonL) this.GameButton('LB', VirtualKey.BUTTON_L, 16, this.strokeColor(), true)
            if (this.config().showButtonR) this.GameButton('RB', VirtualKey.BUTTON_R, 17, this.strokeColor(), true)
          }.margin({ bottom: 8 }).hitTestBehavior(HitTestMode.Block)
        }
        Stack() {
          if (this.config().showButtonY) {
            Stack() { this.GameButton('Y', VirtualKey.BUTTON_Y, 31, this.strokeColor()) }
              .width(50 * this.config().buttonSize / 100).height(50 * this.config().buttonSize / 100).position({ x: 45 * this.config().buttonSize / 100, y: 0 })
          }
          if (this.config().showButtonX) {
            Stack() { this.GameButton('X', VirtualKey.BUTTON_X, 30, this.strokeColor()) }
              .width(50 * this.config().buttonSize / 100).height(50 * this.config().buttonSize / 100).position({ x: 0, y: 45 * this.config().buttonSize / 100 })
          }
          if (this.config().showButtonA) {
            Stack() { this.GameButton('A', VirtualKey.BUTTON_A, 57, '#FF81C784') }
              .width(50 * this.config().buttonSize / 100).height(50 * this.config().buttonSize / 100).position({ x: 90 * this.config().buttonSize / 100, y: 45 * this.config().buttonSize / 100 })
          }
          if (this.config().showButtonB) {
            Stack() { this.GameButton('B', VirtualKey.BUTTON_B, 45, '#FFFF5252') }
              .width(50 * this.config().buttonSize / 100).height(50 * this.config().buttonSize / 100).position({ x: 45 * this.config().buttonSize / 100, y: 90 * this.config().buttonSize / 100 })
          }
        }.width(140 * this.config().buttonSize / 100).height(140 * this.config().buttonSize / 100).hitTestBehavior(HitTestMode.Block)
      }
      .width(this.actionWidth()).height(this.actionHeight()).hitTestBehavior(HitTestMode.None)

      Column()
        .width(this.actionWidth()).height(this.actionHeight())
        .backgroundColor('#00000000')
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent): void => this.handleActionGroupTouch(event))
        .onMouse((event: MouseEvent): void => this.handleActionGroupMouse(event))
    }
    .width(this.actionWidth()).height(this.actionHeight()).hitTestBehavior(HitTestMode.Transparent)
    .id('wine-vintage-action')
    .position(this.groupPosition(this.layout().action.centerX, this.layout().action.centerY, this.actionWidth(), this.actionHeight()))
  }

  @Builder
  private AuxGroup() {
    if (this.auxWidth() > 0) {
      Row() {
        if (this.config().showButtonMenu) this.GameButton('菜单', VirtualKey.BUTTON_MENU, 1, this.strokeColor(), true)
      }
      .width(this.auxWidth()).height(35 * this.config().buttonSize / 100).hitTestBehavior(HitTestMode.Block)
      .id('wine-vintage-aux')
      .position(this.groupPosition(this.layout().aux.centerX, this.layout().aux.centerY, this.auxWidth(), 35 * this.config().buttonSize / 100))
    }
  }

  /** VintagePomelo's optional free-button mode, rendered in place of fixed controls. */
  @Builder
  private FreeButtonGroup() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.profile.freeButtonsConfig.buttons, (button: FreeButton, index: number): void => {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(this.freeButtonSize()).height(this.freeButtonSize())
            .fill(this.isFreePressed(button) ? '#FF2979FF' : '#8032323A')
            .stroke(this.strokeColor()).strokeWidth(2)
            .opacity(this.visibleOpacity(this.config().transparency))
          Text(button.keyLabel).fontSize(12 * this.config().buttonSize / 100).fontWeight(FontWeight.Bold)
            .fontColor(this.isFreePressed(button) ? '#FFFFFFFF' : '#FFE7F2FF').maxLines(1)
        }
        .width(this.freeButtonSize()).height(this.freeButtonSize())
        .position({ x: this.freePositionX(index), y: this.freePositionY(index) })
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent): void => this.handleFreeButtonTouch(event, button))
      }, (button: FreeButton): string => button.id)
    }
    .width(this.freeGroupSize()).height(this.freeGroupSize()).hitTestBehavior(HitTestMode.Block)
    .id('wine-vintage-free-buttons')
    .position(this.groupPosition(this.layout().action.centerX, this.layout().action.centerY, this.freeGroupSize(), this.freeGroupSize()))
  }

  @Builder
  private ControlBarButton(icon: Resource, id: string, action: () => void, highlighted: boolean = false) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon).fontSize(16).fontColor(['#FFFFFFFF'])
    }
    .width(36).height(36)
    .backgroundColor(highlighted ? '#44FFFFFF' : '#BF282828')
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 2 })
    .id(id)
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => event.stopPropagation())
    .onMouse((event: MouseEvent): void => event.stopPropagation())
    .onClick(action)
  }

  /** Direct ArkTS adaptation of VintagePomelo's collapsible icon control bar. */
  @Builder
  private Toolbar() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.controlsExpanded ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
          .fontSize(14).fontColor(['#FFFFFFFF'])
      }
      .width(28).height(28)
      .backgroundColor(this.controlsExpanded ? '#1AFFFFFF' : '#BF282828')
      .border({ width: 1, color: '#33FFFFFF' })
      .id('wine-input-overlay-toggle')
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent): void => event.stopPropagation())
      .onMouse((event: MouseEvent): void => event.stopPropagation())
      .onClick((): void => { this.controlsExpanded = !this.controlsExpanded; })

      if (this.controlsExpanded) {
        this.ControlBarButton($r('sys.symbol.gearshape'), 'wine-input-layout-editor', (): void => {
          this.onOpenLayoutEditor();
        })
        this.ControlBarButton($r('sys.symbol.gamecontroller'), 'wine-input-overlay-fold', (): void => {
          this.controlsExpanded = false;
        }, true)
      }
    }
    .padding(this.controlsExpanded ? 8 : 4)
    .backgroundColor('#4D000000')
    .borderRadius(20)
    .hitTestBehavior(HitTestMode.Block)
    .position({ x: Math.max(4, this.overlayW - (this.controlsExpanded ? 150 : 54)), y: 14 })
  }

  build() {
    Stack() {
      if (this.overlayW > 0 && this.overlayH > 0 && this.controlsExpanded) {
        if (this.profile.freeButtonsConfig.enabled && this.profile.freeButtonsConfig.buttons.length > 0) {
          this.FreeButtonGroup()
        } else {
          this.DirectionGroup()
          this.ActionGroup()
          this.AuxGroup()
        }
      }
      if (!this.hideToolbar) this.Toolbar()
    }
    .width('100%').height('100%').hitTestBehavior(HitTestMode.Block).id('wine-vintage-gamepad-overlay')
    .onTouch((event: TouchEvent): void => this.handleOverlayTouch(event))
    .onMouse((event: MouseEvent): void => this.onUnhandledMouse(event))
    .onAxisEvent((event?: AxisEvent): void => this.onUnhandledAxis(event))
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.overlayW = area.width as number;
      this.overlayH = area.height as number;
    })
  }
}
