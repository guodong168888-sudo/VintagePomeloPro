import testNapi from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OH2EVDEV } from '../common/KeyMap';
import { mapMouseButton } from '../common/MouseMap';
import { common } from '@kit.AbilityKit';
import { GlobalSettings, InputProfile, createDefaultGlobalSettings, createDefaultInputProfile, resolveInputProfileId } from '../model/AppModels';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { InputRouter } from '../service/InputRouter';
import { InputDispatcher } from '../service/InputDispatcher';
import { GamepadActivityListener, GamepadConnectionListener, GamepadManager } from '../service/GamepadManager';
import { InputProfileService } from '../service/InputProfileService';
import { WineWindowManager } from '../service/WineWindowManager';
import { AppSessionService } from '../service/AppSessionService';
import { InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { InputEventGate } from '../service/InputEventGate';
import { WineEngineBlockingOverlay } from '../components/WineEngineBlockingOverlay';

const INPUT_DOMAIN = 0x0000;

class SingleAppController extends XComponentController {
  toplevelId: number = 0;
  surfaceId: string = '';

  switchToplevel(value: number): void {
    if (value <= 0 || value === this.toplevelId) return;
    if (this.toplevelId > 0 && this.surfaceId.length > 0) {
      try { testNapi.destroyRenderer(this.toplevelId); } catch (_) {}
    }
    this.toplevelId = value;
    if (this.surfaceId.length > 0) {
      try {
        testNapi.createRenderer(this.toplevelId, BigInt(this.surfaceId));
        InputOverlayWindowCoordinator.getInstance().markRendererRebound();
      } catch (_) {}
    }
  }

  onSurfaceCreated(surfaceId: string): void {
    this.surfaceId = surfaceId;
    if (this.toplevelId > 0) {
      testNapi.createRenderer(this.toplevelId, BigInt(surfaceId));
      InputOverlayWindowCoordinator.getInstance().markRendererRebound();
    }
  }

  onSurfaceChanged(_surfaceId: string, rect: SurfaceRect): void {
    if (this.toplevelId <= 0) return;
    testNapi.resizeRenderer(this.toplevelId, rect.surfaceWidth, rect.surfaceHeight);
    const scale = WineWindowManager.getInstance().getEffectiveScale();
    testNapi.notifyToplevelResize(this.toplevelId,
      Math.round(rect.surfaceWidth / scale), Math.round(rect.surfaceHeight / scale));
  }

  onSurfaceDestroyed(_surfaceId: string): void {
    if (this.toplevelId > 0) testNapi.destroyRenderer(this.toplevelId);
    this.surfaceId = '';
  }

  rebindRenderer(): boolean {
    if (this.toplevelId <= 0 || this.surfaceId.length === 0) return false;
    try {
      // 保持同一 NativeWindow/EGLContext，只要求 Wayland 重绘当前帧。
      // 真正的 surface 重建只在 XComponent 生命周期回调中执行。
      testNapi.refreshRenderer(this.toplevelId);
      InputOverlayWindowCoordinator.getInstance().markRendererRebound();
      return true;
    } catch (_) {
      return false;
    }
  }
}

@Entry
@Component
struct SingleAppWindow {
  @StorageLink('singleAppToplevelId') @Watch('onToplevelChanged') private toplevelId: number = 0;
  @StorageLink('singleAppSessionId') private sessionId: string = '';
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private inputProfile: InputProfile = createDefaultInputProfile();
  private controller: SingleAppController = new SingleAppController();
  private gamepadConnectionCallback: GamepadConnectionListener | null = null;
  private gamepadActivityCallback: GamepadActivityListener | null = null;
  private eventGate: InputEventGate = new InputEventGate();

  private noteHardwareActivity(): void {
    if (this.settings.autoHideVirtualControls && this.settings.showVirtualControls) {
      InputOverlayWindowCoordinator.getInstance().setControlsVisible(false);
    }
  }

  aboutToAppear(): void {
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    InputProfileService.getInstance().initialize(getContext(this) as common.UIAbilityContext).then(() => {
      const session = AppSessionService.getInstance().getSession(this.sessionId);
      const appProfileId = session ? AppSettingsStore.getInstance().getAppSettings(session.appId).inputProfileId : 'default';
      const profileId = resolveInputProfileId(appProfileId, this.settings.desktopInputProfileId);
      const profile = InputProfileService.getInstance().getProfile(profileId);
      this.inputProfile = profile;
      GamepadManager.getInstance().setButtonMappings(profile.gamepadMappings);
    });
    GamepadManager.getInstance().initialize(this.settings.gamepadDeadzone);
    this.gamepadConnectionCallback = (connected: boolean): void => {
      if (!connected && this.settings.autoHideVirtualControls && this.settings.showVirtualControls) {
        InputOverlayWindowCoordinator.getInstance().setControlsVisible(true);
      }
    };
    this.gamepadActivityCallback = (): void => {
      this.noteHardwareActivity();
    };
    GamepadManager.getInstance().subscribeConnection(this.gamepadConnectionCallback);
    GamepadManager.getInstance().subscribeActivity(this.gamepadActivityCallback);
    this.controller.switchToplevel(this.toplevelId);
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
    InputOverlayWindowCoordinator.getInstance().registerRendererStressDriver(() => this.controller.rebindRenderer());
  }

  aboutToDisappear(): void {
    if (this.gamepadConnectionCallback) {
      GamepadManager.getInstance().unsubscribeConnection(this.gamepadConnectionCallback);
    }
    if (this.gamepadActivityCallback) {
      GamepadManager.getInstance().unsubscribeActivity(this.gamepadActivityCallback);
    }
    GamepadManager.getInstance().releaseAll();
    InputDispatcher.getInstance().releaseAll('single-app-page-disappear');
    InputRouter.getInstance().releaseAllKeys();
    InputOverlayWindowCoordinator.getInstance().unregisterRendererStressDriver();
  }

  private onToplevelChanged(): void {
    this.controller.switchToplevel(this.toplevelId);
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
    InputOverlayWindowCoordinator.getInstance().setActiveToplevel(this.toplevelId);
  }

  private pointerTarget(x: number, y: number): number {
    const found = testNapi.findToplevelAt(x, y) as number;
    return found > 0 ? found : this.toplevelId;
  }

  private handleHardwareKey(event: KeyEvent): void {
    this.noteHardwareActivity();
    event.stopPropagation();
    hilog.info(INPUT_DOMAIN, 'KBD-PIPE', '[ArkTS] single-app key code=%{public}d type=%{public}d',
      event.keyCode, event.type);
    if (GamepadManager.getInstance().handleKey(event.keyCode, event.type === KeyType.Down)) return;
    const code = OH2EVDEV[event.keyCode] ?? 0;
    if (code > 0) InputRouter.getInstance().sendKey(code, event.type === KeyType.Down);
  }

  build() {
    Stack() {
      XComponent({ id: 'wine_single_app_xc', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%').height('100%').backgroundColor('#000000').focusable(false)
        .onMouse((event: MouseEvent) => {
          if (!this.eventGate.shouldHandleMouse(event.source, event.sourceTool)) return;
          this.noteHardwareActivity();
          const x = vp2px(event.x);
          const y = vp2px(event.y);
          const target = this.pointerTarget(x, y);
          if (event.action === MouseAction.Press) {
            testNapi.raiseToplevel(target);
            InputRouter.getInstance().setActiveToplevel(target);
          }
          InputRouter.getInstance().sendPointer(event.action, x, y, mapMouseButton(event.button));
        })
        .onTouch((event: TouchEvent) => {
          if (!this.eventGate.shouldHandleTouch(event.source, event.sourceTool)) return;
          const point = event.changedTouches[0];
          if (!point) return;
          const x = vp2px(point.x);
          const y = vp2px(point.y);
          const target = this.pointerTarget(x, y);
          InputRouter.getInstance().setActiveToplevel(target);
          if (event.type === TouchType.Down) InputRouter.getInstance().sendPointer(MouseAction.Press, x, y, mapMouseButton(1));
          if (event.type === TouchType.Move) InputRouter.getInstance().sendPointer(MouseAction.Move, x, y, 0);
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) InputRouter.getInstance().sendPointer(MouseAction.Release, x, y, mapMouseButton(1));
        })
        .onAxisEvent((event?: AxisEvent) => {
          this.noteHardwareActivity();
          if (!event) return;
          const x = vp2px(event.x);
          const y = vp2px(event.y);
          const target = this.pointerTarget(x, y);
          InputRouter.getInstance().setActiveToplevel(target);
          const vertical = event.getVerticalAxisValue();
          const horizontal = event.getHorizontalAxisValue();
          if (vertical !== 0) InputRouter.getInstance().sendScroll(0, vertical, event.scrollStep ?? 0, x, y);
          if (horizontal !== 0) InputRouter.getInstance().sendScroll(1, horizontal, event.scrollStep ?? 0, x, y);
        })

      WineEngineBlockingOverlay()
    }
    .width('100%').height('100%').backgroundColor('#000000')
    .id('wine-single-input-root')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent): void => this.handleHardwareKey(event))
  }
}
