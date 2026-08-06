import { bindingToEvdevName, evdevNameToBinding } from '../common/EvdevKeyNames';
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

/** 用户可见显示模式：单应用全屏已移除，统一使用桌面模式。 */
export enum DisplayMode {
  DESKTOP = 'desktop'
}

/** Internal host topology. */
export enum WinePresentationMode {
  DESKTOP = 'desktop',
  MANAGED_WINDOWS = 'managed-windows'
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

/** Orientation policy for the Wine desktop host window. */
export enum ScreenOrientationSetting {
  SENSOR_LANDSCAPE = 'sensor-landscape',
  LANDSCAPE = 'landscape',
  PORTRAIT = 'portrait'
}

/**
 * Wine desktop host window layout. Rounded-screen tablets clip the start menu
 * when the window is stretched edge-to-edge, so a safe-area mode keeps the
 * system bars and the corner cutouts out of the Wine surface.
 */
export enum DesktopWindowMode {
  /** Immersive edge-to-edge window with status/navigation bars hidden. */
  FULLSCREEN = 'fullscreen',
  /** Keep the window inside the system safe area (bars and rounded corners). */
  SAFE_AREA = 'safe_area'
}

/**
 * 自动估算设备圆角半径 (物理像素): 取显示短边的 5%, 夹在 [40, 100]。
 * 不同设备圆角不同, 固定值不合适; 短边比例估算对主流设备误差在
 * ±20px 内, 且保证避让量足够又不至于像窗口边框。
 */
export function resolveCornerSafeMarginPx(width: number, height: number): number {
  const short = Math.min(width, height);
  return Math.max(40, Math.min(100, Math.round(short * 0.05)));
}

/** Matches VintagePomelo's control-bar behavior contract. */
export enum ControlBarDirection {
  HORIZONTAL = 'horizontal',
  VERTICAL = 'vertical',
  AUTO = 'auto',
  AUTO_HIDE = 'auto_hide'
}

/** Global Direct3D translation policy used by Explorer and app-card launches. */
export enum D3DRendererPreference {
  DXVK = 'dxvk',
  VIRGL = 'virgl'
}

/** Box64 兼容性预设：默认档不注入任何覆盖（沿用系统当前已验证的配置）。 */
export const BOX64_PRESET_DEFAULT = 'default';
export const BOX64_PRESET_STABILITY = 'stability';
export const BOX64_PRESET_CONSERVATIVE = 'conservative';
export const BOX64_PRESET_INTERMEDIATE = 'intermediate';
export const BOX64_PRESET_PERFORMANCE = 'performance';

export const BOX64_PRESET_IDS: string[] = [
  BOX64_PRESET_DEFAULT,
  BOX64_PRESET_STABILITY,
  BOX64_PRESET_CONSERVATIVE,
  BOX64_PRESET_INTERMEDIATE,
  BOX64_PRESET_PERFORMANCE
];

export function box64PresetLabel(presetId: string): string {
  switch (presetId) {
    case BOX64_PRESET_STABILITY:
      return '稳定模式';
    case BOX64_PRESET_CONSERVATIVE:
      return '兼容模式';
    case BOX64_PRESET_INTERMEDIATE:
      return '均衡模式';
    case BOX64_PRESET_PERFORMANCE:
      return '性能模式';
    default:
      return '默认（当前配置）';
  }
}

export function box64PresetDescription(presetId: string): string {
  switch (presetId) {
    case BOX64_PRESET_STABILITY:
      return '优先保证兼容与稳定，适合新引擎、Unity 或频繁崩溃的程序。';
    case BOX64_PRESET_CONSERVATIVE:
      return '兼容与性能之间偏保守，适合大部分老游戏。';
    case BOX64_PRESET_INTERMEDIATE:
      return '兼顾兼容性与速度，是多数程序的均衡选择。';
    case BOX64_PRESET_PERFORMANCE:
      return '追求最高帧率，部分程序可能因此变慢或崩溃。';
    default:
      return '不注入额外参数，使用系统已验证的默认兼容配置。';
  }
}

/**
 * 把预设展开为 KEY=VALUE 环境变量列表；默认档返回空数组，
 * 即完全不覆盖 C++ 侧的当前生产配置。
 * 弱内存屏障(WEAKBARRIER)与易失元数据(VOLATILE_METADATA)是私有保护项，
 * 不随预设下发，避免破坏已验证的渲染与文件访问路径。
 */
export function resolveBox64PresetEnv(presetId: string): string[] {
  switch (presetId) {
    case BOX64_PRESET_STABILITY:
      return [
        'BOX64_DYNAREC_SAFEFLAGS=2',
        'BOX64_DYNAREC_FASTNAN=0',
        'BOX64_DYNAREC_FASTROUND=0',
        'BOX64_DYNAREC_X87DOUBLE=1',
        'BOX64_DYNAREC_BIGBLOCK=0',
        'BOX64_DYNAREC_STRONGMEM=2',
        'BOX64_DYNAREC_FORWARD=128',
        'BOX64_DYNAREC_CALLRET=0',
        'BOX64_DYNAREC_WAIT=0',
        'BOX64_DYNAREC_NATIVEFLAGS=0'
      ];
    case BOX64_PRESET_CONSERVATIVE:
      return [
        'BOX64_DYNAREC_SAFEFLAGS=2',
        'BOX64_DYNAREC_FASTNAN=0',
        'BOX64_DYNAREC_FASTROUND=0',
        'BOX64_DYNAREC_X87DOUBLE=1',
        'BOX64_DYNAREC_BIGBLOCK=1',
        'BOX64_DYNAREC_STRONGMEM=1',
        'BOX64_DYNAREC_FORWARD=128',
        'BOX64_DYNAREC_CALLRET=0',
        'BOX64_DYNAREC_WAIT=1',
        'BOX64_DYNAREC_NATIVEFLAGS=0'
      ];
    case BOX64_PRESET_INTERMEDIATE:
      return [
        'BOX64_DYNAREC_SAFEFLAGS=2',
        'BOX64_DYNAREC_FASTNAN=1',
        'BOX64_DYNAREC_FASTROUND=0',
        'BOX64_DYNAREC_X87DOUBLE=1',
        'BOX64_DYNAREC_BIGBLOCK=2',
        'BOX64_DYNAREC_STRONGMEM=0',
        'BOX64_DYNAREC_FORWARD=128',
        'BOX64_DYNAREC_CALLRET=0',
        'BOX64_DYNAREC_WAIT=1',
        'BOX64_DYNAREC_NATIVEFLAGS=0'
      ];
    case BOX64_PRESET_PERFORMANCE:
      return [
        'BOX64_DYNAREC_SAFEFLAGS=1',
        'BOX64_DYNAREC_FASTNAN=1',
        'BOX64_DYNAREC_FASTROUND=1',
        'BOX64_DYNAREC_X87DOUBLE=0',
        'BOX64_DYNAREC_BIGBLOCK=3',
        'BOX64_DYNAREC_STRONGMEM=0',
        'BOX64_DYNAREC_FORWARD=512',
        'BOX64_DYNAREC_CALLRET=1',
        'BOX64_DYNAREC_WAIT=1',
        'BOX64_DYNAREC_NATIVEFLAGS=1'
      ];
    default:
      return [];
  }
}

export interface VirtualMouseConfig {
  mouseSensitivity: number;
  doubleClickInterval: number;
  showCursor: boolean;
}

export const DEFAULT_VIRTUAL_MOUSE_CONFIG: VirtualMouseConfig = {
  mouseSensitivity: 100,
  doubleClickInterval: 100,
  showCursor: true
};

export function cloneVirtualMouseConfig(config?: VirtualMouseConfig): VirtualMouseConfig {
  const value = config ?? DEFAULT_VIRTUAL_MOUSE_CONFIG;
  return {
    mouseSensitivity: value.mouseSensitivity ?? DEFAULT_VIRTUAL_MOUSE_CONFIG.mouseSensitivity,
    doubleClickInterval: value.doubleClickInterval ?? DEFAULT_VIRTUAL_MOUSE_CONFIG.doubleClickInterval,
    showCursor: value.showCursor ?? DEFAULT_VIRTUAL_MOUSE_CONFIG.showCursor
  };
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
  /** Box64 兼容性预设；'default' 表示跟随全局设置。 */
  box64Preset: string;
  executable: string;
  arguments: string[];
  workingDirectory: string;
  displayModeOverride: DisplayMode | null;
  inputProfileId: string;
  prefixId: string;
}

export interface GlobalSettings {
  defaultDisplayMode: DisplayMode;
  desktopOrientation: ScreenOrientationSetting;
  /** Desktop host window layout: immersive fullscreen or safe-area inset. */
  desktopWindowMode: DesktopWindowMode;
  /** 桌面/游戏窗口打开时保持屏幕常亮，避免游玩中自动锁屏。默认开启。 */
  keepScreenOn: boolean;
  /** Box64 兼容性预设；'default' 表示使用系统当前配置。 */
  box64Preset: string;
  /** Desktop mode always uses this global profile; single-app may override it. */
  desktopInputProfileId: string;
  viewMode: ViewMode;
  themeMode: ThemeMode;
  useGlassEffect: boolean;
  usePageBackground: boolean;
  pageBackgroundUri: string;
  /** Entire ArkTS screen-input layer, including controls, mouse mode and toolbar. */
  virtualInputEnabled: boolean;
  showVirtualControls: boolean;
  autoHideVirtualControls: boolean;
  controlBarDirection: ControlBarDirection;
  /** Normalized top-left anchor inside the available overlay area. */
  controlBarPositionX: number;
  controlBarPositionY: number;
  virtualMouseConfig: VirtualMouseConfig;
  controlOpacity: number;
  gamepadDeadzone: number;
  outputScale: number;
  d3dRendererPreference: D3DRendererPreference;
}

export interface RuntimeSession {
  sessionId: string;
  appId: string;
  executable: string;
  pid: number;
  displayMode: DisplayMode;
  presentationMode: WinePresentationMode;
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

export const INPUT_PROFILE_SCHEMA_VERSION = 6;

/** Winlator 风格的可排布输入元素类型。 */
export enum ControlElementType {
  BUTTON = 'BUTTON',
  D_PAD = 'D_PAD',
  STICK = 'STICK',
  TRACKPAD = 'TRACKPAD',
  RANGE_BUTTON = 'RANGE_BUTTON'
}

export enum ControlElementShape {
  CIRCLE = 'CIRCLE',
  RECT = 'RECT',
  ROUND_RECT = 'ROUND_RECT',
  SQUARE = 'SQUARE'
}

export enum InputBindingKind {
  NONE = 'NONE',
  KEY = 'KEY',
  MOUSE = 'MOUSE'
}

export interface InputBinding {
  kind: InputBindingKind;
  code: number;
}

export const MOUSE_LEFT_BUTTON = 272;
export const MOUSE_RIGHT_BUTTON = 273;
export const MOUSE_MIDDLE_BUTTON = 274;

export function keyBinding(code: number): InputBinding {
  return { kind: InputBindingKind.KEY, code: code };
}

export function mouseBinding(code: number): InputBinding {
  return { kind: InputBindingKind.MOUSE, code: code };
}

export function cloneInputBinding(binding?: InputBinding): InputBinding {
  const value = binding ?? { kind: InputBindingKind.NONE, code: 0 };
  return { kind: value.kind ?? InputBindingKind.NONE, code: value.code ?? 0 };
}

/**
 * 元素中心使用归一化坐标（0.0-1.0），与屏幕比例无关（参考 Winlator .icp）。
 * bindings 为多键组合：BUTTON 按下时同时按下全部槽位；D_PAD/STICK 依次为
 * 上/右/下/左；TRACKPAD 不发键；RANGE_BUTTON 使用 keyList 滑动选键。
 */
export interface ControlElement {
  id: string;
  type: ControlElementType;
  shape: ControlElementShape;
  x: number;
  y: number;
  scale: number;
  /** -1 继承方案透明度 overlayOpacity；0-100 为元素级覆盖。 */
  opacity: number;
  bindings: InputBinding[];
  toggleSwitch: boolean;
  text: string;
  iconId: number;
  visible: boolean;
  /** RANGE_BUTTON 可选键列表（evdev 码）。 */
  keyList: number[];
}

export interface InputProfile {
  id: string;
  name: string;
  schemaVersion: number;
  /** 触摸板指针速度倍率（0.1-5.0）。 */
  cursorSpeed: number;
  /** 方案级覆盖层透明度（0-100）。 */
  overlayOpacity: number;
  gamepadMappings: GamepadButtonMapping[];
  /** 手机（<720vp）元素集，竖屏友好排布。 */
  elementsPhone: ControlElement[];
  /** 平板（720-1280vp）元素集，横屏友好排布。 */
  elementsTablet: ControlElement[];
  /** PC/大屏（>=1280vp）元素集，配合实体键鼠的精简覆盖。 */
  elementsDesktop: ControlElement[];
  /** 旧 v6 单元素集兼容字段：加载时复制到三套，不参与新逻辑。 */
  elements?: ControlElement[];
}

/**
 * 输入方案按断点布局分成三种形态，与 BreakpointSystem 对齐：
 * xs/sm（<720vp）→ 手机，md/lg（720-1280vp）→ 平板，xl（>=1280vp）→ PC。
 */
export enum InputLayoutForm {
  PHONE = 'phone',
  TABLET = 'tablet',
  DESKTOP = 'desktop'
}

export const INPUT_LAYOUT_FORMS: InputLayoutForm[] = [
  InputLayoutForm.PHONE,
  InputLayoutForm.TABLET,
  InputLayoutForm.DESKTOP
];

export function inputLayoutFormLabel(form: InputLayoutForm): string {
  if (form === InputLayoutForm.PHONE) return '手机';
  if (form === InputLayoutForm.DESKTOP) return 'PC';
  return '平板';
}

export function resolveInputLayoutForm(widthVp: number): InputLayoutForm {
  if (widthVp >= 1280) return InputLayoutForm.DESKTOP;
  if (widthVp >= 720) return InputLayoutForm.TABLET;
  return InputLayoutForm.PHONE;
}

export function elementsForForm(profile: InputProfile, form: InputLayoutForm): ControlElement[] {
  if (form === InputLayoutForm.PHONE) return profile.elementsPhone ?? [];
  if (form === InputLayoutForm.DESKTOP) return profile.elementsDesktop ?? [];
  return profile.elementsTablet ?? [];
}

/** VintagePomelo-compatible 4/8-way virtual joystick quantization. */
export function resolveVirtualJoystickDirection(dx: number, dy: number, radius: number,
  deadzonePercent: number, eightDirection: boolean): VirtualJoystickDirection {
  const none: VirtualJoystickDirection = { up: false, down: false, left: false, right: false };
  const safeRadius = Math.max(1, radius);
  const deadzone = safeRadius * Math.max(0, Math.min(100, deadzonePercent)) / 100;
  if (Math.sqrt(dx * dx + dy * dy) < deadzone) return none;
  const angle = Math.atan2(dy, dx) * 180 / Math.PI;
  if (!eightDirection) {
    if (angle >= -45 && angle < 45) return { up: false, down: false, left: false, right: true };
    if (angle >= 45 && angle < 135) return { up: false, down: true, left: false, right: false };
    if (angle >= 135 || angle < -135) return { up: false, down: false, left: true, right: false };
    return { up: true, down: false, left: false, right: false };
  }
  if (angle >= -22.5 && angle < 22.5) return { up: false, down: false, left: false, right: true };
  if (angle >= 22.5 && angle < 67.5) return { up: false, down: true, left: false, right: true };
  if (angle >= 67.5 && angle < 112.5) return { up: false, down: true, left: false, right: false };
  if (angle >= 112.5 && angle < 157.5) return { up: false, down: true, left: true, right: false };
  if (angle >= 157.5 || angle < -157.5) return { up: false, down: false, left: true, right: false };
  if (angle >= -157.5 && angle < -112.5) return { up: true, down: false, left: false, right: false };
  if (angle >= -112.5 && angle < -67.5) return { up: true, down: false, left: false, right: true };
  return { up: true, down: false, left: false, right: true };
}

export interface VirtualJoystickDirection {
  up: boolean;
  down: boolean;
  left: boolean;
  right: boolean;
}

export interface GamepadButtonMapping {
  id: string;
  label: string;
  buttonCode: number;
  evdevCode: number;
}

export const DEFAULT_GAMEPAD_MAPPINGS: GamepadButtonMapping[] = [
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
  { id: 'start', label: 'Start', buttonCode: 2312, evdevCode: 28 },
  { id: 'l3', label: 'L3', buttonCode: 2313, evdevCode: 28 },
  { id: 'r3', label: 'R3', buttonCode: 2314, evdevCode: 57 },
  { id: 'home', label: 'Home', buttonCode: 2315, evdevCode: 63 }
];

export function generateControlElementId(prefix: string = 'el'): string {
  return prefix + '-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 0x10000).toString(36);
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

/**
 * 创建一个新元素。shape 缺省按类型选择：触摸板/滚动键为圆角矩形，
 * 其余为圆形。
 */
export function createControlElement(
  type: ControlElementType,
  x: number,
  y: number,
  text: string,
  bindings: InputBinding[],
  shape?: ControlElementShape,
  scale?: number,
  toggleSwitch?: boolean,
  keyList?: number[]): ControlElement {
  const resolvedShape = shape ?? (type === ControlElementType.TRACKPAD || type === ControlElementType.RANGE_BUTTON
    ? ControlElementShape.ROUND_RECT : ControlElementShape.CIRCLE);
  return {
    id: generateControlElementId('el'),
    type: type,
    shape: resolvedShape,
    x: clamp01(x),
    y: clamp01(y),
    scale: Math.max(0.5, Math.min(2, scale ?? 1)),
    opacity: -1,
    bindings: (bindings ?? []).map(cloneInputBinding),
    toggleSwitch: toggleSwitch ?? false,
    text: text,
    iconId: 0,
    visible: true,
    keyList: (keyList ?? []).map((code: number): number => code)
  };
}

export function cloneControlElement(element: ControlElement): ControlElement {
  return {
    id: element.id,
    type: element.type ?? ControlElementType.BUTTON,
    shape: element.shape ?? ControlElementShape.CIRCLE,
    x: clamp01(element.x ?? 0.5),
    y: clamp01(element.y ?? 0.5),
    scale: element.scale ?? 1,
    opacity: element.opacity ?? -1,
    bindings: (element.bindings ?? []).map(cloneInputBinding),
    toggleSwitch: element.toggleSwitch ?? false,
    text: element.text ?? '',
    iconId: element.iconId ?? 0,
    visible: element.visible ?? true,
    keyList: (element.keyList ?? []).map((code: number): number => code)
  };
}

export function cloneGamepadMappings(mappings?: GamepadButtonMapping[]): GamepadButtonMapping[] {
  return (mappings ?? DEFAULT_GAMEPAD_MAPPINGS).map((mapping: GamepadButtonMapping): GamepadButtonMapping => ({
    id: mapping.id,
    label: mapping.label,
    buttonCode: mapping.buttonCode,
    evdevCode: mapping.evdevCode
  }));
}

export function cloneInputProfile(profile?: InputProfile, profileId?: string, profileName?: string): InputProfile {
  const fallback = createDefaultInputProfile();
  const value = profile ?? fallback;
  const legacy = value.elements ?? [];
  return {
    id: profileId ?? value.id,
    name: profileName ?? value.name,
    schemaVersion: INPUT_PROFILE_SCHEMA_VERSION,
    cursorSpeed: value.cursorSpeed ?? fallback.cursorSpeed,
    overlayOpacity: value.overlayOpacity ?? fallback.overlayOpacity,
    gamepadMappings: cloneGamepadMappings(value.gamepadMappings),
    elementsPhone: (value.elementsPhone ?? legacy).map(cloneControlElement),
    elementsTablet: (value.elementsTablet ?? legacy).map(cloneControlElement),
    elementsDesktop: (value.elementsDesktop ?? legacy).map(cloneControlElement)
  };
}

export interface InputTemplate {
  id: string;
  name: string;
}

export const INPUT_TEMPLATES: InputTemplate[] = [
  { id: 'default', name: '通用' },
  { id: 'shooter', name: '射击' },
  { id: 'action', name: '动作' }
];

function dpadWASD(): InputBinding[] {
  return [keyBinding(17), keyBinding(32), keyBinding(31), keyBinding(30)];
}

function arrowBindings(): InputBinding[] {
  return [keyBinding(103), keyBinding(106), keyBinding(108), keyBinding(105)];
}

function defaultTemplateElements(form: InputLayoutForm): ControlElement[] {
  if (form === InputLayoutForm.PHONE) {
    return [
      createControlElement(ControlElementType.D_PAD, 0.16, 0.80, '', dpadWASD(), undefined, 0.9),
      createControlElement(ControlElementType.TRACKPAD, 0.62, 0.46, '鼠标', [], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.80, 0.72, '左键', [mouseBinding(MOUSE_LEFT_BUTTON)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.90, 0.60, '右键', [mouseBinding(MOUSE_RIGHT_BUTTON)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.86, 0.84, '空格', [keyBinding(57)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.92, 0.70, 'E', [keyBinding(18)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.06, 0.06, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.08, 0.90, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.22, 0.90, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT, 0.9)
    ];
  }
  if (form === InputLayoutForm.DESKTOP) {
    return [
      createControlElement(ControlElementType.TRACKPAD, 0.68, 0.40, '鼠标', []),
      createControlElement(ControlElementType.BUTTON, 0.84, 0.74, '左键', [mouseBinding(MOUSE_LEFT_BUTTON)]),
      createControlElement(ControlElementType.BUTTON, 0.92, 0.62, '右键', [mouseBinding(MOUSE_RIGHT_BUTTON)]),
      createControlElement(ControlElementType.BUTTON, 0.05, 0.06, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT),
      createControlElement(ControlElementType.BUTTON, 0.05, 0.13, 'Enter', [keyBinding(28)], ControlElementShape.ROUND_RECT),
      createControlElement(ControlElementType.BUTTON, 0.13, 0.06, 'Tab', [keyBinding(15)], ControlElementShape.ROUND_RECT)
    ];
  }
  return [
    createControlElement(ControlElementType.D_PAD, 0.13, 0.74, '', dpadWASD()),
    createControlElement(ControlElementType.TRACKPAD, 0.68, 0.42, '鼠标', []),
    createControlElement(ControlElementType.BUTTON, 0.80, 0.70, '左键', [mouseBinding(MOUSE_LEFT_BUTTON)]),
    createControlElement(ControlElementType.BUTTON, 0.88, 0.60, '右键', [mouseBinding(MOUSE_RIGHT_BUTTON)]),
    createControlElement(ControlElementType.BUTTON, 0.86, 0.82, '空格', [keyBinding(57)]),
    createControlElement(ControlElementType.BUTTON, 0.93, 0.70, 'E', [keyBinding(18)]),
    createControlElement(ControlElementType.BUTTON, 0.05, 0.07, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.08, 0.88, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.20, 0.88, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT)
  ];
}

function shooterTemplateElements(form: InputLayoutForm): ControlElement[] {
  if (form === InputLayoutForm.PHONE) {
    return [
      createControlElement(ControlElementType.D_PAD, 0.15, 0.80, '', dpadWASD(), undefined, 0.9),
      createControlElement(ControlElementType.TRACKPAD, 0.62, 0.46, '视角', [], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.80, 0.72, '开火', [mouseBinding(MOUSE_LEFT_BUTTON)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.90, 0.60, '瞄准', [mouseBinding(MOUSE_RIGHT_BUTTON)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.90, 0.86, 'R', [keyBinding(19)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.74, 0.86, '跳', [keyBinding(57)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.08, 0.90, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.22, 0.90, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.06, 0.06, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.RANGE_BUTTON, 0.94, 0.46, '武器', [], ControlElementShape.ROUND_RECT, 0.8, false, [2, 3, 4, 5, 6])
    ];
  }
  if (form === InputLayoutForm.DESKTOP) {
    return [
      createControlElement(ControlElementType.TRACKPAD, 0.68, 0.40, '视角', []),
      createControlElement(ControlElementType.BUTTON, 0.84, 0.74, '开火', [mouseBinding(MOUSE_LEFT_BUTTON)]),
      createControlElement(ControlElementType.BUTTON, 0.92, 0.62, '瞄准', [mouseBinding(MOUSE_RIGHT_BUTTON)]),
      createControlElement(ControlElementType.BUTTON, 0.92, 0.86, 'R', [keyBinding(19)]),
      createControlElement(ControlElementType.BUTTON, 0.76, 0.86, '跳', [keyBinding(57)]),
      createControlElement(ControlElementType.BUTTON, 0.05, 0.06, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT)
    ];
  }
  return [
    createControlElement(ControlElementType.D_PAD, 0.12, 0.72, '', dpadWASD()),
    createControlElement(ControlElementType.TRACKPAD, 0.68, 0.38, '视角', []),
    createControlElement(ControlElementType.BUTTON, 0.80, 0.68, '开火', [mouseBinding(MOUSE_LEFT_BUTTON)]),
    createControlElement(ControlElementType.BUTTON, 0.89, 0.58, '瞄准', [mouseBinding(MOUSE_RIGHT_BUTTON)]),
    createControlElement(ControlElementType.BUTTON, 0.90, 0.84, 'R', [keyBinding(19)]),
    createControlElement(ControlElementType.BUTTON, 0.72, 0.84, '跳', [keyBinding(57)]),
    createControlElement(ControlElementType.BUTTON, 0.08, 0.86, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.20, 0.86, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.05, 0.07, 'Esc', [keyBinding(1)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.RANGE_BUTTON, 0.95, 0.46, '武器', [], ControlElementShape.ROUND_RECT, 0.9, false, [2, 3, 4, 5, 6])
  ];
}

function actionTemplateElements(form: InputLayoutForm): ControlElement[] {
  if (form === InputLayoutForm.PHONE) {
    return [
      createControlElement(ControlElementType.STICK, 0.15, 0.80, '', dpadWASD(), undefined, 0.9),
      createControlElement(ControlElementType.STICK, 0.72, 0.80, '', arrowBindings(), ControlElementShape.CIRCLE, 0.8),
      createControlElement(ControlElementType.BUTTON, 0.82, 0.72, 'A', [keyBinding(57)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.90, 0.62, 'B', [keyBinding(36)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.82, 0.86, 'X', [keyBinding(18)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.90, 0.86, 'Y', [keyBinding(37)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.06, 0.70, 'L', [keyBinding(16)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.16, 0.70, 'R', [keyBinding(17)], undefined, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.06, 0.06, 'Start', [keyBinding(28)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.08, 0.90, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT, 0.9),
      createControlElement(ControlElementType.BUTTON, 0.22, 0.90, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT, 0.9)
    ];
  }
  if (form === InputLayoutForm.DESKTOP) {
    return [
      createControlElement(ControlElementType.TRACKPAD, 0.62, 0.42, '鼠标', []),
      createControlElement(ControlElementType.BUTTON, 0.80, 0.74, 'A', [keyBinding(57)]),
      createControlElement(ControlElementType.BUTTON, 0.88, 0.62, 'B', [keyBinding(36)]),
      createControlElement(ControlElementType.BUTTON, 0.80, 0.86, 'X', [keyBinding(18)]),
      createControlElement(ControlElementType.BUTTON, 0.88, 0.86, 'Y', [keyBinding(37)]),
      createControlElement(ControlElementType.BUTTON, 0.06, 0.70, 'L', [keyBinding(16)]),
      createControlElement(ControlElementType.BUTTON, 0.16, 0.70, 'R', [keyBinding(17)]),
      createControlElement(ControlElementType.BUTTON, 0.05, 0.06, 'Start', [keyBinding(28)], ControlElementShape.ROUND_RECT),
      createControlElement(ControlElementType.BUTTON, 0.08, 0.90, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT),
      createControlElement(ControlElementType.BUTTON, 0.22, 0.90, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT)
    ];
  }
  return [
    createControlElement(ControlElementType.STICK, 0.13, 0.74, '', dpadWASD()),
    createControlElement(ControlElementType.STICK, 0.76, 0.78, '', arrowBindings(), ControlElementShape.CIRCLE, 0.9),
    createControlElement(ControlElementType.BUTTON, 0.85, 0.70, 'A', [keyBinding(57)]),
    createControlElement(ControlElementType.BUTTON, 0.92, 0.60, 'B', [keyBinding(36)]),
    createControlElement(ControlElementType.BUTTON, 0.85, 0.84, 'X', [keyBinding(18)]),
    createControlElement(ControlElementType.BUTTON, 0.92, 0.84, 'Y', [keyBinding(37)]),
    createControlElement(ControlElementType.BUTTON, 0.06, 0.64, 'L', [keyBinding(16)]),
    createControlElement(ControlElementType.BUTTON, 0.16, 0.64, 'R', [keyBinding(17)]),
    createControlElement(ControlElementType.BUTTON, 0.05, 0.07, 'Start', [keyBinding(28)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.08, 0.88, 'Shift', [keyBinding(42)], ControlElementShape.ROUND_RECT),
    createControlElement(ControlElementType.BUTTON, 0.20, 0.88, 'Ctrl', [keyBinding(29)], ControlElementShape.ROUND_RECT)
  ];
}

function templateElements(templateId: string, form: InputLayoutForm): ControlElement[] {
  if (templateId === 'shooter') return shooterTemplateElements(form);
  if (templateId === 'action') return actionTemplateElements(form);
  return defaultTemplateElements(form);
}

export function createInputProfileFromTemplate(id: string, name: string, templateId: string): InputProfile {
  return {
    id: id,
    name: name,
    schemaVersion: INPUT_PROFILE_SCHEMA_VERSION,
    cursorSpeed: 1,
    overlayOpacity: 70,
    gamepadMappings: cloneGamepadMappings(DEFAULT_GAMEPAD_MAPPINGS),
    elementsPhone: templateElements(templateId, InputLayoutForm.PHONE),
    elementsTablet: templateElements(templateId, InputLayoutForm.TABLET),
    elementsDesktop: templateElements(templateId, InputLayoutForm.DESKTOP)
  };
}

export function createDefaultInputProfile(): InputProfile {
  return createInputProfileFromTemplate('default', '默认输入方案', 'default');
}

export function createDefaultGlobalSettings(): GlobalSettings {
  return {
    defaultDisplayMode: DisplayMode.DESKTOP,
    desktopOrientation: ScreenOrientationSetting.SENSOR_LANDSCAPE,
    desktopWindowMode: DesktopWindowMode.FULLSCREEN,
    keepScreenOn: true,
    box64Preset: BOX64_PRESET_DEFAULT,
    desktopInputProfileId: 'default',
    viewMode: ViewMode.GRID,
    themeMode: ThemeMode.SYSTEM,
    useGlassEffect: true,
    usePageBackground: false,
    pageBackgroundUri: '',
    virtualInputEnabled: true,
    showVirtualControls: false,
    autoHideVirtualControls: false,
    controlBarDirection: ControlBarDirection.AUTO,
    controlBarPositionX: 1,
    controlBarPositionY: 0,
    virtualMouseConfig: cloneVirtualMouseConfig(DEFAULT_VIRTUAL_MOUSE_CONFIG),
    controlOpacity: 72,
    gamepadDeadzone: 18,
    outputScale: 100,
    d3dRendererPreference: D3DRendererPreference.DXVK
  };
}

export function resolveInputProfileId(appProfileId: string, desktopProfileId: string): string {
  const appValue = (appProfileId ?? '').trim();
  if (appValue.length > 0 && appValue !== 'default') return appValue;
  const desktopValue = (desktopProfileId ?? '').trim();
  return desktopValue.length > 0 ? desktopValue : 'default';
}

export function createDefaultAppSettings(appId: string): AppSettings {
  return {
    appId: appId,
    customTitle: '',
    customCover: '',
    favorite: false,
    box64Preset: BOX64_PRESET_DEFAULT,
    executable: '',
    arguments: [],
    workingDirectory: '',
    displayModeOverride: null,
    inputProfileId: 'default',
    prefixId: 'default'
  };
}

export function normalizeLaunchPath(path: string): string {
  return path.trim().replace(/\\/g, '/').replace(/\/+/g, '/').toLowerCase();
}

/**
 * Wine maps the app-owned Download library to Z:\, so a program started
 * from Explorer is reported as Z:\games\... while the catalog stores the
 * same file as /storage/Users/currentUser/Download/<bundle>/games/....
 * Collapse only those two app-library forms; arbitrary C:\Games paths must
 * remain distinct from the app-owned games directory.
 */
export function normalizeCatalogLaunchIdentity(path: string): string {
  const normalized = normalizeLaunchPath(path);
  const gamesMarker = '/games/';
  if (normalized.startsWith('z:/games/')) return normalized.substring(3);
  if (normalized.startsWith('/storage/users/currentuser/download/')) {
    const markerIndex = normalized.indexOf(gamesMarker);
    if (markerIndex >= 0) return normalized.substring(markerIndex + 1);
  }
  return normalized;
}

/**
 * Merge ArkTS-owned sessions with the native Wine process registry.  A native
 * path is used only when it identifies one catalog card unambiguously.
 */
export function resolveRunningAppIds(apps: AppDescriptor[], sessionAppIds: Set<string>,
  nativeRunningPaths: Set<string>): Set<string> {
  const result: Set<string> = new Set<string>();
  sessionAppIds.forEach((appId: string): void => { result.add(appId); });

  const normalizedNativePaths: Set<string> = new Set<string>();
  nativeRunningPaths.forEach((path: string): void => {
    const normalized = normalizeCatalogLaunchIdentity(path);
    if (normalized.length > 0) normalizedNativePaths.add(normalized);
  });

  const catalogPathCounts: Map<string, number> = new Map<string, number>();
  apps.forEach((app: AppDescriptor): void => {
    const normalized = normalizeCatalogLaunchIdentity(app.launchTarget.executable);
    if (normalized.length > 0) {
      catalogPathCounts.set(normalized, (catalogPathCounts.get(normalized) ?? 0) + 1);
    }
  });
  apps.forEach((app: AppDescriptor): void => {
    const normalized = normalizeCatalogLaunchIdentity(app.launchTarget.executable);
    if (normalized.length > 0 && catalogPathCounts.get(normalized) === 1 &&
      normalizedNativePaths.has(normalized)) result.add(app.id);
  });
  return result;
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

interface IcpElementRaw {
  type?: string;
  shape?: string;
  bindings?: string[];
  scale?: number;
  x?: number;
  y?: number;
  toggleSwitch?: boolean;
  text?: string;
  iconId?: number;
}

interface IcpProfileRaw {
  id?: number;
  name?: string;
  cursorSpeed?: number;
  elements?: IcpElementRaw[];
}

function parseElementType(value: string): ControlElementType | null {
  if (value === 'BUTTON') return ControlElementType.BUTTON;
  if (value === 'D_PAD') return ControlElementType.D_PAD;
  if (value === 'STICK') return ControlElementType.STICK;
  if (value === 'TRACKPAD') return ControlElementType.TRACKPAD;
  if (value === 'RANGE_BUTTON') return ControlElementType.RANGE_BUTTON;
  return null;
}

function parseElementShape(value: string, type: ControlElementType): ControlElementShape {
  if (value === 'RECT') return ControlElementShape.RECT;
  if (value === 'ROUND_RECT') return ControlElementShape.ROUND_RECT;
  if (value === 'SQUARE') return ControlElementShape.SQUARE;
  if (value === 'CIRCLE') return ControlElementShape.CIRCLE;
  return type === ControlElementType.TRACKPAD || type === ControlElementType.RANGE_BUTTON
    ? ControlElementShape.ROUND_RECT : ControlElementShape.CIRCLE;
}

function clampNumber(value: number | undefined, min: number, max: number, fallback: number): number {
  if (value === undefined || Number.isNaN(value)) return fallback;
  return Math.max(min, Math.min(max, value));
}

function parseIcpBinding(value: string): InputBinding {
  const named = evdevNameToBinding(value);
  if (named.kind === 'MOUSE') return mouseBinding(named.code);
  if (named.kind === 'KEY') return keyBinding(named.code);
  return { kind: InputBindingKind.NONE, code: 0 };
}

/**
 * 解析 Winlator .icp JSON。未知元素类型跳过，未知字段忽略。
 * 导入的元素位置/绑定/形状尽量保留，透明度与可见性使用默认值。
 */
export function importProfileFromIcpJson(json: string, profileId: string, name?: string): InputProfile {
  const raw = JSON.parse(json) as IcpProfileRaw;
  const elements: ControlElement[] = [];
  const raws = raw.elements ?? [];
  for (let index = 0; index < raws.length; index++) {
    const el = raws[index];
    const type = parseElementType(el.type ?? '');
    if (type === null) continue;
    const rawBindings = (el.bindings ?? [])
      .slice(0, 8)
      .map((value: string): InputBinding => parseIcpBinding(value))
      .filter((binding: InputBinding): boolean => binding.kind !== InputBindingKind.NONE);
    let bindings: InputBinding[] = [];
    let keyList: number[] = [];
    if (type === ControlElementType.BUTTON) {
      bindings = rawBindings.slice(0, 4);
    } else if (type === ControlElementType.D_PAD || type === ControlElementType.STICK) {
      bindings = [
        rawBindings[0] ?? { kind: InputBindingKind.NONE, code: 0 },
        rawBindings[1] ?? { kind: InputBindingKind.NONE, code: 0 },
        rawBindings[2] ?? { kind: InputBindingKind.NONE, code: 0 },
        rawBindings[3] ?? { kind: InputBindingKind.NONE, code: 0 }
      ];
    } else if (type === ControlElementType.RANGE_BUTTON) {
      keyList = rawBindings.map((binding: InputBinding): number => binding.code);
      bindings = keyList.length > 0 ? [keyBinding(keyList[0])] : [];
    }
    elements.push({
      id: 'imp-' + index.toString(),
      type: type,
      shape: parseElementShape(el.shape ?? '', type),
      x: clampNumber(el.x, 0, 1, 0.5),
      y: clampNumber(el.y, 0, 1, 0.5),
      scale: clampNumber(el.scale, 0.5, 2, 1),
      opacity: -1,
      bindings: bindings.map(cloneInputBinding),
      toggleSwitch: el.toggleSwitch ?? false,
      text: (el.text ?? '').trim().slice(0, 24),
      iconId: 0,
      visible: true,
      keyList: keyList
    });
  }
  return {
    id: profileId,
    name: (name ?? raw.name ?? '导入方案').trim().slice(0, 40),
    schemaVersion: INPUT_PROFILE_SCHEMA_VERSION,
    cursorSpeed: clampNumber(raw.cursorSpeed, 0.1, 5, 1),
    overlayOpacity: 70,
    gamepadMappings: cloneGamepadMappings(DEFAULT_GAMEPAD_MAPPINGS),
    elementsPhone: elements.map(cloneControlElement),
    elementsTablet: elements.map(cloneControlElement),
    elementsDesktop: elements.map(cloneControlElement)
  };
}

function exportBindingName(binding: InputBinding): string {
  if (binding.kind === InputBindingKind.MOUSE) return evdevNameToBindingName('MOUSE', binding.code);
  if (binding.kind === InputBindingKind.KEY) return evdevNameToBindingName('KEY', binding.code);
  return 'NONE';
}

function exportBindingNames(element: ControlElement): string[] {
  const names: string[] = [];
  const slotCount = 4;
  for (let slot = 0; slot < slotCount; slot++) {
    if (element.type === ControlElementType.RANGE_BUTTON) {
      const codes = element.keyList ?? [];
      names.push(slot < codes.length ? evdevNameToBindingName('KEY', codes[slot]) : 'NONE');
      continue;
    }
    if (element.type === ControlElementType.TRACKPAD) {
      names.push('NONE');
      continue;
    }
    const binding = (element.bindings ?? [])[slot];
    names.push(binding ? exportBindingName(binding) : 'NONE');
  }
  return names;
}

/**
 * 导出为 Winlator 兼容的 .icp JSON（标准字段子集；本项目扩展字段如
 * 元素级透明度、可见性不导出）。
 */
export function exportProfileToIcpJson(profile: InputProfile, form: InputLayoutForm = InputLayoutForm.TABLET): string {
  const elements = elementsForForm(profile, form).map((element: ControlElement): IcpElementRaw => ({
    type: element.type,
    shape: element.shape,
    bindings: exportBindingNames(element),
    scale: element.scale,
    x: element.x,
    y: element.y,
    toggleSwitch: element.toggleSwitch,
    text: element.text,
    iconId: element.iconId ?? 0
  }));
  const payload: IcpProfileRaw = {
    id: 0,
    name: profile.name,
    cursorSpeed: profile.cursorSpeed,
    elements: elements
  };
  return JSON.stringify(payload);
}

function evdevNameToBindingName(kind: string, code: number): string {
  if (kind === 'MOUSE') return bindingToEvdevName('MOUSE', code);
  return bindingToEvdevName('KEY', code);
}

export function resolveDisplayMode(override: DisplayMode | null, defaultMode: DisplayMode): DisplayMode {
  // 单应用全屏模式已移除，override 仅保留存储兼容，恒不生效。
  return override ?? defaultMode;
}

/**
 * Resolve the user-facing mode without treating the explicit Wine desktop
 * card as a normal Windows program.
 */
export function resolveLaunchDisplayMode(kind: LaunchKind, override: DisplayMode | null,
  defaultMode: DisplayMode): DisplayMode {
  // 单应用全屏模式已移除：统一使用桌面模式，让游戏在 Wine 内自行全屏。
  return DisplayMode.DESKTOP;
}

export function resolveWinePresentationMode(kind: LaunchKind, displayMode: DisplayMode,
  managedWindowsHost: boolean): WinePresentationMode {
  if (kind === LaunchKind.WINE_DESKTOP) return WinePresentationMode.DESKTOP;
  return managedWindowsHost ? WinePresentationMode.MANAGED_WINDOWS : WinePresentationMode.DESKTOP;
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
