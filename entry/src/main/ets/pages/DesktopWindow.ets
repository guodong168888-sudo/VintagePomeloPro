import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import testNapi from 'libentry.so';
import { WineWindowManager } from '../service/WineWindowManager';
import { OH2EVDEV } from '../common/KeyMap';
import { mapMouseButton } from '../common/MouseMap';
import { GlobalSettings, InputProfile, createDefaultGlobalSettings, createDefaultInputProfile } from '../model/AppModels';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { InputRouter } from '../service/InputRouter';
import { InputDispatcher } from '../service/InputDispatcher';
import { GamepadActivityListener, GamepadConnectionListener, GamepadManager } from '../service/GamepadManager';
import { InputProfileService } from '../service/InputProfileService';
import { InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { InputEventGate } from '../service/InputEventGate';

const DOMAIN = 0x0000;

class DesktopController extends XComponentController {
  private surfaceId: string = '';
  private rendererRootId: number = 0;

  onSurfaceCreated(surfaceId: string): void {
    this.surfaceId = surfaceId;
    const rootId = WineWindowManager.getInstance().getDesktopRootId();
    hilog.info(DOMAIN, 'LIFE', '[XComp] onSurfaceCreated rootId=%{public}d surfaceId=%{public}s', rootId, surfaceId);
    this.bindDesktopRoot(rootId, true);
  }
  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    const rootId = this.rendererRootId || WineWindowManager.getInstance().getDesktopRootId();
    hilog.info(DOMAIN, 'LIFE', '[XComp] onSurfaceChanged rootId=%{public}d %{public}dx%{public}d', rootId, rect.surfaceWidth, rect.surfaceHeight);
    if (rootId > 0) {
      try {
        testNapi.resizeRenderer(rootId, rect.surfaceWidth, rect.surfaceHeight);
        const s = WineWindowManager.getInstance().getEffectiveScale();
        testNapi.notifyToplevelResize(rootId,
          Math.round(rect.surfaceWidth / s), Math.round(rect.surfaceHeight / s));
      } catch (_) {}
    }
  }
  onSurfaceDestroyed(_s: string): void {
    const rootId = this.rendererRootId;
    hilog.warn(DOMAIN, 'LIFE', '[XComp] onSurfaceDestroyed rootId=%{public}d', rootId);
    if (rootId > 0) {
      try { testNapi.destroyRenderer(rootId); } catch (_) {}
    }
    this.rendererRootId = 0;
    this.surfaceId = '';
  }

  switchDesktopRoot(rootId: number): boolean {
    return this.bindDesktopRoot(rootId || WineWindowManager.getInstance().getDesktopRootId(), false);
  }

  rebindRenderer(): boolean {
    const rootId = WineWindowManager.getInstance().getDesktopRootId();
    if (rootId <= 0 || this.surfaceId.length === 0 || this.rendererRootId !== rootId) return false;
    try {
      // 调试压测保留 ArkUI 提供的 NativeWindow。真实 Surface 变化由
      // onSurfaceCreated/onSurfaceDestroyed 走完整 renderer 生命周期。
      testNapi.refreshRenderer(rootId);
      InputOverlayWindowCoordinator.getInstance().markRendererRebound();
      return true;
    } catch (_) {
      return false;
    }
  }

  private bindDesktopRoot(rootId: number, force: boolean): boolean {
    if (rootId <= 0 || this.surfaceId.length === 0) return false;
    try {
      if (this.rendererRootId > 0 && (this.rendererRootId !== rootId || force)) {
        testNapi.destroyRenderer(this.rendererRootId);
      }
      testNapi.createRenderer(rootId, BigInt(this.surfaceId));
      this.rendererRootId = rootId;
      InputOverlayWindowCoordinator.getInstance().setActiveToplevel(rootId);
      InputOverlayWindowCoordinator.getInstance().markRendererRebound();
      return true;
    } catch (_) {
      return false;
    }
  }
}

@Entry
@Component
struct DesktopPage {
  @StorageLink('desktopToplevelId') @Watch('onDesktopToplevelChanged') private desktopToplevelId: number = 0;
  controller: DesktopController = new DesktopController();
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private inputProfile: InputProfile = createDefaultInputProfile();
  private gamepadConnectionCallback: GamepadConnectionListener | null = null;
  private gamepadActivityCallback: GamepadActivityListener | null = null;
  // 触控状态机: IDLE → PENDING → (DRAGGING | 长按 | 点击)
  // 双指进入 SCROLLING 模式, 覆盖单指状态
  private touchPending: boolean = false;
  private isDragging: boolean = false;
  private touchStartTime: number = 0;
  private touchStartPx: number = 0;
  private touchStartPy: number = 0;
  private pendingTl: number = 0;
  private pendingPx: number = 0;
  private pendingPy: number = 0;
  private motionLogCounter: number = 0;
  private static readonly LONG_PRESS_MS: number = 500;
  private static readonly DRAG_THRESHOLD: number = 10; // 物理像素, 区分点击抖动和拖拽
  // 双击检测
  private lastTapTime: number = 0;
  private lastTapPx: number = 0;
  private lastTapPy: number = 0;
  private lastTapTl: number = 0;
  private static readonly DOUBLE_TAP_MS: number = 400;
  private static readonly DOUBLE_TAP_DIST: number = 30;
  // 双指滚动
  private twoFingerActive: boolean = false;
  private twoFingerLastMidX: number = 0;
  private twoFingerLastMidY: number = 0;
  private twoFingerTl: number = 0;
  private scrollLogCounter: number = 0;
  private twoFingerAccumY: number = 0;
  private twoFingerAccumX: number = 0;
  private static readonly SCROLL_STEP_PX: number = 40; // 物理像素/滚动步, winewayland.drv 只处理 discrete
  // 物理鼠标右键: Press 时捕获目标 tl, Release 发给同一 tl (按下捕获语义)
  private rightBtnTl: number = 0;
  // hover 移动抽样日志计数
  private hoverLogCounter: number = 0;
  private eventGate: InputEventGate = new InputEventGate();

  private noteHardwareActivity(): void {
    if (this.settings.autoHideVirtualControls && this.settings.showVirtualControls) {
      InputOverlayWindowCoordinator.getInstance().setControlsVisible(false);
    }
  }

  aboutToAppear(): void {
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    InputProfileService.getInstance().initialize(getContext(this) as common.UIAbilityContext).then(() => {
      const profile = InputProfileService.getInstance().getProfile(this.settings.desktopInputProfileId || 'default');
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
    InputRouter.getInstance().setActiveToplevel(WineWindowManager.getInstance().getDesktopRootId());
    this.controller.switchDesktopRoot(this.desktopToplevelId);
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
    InputDispatcher.getInstance().releaseAll('desktop-page-disappear');
    InputRouter.getInstance().releaseAllKeys();
    InputOverlayWindowCoordinator.getInstance().unregisterRendererStressDriver();
  }

  private onDesktopToplevelChanged(): void {
    const rootId = this.desktopToplevelId || WineWindowManager.getInstance().getDesktopRootId();
    if (this.controller.switchDesktopRoot(rootId)) {
      InputOverlayWindowCoordinator.getInstance().setActiveToplevel(rootId);
    }
  }

  private handleHardwareKey(ev: KeyEvent): void {
    this.noteHardwareActivity();
    const rootId = WineWindowManager.getInstance().getDesktopRootId();
    if (rootId <= 0) return;
    ev.stopPropagation();
    hilog.info(DOMAIN, 'KBD-PIPE', '[ArkTS] desktop key code=%{public}d type=%{public}d',
      ev.keyCode, ev.type);
    if (GamepadManager.getInstance().handleKey(ev.keyCode, ev.type === KeyType.Down)) return;
    const code = OH2EVDEV[ev.keyCode] ?? 0;
    if (code <= 0) return;
    if (InputRouter.getInstance().getActiveToplevel() <= 0) {
      InputRouter.getInstance().setActiveToplevel(rootId);
    }
    InputRouter.getInstance().sendKey(code, ev.type === KeyType.Down);
  }

  build() {
    Stack() {
      XComponent({
        id: 'wine_desktop_xc',
        type: XComponentType.SURFACE,
        controller: this.controller
      }).width('100%').height('100%').backgroundColor('#000').focusable(false)

      // ── 触控处理: 单指→左键/右键/拖拽, 双指→滚轮 ──
      .onTouch((ev: TouchEvent) => {
        if (!this.eventGate.shouldHandleTouch(ev.source, ev.sourceTool)) return;
        try {
          // ── 双指滚动 ──
          if (ev.touches.length >= 2) {
            // 取消单指状态
            if (this.touchPending || this.isDragging) {
              if (this.isDragging) {
                const btnLeft = mapMouseButton(1);
                testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, this.pendingPx, this.pendingPy, btnLeft);
              }
              this.touchPending = false;
              this.isDragging = false;
            }

            // 计算双指中点
            let midX = 0, midY = 0;
            for (let i = 0; i < ev.touches.length; i++) {
              midX += vp2px(ev.touches[i].x);
              midY += vp2px(ev.touches[i].y);
            }
            midX = Math.round(midX / ev.touches.length);
            midY = Math.round(midY / ev.touches.length);

            if (!this.twoFingerActive) {
              // 进入双指模式
              this.twoFingerActive = true;
              this.twoFingerLastMidX = midX;
              this.twoFingerLastMidY = midY;
              this.twoFingerAccumY = 0;
              this.twoFingerAccumX = 0;
              this.twoFingerTl = testNapi.findToplevelAt(midX, midY) as number ?? 0;
              this.scrollLogCounter = 0;
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] SCROLL-START tl=%{public}d fingers=%{public}d',
                this.twoFingerTl, ev.touches.length);
            } else {
              // 累积位移 → 超过阈值发送离散步
              this.twoFingerAccumY += this.twoFingerLastMidY - midY;  // 向上=正=向下滚
              this.twoFingerAccumX += midX - this.twoFingerLastMidX;  // 向右=正=向右滚
              this.twoFingerLastMidX = midX;
              this.twoFingerLastMidY = midY;

              if (this.twoFingerTl > 0) {
                // 垂直滚动
                while (Math.abs(this.twoFingerAccumY) >= DesktopPage.SCROLL_STEP_PX) {
                  const sign = this.twoFingerAccumY > 0 ? 1 : -1;
                  testNapi.sendScrollEvent(this.twoFingerTl, 0, sign, DesktopPage.SCROLL_STEP_PX, midX, midY);
                  this.twoFingerAccumY -= sign * DesktopPage.SCROLL_STEP_PX;
                  if (++this.scrollLogCounter % 5 === 0) {
                    hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] SCROLL-V tl=%{public}d',
                      this.twoFingerTl);
                  }
                }
                // 水平滚动
                while (Math.abs(this.twoFingerAccumX) >= DesktopPage.SCROLL_STEP_PX) {
                  const sign = this.twoFingerAccumX > 0 ? 1 : -1;
                  testNapi.sendScrollEvent(this.twoFingerTl, 1, sign, DesktopPage.SCROLL_STEP_PX, midX, midY);
                  this.twoFingerAccumX -= sign * DesktopPage.SCROLL_STEP_PX;
                }
              }
            }
            return;
          }

          // ── 单指模式: 恢复双指状态 ──
          if (this.twoFingerActive) {
            this.twoFingerActive = false;
            hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] SCROLL-END');
            return;
          }

          const t = ev.changedTouches[0];
          if (!t) return;
          const px = Math.round(vp2px(t.x));
          const py = Math.round(vp2px(t.y));
          InputRouter.getInstance().rememberPointer(px, py);

          if (ev.type === TouchType.Down) {
            // 查找目标 toplevel (px,py 为物理坐标, findToplevelAt 内部通过 viewport 转逻辑坐标)
            const tl: number = testNapi.findToplevelAt(px, py) as number;
            if (tl <= 0) {
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] TOUCH skipped (no toplevel at %{public}d,%{public}d)', px, py);
              return;
            }
            hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] TOUCH tl=%{public}d px=(%{public}d,%{public}d)', tl, px, py);
            testNapi.raiseToplevel(tl);
            InputRouter.getInstance().setActiveToplevel(tl);
            // 进入 PENDING 状态: 暂不发送事件, 等判定长按/拖拽/点击
            this.touchPending = true;
            this.isDragging = false;
            this.touchStartTime = Date.now();
            this.touchStartPx = px;
            this.touchStartPy = py;
            this.pendingTl = tl;
            this.pendingPx = px;
            this.pendingPy = py;
            this.motionLogCounter = 0;

          } else if (ev.type === TouchType.Move) {
            if (!this.touchPending && !this.isDragging) return;

            const dist = Math.abs(px - this.touchStartPx) + Math.abs(py - this.touchStartPy);

            if (this.touchPending && dist >= DesktopPage.DRAG_THRESHOLD) {
              // 进入拖拽模式: 补发 Press (Down 时未发)
              const btnLeft = mapMouseButton(1);
              this.touchPending = false;
              this.isDragging = true;
              // 打断双击序列 (拖拽不是点击)
              this.lastTapTime = 0;
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] DRAG-START tl=%{public}d px=(%{public}d,%{public}d) dist=%{public}d',
                this.pendingTl, px, py, dist);
              testNapi.sendPointerEvent(this.pendingTl, MouseAction.Press, this.pendingPx, this.pendingPy, btnLeft);
              testNapi.sendPointerEvent(this.pendingTl, MouseAction.Move, px, py, btnLeft);
            } else if (this.isDragging) {
              // 拖拽移动: 持续发送 Motion
              testNapi.sendPointerEvent(this.pendingTl, MouseAction.Move, px, py, 0);
              if (++this.motionLogCounter % 10 === 0) {
                hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] DRAG-MOVE tl=%{public}d px=(%{public}d,%{public}d) frame=%{public}d',
                  this.pendingTl, px, py, this.motionLogCounter);
              }
            }
            // PENDING 且未超过阈值: 不做任何事 (等 Up 判定长按/点击)

          } else if (ev.type === TouchType.Up) {
            if (this.isDragging) {
              // 拖拽结束
              const btnLeft = mapMouseButton(1);
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] DRAG-END tl=%{public}d px=(%{public}d,%{public}d)',
                this.pendingTl, px, py);
              testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, px, py, btnLeft);
              this.isDragging = false;

            } else if (this.touchPending) {
              // PENDING 状态: 按按下时长判定长按 vs 点击
              this.touchPending = false;
              const elapsed = Date.now() - this.touchStartTime;

              if (elapsed >= DesktopPage.LONG_PRESS_MS) {
                // 长按 → 右键
                const btnRight = mapMouseButton(2);
                this.lastTapTime = 0; // 长按打断双击序列
                hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] LONGPRESS->RIGHTCLICK tl=%{public}d elapsed=%{public}dms px=(%{public}d,%{public}d)',
                  this.pendingTl, elapsed, this.pendingPx, this.pendingPy);
                testNapi.sendPointerEvent(this.pendingTl, MouseAction.Press, this.pendingPx, this.pendingPy, btnRight);
                testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, this.pendingPx, this.pendingPy, btnRight);
              } else {
                // 短按 → 左键 或 双击
                const btnLeft = mapMouseButton(1);
                const now = Date.now();
                const dist = Math.abs(this.pendingPx - this.lastTapPx) + Math.abs(this.pendingPy - this.lastTapPy);
                const isDoubleTap = (this.lastTapTime > 0 && (now - this.lastTapTime) < DesktopPage.DOUBLE_TAP_MS
                                    && dist < DesktopPage.DOUBLE_TAP_DIST && this.pendingTl === this.lastTapTl);

                if (isDoubleTap) {
                  // 双击: 两个连续点击使用同一位置
                  this.lastTapTime = 0;
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Press, this.lastTapPx, this.lastTapPy, btnLeft);
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, this.lastTapPx, this.lastTapPy, btnLeft);
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Press, this.lastTapPx, this.lastTapPy, btnLeft);
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, this.lastTapPx, this.lastTapPy, btnLeft);
                  hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] DOUBLE-TAP tl=%{public}d px=(%{public}d,%{public}d)',
                    this.pendingTl, this.lastTapPx, this.lastTapPy);
                } else {
                  // 单击
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Press, this.pendingPx, this.pendingPy, btnLeft);
                  testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, this.pendingPx, this.pendingPy, btnLeft);
                  this.lastTapTime = now;
                  this.lastTapPx = this.pendingPx;
                  this.lastTapPy = this.pendingPy;
                  this.lastTapTl = this.pendingTl;
                  hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] TAP->LEFTCLICK tl=%{public}d px=(%{public}d,%{public}d)',
                    this.pendingTl, this.pendingPx, this.pendingPy);
                }
              }
            }
          } else if (ev.type === TouchType.Cancel) {
            // 系统取消触摸 (手势/通知等): 如果正在拖拽则补发 Release
            if (this.isDragging) {
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] CANCEL-DRAG tl=%{public}d px=(%{public}d,%{public}d)',
                this.pendingTl, px, py);
              const btnLeft = mapMouseButton(1);
              testNapi.sendPointerEvent(this.pendingTl, MouseAction.Release, px, py, btnLeft);
            } else {
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] CANCEL tl=%{public}d (no event sent)', this.pendingTl);
            }
            this.touchPending = false;
            this.isDragging = false;
          }
        } catch (e) {
          hilog.error(DOMAIN, 'CLICK-PIPE', '[ArkTS] TOUCH handler exception: %{public}s', JSON.stringify(e));
        }
      })

      // ── 物理鼠标: hover、按键与拖动直通 ──
      .onMouse((ev: MouseEvent) => {
        if (!this.eventGate.shouldHandleMouse(ev.source, ev.sourceTool)) return;
        this.noteHardwareActivity();
        try {
          // Physical mouse events are routed here exclusively. Touch-generated
          // mouse events are rejected by InputEventGate above.
          if (ev.action === MouseAction.Move) {
            const px = Math.round(vp2px(ev.x));
            const py = Math.round(vp2px(ev.y));
            let tl = this.rightBtnTl;
            if (tl <= 0) {
              tl = testNapi.findToplevelAt(px, py) as number;
              if (tl <= 0) return;
            }
            if (++this.hoverLogCounter % 120 === 0) {
              hilog.info(DOMAIN, 'CLICK-PIPE', '[ArkTS] MOUSE-MOVE tl=%{public}d px=(%{public}d,%{public}d) n=%{public}d',
                tl, px, py, this.hoverLogCounter);
            }
            testNapi.sendPointerEvent(tl, MouseAction.Move, px, py, 0);
            return;
          }
          if (ev.action !== MouseAction.Press && ev.action !== MouseAction.Release) return;
          const px = Math.round(vp2px(ev.x));
          const py = Math.round(vp2px(ev.y));
          const button = mapMouseButton(ev.button);
          if (button <= 0) return;
          if (ev.action === MouseAction.Press) {
            const tl: number = testNapi.findToplevelAt(px, py) as number;
            if (tl <= 0) {
              if (ev.button === MouseButton.Right) this.rightBtnTl = 0;
              return;
            }
            if (ev.button === MouseButton.Right) this.rightBtnTl = tl;
            testNapi.raiseToplevel(tl);
            InputRouter.getInstance().setActiveToplevel(tl);
            testNapi.sendPointerEvent(tl, MouseAction.Press, px, py, button);
          } else {
            const hit = testNapi.findToplevelAt(px, py) as number;
            const tl = ev.button === MouseButton.Right && this.rightBtnTl > 0 ? this.rightBtnTl : hit;
            if (tl > 0) testNapi.sendPointerEvent(tl, MouseAction.Release, px, py, button);
            if (ev.button === MouseButton.Right) this.rightBtnTl = 0;
          }
        } catch (e) {
          hilog.error(DOMAIN, 'CLICK-PIPE', '[ArkTS] MOUSE handler exception: %{public}s', JSON.stringify(e));
        }
      })

      // ── 滚轮事件 ──
      .onAxisEvent((ev?: AxisEvent) => {
        this.noteHardwareActivity();
        const rootId = WineWindowManager.getInstance().getDesktopRootId();
        if (rootId <= 0 || !ev) return;
        const wpx = Math.round(vp2px(ev.x));
        const wpy = Math.round(vp2px(ev.y));
        const vert = ev.getVerticalAxisValue();
        const horiz = ev.getHorizontalAxisValue();
        const step = ev.scrollStep ?? 0;
        const hit = testNapi.findToplevelAt(wpx, wpy) as number;
        const tl: number = hit > 0 ? hit : rootId;
        if (vert !== 0) testNapi.sendScrollEvent(tl, 0, vert, step, wpx, wpy);
        if (horiz !== 0) testNapi.sendScrollEvent(tl, 1, horiz, step, wpx, wpy);
      })

    }
    .width('100%').height('100%').backgroundColor('#000')
    .id('wine-desktop-input-root')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((ev: KeyEvent): void => this.handleHardwareKey(ev))
  }
}
