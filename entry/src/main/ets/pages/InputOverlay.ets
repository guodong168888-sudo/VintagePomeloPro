import { common, Want } from '@kit.AbilityKit';
import { DEBUG } from 'BuildProfile';
import { mapMouseButton } from '../common/MouseMap';
import {
  GlobalSettings,
  InputDiagnostics,
  InputProfile,
  createDefaultGlobalSettings,
  createDefaultInputProfile
} from '../model/AppModels';
import { VirtualInputOverlay } from '../components/VirtualInputOverlay';
import { InputDiagnosticsListener, InputDispatcher } from '../service/InputDispatcher';
import { InputOverlayListener, InputOverlaySnapshot, InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { InputProfileService } from '../service/InputProfileService';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { AppSessionService } from '../service/AppSessionService';
import { InputEventGate } from '../service/InputEventGate';

interface DirectTouch {
  x: number;
  y: number;
  startX: number;
  startY: number;
  moved: boolean;
  buttonDown: boolean;
  consumed: boolean;
  startTime: number;
}

interface TouchpadFinger {
  id: number;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  startTime: number;
  moved: boolean;
}

/** 全屏透明应用子窗口的 ArkTS 根页面。 */
@Entry
@Component
struct InputOverlayPage {
  @State private snapshot: InputOverlaySnapshot = InputOverlayWindowCoordinator.getInstance().getSnapshot();
  @State private profile: InputProfile = createDefaultInputProfile();
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private inputDiagnostics: InputDiagnostics = InputDispatcher.getInstance().getDiagnostics();
  @State private cursorX: number = 0;
  @State private cursorY: number = 0;
  @State private cursorVisible: boolean = false;
  @State private cursorFlash: boolean = false;
  @State private touchpadMode: boolean = false;
  @State private overlayW: number = 0;
  @State private overlayH: number = 0;
  private listener: InputOverlayListener | null = null;
  private diagnosticsListener: InputDiagnosticsListener | null = null;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private directTouches: Map<number, DirectTouch> = new Map();
  private twoFinger: boolean = false;
  private twoFingerTapEligible: boolean = false;
  private lastMidX: number = 0;
  private lastMidY: number = 0;
  private eventGate: InputEventGate = new InputEventGate();
  private readonly TAP_TIMEOUT_MS: number = 300;
  private readonly TAP_SLOP_PX: number = 24;
  private cursorHideTimer: number = -1;
  private cursorFlashTimer: number = -1;
  private touchpadFingers: Map<number, TouchpadFinger> = new Map<number, TouchpadFinger>();
  private touchpadTwoFinger: boolean = false;
  private touchpadSuppressSingleTap: boolean = false;
  private touchpadTwoFingerTapEligible: boolean = false;
  private touchpadLastMidX: number = 0;
  private touchpadLastMidY: number = 0;

  aboutToAppear(): void {
    this.listener = (snapshot: InputOverlaySnapshot): void => {
      const profileChanged = this.snapshot.profileId !== snapshot.profileId;
      const sessionChanged = this.snapshot.session.sessionId !== snapshot.session.sessionId;
      const becameVisible = !this.snapshot.visible && snapshot.visible;
      this.snapshot = snapshot;
      this.settings = AppSettingsStore.getInstance().getGlobalSettings();
      if (sessionChanged) {
        this.directTouches.clear();
        this.twoFinger = false;
        this.twoFingerTapEligible = false;
        this.resetTouchpadGesture();
        this.touchpadMode = false;
        this.cursorVisible = false;
      }
      // Editors update the contents of an existing profile ID. Reload when
      // returning to a Wine session as well as when the ID changes so saved
      // fixed/free layouts take effect without restarting the application.
      if (profileChanged || sessionChanged || becameVisible) this.loadProfile(snapshot.profileId);
    };
    InputOverlayWindowCoordinator.getInstance().subscribe(this.listener);
    this.diagnosticsListener = (diagnostics: InputDiagnostics): void => {
      this.inputDiagnostics = diagnostics;
    };
    InputDispatcher.getInstance().subscribeDiagnostics(this.diagnosticsListener);
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    this.loadProfile(this.snapshot.profileId);
  }

  aboutToDisappear(): void {
    if (this.listener) InputOverlayWindowCoordinator.getInstance().unsubscribe(this.listener);
    if (this.diagnosticsListener) InputDispatcher.getInstance().unsubscribeDiagnostics(this.diagnosticsListener);
    this.cancelCursorTimers();
    this.resetTouchpadGesture();
    InputDispatcher.getInstance().releaseAll('overlay-page-disappear');
  }

  private cancelCursorTimers(): void {
    if (this.cursorHideTimer >= 0) clearTimeout(this.cursorHideTimer);
    if (this.cursorFlashTimer >= 0) clearTimeout(this.cursorFlashTimer);
    this.cursorHideTimer = -1;
    this.cursorFlashTimer = -1;
  }

  private showCursorAt(x: number, y: number, flash: boolean = false): void {
    if (!this.touchpadMode || !this.settings.virtualMouseConfig.showCursor) return;
    this.cursorX = x;
    this.cursorY = y;
    this.cursorVisible = true;
    if (this.cursorHideTimer >= 0) clearTimeout(this.cursorHideTimer);
    this.cursorHideTimer = setTimeout((): void => {
      this.cursorHideTimer = -1;
      this.cursorVisible = false;
    }, 900) as number;
    if (!flash) return;
    this.cursorFlash = true;
    if (this.cursorFlashTimer >= 0) clearTimeout(this.cursorFlashTimer);
    this.cursorFlashTimer = setTimeout((): void => {
      this.cursorFlashTimer = -1;
      this.cursorFlash = false;
    }, 90) as number;
  }

  private scrollThresholdPx(): number {
    const sensitivity = Math.max(50, Math.min(200, this.settings.virtualMouseConfig.mouseSensitivity));
    return Math.max(6, 18 * 100 / sensitivity);
  }

  private loadProfile(profileId: string): void {
    InputProfileService.getInstance().initialize(this.context).then(() => {
      this.profile = InputProfileService.getInstance().getProfile(profileId || 'default');
    }).catch(() => {});
  }

  private directSource(touchId: number): string {
    return 'direct-touch-' + touchId;
  }

  private midpointY(): number {
    const values = Array.from(this.directTouches.values());
    if (values.length < 2) return 0;
    return (values[0].y + values[1].y) / 2;
  }

  private midpointX(): number {
    const values = Array.from(this.directTouches.values());
    if (values.length < 2) return 0;
    return (values[0].x + values[1].x) / 2;
  }

  private injectClick(source: string, x: number, y: number, button: number): void {
    InputDispatcher.getInstance().pointerDown(source, x, y, button);
    InputDispatcher.getInstance().pointerUp(source, x, y, button);
  }

  private handleDirectTouch(event: TouchEvent): void {
    if (!this.eventGate.shouldHandleTouch(event.source, event.sourceTool)) return;
    event.stopPropagation();
    for (let index = 0; index < event.changedTouches.length; index++) {
      const touch = event.changedTouches[index];
      const x = vp2px(touch.x);
      const y = vp2px(touch.y);
      const source = this.directSource(touch.id);
      if (event.type === TouchType.Down) {
        this.directTouches.set(touch.id, {
          x, y, startX: x, startY: y, moved: false, buttonDown: false, consumed: false, startTime: Date.now()
        });
        if (this.directTouches.size === 2) {
          this.twoFinger = true;
          this.twoFingerTapEligible = true;
          this.lastMidX = this.midpointX();
          this.lastMidY = this.midpointY();
          // 双指只负责滚动：取消可能中的点击/拖拽，但不触及虚拟手柄按键。
          this.directTouches.forEach((value: DirectTouch, activeTouchId: number): void => {
            value.consumed = true;
            if (value.buttonDown) InputDispatcher.getInstance().releaseSource(this.directSource(activeTouchId));
          });
        } else if (this.directTouches.size > 2) {
          this.twoFingerTapEligible = false;
        }
      } else if (event.type === TouchType.Move) {
        const previous = this.directTouches.get(touch.id);
        if (!previous) continue;
        const moved = previous.moved || Math.abs(x - previous.startX) + Math.abs(y - previous.startY) > this.TAP_SLOP_PX;
        this.directTouches.set(touch.id, {
          x, y, startX: previous.startX, startY: previous.startY, moved,
          buttonDown: previous.buttonDown, consumed: previous.consumed, startTime: previous.startTime
        });
        if (this.twoFinger && this.directTouches.size >= 2) {
          const midX = this.midpointX();
          const midY = this.midpointY();
          const deltaX = this.lastMidX - midX;
          const delta = this.lastMidY - midY;
          const threshold = this.scrollThresholdPx();
          if (Math.abs(deltaX) >= threshold) {
            this.twoFingerTapEligible = false;
            InputDispatcher.getInstance().scroll('direct-scroll', 1, deltaX > 0 ? 1 : -1);
            this.lastMidX = midX;
          }
          if (Math.abs(delta) >= threshold) {
            this.twoFingerTapEligible = false;
            InputDispatcher.getInstance().scroll('direct-scroll', 0, delta > 0 ? 1 : -1);
            this.lastMidY = midY;
          }
        } else if (moved && !previous.consumed) {
          if (!previous.buttonDown) {
            InputDispatcher.getInstance().pointerDown(source, previous.startX, previous.startY, 272);
            const current = this.directTouches.get(touch.id);
            if (current) current.buttonDown = true;
          }
          InputDispatcher.getInstance().pointerMove(source, x, y);
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        const previous = this.directTouches.get(touch.id);
        if (!previous) continue;
        const elapsed = Date.now() - previous.startTime;
        const wasTwoFinger = this.twoFinger || previous.consumed;
        this.directTouches.delete(touch.id);
        if (wasTwoFinger) {
          if (previous.moved || elapsed >= this.TAP_TIMEOUT_MS || event.type === TouchType.Cancel) {
            this.twoFingerTapEligible = false;
          }
          InputDispatcher.getInstance().releaseSource(source);
          if (this.directTouches.size === 0) {
            if (event.type === TouchType.Up && this.twoFingerTapEligible) {
              this.injectClick('direct-rdp-two-finger-right', this.lastMidX, this.lastMidY, 273);
            }
            InputDispatcher.getInstance().releaseSource('direct-scroll');
            this.twoFinger = false;
            this.twoFingerTapEligible = false;
          }
        } else if (previous.buttonDown) {
          InputDispatcher.getInstance().pointerUp(source, x, y, 272);
        } else if (event.type === TouchType.Up && !previous.moved && elapsed < this.TAP_TIMEOUT_MS) {
          this.injectClick('direct-rdp-left', x, y, 272);
        } else {
          InputDispatcher.getInstance().releaseSource(source);
        }
      }
    }
  }

  private touchpadMidpoint(): [number, number] {
    const values = Array.from(this.touchpadFingers.values());
    if (values.length < 2) return [0, 0];
    return [(values[0].lastX + values[1].lastX) / 2, (values[0].lastY + values[1].lastY) / 2];
  }

  private ensureTouchpadCursor(): void {
    const width = this.overlayW > 0 ? this.overlayW : 720;
    const height = this.overlayH > 0 ? this.overlayH : 480;
    if (this.cursorX <= 0 || this.cursorX >= width || this.cursorY <= 0 || this.cursorY >= height) {
      this.cursorX = width / 2;
      this.cursorY = height / 2;
    }
  }

  private resetTouchpadGesture(): void {
    this.touchpadFingers.clear();
    this.touchpadTwoFinger = false;
    this.touchpadSuppressSingleTap = false;
    this.touchpadTwoFingerTapEligible = false;
    InputDispatcher.getInstance().releaseSource('touchpad-scroll');
    InputDispatcher.getInstance().releaseSource('touchpad-cursor');
  }

  private setTouchpadMode(enabled: boolean): void {
    if (this.touchpadMode === enabled) return;
    InputDispatcher.getInstance().releaseAll('touchpad-mode-switch');
    this.directTouches.clear();
    this.twoFinger = false;
    this.twoFingerTapEligible = false;
    this.resetTouchpadGesture();
    this.touchpadMode = enabled;
    if (enabled) {
      this.ensureTouchpadCursor();
      this.showCursorAt(this.cursorX, this.cursorY);
    } else {
      this.cursorVisible = false;
      this.cancelCursorTimers();
    }
  }

  private touchpadClick(button: number, source: string): void {
    const x = vp2px(this.cursorX);
    const y = vp2px(this.cursorY);
    this.injectClick(source, x, y, button);
    this.showCursorAt(this.cursorX, this.cursorY, true);
  }

  /** VintagePomelo full-screen touchpad: relative cursor, tap click, two-finger right/scroll. */
  private handleTouchpadTouch(event: TouchEvent): void {
    if (!this.eventGate.shouldHandleTouch(event.source, event.sourceTool)) return;
    event.stopPropagation();
    this.ensureTouchpadCursor();
    this.showCursorAt(this.cursorX, this.cursorY);
    const sensitivity = Math.max(0.5, Math.min(2, this.settings.virtualMouseConfig.mouseSensitivity / 100));
    const scrollThreshold = Math.max(3, 8 / sensitivity);

    for (let index = 0; index < event.changedTouches.length; index++) {
      const touch = event.changedTouches[index];
      const x = Number(touch.x);
      const y = Number(touch.y);
      if (event.type === TouchType.Down) {
        this.touchpadFingers.set(touch.id, {
          id: touch.id, startX: x, startY: y, lastX: x, lastY: y,
          startTime: Date.now(), moved: false
        });
        if (this.touchpadFingers.size === 2) {
          this.touchpadTwoFinger = true;
          this.touchpadSuppressSingleTap = true;
          this.touchpadTwoFingerTapEligible = true;
          const midpoint = this.touchpadMidpoint();
          this.touchpadLastMidX = midpoint[0];
          this.touchpadLastMidY = midpoint[1];
        } else if (this.touchpadFingers.size > 2) {
          this.touchpadTwoFingerTapEligible = false;
        }
      } else if (event.type === TouchType.Move) {
        const finger = this.touchpadFingers.get(touch.id);
        if (!finger) continue;
        const dx = x - finger.lastX;
        const dy = y - finger.lastY;
        if (Math.abs(x - finger.startX) > 10 || Math.abs(y - finger.startY) > 10) finger.moved = true;
        finger.lastX = x;
        finger.lastY = y;

        if (this.touchpadTwoFinger && this.touchpadFingers.size >= 2) {
          const midpoint = this.touchpadMidpoint();
          const scrollX = this.touchpadLastMidX - midpoint[0];
          const scrollY = this.touchpadLastMidY - midpoint[1];
          if (Math.abs(scrollX) >= scrollThreshold) {
            this.touchpadTwoFingerTapEligible = false;
            InputDispatcher.getInstance().scroll('touchpad-scroll', 1, scrollX > 0 ? 1 : -1);
            this.touchpadLastMidX = midpoint[0];
          }
          if (Math.abs(scrollY) >= scrollThreshold) {
            this.touchpadTwoFingerTapEligible = false;
            InputDispatcher.getInstance().scroll('touchpad-scroll', 0, scrollY > 0 ? 1 : -1);
            this.touchpadLastMidY = midpoint[1];
          }
        } else if (this.touchpadFingers.size === 1) {
          this.cursorX += dx * sensitivity;
          this.cursorY += dy * sensitivity;
          const maxX = Math.max(5, (this.overlayW > 0 ? this.overlayW : 720) - 5);
          const maxY = Math.max(5, (this.overlayH > 0 ? this.overlayH : 480) - 5);
          this.cursorX = Math.max(5, Math.min(maxX, this.cursorX));
          this.cursorY = Math.max(5, Math.min(maxY, this.cursorY));
          InputDispatcher.getInstance().pointerMove('touchpad-cursor', vp2px(this.cursorX), vp2px(this.cursorY), false);
          this.showCursorAt(this.cursorX, this.cursorY);
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        const finger = this.touchpadFingers.get(touch.id);
        if (!finger) continue;
        const elapsed = Date.now() - finger.startTime;
        const moved = finger.moved || Math.abs(x - finger.startX) > 10 || Math.abs(y - finger.startY) > 10;
        const suppressed = this.touchpadSuppressSingleTap;
        this.touchpadFingers.delete(touch.id);
        if (suppressed) {
          if (moved || elapsed >= this.TAP_TIMEOUT_MS || event.type === TouchType.Cancel) {
            this.touchpadTwoFingerTapEligible = false;
          }
          if (this.touchpadFingers.size === 0) {
            if (event.type === TouchType.Up && this.touchpadTwoFingerTapEligible) {
              this.touchpadClick(273, 'touchpad-two-finger-right');
            }
            this.resetTouchpadGesture();
          } else if (this.touchpadFingers.size < 2) {
            this.touchpadTwoFinger = false;
          }
        } else {
          if (!moved && elapsed < this.TAP_TIMEOUT_MS && event.type === TouchType.Up) {
            this.touchpadClick(272, 'touchpad-left');
          }
          this.touchpadTwoFinger = false;
        }
      }
    }
  }

  private handleOverlayTouch(event: TouchEvent): void {
    if (this.touchpadMode) this.handleTouchpadTouch(event);
    else this.handleDirectTouch(event);
  }

  private hideForExternalInput(): void {
    const settings = AppSettingsStore.getInstance().getGlobalSettings();
    if (settings.autoHideVirtualControls && settings.showVirtualControls) {
      InputOverlayWindowCoordinator.getInstance().setControlsVisible(false);
    }
  }

  private handleDirectMouse(event: MouseEvent): void {
    if (!this.eventGate.shouldHandleMouse(event.source, event.sourceTool)) return;
    event.stopPropagation();
    const source = 'external-mouse';
    const x = vp2px(event.x);
    const y = vp2px(event.y);
    if (event.action === MouseAction.Press) {
      InputDispatcher.getInstance().pointerDown(source, x, y, mapMouseButton(event.button));
    }
    else if (event.action === MouseAction.Release) {
      InputDispatcher.getInstance().pointerUp(source, x, y, mapMouseButton(event.button));
      this.hideForExternalInput();
    }
    else InputDispatcher.getInstance().pointerMove(source, x, y, false);
  }

  private handleDirectAxis(event?: AxisEvent): void {
    if (!event) return;
    const vertical = event.getVerticalAxisValue();
    const horizontal = event.getHorizontalAxisValue();
    if (vertical !== 0) InputDispatcher.getInstance().scroll('external-mouse', 0, vertical, event.scrollStep ?? 40);
    if (horizontal !== 0) InputDispatcher.getInstance().scroll('external-mouse', 1, horizontal, event.scrollStep ?? 40);
  }

  private async openInputEditor(route: string): Promise<void> {
    const sessionId = this.snapshot.session.sessionId;
    const session = AppSessionService.getInstance().getSession(sessionId);
    const want: Want = {
      bundleName: 'com.vintage.pomelopro',
      abilityName: 'EntryAbility',
      parameters: {
        overlayRoute: route,
        profileId: this.snapshot.profileId || 'default',
        profileName: this.profile.name || '默认键鼠手柄',
        appId: session?.appId ?? '',
        baseProfileId: this.settings.desktopInputProfileId || 'default'
      }
    };
    const coordinator = InputOverlayWindowCoordinator.getInstance();
    try {
      // The overlay is a zLevel 9000 subwindow. Make it untouchable before
      // bringing the EntryAbility editor forward or it can intercept the
      // editor's drag/save controls during the Ability transition.
      await coordinator.setVisible(false);
      await this.context.startAbility(want);
    } catch (_) {
      // A failed navigation must not leave the active Wine session without
      // controls. DesktopAbility/SingleAppAbility will normally restore the
      // overlay from onForeground after the editor returns.
      await coordinator.setVisible(true).catch((): void => {});
    }
  }

  build() {
    Stack() {
      if (this.snapshot.visible) {
        VirtualInputOverlay({
          profile: this.profile,
          opacityValue: this.snapshot.opacity,
          controlsVisible: this.snapshot.controlsVisible,
          controlBarDirection: this.settings.controlBarDirection,
          touchpadMode: this.touchpadMode,
          onOpenLayoutEditor: (): void => { this.openInputEditor('input-layout'); },
          onOpenKeyMappingEditor: (): void => { this.openInputEditor('key-mapping'); },
          onControlsVisibleChange: (visible: boolean): void => {
            InputOverlayWindowCoordinator.getInstance().setControlsVisible(visible);
          },
          onTouchpadModeChange: (enabled: boolean): void => this.setTouchpadMode(enabled),
          onUnhandledTouch: (event: TouchEvent): void => this.handleOverlayTouch(event),
          onUnhandledMouse: (event: MouseEvent): void => this.handleDirectMouse(event),
          onUnhandledAxis: (event?: AxisEvent): void => this.handleDirectAxis(event)
        })
        .zIndex(10)
      }
      if (this.touchpadMode && this.cursorVisible && this.settings.virtualMouseConfig.showCursor) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(this.cursorFlash ? 10 : 7)
            .height(this.cursorFlash ? 10 : 7)
            .fill(this.cursorFlash ? '#FF4CAF50' : '#E6FFFFFF')
            .stroke(this.cursorFlash ? '#CCB9F6CA' : '#D9000000')
            .strokeWidth(1)
            .shadow({ radius: this.cursorFlash ? 8 : 4, color: '#66000000', offsetX: 0, offsetY: 1 })
        }
        .width(14).height(14)
        .position({ x: this.cursorX, y: this.cursorY })
        .markAnchor({ x: '50%', y: '50%' })
        .hitTestBehavior(HitTestMode.None)
        .id('wine-virtual-mouse-cursor')
        .zIndex(15)
      }
      if (DEBUG) {
        Column({ space: 3 }) {
          Text('Overlay ' + this.snapshot.createdCount + '/z' + this.snapshot.zLevel +
            ' · rebind ' + this.snapshot.rendererRebinds)
            .fontSize(9).fontColor('#FFEAF4FF').maxLines(1)
          Text('keys ' + this.inputDiagnostics.heldKeys +
            ' · buttons ' + this.inputDiagnostics.heldButtons +
            ' · pointers ' + this.inputDiagnostics.activePointers)
            .fontSize(9).fontColor('#C9D5E6FF').maxLines(1)
          // 累计注入数用于 Debug HAP 自动回归：既要验证最终没有卡键，
          // 也要验证虚拟按键/触摸板确实抵达 InputDispatcher。
          Text('events ' + this.inputDiagnostics.injectedEvents)
            .fontSize(9).fontColor('#C9D5E6FF').maxLines(1)
            .id('wine-overlay-input-events')
          Text('stress ' + this.snapshot.stressCompleted + '/300' +
            (this.snapshot.lastError.length > 0 ? ' · failed' : ''))
            .fontSize(9)
            .fontColor(this.snapshot.lastError.length > 0 ? '#FFFF8A80' : '#C9D5E6FF')
            .maxLines(1)
            .id('wine-overlay-stress-result')
          Button(this.snapshot.stressRunning ? '自检中 ' + this.snapshot.stressCompleted + '/300' : '诊断 300')
            .height(36).fontSize(10).fontColor('#FFF8FAFF').backgroundColor('#D8246BFD').borderRadius(18)
            .id('wine-overlay-diagnostics-run')
            .onClick(() => InputOverlayWindowCoordinator.getInstance().runRendererStress(300))
            .onTouch((event: TouchEvent): void => {
              event.stopPropagation();
              if (event.type === TouchType.Up) {
                InputOverlayWindowCoordinator.getInstance().runRendererStress(300);
              }
            })
            .onMouse((event: MouseEvent): void => {
              event.stopPropagation();
              if (event.action === MouseAction.Release) {
                InputOverlayWindowCoordinator.getInstance().runRendererStress(300);
              }
            })
        }
        .padding(8).backgroundColor('#C8162433').borderRadius(12)
        .position({ x: '2%', y: '3%' })
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent): void => {
          event.stopPropagation();
          if (event.type === TouchType.Up) {
            InputOverlayWindowCoordinator.getInstance().runRendererStress(300);
          }
        })
        .onMouse((event: MouseEvent): void => {
          event.stopPropagation();
          if (event.action === MouseAction.Release) {
            InputOverlayWindowCoordinator.getInstance().runRendererStress(300);
          }
        })
        .id('wine-overlay-diagnostics-state')
        .zIndex(20)
      }
      Column()
        .width('100%').height('100%')
        .backgroundColor('#00000000')
        .hitTestBehavior(HitTestMode.Block)
        .id('wine-input-direct-surface')
        .zIndex(0)
        .onTouch((event: TouchEvent): void => this.handleOverlayTouch(event))
        .onMouse((event: MouseEvent): void => this.handleDirectMouse(event))
        .onAxisEvent((event?: AxisEvent): void => this.handleDirectAxis(event))
    }
    .width('100%').height('100%')
    .backgroundColor('#00000000')
    .id('wine-input-overlay-page')
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.overlayW = area.width as number;
      this.overlayH = area.height as number;
    })
  }
}
