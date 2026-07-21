import testNapi from 'libentry.so';
import { DisplayMode, InputDiagnostics, WineInputSession } from '../model/AppModels';
import { InputRouter } from './InputRouter';
import { InputStateTracker, ReleasedInputState } from './InputStateTracker';

export type InputDiagnosticsListener = (diagnostics: InputDiagnostics) => void;

/**
 * VirtualInputOverlay 的唯一输入出口。按下状态以 source 为单位引用计数，
 * 所有取消、切换、失焦都通过 releaseAll 回收，避免 Wine 侧残留卡键。
 */
export class InputDispatcher {
  private static instance: InputDispatcher | null = null;
  private session: WineInputSession = {
    sessionId: '', displayMode: DisplayMode.DESKTOP, toplevelId: 0, active: false
  };
  private tracker: InputStateTracker = new InputStateTracker();
  private injectedEvents: number = 0;
  private diagnosticsListeners: Set<InputDiagnosticsListener> = new Set<InputDiagnosticsListener>();

  static getInstance(): InputDispatcher {
    if (!InputDispatcher.instance) InputDispatcher.instance = new InputDispatcher();
    return InputDispatcher.instance;
  }

  setSession(session: WineInputSession): void {
    if (this.session.sessionId !== session.sessionId || this.session.toplevelId !== session.toplevelId) {
      this.releaseAll('session-change');
    }
    this.session = session;
    if (session.toplevelId > 0) InputRouter.getInstance().setActiveToplevel(session.toplevelId);
    this.publishDiagnostics();
  }

  getSession(): WineInputSession {
    return {
      sessionId: this.session.sessionId,
      displayMode: this.session.displayMode,
      toplevelId: this.session.toplevelId,
      active: this.session.active
    };
  }

  setActiveToplevel(toplevelId: number): void {
    if (toplevelId <= 0) return;
    if (this.session.toplevelId !== toplevelId) this.releaseAll('toplevel-change');
    this.session.toplevelId = toplevelId;
    InputRouter.getInstance().setActiveToplevel(toplevelId);
    this.publishDiagnostics();
  }

  resolveToplevel(x: number, y: number, allowFocusChange: boolean = true): number {
    let found = 0;
    try { found = testNapi.findToplevelAt(Math.round(x), Math.round(y)) as number; } catch (_) {}
    if (found > 0 && allowFocusChange) this.setActiveToplevel(found);
    return found > 0 ? found : this.session.toplevelId;
  }

  pressKey(source: string, evdevCode: number): void {
    if (!this.session.active || !this.tracker.pressKey(source, evdevCode)) return;
    InputRouter.getInstance().sendKey(evdevCode, true);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  releaseKey(source: string, evdevCode: number): void {
    if (!this.tracker.releaseKey(source, evdevCode)) return;
    InputRouter.getInstance().sendKey(evdevCode, false);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  pointerDown(source: string, x: number, y: number, button: number = 272): void {
    if (!this.session.active) return;
    this.resolveToplevel(x, y);
    this.tracker.markPointer(source);
    this.buttonDown(source, button, x, y);
    this.publishDiagnostics();
  }

  buttonDown(source: string, button: number, x?: number, y?: number): void {
    if (!this.session.active || !this.tracker.pressButton(source, button)) return;
    if (x !== undefined && y !== undefined) InputRouter.getInstance().sendPointer(MouseAction.Press, x, y, button);
    else InputRouter.getInstance().sendPointerButton(MouseAction.Press, button);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  pointerMove(source: string, x: number, y: number, pointerActive: boolean = true): void {
    if (!this.session.active) return;
    if (pointerActive) this.tracker.markPointer(source);
    // 已按下的指针必须保持最初归属。否则拖动越过 popup 边界会触发
    // toplevel 切换并提前释放按键，表现为 Wine 中断拖拽。
    const state = this.tracker.snapshot();
    this.resolveToplevel(x, y, state.heldButtons === 0);
    InputRouter.getInstance().sendPointer(MouseAction.Move, x, y, 0);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  pointerDelta(source: string, deltaX: number, deltaY: number): void {
    if (!this.session.active) return;
    this.tracker.markPointer(source);
    InputRouter.getInstance().sendPointerDelta(deltaX, deltaY);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  pointerUp(source: string, x: number, y: number, button: number = 272): void {
    this.buttonUp(source, button, x, y);
    this.tracker.clearPointer(source);
    this.publishDiagnostics();
  }

  buttonUp(source: string, button: number, x?: number, y?: number): void {
    if (!this.tracker.releaseButton(source, button)) return;
    if (x !== undefined && y !== undefined) InputRouter.getInstance().sendPointer(MouseAction.Release, x, y, button);
    else InputRouter.getInstance().sendPointerButton(MouseAction.Release, button);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  scroll(source: string, axis: number, value: number, step: number = 40): void {
    if (!this.session.active || value === 0) return;
    this.tracker.markPointer(source);
    InputRouter.getInstance().sendScrollAtPointer(axis, value, step);
    this.injectedEvents++;
    this.publishDiagnostics();
  }

  releaseSource(source: string): void {
    this.releaseTracked(this.tracker.releaseSource(source));
    this.publishDiagnostics();
  }

  releaseAll(_reason: string): void {
    this.releaseTracked(this.tracker.releaseAll());
    // 兼容主窗口的实体输入路径：即使它没有经过 tracker，也必须收尾。
    InputRouter.getInstance().releaseAllKeys();
    this.publishDiagnostics();
  }

  subscribeDiagnostics(listener: InputDiagnosticsListener): void {
    this.diagnosticsListeners.add(listener);
    listener(this.getDiagnostics());
  }

  unsubscribeDiagnostics(listener: InputDiagnosticsListener): void {
    this.diagnosticsListeners.delete(listener);
  }

  getDiagnostics(): InputDiagnostics {
    const state = this.tracker.snapshot();
    return {
      sessionId: this.session.sessionId,
      activePointers: state.activePointers,
      heldKeys: state.heldKeys,
      heldButtons: state.heldButtons,
      injectedEvents: this.injectedEvents
    };
  }

  private releaseTracked(released: ReleasedInputState): void {
    released.keys.forEach((code: number): void => {
      InputRouter.getInstance().sendKey(code, false);
      this.injectedEvents++;
    });
    released.buttons.forEach((button: number): void => {
      InputRouter.getInstance().sendPointerButton(MouseAction.Release, button);
      this.injectedEvents++;
    });
  }

  private publishDiagnostics(): void {
    const diagnostics = this.getDiagnostics();
    this.diagnosticsListeners.forEach((listener: InputDiagnosticsListener): void => listener(diagnostics));
  }
}
