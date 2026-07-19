import { GamepadSink, KeyMouseGamepadSink } from './InputRouter';
import testNapi from 'libentry.so';

const BUTTON_TO_EVDEV: Map<number, number> = new Map<number, number>([
  [2012, 103], [2013, 108], [2014, 105], [2015, 106],
  [2301, 28], [2302, 1], [2304, 42], [2305, 29],
  [2307, 16], [2308, 18], [2309, 15], [2310, 57],
  [2311, 1], [2312, 28], [2313, 1], [2314, 56], [2315, 57]
]);

export type GamepadConnectionListener = (connected: boolean) => void;
export type GamepadActivityListener = () => void;

export class GamepadManager {
  private static instance: GamepadManager | null = null;
  private sink: GamepadSink = new KeyMouseGamepadSink();
  private pressed: Set<number> = new Set<number>();
  private deadzone: number = 0.18;
  private initialized: boolean = false;
  private axisKeys: Set<number> = new Set<number>();
  private connected: boolean = false;
  private connectionListeners: Set<GamepadConnectionListener> = new Set<GamepadConnectionListener>();
  private activityListeners: Set<GamepadActivityListener> = new Set<GamepadActivityListener>();

  static getInstance(): GamepadManager {
    if (!GamepadManager.instance) GamepadManager.instance = new GamepadManager();
    return GamepadManager.instance;
  }

  setSink(sink: GamepadSink): void {
    this.releaseAll();
    this.sink = sink;
  }

  initialize(deadzonePercent: number): void {
    this.setDeadzone(deadzonePercent);
    if (this.initialized) return;
    this.initialized = true;
    testNapi.setGamepadButtonCallback((buttonCode: number, pressed: boolean) => {
      this.handleKey(buttonCode, pressed);
    });
    testNapi.setGamepadAxisCallback((axisType: number, x: number, y: number) => {
      this.handleAxis(axisType, x, y);
    });
    testNapi.setGamepadDeviceCallback((connected: boolean) => {
      this.connected = connected;
      if (!connected) this.releaseAll();
      this.connectionListeners.forEach((listener: GamepadConnectionListener) => listener(connected));
    });
    try {
      testNapi.initGameController();
      this.connected = testNapi.isGamepadConnected();
    } catch (_) {
      this.connected = false;
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  subscribeConnection(listener: GamepadConnectionListener): void {
    this.connectionListeners.add(listener);
    listener(this.connected);
  }

  unsubscribeConnection(listener: GamepadConnectionListener): void {
    this.connectionListeners.delete(listener);
  }

  subscribeActivity(listener: GamepadActivityListener): void {
    this.activityListeners.add(listener);
  }

  unsubscribeActivity(listener: GamepadActivityListener): void {
    this.activityListeners.delete(listener);
  }

  private notifyActivity(): void {
    this.activityListeners.forEach((listener: GamepadActivityListener) => listener());
  }

  setDeadzone(percent: number): void {
    this.deadzone = Math.max(0, Math.min(0.5, percent / 100));
  }

  handleKey(keyCode: number, pressed: boolean): boolean {
    const evdev = BUTTON_TO_EVDEV.get(keyCode);
    if (!evdev) return false;
    if (pressed && !this.pressed.has(evdev)) {
      this.pressed.add(evdev);
      this.notifyActivity();
      this.sink.onButton(evdev, true);
    } else if (!pressed && this.pressed.has(evdev)) {
      this.pressed.delete(evdev);
      this.notifyActivity();
      this.sink.onButton(evdev, false);
    }
    return true;
  }

  handleRightStick(x: number, y: number): void {
    const dx = Math.abs(x) >= this.deadzone ? Math.round(x * 18) : 0;
    const dy = Math.abs(y) >= this.deadzone ? Math.round(y * 18) : 0;
    if (dx !== 0 || dy !== 0) {
      this.notifyActivity();
      this.sink.onPointerDelta(dx, dy);
    }
  }

  private setAxisKey(code: number, pressed: boolean): void {
    const active = this.axisKeys.has(code);
    if (pressed === active) return;
    if (pressed) this.axisKeys.add(code); else this.axisKeys.delete(code);
    this.sink.onButton(code, pressed);
  }

  handleAxis(axisType: number, x: number, y: number): void {
    if (axisType === 1) {
      this.handleRightStick(x, y);
      return;
    }
    const active = Math.abs(x) >= this.deadzone || Math.abs(y) >= this.deadzone;
    if (active) this.notifyActivity();
    if (axisType === 0) {
      this.setAxisKey(30, x < -this.deadzone);
      this.setAxisKey(32, x > this.deadzone);
      this.setAxisKey(17, y < -this.deadzone);
      this.setAxisKey(31, y > this.deadzone);
    } else if (axisType === 2) {
      this.setAxisKey(105, x < -this.deadzone);
      this.setAxisKey(106, x > this.deadzone);
      this.setAxisKey(103, y < -this.deadzone);
      this.setAxisKey(108, y > this.deadzone);
    } else if (axisType === 3) {
      this.setAxisKey(29, x > this.deadzone);
    } else if (axisType === 4) {
      this.setAxisKey(57, x > this.deadzone);
    }
  }

  releaseAll(): void {
    this.pressed.forEach((evdev: number) => this.sink.onButton(evdev, false));
    this.pressed.clear();
    this.axisKeys.forEach((evdev: number) => this.sink.onButton(evdev, false));
    this.axisKeys.clear();
  }
}
