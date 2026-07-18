import testNapi from 'libentry.so';
import { OH2EVDEV } from '../common/KeyMap';
import { mapMouseButton } from '../common/MouseMap';
import { VirtualControls } from '../components/VirtualControls';
import { common } from '@kit.AbilityKit';
import { GlobalSettings, InputProfile, createDefaultGlobalSettings, createDefaultInputProfile } from '../model/AppModels';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { InputRouter } from '../service/InputRouter';
import { GamepadConnectionListener, GamepadManager } from '../service/GamepadManager';
import { InputProfileService } from '../service/InputProfileService';
import { WineWindowManager } from '../service/WineWindowManager';
import { AppSessionService } from '../service/AppSessionService';

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
      try { testNapi.createRenderer(this.toplevelId, BigInt(this.surfaceId)); } catch (_) {}
    }
  }

  onSurfaceCreated(surfaceId: string): void {
    this.surfaceId = surfaceId;
    if (this.toplevelId > 0) testNapi.createRenderer(this.toplevelId, BigInt(surfaceId));
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
}

@Entry
@Component
struct SingleAppWindow {
  @StorageLink('singleAppToplevelId') @Watch('onToplevelChanged') private toplevelId: number = 0;
  @StorageLink('singleAppSessionId') private sessionId: string = '';
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private inputProfile: InputProfile = createDefaultInputProfile();
  @State private hardwareInputActive: boolean = false;
  private controller: SingleAppController = new SingleAppController();
  private gamepadConnectionCallback: GamepadConnectionListener | null = null;

  aboutToAppear(): void {
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    InputProfileService.getInstance().initialize(getContext(this) as common.UIAbilityContext).then(() => {
      const session = AppSessionService.getInstance().getSession(this.sessionId);
      const profileId = session ? AppSettingsStore.getInstance().getAppSettings(session.appId).inputProfileId : 'default';
      this.inputProfile = InputProfileService.getInstance().getProfile(profileId);
    });
    GamepadManager.getInstance().initialize(this.settings.gamepadDeadzone);
    this.gamepadConnectionCallback = (connected: boolean): void => {
      if (connected) this.hardwareInputActive = true;
    };
    GamepadManager.getInstance().subscribeConnection(this.gamepadConnectionCallback);
    this.controller.switchToplevel(this.toplevelId);
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
  }

  aboutToDisappear(): void {
    if (this.gamepadConnectionCallback) {
      GamepadManager.getInstance().unsubscribeConnection(this.gamepadConnectionCallback);
    }
    GamepadManager.getInstance().releaseAll();
    InputRouter.getInstance().releaseAllKeys();
  }

  private onToplevelChanged(): void {
    this.controller.switchToplevel(this.toplevelId);
    InputRouter.getInstance().setActiveToplevel(this.toplevelId);
  }

  private pointerTarget(x: number, y: number): number {
    const found = testNapi.findToplevelAt(x, y) as number;
    return found > 0 ? found : this.toplevelId;
  }

  build() {
    Stack() {
      XComponent({ id: 'wine_single_app_xc', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%').height('100%').backgroundColor('#000000').focusable(true).focusOnTouch(true)
        .onMouse((event: MouseEvent) => {
          this.hardwareInputActive = true;
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
        .onKeyEvent((event: KeyEvent) => {
          this.hardwareInputActive = true;
          event.stopPropagation();
          if (GamepadManager.getInstance().handleKey(event.keyCode, event.type === KeyType.Down)) return;
          const code = OH2EVDEV[event.keyCode] ?? 0;
          if (code > 0) InputRouter.getInstance().sendKey(code, event.type === KeyType.Down);
        })
        .onAxisEvent((event?: AxisEvent) => {
          this.hardwareInputActive = true;
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

      if (this.settings.showVirtualControls &&
        !(this.settings.autoHideVirtualControls && this.hardwareInputActive)) {
        VirtualControls({ opacityValue: this.settings.controlOpacity, profile: this.inputProfile })
      }
    }
    .width('100%').height('100%').backgroundColor('#000000')
  }
}
