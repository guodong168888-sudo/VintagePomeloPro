import { GamepadSink, KeyMouseGamepadSink } from './InputRouter';
import { GamepadButtonMapping, createDefaultInputProfile } from '../model/AppModels';
import testNapi from 'libentry.so';

export type GamepadConnectionListener = (connected: boolean) => void;
export type GamepadActivityListener = () => void;
export type ControllerOutputMode = 'dinput' | 'keyboard_legacy';

export class GamepadManager {
  private static instance: GamepadManager | null = null;
  private sink: GamepadSink = new KeyMouseGamepadSink();
  private pressed: Set<number> = new Set<number>();
  private deadzone: number = 0.18;
  private initialized: boolean = false;
  private axisKeys: Set<number> = new Set<number>();
  private connected: boolean = false;
  private outputMode: ControllerOutputMode = 'dinput';
  private connectionListeners: Set<GamepadConnectionListener> = new Set<GamepadConnectionListener>();
  private activityListeners: Set<GamepadActivityListener> = new Set<GamepadActivityListener>();
  private buttonMappings: Map<number, number> = new Map<number, number>(
    createDefaultInputProfile().gamepadMappings.map((mapping: GamepadButtonMapping): [number, number] =>
      [mapping.buttonCode, mapping.evdevCode])
  );

  static getInstance(): GamepadManager {
    if (!GamepadManager.instance) GamepadManager.instance = new GamepadManager();
    return GamepadManager.instance;
  }

  setSink(sink: GamepadSink): void {
    this.releaseAll();
    this.sink = sink;
  }

  setOutputMode(mode: ControllerOutputMode): void {
    if (this.outputMode === mode) return;
    this.releaseAll();
    this.outputMode = mode;
    try {
      testNapi.controllerSetOutputMode(mode);
      if (mode === 'dinput') {
        testNapi.controllerSetEnabled(true);
      }
    } catch (_) {
    }
  }

  getOutputMode(): ControllerOutputMode {
    return this.outputMode;
  }

  setButtonMappings(mappings: GamepadButtonMapping[]): void {
    this.releaseAll();
    const source = mappings.length > 0 ? mappings : createDefaultInputProfile().gamepadMappings;
    this.buttonMappings = new Map<number, number>(
      source.map((mapping: GamepadButtonMapping): [number, number] => [mapping.buttonCode, mapping.evdevCode])
    );
  }

  initialize(deadzonePercent: number, outputMode?: ControllerOutputMode): void {
    this.setDeadzone(deadzonePercent);
    if (outputMode) this.outputMode = outputMode;
    try {
      testNapi.controllerSetOutputMode(this.outputMode);
      if (this.outputMode === 'dinput') testNapi.controllerSetEnabled(true);
    } catch (_) {
    }
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
      if (this.outputMode === 'dinput') {
        testNapi.controllerSetEnabled(true);
      }
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
    // dinput: Physical already feeds ControllerHub in native; skip evdev mapping.
    if (this.outputMode === 'dinput') {
      if (this.buttonMappings.has(keyCode)) {
        this.notifyActivity();
        return true;
      }
      return false;
    }
    const evdev = this.buttonMappings.get(keyCode);
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
    if (this.outputMode === 'dinput') {
      if (Math.abs(x) >= this.deadzone || Math.abs(y) >= this.deadzone) this.notifyActivity();
      return;
    }
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
    if (this.outputMode === 'dinput') {
      const active = Math.abs(x) >= this.deadzone || Math.abs(y) >= this.deadzone;
      if (active) this.notifyActivity();
      return;
    }
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
    if (this.outputMode === 'dinput') {
      // Overlay / key-emulation leftovers only. Physical is owned by native kit.
      try { testNapi.controllerResetSource(0); } catch (_) {}
    }
  }
}
