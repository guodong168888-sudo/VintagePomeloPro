import {
  ButtonGroupPosition,
  ControlBarDirection,
  DirectionControlMode,
  FreeButton,
  FreeButtonLayoutMode,
  GamepadButtonMapping,
  InputProfile,
  RightJoystickOutputMode,
  VirtualKey,
  VirtualKeyColorScheme,
  VirtualKeyMapping,
  cloneFreeButtonsConfig,
  cloneGamepadLayout,
  cloneVirtualKeyConfig,
  computeGamepadPositions,
  computeRadialPositions,
  createDefaultInputProfile,
  resolveVirtualJoystickDirection,
  resolveVirtualKeyMapping
} from '../model/AppModels';
import { InputDispatcher } from '../service/InputDispatcher';

type DirectionName = 'up' | 'down' | 'left' | 'right';
type ToolbarAction = 'toolbar' | 'editor' | 'mapping' | 'controls' | 'mouse' | 'wake';

interface OverlayPoint {
  x: number;
  y: number;
}

function cloneInputProfile(profile: InputProfile): InputProfile {
  return {
    id: profile.id,
    name: profile.name,
    schemaVersion: profile.schemaVersion,
    virtualKeyConfig: cloneVirtualKeyConfig(profile.virtualKeyConfig),
    layoutLandscape: cloneGamepadLayout(profile.layoutLandscape),
    layoutPortrait: cloneGamepadLayout(profile.layoutPortrait),
    virtualKeyMappings: profile.virtualKeyMappings.map((item: VirtualKeyMapping): VirtualKeyMapping => ({
      virtualKey: item.virtualKey,
      evdevCode: item.evdevCode,
      keyLabel: item.keyLabel
    })),
    gamepadMappings: profile.gamepadMappings.map((item: GamepadButtonMapping): GamepadButtonMapping => ({
      id: item.id,
      label: item.label,
      buttonCode: item.buttonCode,
      evdevCode: item.evdevCode
    })),
    freeButtonsConfig: cloneFreeButtonsConfig(profile.freeButtonsConfig)
  };
}

/**
 * Wine adapter of VintagePomelo's VirtualGamepad overlay.  Its layout contract
 * is intentionally group based: direction, camera, action and auxiliary.
 * Individual button coordinates are not supported. The left d-pad/joystick
 * remains mutually exclusive while the right camera joystick is independent.
 */
@Component
export struct VirtualInputOverlay {
  @Prop @Watch('onProfileChanged') profile: InputProfile = createDefaultInputProfile();
  /** Forces editor previews to rebuild when a group is dragged in-place. */
  @Prop @Watch('onRenderRevisionChanged') renderRevision: number = 0;
  @Prop opacityValue: number = 100;
  @Prop interactive: boolean = true;
  @Prop hideToolbar: boolean = false;
  @Prop @Watch('onControlsVisibleChanged') controlsVisible: boolean = true;
  @Prop @Watch('onControlBarDirectionChanged') controlBarDirection: ControlBarDirection = ControlBarDirection.AUTO;
  @Prop @Watch('onTouchpadModeChanged') touchpadMode: boolean = false;
  onOpenLayoutEditor: () => void = (): void => {};
  onOpenKeyMappingEditor: () => void = (): void => {};
  onControlsVisibleChange: (visible: boolean) => void = (_visible: boolean): void => {};
  onTouchpadModeChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onUnhandledTouch: (event: TouchEvent) => void = (_event: TouchEvent): void => {};
  onUnhandledMouse: (event: MouseEvent) => void = (_event: MouseEvent): void => {};
  onUnhandledAxis: (event?: AxisEvent) => void = (_event?: AxisEvent): void => {};

  @State private overlayW: number = 0;
  @State private overlayH: number = 0;
  @State private pressedKeys: string = '';
  @State private joystickActive: boolean = false;
  @State private joystickX: number = 0;
  @State private joystickY: number = 0;
  @State private rightJoystickActive: boolean = false;
  @State private rightJoystickX: number = 0;
  @State private rightJoystickY: number = 0;
  @State private rightStickUp: boolean = false;
  @State private rightStickDown: boolean = false;
  @State private rightStickLeft: boolean = false;
  @State private rightStickRight: boolean = false;
  @State private dpadUp: boolean = false;
  @State private dpadDown: boolean = false;
  @State private dpadLeft: boolean = false;
  @State private dpadRight: boolean = false;
  @State private pressedFreeButtons: string = '';
  // Toolbar folding and virtual-control visibility are deliberately separate:
  // the chevron changes only this local state, while controlsVisible is owned
  // by the coordinator and never disables the full-screen mouse surface.
  @State private toolbarExpanded: boolean = true;
  @State private toolbarAutoHidden: boolean = false;
  @State private controlsVisibleVisual: boolean = true;
  @State private touchpadModeVisual: boolean = false;
  @State private renderedProfile: InputProfile = createDefaultInputProfile();
  private activeButtonTouches: Map<VirtualKey, number> = new Map<VirtualKey, number>();
  private joystickTouchId: number = -1;
  private joystickCenterX: number = 0;
  private joystickCenterY: number = 0;
  private rightJoystickTouchId: number = -1;
  private rightJoystickCenterX: number = 0;
  private rightJoystickCenterY: number = 0;
  private rightJoystickLastX: number = 0;
  private rightJoystickLastY: number = 0;
  private dpadTouchId: number = -1;
  private activeFreeTouches: Map<string, number> = new Map<string, number>();
  private activeActionMouseKey: VirtualKey | null = null;
  private activeActionMouseFallback: number = 0;
  private lastActionTouchAt: number = 0;
  private toolbarTouchId: number = -1;
  private toolbarTouchAction: ToolbarAction | null = null;
  private toolbarMouseAction: ToolbarAction | null = null;
  private lastToolbarTouchAt: number = 0;
  private lastToolbarButtonTouchAt: number = 0;
  private toolbarAutoHideTimer: number = -1;

  private config() {
    return this.renderedProfile.virtualKeyConfig;
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

  private rightJoystickRadius(): number {
    return 55 * this.config().rightJoystickSize / 100;
  }

  private rightJoystickSize(): number {
    return this.rightJoystickRadius() * 2;
  }

  private rightJoystickKnobSize(): number {
    return 44 * this.config().rightJoystickSize / 100;
  }

  private rightJoystickMaxOffset(): number {
    return Math.max(0, this.rightJoystickRadius() - this.rightJoystickKnobSize() / 2);
  }

  private actionWidth(): number {
    return 140 * this.config().buttonSize / 100;
  }

  private actionHeight(): number {
    return 140 * this.config().buttonSize / 100;
  }

  private shoulderWidth(): number {
    return 56 * this.config().buttonSize / 100;
  }

  private shoulderHeight(): number {
    return 40 * this.config().buttonSize / 100;
  }

  private shoulderHitWidth(): number {
    return Math.max(48, this.shoulderWidth());
  }

  private shoulderHitHeight(): number {
    return Math.max(48, this.shoulderHeight());
  }

  private auxWidth(): number {
    return this.config().showButtonMenu ? Math.max(48, 35 * this.config().buttonSize / 100) : 0;
  }

  private auxHeight(): number {
    return Math.max(48, 35 * this.config().buttonSize / 100);
  }

  private groupPosition(centerX: number, centerY: number, groupW: number, groupH: number): OverlayPoint {
    return { x: this.overlayW * centerX - groupW / 2, y: this.overlayH * centerY - groupH / 2 };
  }

  private layout() {
    return this.overlayH > this.overlayW ? this.renderedProfile.layoutPortrait : this.renderedProfile.layoutLandscape;
  }

  private mapping(key: VirtualKey, fallback: number): number {
    return resolveVirtualKeyMapping(this.renderedProfile.virtualKeyMappings, key, fallback);
  }

  private freeButtonSize(): number {
    return 50 * this.config().buttonSize / 100;
  }

  private freeButtonPositions() {
    const free = this.renderedProfile.freeButtonsConfig;
    return free.layoutMode === FreeButtonLayoutMode.RADIAL ?
      computeRadialPositions(free.buttons.length, free.radialScale * 0.6) :
      computeGamepadPositions(free.buttons.length, free.gamepadSpacing);
  }

  private freeGroupSize(): number {
    return Math.max(240, this.renderedProfile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.RADIAL ? this.renderedProfile.freeButtonsConfig.radialScale * 1.5 : 280);
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

  private resolveToolbarVertical(): boolean {
    if (this.controlBarDirection === ControlBarDirection.VERTICAL) return true;
    if (this.controlBarDirection === ControlBarDirection.HORIZONTAL) return false;
    // VintagePomelo AUTO / AUTO_HIDE contract: portrait uses a vertical bar.
    return this.overlayH > this.overlayW;
  }

  private isAutoHideMode(): boolean {
    return this.controlBarDirection === ControlBarDirection.AUTO_HIDE;
  }

  private cancelToolbarAutoHide(): void {
    if (this.toolbarAutoHideTimer >= 0) {
      clearTimeout(this.toolbarAutoHideTimer);
      this.toolbarAutoHideTimer = -1;
    }
  }

  private startToolbarAutoHide(): void {
    this.cancelToolbarAutoHide();
    if (!this.isAutoHideMode() || this.toolbarExpanded) return;
    this.toolbarAutoHideTimer = setTimeout((): void => {
      this.toolbarAutoHideTimer = -1;
      if (this.isAutoHideMode() && !this.toolbarExpanded) this.toolbarAutoHidden = true;
    }, 3000) as number;
  }

  private onControlBarDirectionChanged(): void {
    this.toolbarAutoHidden = false;
    if (this.toolbarExpanded) this.cancelToolbarAutoHide();
    else this.startToolbarAutoHide();
  }

  private onTouchpadModeChanged(): void {
    this.touchpadModeVisual = this.touchpadMode;
  }

  private onProfileChanged(): void {
    this.renderedProfile = cloneInputProfile(this.profile);
  }

  private onRenderRevisionChanged(): void {
    // Editor drag updates replace the profile and increment this primitive in
    // the same render pass. Copying here prevents ArkUI from retaining a stale
    // nested layout object in the long-lived overlay component.
    this.renderedProfile = cloneInputProfile(this.profile);
  }

  private onControlsVisibleChanged(): void {
    this.controlsVisibleVisual = this.controlsVisible;
    if (this.controlsVisible) return;
    this.releaseRightJoystickInteraction();
    this.activeButtonTouches.clear();
    this.activeFreeTouches.clear();
    this.joystickTouchId = -1;
    this.dpadTouchId = -1;
    this.pressedKeys = '';
    this.pressedFreeButtons = '';
    this.joystickActive = false;
    this.joystickX = 0;
    this.joystickY = 0;
    this.dpadUp = false;
    this.dpadDown = false;
    this.dpadLeft = false;
    this.dpadRight = false;
  }

  aboutToAppear(): void {
    this.renderedProfile = cloneInputProfile(this.profile);
    this.controlsVisibleVisual = this.controlsVisible;
    this.touchpadModeVisual = this.touchpadMode;
  }

  aboutToDisappear(): void {
    this.cancelToolbarAutoHide();
    this.releaseRightJoystickInteraction();
  }

  private toolbarOriginX(): number {
    if (this.resolveToolbarVertical()) return Math.max(4, this.overlayW - 54);
    return Math.max(4, this.overlayW - (this.toolbarExpanded ? 230 : 54));
  }

  private toolbarActionAt(x: number, y: number): ToolbarAction | null {
    const originX = this.toolbarOriginX();
    if (this.toolbarAutoHidden && this.isAutoHideMode()) {
      return this.rectContains(x, y, Math.max(0, this.overlayW - 52), 8, 48, 48) ? 'wake' : null;
    }
    if (!this.toolbarExpanded) {
      return this.rectContains(x, y, originX, 14, 44, 44) ? 'toolbar' : null;
    }
    if (this.resolveToolbarVertical()) {
      if (this.rectContains(x, y, originX, 14, 44, 40)) return 'toolbar';
      if (this.rectContains(x, y, originX, 54, 44, 44)) return 'editor';
      if (this.rectContains(x, y, originX, 98, 44, 44)) return 'mapping';
      if (this.rectContains(x, y, originX, 142, 44, 44)) return 'controls';
      if (this.rectContains(x, y, originX, 186, 44, 44)) return 'mouse';
      return null;
    }
    if (this.rectContains(x, y, originX + 4, 14, 40, 48)) return 'toolbar';
    if (this.rectContains(x, y, originX + 44, 14, 44, 52)) return 'editor';
    if (this.rectContains(x, y, originX + 88, 14, 44, 52)) return 'mapping';
    if (this.rectContains(x, y, originX + 132, 14, 44, 52)) return 'controls';
    if (this.rectContains(x, y, originX + 176, 14, 44, 52)) return 'mouse';
    return null;
  }

  private runToolbarAction(action: ToolbarAction): void {
    if (action === 'editor') {
      this.onOpenLayoutEditor();
      return;
    }
    if (action === 'mapping') {
      this.onOpenKeyMappingEditor();
      return;
    }
    if (action === 'controls') {
      const nextVisible = !this.controlsVisibleVisual;
      this.controlsVisibleVisual = nextVisible;
      this.onControlsVisibleChange(nextVisible);
      return;
    }
    if (action === 'mouse') {
      const nextTouchpadMode = !this.touchpadModeVisual;
      this.touchpadModeVisual = nextTouchpadMode;
      this.onTouchpadModeChange(nextTouchpadMode);
      return;
    }
    if (action === 'wake') {
      this.toolbarAutoHidden = false;
      this.startToolbarAutoHide();
      return;
    }
    this.toolbarExpanded = !this.toolbarExpanded;
    this.toolbarAutoHidden = false;
    if (this.toolbarExpanded) this.cancelToolbarAutoHide();
    else this.startToolbarAutoHide();
  }

  private handleToolbarButtonTouch(event: TouchEvent, action: () => void): void {
    event.stopPropagation();
    if (event.type !== TouchType.Up) return;
    this.invokeToolbarButtonAction(action);
  }

  private handleToolbarButtonMouse(event: MouseEvent, action: () => void): void {
    event.stopPropagation();
    if (event.action === MouseAction.Release) this.invokeToolbarButtonAction(action);
  }

  private invokeToolbarButtonAction(action: () => void): void {
    const now = Date.now();
    if (now - this.lastToolbarButtonTouchAt < 250) return;
    this.lastToolbarButtonTouchAt = now;
    action();
  }

  private handleToolbarOverlayTouch(event: TouchEvent): boolean {
    const touch = event.changedTouches[0];
    if (!touch) return false;
    if (this.toolbarTouchId === touch.id) {
      event.stopPropagation();
      this.lastToolbarTouchAt = Date.now();
      if (event.type === TouchType.Up && this.toolbarTouchAction) this.runToolbarAction(this.toolbarTouchAction);
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.toolbarTouchId = -1;
        this.toolbarTouchAction = null;
      }
      return true;
    }
    if (event.type !== TouchType.Down) return false;
    const action = this.toolbarActionAt(Number(touch.x), Number(touch.y));
    if (!action) return false;
    this.toolbarTouchId = touch.id;
    this.toolbarTouchAction = action;
    this.lastToolbarTouchAt = Date.now();
    event.stopPropagation();
    return true;
  }

  private handleToolbarOverlayMouse(event: MouseEvent): boolean {
    const action = this.toolbarActionAt(Number(event.x), Number(event.y));
    if (event.action === MouseAction.Press && action) {
      this.toolbarMouseAction = action;
      event.stopPropagation();
      return true;
    }
    if (event.action === MouseAction.Release && this.toolbarMouseAction) {
      const active = this.toolbarMouseAction;
      this.toolbarMouseAction = null;
      event.stopPropagation();
      if (Date.now() - this.lastToolbarTouchAt > 350) this.runToolbarAction(active);
      return true;
    }
    if (action) {
      event.stopPropagation();
      return true;
    }
    return false;
  }

  private actionOrigin(): OverlayPoint {
    return this.groupPosition(this.layout().action.centerX, this.layout().action.centerY,
      this.actionWidth(), this.actionHeight());
  }

  private actionButtonAtLocal(localX: number, localY: number): [VirtualKey, number] | null {
    const scale = this.config().buttonSize / 100;
    const big = 50 * scale;
    if (this.config().showButtonY && this.rectContains(localX, localY, 45 * scale, 0, big, big)) {
      return [VirtualKey.BUTTON_Y, 31];
    }
    if (this.config().showButtonX && this.rectContains(localX, localY, 0, 45 * scale, big, big)) {
      return [VirtualKey.BUTTON_X, 30];
    }
    if (this.config().showButtonA && this.rectContains(localX, localY, 90 * scale, 45 * scale, big, big)) {
      return [VirtualKey.BUTTON_A, 57];
    }
    if (this.config().showButtonB && this.rectContains(localX, localY, 45 * scale, 90 * scale, big, big)) {
      return [VirtualKey.BUTTON_B, 45];
    }
    return null;
  }

  private shoulderTargetAt(x: number, y: number): [VirtualKey, number] | null {
    const layout = this.layout();
    const targets: Array<[boolean, ButtonGroupPosition, VirtualKey, number]> = [
      [this.config().showButtonShift, layout.leftTrigger, VirtualKey.BUTTON_SHIFT, 42],
      [this.config().showButtonL, layout.leftBumper, VirtualKey.BUTTON_L, 16],
      [this.config().showButtonR, layout.rightBumper, VirtualKey.BUTTON_R, 17],
      [this.config().showButtonCtrl, layout.rightTrigger, VirtualKey.BUTTON_CTRL, 29]
    ];
    for (const target of targets) {
      if (!target[0]) continue;
      const origin = this.groupPosition(target[1].centerX, target[1].centerY,
        this.shoulderHitWidth(), this.shoulderHitHeight());
      if (this.rectContains(x, y, origin.x, origin.y, this.shoulderHitWidth(), this.shoulderHitHeight())) {
        return [target[2], target[3]];
      }
    }
    return null;
  }

  private buttonTargetAt(x: number, y: number): [VirtualKey, number] | null {
    const shoulder = this.shoulderTargetAt(x, y);
    if (shoulder) return shoulder;
    const origin = this.actionOrigin();
    const action = this.actionButtonAtLocal(x - origin.x, y - origin.y);
    if (action) return action;
    if (this.config().showButtonMenu && this.auxWidth() > 0) {
      const aux = this.groupPosition(this.layout().aux.centerX, this.layout().aux.centerY,
        this.auxWidth(), this.auxHeight());
      if (this.rectContains(x, y, aux.x, aux.y, this.auxWidth(), this.auxHeight())) {
        return [VirtualKey.BUTTON_MENU, 1];
      }
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
      case VirtualKey.RIGHT_STICK_UP: return 23;
      case VirtualKey.RIGHT_STICK_DOWN: return 37;
      case VirtualKey.RIGHT_STICK_LEFT: return 36;
      case VirtualKey.RIGHT_STICK_RIGHT: return 38;
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
    for (const button of this.renderedProfile.freeButtonsConfig.buttons) {
      if (this.activeFreeTouches.get(button.id) === touch.id) {
        this.handleFreeButtonTouch(event, button);
        return true;
      }
    }
    for (const button of this.renderedProfile.freeButtonsConfig.buttons) {
      const index = this.renderedProfile.freeButtonsConfig.buttons.indexOf(button);
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
    if (!this.hideToolbar && this.handleToolbarOverlayTouch(event)) return;
    if (!this.interactive || !this.controlsVisible) {
      this.onUnhandledTouch(event);
      return;
    }
    const touch = event.changedTouches[0];
    const x = Number(touch.x);
    const y = Number(touch.y);
    const direction = this.groupPosition(this.layout().direction.centerX, this.layout().direction.centerY,
      this.directionSize(), this.directionSize());
    let claimed = false;
    if (this.dpadTouchId === touch.id) {
      this.handleDpadTouch(event);
      claimed = true;
    } else if (this.joystickTouchId === touch.id) {
      this.handleJoystickTouch(event);
      claimed = true;
    } else if (this.rightJoystickTouchId === touch.id) {
      this.handleRightJoystickTouch(event);
      claimed = true;
    } else if (this.activeButtonForTouch(touch.id)) {
      this.lastActionTouchAt = Date.now();
      const active = this.activeButtonForTouch(touch.id);
      if (active) this.handleButtonTouch(event, active[0], active[1]);
      claimed = true;
    } else if (this.renderedProfile.freeButtonsConfig.enabled && this.renderedProfile.freeButtonsConfig.buttons.length > 0) {
      claimed = this.handleFreeOverlayTouch(event, x, y);
    } else if (this.rectContains(x, y, direction.x, direction.y, this.directionSize(), this.directionSize())) {
      if (this.config().dpadMode === DirectionControlMode.DPAD) this.handleDpadTouch(event);
      else this.handleJoystickTouch(event);
      claimed = true;
    } else {
      const target = event.type === TouchType.Down ? this.buttonTargetAt(x, y) : null;
      if (target) {
        this.lastActionTouchAt = Date.now();
        this.handleButtonTouch(event, target[0], target[1]);
        claimed = true;
      } else if (event.type === TouchType.Down && this.isRightJoystickHit(x, y)) {
        this.handleRightJoystickTouch(event);
        claimed = true;
      }
    }
    if (claimed) event.stopPropagation();
    else this.onUnhandledTouch(event);
  }

  private handleOverlayMouse(event: MouseEvent): void {
    if (!this.hideToolbar && this.handleToolbarOverlayMouse(event)) return;
    if (!this.interactive || !this.controlsVisible ||
      this.renderedProfile.freeButtonsConfig.enabled || Date.now() - this.lastActionTouchAt <= 320) {
      this.onUnhandledMouse(event);
      return;
    }
    const x = Number(event.x);
    const y = Number(event.y);
    if (event.action === MouseAction.Press) {
      const target = this.buttonTargetAt(x, y);
      if (!target) {
        this.onUnhandledMouse(event);
        return;
      }
      event.stopPropagation();
      this.activeActionMouseKey = target[0];
      this.activeActionMouseFallback = target[1];
      this.setPressed(target[0], true);
      this.pressVirtualKey(target[0], target[1], -100, 'overlay-mouse');
      return;
    }
    if (event.action === MouseAction.Release && this.activeActionMouseKey !== null) {
      event.stopPropagation();
      const key = this.activeActionMouseKey;
      const fallback = this.activeActionMouseFallback;
      this.activeActionMouseKey = null;
      this.activeActionMouseFallback = 0;
      this.setPressed(key, false);
      this.releaseVirtualKey(key, fallback, -100, 'overlay-mouse');
      return;
    }
    this.onUnhandledMouse(event);
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
    const direction = resolveVirtualJoystickDirection(dx, dy, this.joystickRadius(),
      this.config().joystickDeadzone, this.config().eightDirectionJoystick);
    return [direction.up, direction.down, direction.left, direction.right];
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

  private rightJoystickSource(touchId: number): string {
    return 'right-joystick-' + touchId;
  }

  private isRightJoystickHit(x: number, y: number): boolean {
    if (!this.config().showRightJoystick) return false;
    const centerX = this.overlayW * this.layout().camera.centerX;
    const centerY = this.overlayH * this.layout().camera.centerY;
    const radius = this.rightJoystickRadius() + 12;
    const dx = x - centerX;
    const dy = y - centerY;
    return dx * dx + dy * dy <= radius * radius;
  }

  private releaseRightJoystickInteraction(): void {
    if (this.rightJoystickTouchId >= 0) {
      this.releaseRightDirections(this.rightJoystickTouchId);
      InputDispatcher.getInstance().releaseSource(this.rightJoystickSource(this.rightJoystickTouchId));
    }
    this.rightJoystickTouchId = -1;
    this.rightJoystickActive = false;
    this.rightJoystickX = 0;
    this.rightJoystickY = 0;
    this.rightStickUp = false;
    this.rightStickDown = false;
    this.rightStickLeft = false;
    this.rightStickRight = false;
  }

  private setRightDirection(key: VirtualKey, name: DirectionName, fallback: number,
    pressed: boolean, touchId: number): void {
    const previous = name === 'up' ? this.rightStickUp : name === 'down' ? this.rightStickDown :
      name === 'left' ? this.rightStickLeft : this.rightStickRight;
    if (previous === pressed) return;
    if (name === 'up') this.rightStickUp = pressed;
    if (name === 'down') this.rightStickDown = pressed;
    if (name === 'left') this.rightStickLeft = pressed;
    if (name === 'right') this.rightStickRight = pressed;
    this.setPressed(key, pressed);
    if (pressed) this.pressVirtualKey(key, fallback, touchId, 'right-joystick');
    else this.releaseVirtualKey(key, fallback, touchId, 'right-joystick');
  }

  private applyRightDirection(up: boolean, down: boolean, left: boolean, right: boolean, touchId: number): void {
    this.setRightDirection(VirtualKey.RIGHT_STICK_UP, 'up', 23, up, touchId);
    this.setRightDirection(VirtualKey.RIGHT_STICK_DOWN, 'down', 37, down, touchId);
    this.setRightDirection(VirtualKey.RIGHT_STICK_LEFT, 'left', 36, left, touchId);
    this.setRightDirection(VirtualKey.RIGHT_STICK_RIGHT, 'right', 38, right, touchId);
  }

  private releaseRightDirections(touchId: number): void {
    this.applyRightDirection(false, false, false, false, touchId);
  }

  /** Right analog stick adapted from VintagePomelo's camera-look control. */
  private handleRightJoystickTouch(event: TouchEvent): void {
    if (!this.interactive) return;
    event.stopPropagation();
    if (event.type === TouchType.Down && event.changedTouches.length > 0 && this.rightJoystickTouchId < 0) {
      const touch = event.changedTouches[0];
      this.rightJoystickTouchId = touch.id;
      this.rightJoystickCenterX = Number(touch.x);
      this.rightJoystickCenterY = Number(touch.y);
      this.rightJoystickLastX = Number(touch.x);
      this.rightJoystickLastY = Number(touch.y);
      this.rightJoystickActive = true;
      this.rightJoystickX = 0;
      this.rightJoystickY = 0;
      return;
    }
    if (event.type === TouchType.Move && this.rightJoystickTouchId >= 0) {
      for (let index = 0; index < event.touches.length; index++) {
        const touch = event.touches[index];
        if (touch.id !== this.rightJoystickTouchId) continue;
        const currentX = Number(touch.x);
        const currentY = Number(touch.y);
        const rawX = currentX - this.rightJoystickCenterX;
        const rawY = currentY - this.rightJoystickCenterY;
        const distance = Math.sqrt(rawX * rawX + rawY * rawY);
        const maxOffset = this.rightJoystickMaxOffset();
        if (distance > maxOffset && distance > 0) {
          this.rightJoystickX = rawX * maxOffset / distance;
          this.rightJoystickY = rawY * maxOffset / distance;
        } else {
          this.rightJoystickX = rawX;
          this.rightJoystickY = rawY;
        }

        const deltaX = currentX - this.rightJoystickLastX;
        const deltaY = currentY - this.rightJoystickLastY;
        this.rightJoystickLastX = currentX;
        this.rightJoystickLastY = currentY;
        const deadzone = this.rightJoystickRadius() * this.config().rightJoystickDeadzone / 100;
        if (this.config().rightJoystickOutputMode === RightJoystickOutputMode.KEYS) {
          const direction = resolveVirtualJoystickDirection(rawX, rawY, this.rightJoystickRadius(),
            this.config().rightJoystickDeadzone, true);
          this.applyRightDirection(direction.up, direction.down, direction.left, direction.right,
            this.rightJoystickTouchId);
        } else if (distance > deadzone && (deltaX !== 0 || deltaY !== 0)) {
          this.releaseRightDirections(this.rightJoystickTouchId);
          const sensitivity = Math.max(0.25, Math.min(3, this.config().rightJoystickSensitivity / 100));
          const ui = this.getUIContext();
          InputDispatcher.getInstance().pointerDelta(this.rightJoystickSource(this.rightJoystickTouchId),
            ui.vp2px(deltaX) * sensitivity, ui.vp2px(deltaY) * sensitivity);
        }
        break;
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      for (let index = 0; index < event.changedTouches.length; index++) {
        if (event.changedTouches[index].id === this.rightJoystickTouchId) {
          this.releaseRightJoystickInteraction();
          break;
        }
      }
    }
  }

  private updateDpad(event: TouchEvent): void {
    for (let index = 0; index < event.touches.length; index++) {
      const touch = event.touches[index];
      if (touch.id !== this.dpadTouchId) continue;
      const centerX = this.overlayW * this.layout().direction.centerX;
      const centerY = this.overlayH * this.layout().direction.centerY;
      const direction = this.directionFor(Number(touch.x) - centerX, Number(touch.y) - centerY);
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
    .hitTestBehavior(HitTestMode.None)
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
    .width(this.directionSize()).height(this.directionSize()).hitTestBehavior(HitTestMode.None).id('wine-vintage-direction-dpad')
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
    .width(this.directionSize()).height(this.directionSize()).hitTestBehavior(HitTestMode.None).id('wine-vintage-direction-joystick')
  }

  @Builder
  private DirectionGroup() {
    Column() {
      if (this.config().dpadMode === DirectionControlMode.DPAD) this.Dpad()
      else this.Joystick()
    }
    .width(this.directionSize()).height(this.directionSize())
    .hitTestBehavior(HitTestMode.None)
    .position(this.groupPosition(this.layout().direction.centerX, this.layout().direction.centerY, this.directionSize(), this.directionSize()))
  }

  @Builder
  private RightJoystickGroup() {
    if (this.config().showRightJoystick) {
      Stack() {
        Circle().width(this.rightJoystickSize()).height(this.rightJoystickSize()).fill('#16000000')
          .stroke(this.outlineBackdropColor()).strokeWidth(4)
          .opacity(this.visibleOpacity(this.config().joystickTransparency))
          .shadow({ radius: 5, color: '#88000000' })
        Circle().width(this.rightJoystickSize() - 4).height(this.rightJoystickSize() - 4).fill('#00000000')
          .stroke('#FF8BC34A').strokeWidth(2)
          .opacity(this.visibleOpacity(this.config().joystickTransparency))
        ForEach([0, 90, 180, 270], (angle: number): void => {
          Line().width(10).height(2).backgroundColor('#FF8BC34A')
            .opacity(this.visibleOpacity(this.config().joystickTransparency) * 0.6)
            .rotate({ angle: angle })
            .position({
              x: this.rightJoystickRadius() + Math.cos(angle * Math.PI / 180) * (this.rightJoystickRadius() - 8) - 5,
              y: this.rightJoystickRadius() + Math.sin(angle * Math.PI / 180) * (this.rightJoystickRadius() - 8) - 1
            })
        }, (angle: number): string => angle.toString())
        Circle().width(6).height(6).fill('#B38BC34A')
          .opacity(this.visibleOpacity(this.config().joystickTransparency) * 0.7)
        Circle().width(this.rightJoystickKnobSize()).height(this.rightJoystickKnobSize())
          .fill(this.rightJoystickActive ? '#738BC34A' : '#428BC34A')
          .stroke('#FF8BC34A').strokeWidth(1.5)
          .opacity(this.visibleOpacity(this.config().joystickTransparency) * (this.rightJoystickActive ? 1 : 0.8))
          .shadow({ radius: 4, color: '#66000000' })
          .translate({ x: this.rightJoystickX, y: this.rightJoystickY })
      }
      .width(this.rightJoystickSize()).height(this.rightJoystickSize())
      .hitTestBehavior(HitTestMode.None).id('wine-vintage-right-joystick')
      .position(this.groupPosition(this.layout().camera.centerX, this.layout().camera.centerY,
        this.rightJoystickSize(), this.rightJoystickSize()))
    }
  }

  @Builder
  private ActionGroup() {
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
    }
    .width(this.actionWidth()).height(this.actionHeight()).hitTestBehavior(HitTestMode.None)
    .id('wine-vintage-action')
    .position(this.groupPosition(this.layout().action.centerX, this.layout().action.centerY, this.actionWidth(), this.actionHeight()))
  }

  @Builder
  private ShoulderButton(label: string, key: VirtualKey, accent: string, position: ButtonGroupPosition, id: string) {
    Stack({ alignContent: Alignment.Center }) {
      Rect().width(this.shoulderWidth()).height(this.shoulderHeight())
        .fill(this.isPressed(key) ? accent : this.fillColor(false))
        .stroke(accent).strokeWidth(2).borderRadius(this.shoulderHeight() / 2)
        .opacity(this.visibleOpacity(this.config().transparency))
        .shadow({ radius: this.isPressed(key) ? 2 : 5, color: '#66000000' })
      Text(label).fontSize(12 * this.config().buttonSize / 100).fontWeight(FontWeight.Bold)
        .fontColor(this.textColor(this.isPressed(key), accent))
    }
    .width(this.shoulderHitWidth()).height(this.shoulderHitHeight())
    .position(this.groupPosition(position.centerX, position.centerY, this.shoulderHitWidth(), this.shoulderHitHeight()))
    .hitTestBehavior(HitTestMode.None).id(id)
  }

  @Builder
  private ShoulderGroups() {
    if (this.config().showButtonShift) {
      this.ShoulderButton('LT', VirtualKey.BUTTON_SHIFT, '#FFFFB74D', this.layout().leftTrigger, 'wine-vintage-left-trigger')
    }
    if (this.config().showButtonL) {
      this.ShoulderButton('LB', VirtualKey.BUTTON_L, this.strokeColor(), this.layout().leftBumper, 'wine-vintage-left-bumper')
    }
    if (this.config().showButtonR) {
      this.ShoulderButton('RB', VirtualKey.BUTTON_R, this.strokeColor(), this.layout().rightBumper, 'wine-vintage-right-bumper')
    }
    if (this.config().showButtonCtrl) {
      this.ShoulderButton('RT', VirtualKey.BUTTON_CTRL, '#FF64B5F6', this.layout().rightTrigger, 'wine-vintage-right-trigger')
    }
  }

  @Builder
  private AuxGroup() {
    if (this.auxWidth() > 0) {
      Row() {
        if (this.config().showButtonMenu) this.GameButton('菜单', VirtualKey.BUTTON_MENU, 1, this.strokeColor(), true)
      }
      .width(this.auxWidth()).height(this.auxHeight()).justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
      .id('wine-vintage-aux')
      .position(this.groupPosition(this.layout().aux.centerX, this.layout().aux.centerY, this.auxWidth(), this.auxHeight()))
    }
  }

  /** VintagePomelo's optional free-button mode, rendered in place of fixed controls. */
  @Builder
  private FreeButtonGroup() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.renderedProfile.freeButtonsConfig.buttons, (button: FreeButton, index: number): void => {
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
        .hitTestBehavior(HitTestMode.None)
      }, (button: FreeButton): string => button.id)
    }
    .width(this.freeGroupSize()).height(this.freeGroupSize()).hitTestBehavior(HitTestMode.None)
    .id('wine-vintage-free-buttons')
    .position(this.groupPosition(this.layout().action.centerX, this.layout().action.centerY, this.freeGroupSize(), this.freeGroupSize()))
  }

  @Builder
  private ControlBarButton(icon: Resource, id: string, highlighted: boolean = false,
    tint: string = '#FFFFFFFF', highlightedBackground: string = '#44FFFFFF', stateful: boolean = false,
    action: () => void = (): void => {}) {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon).fontSize(stateful ? 14 : 16).fontColor([tint])
          .translate({ y: stateful ? -3 : 0 })
        if (stateful) {
          Text(highlighted ? 'ON' : 'OFF')
            .fontSize(6.5).fontWeight(FontWeight.Bold)
            .fontColor(highlighted ? '#FFB9F6CA' : '#FFAAB0BA')
            .position({ x: '50%', y: 24 }).translate({ x: '-50%' })
        }
      }.width(36).height(36)
    }
    .width(36).height(36)
    .backgroundColor(highlighted ? highlightedBackground : '#BF282828')
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 2 })
    .id(id)
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => this.handleToolbarButtonTouch(event, action))
    .onMouse((event: MouseEvent): void => this.handleToolbarButtonMouse(event, action))
    .onClick((): void => this.invokeToolbarButtonAction(action))
  }

  @Builder
  private ControlsVisibilityButton() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.controlsVisibleVisual ? $r('sys.symbol.gamecontroller') : $r('sys.symbol.eye_slash'))
          .fontSize(14).fontColor(['#FFFFFFFF']).translate({ y: -3 })
        Text(this.controlsVisibleVisual ? 'ON' : 'OFF')
          .fontSize(6.5).fontWeight(FontWeight.Bold)
          .fontColor(this.controlsVisibleVisual ? '#FFB9F6CA' : '#FFAAB0BA')
          .position({ x: '50%', y: 24 }).translate({ x: '-50%' })
      }.width(36).height(36)
    }
    .width(36).height(36)
    .backgroundColor(this.controlsVisibleVisual ? '#384F7CFF' : '#BF282828')
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 2 })
    .id('wine-input-overlay-fold').hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => this.handleToolbarButtonTouch(event,
      (): void => this.runToolbarAction('controls')))
    .onMouse((event: MouseEvent): void => this.handleToolbarButtonMouse(event,
      (): void => this.runToolbarAction('controls')))
    .onClick((): void => this.invokeToolbarButtonAction((): void => this.runToolbarAction('controls')))
  }

  @Builder
  private TouchpadModeButton() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.hand_tap')).fontSize(14)
          .fontColor([this.touchpadModeVisual ? '#FFB9F6CA' : '#FFFFFFFF']).translate({ y: -3 })
        Text(this.touchpadModeVisual ? 'ON' : 'OFF')
          .fontSize(6.5).fontWeight(FontWeight.Bold)
          .fontColor(this.touchpadModeVisual ? '#FFB9F6CA' : '#FFAAB0BA')
          .position({ x: '50%', y: 24 }).translate({ x: '-50%' })
      }.width(36).height(36)
    }
    .width(36).height(36)
    .backgroundColor(this.touchpadModeVisual ? '#B0267A48' : '#BF282828')
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 2 })
    .id('wine-input-touchpad-mode').hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => this.handleToolbarButtonTouch(event,
      (): void => this.runToolbarAction('mouse')))
    .onMouse((event: MouseEvent): void => this.handleToolbarButtonMouse(event,
      (): void => this.runToolbarAction('mouse')))
    .onClick((): void => this.invokeToolbarButtonAction((): void => this.runToolbarAction('mouse')))
  }

  @Builder
  private ExpandedToolbarButtons() {
    this.ControlBarButton($r('sys.symbol.gearshape'), 'wine-input-layout-editor', false,
      '#FFFFFFFF', '#44FFFFFF', false, (): void => this.runToolbarAction('editor'))
    this.ControlBarButton($r('sys.symbol.keyboard'), 'wine-input-key-mapping-editor', false,
      '#FFFFFFFF', '#44FFFFFF', false, (): void => this.runToolbarAction('mapping'))
    this.ControlsVisibilityButton()
    this.TouchpadModeButton()
  }

  @Builder
  private ToolbarToggleButton(vertical: boolean) {
    Button({ type: ButtonType.Circle }) {
      if (vertical) {
        SymbolGlyph(this.toolbarExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
          .fontSize(14).fontColor(['#FFFFFFFF'])
      } else {
        SymbolGlyph(this.toolbarExpanded ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
          .fontSize(14).fontColor(['#FFFFFFFF'])
      }
    }
    .width(28).height(28)
    .backgroundColor(this.toolbarExpanded ? '#1AFFFFFF' : '#BF282828')
    .border({ width: 1, color: '#33FFFFFF' })
    .id('wine-input-overlay-toggle')
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => this.handleToolbarButtonTouch(event,
      (): void => this.runToolbarAction('toolbar')))
    .onMouse((event: MouseEvent): void => this.handleToolbarButtonMouse(event,
      (): void => this.runToolbarAction('toolbar')))
    .onClick((): void => this.invokeToolbarButtonAction((): void => this.runToolbarAction('toolbar')))
  }

  /** Direct ArkTS adaptation of VintagePomelo's collapsible icon control bar. */
  @Builder
  private Toolbar() {
    if (this.toolbarAutoHidden && this.isAutoHideMode()) {
      Button({ type: ButtonType.Normal }) {}
        .width(48).height(48)
        .backgroundColor('#00000000').opacity(0)
        .hitTestBehavior(HitTestMode.Block)
        .position({ x: Math.max(0, this.overlayW - 52), y: 8 })
        .id('wine-input-overlay-wake')
        .onClick((): void => this.runToolbarAction('wake'))
        .zIndex(30)
    } else if (this.resolveToolbarVertical()) {
      Column({ space: 8 }) {
        this.ToolbarToggleButton(true)

        if (this.toolbarExpanded) {
          this.ExpandedToolbarButtons()
        }
      }
      .padding(this.toolbarExpanded ? 8 : 4)
      .backgroundColor('#4D000000')
      .borderRadius(20)
      .hitTestBehavior(HitTestMode.Transparent)
      .position({ x: this.toolbarOriginX(), y: 14 })
      .id('wine-input-toolbar-vertical')
      .zIndex(30)
    } else {
      Row({ space: 8 }) {
        this.ToolbarToggleButton(false)

        if (this.toolbarExpanded) {
          this.ExpandedToolbarButtons()
        }
      }
      .padding(this.toolbarExpanded ? 8 : 4)
      .backgroundColor('#4D000000')
      .borderRadius(20)
      .hitTestBehavior(HitTestMode.Transparent)
      .position({ x: this.toolbarOriginX(), y: 14 })
      .id('wine-input-toolbar-horizontal')
      .zIndex(30)
    }
  }

  build() {
    Stack() {
      // Referencing the revision in the render tree makes ArkUI invalidate an
      // editor preview while preserving stable production test IDs.
      Text(this.renderRevision.toString()).width(0).height(0).opacity(0).hitTestBehavior(HitTestMode.None)
      if (this.overlayW > 0 && this.overlayH > 0 && this.controlsVisibleVisual) {
        if (this.renderedProfile.freeButtonsConfig.enabled && this.renderedProfile.freeButtonsConfig.buttons.length > 0) {
          this.FreeButtonGroup()
        } else {
          this.DirectionGroup()
          this.RightJoystickGroup()
          this.ShoulderGroups()
          this.ActionGroup()
          this.AuxGroup()
        }
      }
      if (!this.hideToolbar) this.Toolbar()
    }
    .width('100%').height('100%').hitTestBehavior(HitTestMode.Block).id('wine-vintage-gamepad-overlay')
    .onTouch((event: TouchEvent): void => this.handleOverlayTouch(event))
    .onMouse((event: MouseEvent): void => this.handleOverlayMouse(event))
    .onAxisEvent((event?: AxisEvent): void => this.onUnhandledAxis(event))
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.overlayW = area.width as number;
      this.overlayH = area.height as number;
    })
  }
}
