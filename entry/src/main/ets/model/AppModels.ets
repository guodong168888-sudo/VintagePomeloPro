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
  buttonOpacity: number;
  stickDeadzone: number;
  controls: VirtualControlDescriptor[];
  gamepadMappings: GamepadButtonMapping[];
}

export enum VirtualControlKind {
  BUTTON = 'button',
  DPAD = 'dpad',
  STICK = 'stick',
  TOUCHPAD = 'touchpad',
  MOUSE_BUTTON = 'mouse-button',
  SCROLL = 'scroll'
}

export interface VirtualControlDescriptor {
  id: string;
  label: string;
  kind: VirtualControlKind;
  evdevCode: number;
  xPercent: number;
  yPercent: number;
  size: number;
  opacity: number;
}

export interface GamepadButtonMapping {
  id: string;
  label: string;
  buttonCode: number;
  evdevCode: number;
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
    autoHideVirtualControls: true,
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
    name: '默认键鼠手柄',
    buttonOpacity: 72,
    stickDeadzone: 18,
    gamepadMappings: [
      { id: 'dpad-up', label: '方向键 ↑', buttonCode: 2012, evdevCode: 103 },
      { id: 'dpad-down', label: '方向键 ↓', buttonCode: 2013, evdevCode: 108 },
      { id: 'dpad-left', label: '方向键 ←', buttonCode: 2014, evdevCode: 105 },
      { id: 'dpad-right', label: '方向键 →', buttonCode: 2015, evdevCode: 106 },
      { id: 'a', label: 'A / 确认', buttonCode: 2301, evdevCode: 28 },
      { id: 'b', label: 'B / 返回', buttonCode: 2302, evdevCode: 1 },
      { id: 'x', label: 'X', buttonCode: 2304, evdevCode: 42 },
      { id: 'y', label: 'Y', buttonCode: 2305, evdevCode: 29 },
      { id: 'l1', label: 'L1', buttonCode: 2307, evdevCode: 16 },
      { id: 'r1', label: 'R1', buttonCode: 2308, evdevCode: 18 },
      { id: 'l2', label: 'L2', buttonCode: 2309, evdevCode: 15 },
      { id: 'r2', label: 'R2', buttonCode: 2310, evdevCode: 57 },
      { id: 'select', label: 'Select', buttonCode: 2311, evdevCode: 1 },
      { id: 'start', label: 'Start', buttonCode: 2312, evdevCode: 28 },
      { id: 'l3', label: 'L3', buttonCode: 2313, evdevCode: 1 },
      { id: 'r3', label: 'R3', buttonCode: 2314, evdevCode: 56 },
      { id: 'home', label: 'Home', buttonCode: 2315, evdevCode: 57 }
    ],
    controls: [
      { id: 'l2', label: 'L2', kind: VirtualControlKind.BUTTON, evdevCode: 15, xPercent: 3, yPercent: 4, size: 52, opacity: 78 },
      { id: 'l1', label: 'L1', kind: VirtualControlKind.BUTTON, evdevCode: 16, xPercent: 10, yPercent: 4, size: 52, opacity: 78 },
      { id: 'r1', label: 'R1', kind: VirtualControlKind.BUTTON, evdevCode: 18, xPercent: 78, yPercent: 4, size: 52, opacity: 78 },
      { id: 'r2', label: 'R2', kind: VirtualControlKind.BUTTON, evdevCode: 57, xPercent: 85, yPercent: 4, size: 52, opacity: 78 },
      { id: 'up', label: '↑', kind: VirtualControlKind.DPAD, evdevCode: 103, xPercent: 9, yPercent: 65, size: 44, opacity: 100 },
      { id: 'left', label: '←', kind: VirtualControlKind.DPAD, evdevCode: 105, xPercent: 4, yPercent: 73, size: 44, opacity: 100 },
      { id: 'down', label: '↓', kind: VirtualControlKind.DPAD, evdevCode: 108, xPercent: 9, yPercent: 73, size: 44, opacity: 100 },
      { id: 'right', label: '→', kind: VirtualControlKind.DPAD, evdevCode: 106, xPercent: 14, yPercent: 73, size: 44, opacity: 100 },
      { id: 'y', label: 'Y', kind: VirtualControlKind.BUTTON, evdevCode: 21, xPercent: 83, yPercent: 62, size: 48, opacity: 100 },
      { id: 'b', label: 'B', kind: VirtualControlKind.BUTTON, evdevCode: 48, xPercent: 89, yPercent: 69, size: 48, opacity: 100 },
      { id: 'x', label: 'X', kind: VirtualControlKind.BUTTON, evdevCode: 45, xPercent: 77, yPercent: 69, size: 48, opacity: 100 },
      { id: 'a', label: 'A', kind: VirtualControlKind.BUTTON, evdevCode: 30, xPercent: 83, yPercent: 76, size: 48, opacity: 100 },
      { id: 'esc', label: 'Esc', kind: VirtualControlKind.BUTTON, evdevCode: 1, xPercent: 41, yPercent: 87, size: 50, opacity: 100 },
      { id: 'enter', label: 'Enter', kind: VirtualControlKind.BUTTON, evdevCode: 28, xPercent: 48, yPercent: 87, size: 58, opacity: 100 },
      { id: 'space', label: 'Space', kind: VirtualControlKind.BUTTON, evdevCode: 57, xPercent: 56, yPercent: 87, size: 58, opacity: 100 },
      { id: 'left-stick', label: 'L', kind: VirtualControlKind.STICK, evdevCode: 0, xPercent: 17, yPercent: 49, size: 88, opacity: 68 },
      { id: 'right-stick', label: 'R', kind: VirtualControlKind.STICK, evdevCode: 1, xPercent: 70, yPercent: 49, size: 88, opacity: 68 },
      { id: 'touchpad', label: '触控板', kind: VirtualControlKind.TOUCHPAD, evdevCode: 0, xPercent: 34, yPercent: 49, size: 150, opacity: 48 },
      { id: 'mouse-left', label: 'L', kind: VirtualControlKind.MOUSE_BUTTON, evdevCode: 272, xPercent: 38, yPercent: 76, size: 48, opacity: 75 },
      { id: 'mouse-right', label: 'R', kind: VirtualControlKind.MOUSE_BUTTON, evdevCode: 273, xPercent: 45, yPercent: 76, size: 48, opacity: 75 },
      { id: 'scroll', label: '滚轮', kind: VirtualControlKind.SCROLL, evdevCode: 0, xPercent: 62, yPercent: 58, size: 78, opacity: 55 }
    ]
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
