export enum AppSource {
  BUILTIN = 'builtin',
  DOWNLOAD = 'download'
}

export enum LaunchKind {
  WINE_EXE = 'wine-exe',
  WINE_SYSTEM = 'wine-system',
  WINE_DESKTOP = 'wine-desktop',
  HARMONY_ABILITY = 'harmony-ability',
  NATIVE_TOOL = 'native-tool',
  OTHER_ENGINE = 'other-engine'
}

export enum DisplayMode {
  DESKTOP = 'desktop',
  SINGLE_APP = 'single-app'
}

export enum EngineState {
  STOPPED = 'stopped',
  PREPARING = 'preparing',
  READY = 'ready',
  SWITCHING = 'switching',
  ERROR = 'error'
}

export enum SessionState {
  STARTING = 'starting',
  RUNNING = 'running',
  BACKGROUND = 'background',
  STOPPED = 'stopped',
  ERROR = 'error'
}

export enum ViewMode {
  GRID = 'grid',
  COMPACT = 'compact',
  LARGE = 'large'
}

export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

export interface LaunchTarget {
  kind: LaunchKind;
  executable: string;
  arguments: string[];
  workingDirectory: string;
}

export interface AppDescriptor {
  id: string;
  title: string;
  source: AppSource;
  directory: string;
  coverPath: string;
  available: boolean;
  launchTarget: LaunchTarget;
  displayModeOverride: DisplayMode | null;
}

export interface AppSettings {
  appId: string;
  customTitle: string;
  customCover: string;
  /** Kept separately from catalog discovery so a moved game can stay starred. */
  favorite: boolean;
  executable: string;
  arguments: string[];
  workingDirectory: string;
  displayModeOverride: DisplayMode | null;
  inputProfileId: string;
  prefixId: string;
}

export interface GlobalSettings {
  defaultDisplayMode: DisplayMode;
  viewMode: ViewMode;
  themeMode: ThemeMode;
  useGlassEffect: boolean;
  usePageBackground: boolean;
  showVirtualControls: boolean;
  autoHideVirtualControls: boolean;
  controlOpacity: number;
  gamepadDeadzone: number;
  outputScale: number;
}

export interface RuntimeSession {
  sessionId: string;
  appId: string;
  executable: string;
  pid: number;
  displayMode: DisplayMode;
  state: SessionState;
  toplevelId: number;
  startedAt: number;
}

/** ArkTS 覆盖层所使用的 Wine 会话视图，不等同于 Wine/NCP 子进程。 */
export interface WineInputSession {
  sessionId: string;
  displayMode: DisplayMode;
  toplevelId: number;
  active: boolean;
}

export interface InputDiagnostics {
  sessionId: string;
  activePointers: number;
  heldKeys: number;
  heldButtons: number;
  injectedEvents: number;
}

export interface NativeProcessInfo {
  pid: number;
  name: string;
  path: string;
  state: string;
  sessionId?: string;
}

export interface NativeLaunchResult {
  pid: number;
  sessionId: string;
  reused: boolean;
}

export interface NativeWineSessionInfo {
  pid: number;
  sessionId: string;
  path: string;
  state: string;
  toplevelId: number;
}

export interface InputProfile {
  id: string;
  name: string;
  schemaVersion: number;
  virtualKeyConfig: VirtualKeyConfig;
  layoutLandscape: VirtualGamepadLayout;
  layoutPortrait: VirtualGamepadLayout;
  virtualKeyMappings: VirtualKeyMapping[];
  gamepadMappings: GamepadButtonMapping[];
  /** VintagePomelo-compatible optional free-key overlay. */
  freeButtonsConfig: FreeButtonsConfig;
}

// These models intentionally follow VintagePomelo's virtual gamepad contract.
// A direction group has exactly one renderer: d-pad or joystick, never both.
export enum DirectionControlMode {
  DPAD = 'dpad',
  JOYSTICK = 'joystick'
}

export enum VirtualKeyColorScheme {
  DEFAULT = 'default',
  WHITE = 'white'
}

export interface VirtualKeyConfig {
  transparency: number;
  joystickTransparency: number;
  joystickSize: number;
  buttonSize: number;
  showButtonA: boolean;
  showButtonB: boolean;
  showButtonX: boolean;
  showButtonY: boolean;
  showButtonL: boolean;
  showButtonR: boolean;
  showButtonMenu: boolean;
  showButtonShift: boolean;
  showButtonCtrl: boolean;
  joystickDeadzone: number;
  eightDirectionJoystick: boolean;
  dpadMode: DirectionControlMode;
  colorScheme: VirtualKeyColorScheme;
}

export enum VirtualKey {
  DPAD_UP = 'dpad_up',
  DPAD_DOWN = 'dpad_down',
  DPAD_LEFT = 'dpad_left',
  DPAD_RIGHT = 'dpad_right',
  BUTTON_A = 'button_a',
  BUTTON_B = 'button_b',
  BUTTON_X = 'button_x',
  BUTTON_Y = 'button_y',
  BUTTON_L = 'button_l',
  BUTTON_R = 'button_r',
  BUTTON_MENU = 'button_menu',
  BUTTON_SHIFT = 'button_shift',
  BUTTON_CTRL = 'button_ctrl'
}

export interface VirtualKeyMapping {
  virtualKey: VirtualKey;
  evdevCode: number;
  keyLabel: string;
}

export interface ButtonGroupPosition {
  centerX: number;
  centerY: number;
}

export interface VirtualGamepadLayout {
  direction: ButtonGroupPosition;
  leftTrigger: ButtonGroupPosition;
  leftBumper: ButtonGroupPosition;
  action: ButtonGroupPosition;
  rightBumper: ButtonGroupPosition;
  rightTrigger: ButtonGroupPosition;
  aux: ButtonGroupPosition;
}

export interface GamepadButtonMapping {
  id: string;
  label: string;
  buttonCode: number;
  evdevCode: number;
}

/**
 * Free buttons deliberately remain a separate mode from the grouped gamepad.
 * The fixed gamepad still moves and scales by group; free buttons use the
 * familiar VintagePomelo gamepad/radial presets and never re-introduce the
 * former per-control coordinate editor.
 */
export enum FreeButtonLayoutMode {
  GAMEPAD = 'gamepad',
  RADIAL = 'radial'
}

export interface FreeButton {
  id: string;
  evdevCode: number;
  keyLabel: string;
}

export interface FreeButtonsConfig {
  enabled: boolean;
  layoutMode: FreeButtonLayoutMode;
  buttons: FreeButton[];
  radialScale: number;
  gamepadSpacing: number;
}

export interface FreeButtonPosition {
  offsetX: number;
  offsetY: number;
}

export const DEFAULT_FREE_BUTTONS_CONFIG: FreeButtonsConfig = {
  enabled: false,
  layoutMode: FreeButtonLayoutMode.GAMEPAD,
  buttons: [],
  radialScale: 100,
  gamepadSpacing: 100
};

export function cloneFreeButtonsConfig(config?: FreeButtonsConfig): FreeButtonsConfig {
  const value = config ?? DEFAULT_FREE_BUTTONS_CONFIG;
  return {
    enabled: value.enabled ?? DEFAULT_FREE_BUTTONS_CONFIG.enabled,
    layoutMode: value.layoutMode === FreeButtonLayoutMode.RADIAL ? FreeButtonLayoutMode.RADIAL : FreeButtonLayoutMode.GAMEPAD,
    buttons: (value.buttons ?? []).slice(0, 8).map((button: FreeButton): FreeButton => ({
      id: button.id,
      evdevCode: button.evdevCode,
      keyLabel: button.keyLabel
    })),
    radialScale: value.radialScale ?? DEFAULT_FREE_BUTTONS_CONFIG.radialScale,
    gamepadSpacing: value.gamepadSpacing ?? DEFAULT_FREE_BUTTONS_CONFIG.gamepadSpacing
  };
}

export function generateFreeButtonId(): string {
  return 'free-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 0x10000).toString(36);
}

/** Same arrangement and scaling contract used by VintagePomelo's free mode. */
export function computeGamepadPositions(count: number, spacing: number = 100): FreeButtonPosition[] {
  const unit = 55 * Math.max(0.8, Math.min(1.5, spacing / 100));
  const positions: FreeButtonPosition[] = [];
  if (count <= 0) return positions;
  if (count === 1) return [{ offsetX: 0, offsetY: 0 }];
  if (count === 2) return [{ offsetX: -unit * 0.5, offsetY: 0 }, { offsetX: unit * 0.5, offsetY: 0 }];
  if (count === 3) return [{ offsetX: -unit * 0.5, offsetY: -unit * 0.35 }, { offsetX: unit * 0.5, offsetY: -unit * 0.35 }, { offsetX: 0, offsetY: unit * 0.35 }];
  positions.push(
    { offsetX: unit * 0.82, offsetY: 0 }, { offsetX: 0, offsetY: unit * 0.82 },
    { offsetX: -unit * 0.82, offsetY: 0 }, { offsetX: 0, offsetY: -unit * 0.82 }
  );
  if (count >= 5) positions.push({ offsetX: count === 5 ? unit * 0.6 : -unit * 0.6, offsetY: -unit * 1.85 });
  if (count >= 6) positions.push({ offsetX: unit * 0.6, offsetY: -unit * 1.85 });
  if (count >= 7) positions.push({ offsetX: -unit * 0.6, offsetY: -unit * 2.9 });
  if (count >= 8) positions.push({ offsetX: unit * 0.6, offsetY: -unit * 2.9 });
  return positions;
}

export function computeRadialPositions(count: number, radius: number): FreeButtonPosition[] {
  const positions: FreeButtonPosition[] = [];
  const safeCount = Math.max(1, count);
  for (let index = 0; index < count; index++) {
    const angle = -Math.PI / 2 + (Math.PI * 2 * index / safeCount);
    positions.push({ offsetX: Math.cos(angle) * radius, offsetY: Math.sin(angle) * radius });
  }
  return positions;
}

export const DEFAULT_GAMEPAD_LAYOUT: VirtualGamepadLayout = {
  direction: { centerX: 0.13, centerY: 0.70 },
  leftTrigger: { centerX: 0.075, centerY: 0.45 },
  leftBumper: { centerX: 0.16, centerY: 0.45 },
  action: { centerX: 0.87, centerY: 0.70 },
  rightBumper: { centerX: 0.84, centerY: 0.45 },
  rightTrigger: { centerX: 0.925, centerY: 0.45 },
  aux: { centerX: 0.50, centerY: 0.10 }
};

export const DEFAULT_GAMEPAD_LAYOUT_PORTRAIT: VirtualGamepadLayout = {
  direction: { centerX: 0.16, centerY: 0.83 },
  leftTrigger: { centerX: 0.09, centerY: 0.66 },
  leftBumper: { centerX: 0.23, centerY: 0.66 },
  action: { centerX: 0.84, centerY: 0.81 },
  rightBumper: { centerX: 0.77, centerY: 0.66 },
  rightTrigger: { centerX: 0.91, centerY: 0.66 },
  aux: { centerX: 0.50, centerY: 0.65 }
};

export const DEFAULT_VIRTUAL_KEY_CONFIG: VirtualKeyConfig = {
  transparency: 40,
  joystickTransparency: 50,
  joystickSize: 100,
  buttonSize: 100,
  showButtonA: true,
  showButtonB: true,
  showButtonX: true,
  showButtonY: true,
  showButtonL: true,
  showButtonR: true,
  showButtonMenu: true,
  showButtonShift: true,
  showButtonCtrl: true,
  joystickDeadzone: 15,
  eightDirectionJoystick: true,
  dpadMode: DirectionControlMode.DPAD,
  colorScheme: VirtualKeyColorScheme.DEFAULT
};

export function cloneVirtualKeyConfig(config: VirtualKeyConfig): VirtualKeyConfig {
  return {
    transparency: config.transparency ?? DEFAULT_VIRTUAL_KEY_CONFIG.transparency,
    joystickTransparency: config.joystickTransparency ?? DEFAULT_VIRTUAL_KEY_CONFIG.joystickTransparency,
    joystickSize: config.joystickSize ?? DEFAULT_VIRTUAL_KEY_CONFIG.joystickSize,
    buttonSize: config.buttonSize ?? DEFAULT_VIRTUAL_KEY_CONFIG.buttonSize,
    showButtonA: config.showButtonA ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonA,
    showButtonB: config.showButtonB ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonB,
    showButtonX: config.showButtonX ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonX,
    showButtonY: config.showButtonY ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonY,
    showButtonL: config.showButtonL ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonL,
    showButtonR: config.showButtonR ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonR,
    showButtonMenu: config.showButtonMenu ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonMenu,
    showButtonShift: config.showButtonShift ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonShift,
    showButtonCtrl: config.showButtonCtrl ?? DEFAULT_VIRTUAL_KEY_CONFIG.showButtonCtrl,
    joystickDeadzone: config.joystickDeadzone ?? DEFAULT_VIRTUAL_KEY_CONFIG.joystickDeadzone,
    eightDirectionJoystick: config.eightDirectionJoystick ?? DEFAULT_VIRTUAL_KEY_CONFIG.eightDirectionJoystick,
    dpadMode: config.dpadMode ?? DEFAULT_VIRTUAL_KEY_CONFIG.dpadMode,
    colorScheme: config.colorScheme ?? DEFAULT_VIRTUAL_KEY_CONFIG.colorScheme
  };
}

export function cloneGamepadLayout(layout: VirtualGamepadLayout,
  defaults: VirtualGamepadLayout = DEFAULT_GAMEPAD_LAYOUT): VirtualGamepadLayout {
  return {
    direction: { centerX: layout.direction?.centerX ?? defaults.direction.centerX, centerY: layout.direction?.centerY ?? defaults.direction.centerY },
    leftTrigger: { centerX: layout.leftTrigger?.centerX ?? defaults.leftTrigger.centerX, centerY: layout.leftTrigger?.centerY ?? defaults.leftTrigger.centerY },
    leftBumper: { centerX: layout.leftBumper?.centerX ?? defaults.leftBumper.centerX, centerY: layout.leftBumper?.centerY ?? defaults.leftBumper.centerY },
    action: { centerX: layout.action?.centerX ?? defaults.action.centerX, centerY: layout.action?.centerY ?? defaults.action.centerY },
    rightBumper: { centerX: layout.rightBumper?.centerX ?? defaults.rightBumper.centerX, centerY: layout.rightBumper?.centerY ?? defaults.rightBumper.centerY },
    rightTrigger: { centerX: layout.rightTrigger?.centerX ?? defaults.rightTrigger.centerX, centerY: layout.rightTrigger?.centerY ?? defaults.rightTrigger.centerY },
    aux: { centerX: layout.aux?.centerX ?? defaults.aux.centerX, centerY: layout.aux?.centerY ?? defaults.aux.centerY }
  };
}

export function normalizeLaunchPath(path: string): string {
  return path.trim().replace(/\\/g, '/').replace(/\/+/g, '/').toLowerCase();
}

export function stableAppId(source: AppSource, path: string): string {
  const value = source + ':' + normalizeLaunchPath(path);
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return source + '-' + (hash >>> 0).toString(16).padStart(8, '0');
}

export function createDefaultGlobalSettings(): GlobalSettings {
  return {
    defaultDisplayMode: DisplayMode.DESKTOP,
    viewMode: ViewMode.GRID,
    themeMode: ThemeMode.SYSTEM,
    useGlassEffect: true,
    usePageBackground: false,
    showVirtualControls: true,
    // 独立 ArkTS 覆盖层默认保持可见，避免实体输入后无法恢复控制层。
    autoHideVirtualControls: false,
    controlOpacity: 72,
    gamepadDeadzone: 18,
    outputScale: 100
  };
}

export function createDefaultAppSettings(appId: string): AppSettings {
  return {
    appId: appId,
    customTitle: '',
    customCover: '',
    favorite: false,
    executable: '',
    arguments: [],
    workingDirectory: '',
    displayModeOverride: null,
    inputProfileId: 'default',
    prefixId: 'default'
  };
}

export function createDefaultInputProfile(): InputProfile {
  return {
    id: 'default',
    name: 'Vintage 默认手柄布局',
    schemaVersion: 3,
    virtualKeyConfig: cloneVirtualKeyConfig(DEFAULT_VIRTUAL_KEY_CONFIG),
    layoutLandscape: cloneGamepadLayout(DEFAULT_GAMEPAD_LAYOUT),
    layoutPortrait: cloneGamepadLayout(DEFAULT_GAMEPAD_LAYOUT_PORTRAIT, DEFAULT_GAMEPAD_LAYOUT_PORTRAIT),
    virtualKeyMappings: [
      { virtualKey: VirtualKey.DPAD_UP, evdevCode: 103, keyLabel: '↑' },
      { virtualKey: VirtualKey.DPAD_DOWN, evdevCode: 108, keyLabel: '↓' },
      { virtualKey: VirtualKey.DPAD_LEFT, evdevCode: 105, keyLabel: '←' },
      { virtualKey: VirtualKey.DPAD_RIGHT, evdevCode: 106, keyLabel: '→' },
      { virtualKey: VirtualKey.BUTTON_A, evdevCode: 57, keyLabel: 'Space' },
      { virtualKey: VirtualKey.BUTTON_B, evdevCode: 45, keyLabel: 'X' },
      { virtualKey: VirtualKey.BUTTON_X, evdevCode: 30, keyLabel: 'A' },
      { virtualKey: VirtualKey.BUTTON_Y, evdevCode: 31, keyLabel: 'S' },
      { virtualKey: VirtualKey.BUTTON_L, evdevCode: 16, keyLabel: 'Q' },
      { virtualKey: VirtualKey.BUTTON_R, evdevCode: 17, keyLabel: 'W' },
      { virtualKey: VirtualKey.BUTTON_MENU, evdevCode: 1, keyLabel: 'Esc' },
      { virtualKey: VirtualKey.BUTTON_SHIFT, evdevCode: 42, keyLabel: 'Shift' },
      { virtualKey: VirtualKey.BUTTON_CTRL, evdevCode: 29, keyLabel: 'Ctrl' }
    ],
    gamepadMappings: [
      { id: 'dpad-up', label: '方向键 ↑', buttonCode: 2012, evdevCode: 103 },
      { id: 'dpad-down', label: '方向键 ↓', buttonCode: 2013, evdevCode: 108 },
      { id: 'dpad-left', label: '方向键 ←', buttonCode: 2014, evdevCode: 105 },
      { id: 'dpad-right', label: '方向键 →', buttonCode: 2015, evdevCode: 106 },
      { id: 'a', label: 'A / 确认', buttonCode: 2301, evdevCode: 57 },
      { id: 'b', label: 'B / 返回', buttonCode: 2302, evdevCode: 45 },
      { id: 'x', label: 'X', buttonCode: 2304, evdevCode: 30 },
      { id: 'y', label: 'Y', buttonCode: 2305, evdevCode: 31 },
      { id: 'l1', label: 'L1', buttonCode: 2307, evdevCode: 16 },
      { id: 'r1', label: 'R1', buttonCode: 2308, evdevCode: 17 },
      { id: 'l2', label: 'L2', buttonCode: 2309, evdevCode: 42 },
      { id: 'r2', label: 'R2', buttonCode: 2310, evdevCode: 29 },
      { id: 'select', label: 'Select', buttonCode: 2311, evdevCode: 1 },
      { id: 'start', label: 'Start', buttonCode: 2312, evdevCode: 1 },
      { id: 'l3', label: 'L3', buttonCode: 2313, evdevCode: 28 },
      { id: 'r3', label: 'R3', buttonCode: 2314, evdevCode: 57 },
      { id: 'home', label: 'Home', buttonCode: 2315, evdevCode: 63 }
    ],
    freeButtonsConfig: cloneFreeButtonsConfig(DEFAULT_FREE_BUTTONS_CONFIG)
  };
}

export function resolveDisplayMode(override: DisplayMode | null, defaultMode: DisplayMode): DisplayMode {
  return override ?? defaultMode;
}

export function canTransitionEngineState(from: EngineState, to: EngineState): boolean {
  if (from === to) return true;
  if (to === EngineState.ERROR || to === EngineState.STOPPED) return true;
  if (from === EngineState.STOPPED) return to === EngineState.PREPARING;
  if (from === EngineState.PREPARING) return to === EngineState.READY || to === EngineState.SWITCHING;
  if (from === EngineState.READY) return to === EngineState.SWITCHING;
  if (from === EngineState.SWITCHING) return to === EngineState.PREPARING;
  if (from === EngineState.ERROR) return to === EngineState.PREPARING;
  return false;
}
