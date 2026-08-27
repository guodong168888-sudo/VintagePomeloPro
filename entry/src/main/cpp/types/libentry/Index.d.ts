export const startServer: (sockPath: string) => boolean;
export const setHostShadowProfile: (profile: string) => boolean;
export const launchClient: (exePath: string, argv: string[], sockPath: string, libPath: string,
  homeDir: string, automationMode?: boolean, prefixMode?: string, d3dBackend?: string,
  compatEnvStr?: string) => number;
export const stopClient: () => void;
export const stopAll: () => void;
export const setStateCallback: (cb: (state: string) => void) => void;
export const setToplevelCallback: (cb: (id: number, event: string, data: string) => void) => void;
export const setImeCallback: (cb: (active: number, x: number, y: number, w: number, h: number) => void) => void;
export const registerHostWindow: (windowId: number) => void;
export const setPointerLockCallback: (cb: (locked: boolean, toplevelId: number) => void) => void;
export const sendImeCommit: (text: string) => void;
export const sendImePreedit: (text: string, start: number, end: number) => void;
export const imeBackspace: () => void;
export const setPendingToplevel: (id: number) => void;
export const getCurrentToplevelId: () => number;
export const destroyToplevel: (id: number) => void;
export const sendToplevelClose: (id: number) => void;
export interface WineLaunchResult { pid: number; sessionId: string; reused: boolean; }
export interface WineSessionInfo {
  pid: number;
  sessionId: string;
  path: string;
  state: string;
  toplevelId: number;
}
export const runWineExe: (binDir: string, sockPath: string, libPath: string, exePath: string,
  homeDir: string, argumentsValue?: string[], workingDirectory?: string, d3dBackend?: string,
  envOverrides?: string[]) => WineLaunchResult;
export const runWineExeLegacy: (binDir: string, sockPath: string, libPath: string,
  exePath: string, homeDir: string) => number;
export const getWineSession: (sessionId: string) => WineSessionInfo | null;
export const stopWineSession: (sessionId: string) => boolean;
export const activateWineSession: (sessionId: string) => boolean;
export interface WineProgramOptions {
  windowsExePath: string;
  argv: string[];
  environment: Record<string, string>;
  workingDirectory: string;
  prefixMode: string;
  d3dBackend: string;
  presentBackend: string;
  automationMode: boolean;
}
export interface WineProcessHandle {
  found: boolean;
  pid: number;
  status: string;
  startTimestamp: number;
  endTimestamp: number;
  exitCode: number | null;
  exitCodeSource: string;
}
export const runWineProgram: (options: WineProgramOptions) => WineProcessHandle;
export interface FontZipExtractResult {
  ok: boolean;
  fonts: number;
  bad: number;
  firstBadExt: string;
  error: string;
}
/** 解压字体 ZIP 到 outDir, 落盘一律使用 ASCII 安全名 (font-NNN.ext)。 */
export const extractFontZip: (zipPath: string, outDir: string) => FontZipExtractResult;
/** 异步解压（后台线程执行，避免 UI 线程 ANR），返回 Promise。 */
export const extractFontZipAsync: (zipPath: string, outDir: string) => Promise<FontZipExtractResult>;
export interface GuestProgramOptions {
  executablePath: string;
  argv: string[];
  environment: Record<string, string>;
  workingDirectory: string;
  automationMode: boolean;
}
export const runGuestProgram: (options: GuestProgramOptions) => WineProcessHandle;
export interface HostProgramOptions {
  executablePath: string;
  argv: string[];
  environment: Record<string, string>;
  workingDirectory: string;
  automationMode: boolean;
}
export const runHostProgram: (options: HostProgramOptions) => WineProcessHandle;
export const runHostReplay: (options: HostProgramOptions) => boolean;
export const isHostReplayRunning: () => boolean;
export const queryWineProcess: (pid: number) => WineProcessHandle;
export const terminateWineProcess: (pid: number) => boolean;
export const checkWinePrefix: (prefixMode?: string) => boolean;
export const resetWinePrefix: (prefixMode?: string) => boolean;
export const runHostVulkanProbe: (surfaceId: bigint, runId: string) => boolean;
export const stopHostVulkanProbe: () => boolean;
export const getHostGpuName: () => string;
/** Host compositor displayed FPS for the renderer bound to toplevelId (0 = best active). */
export const getDisplayFps: (toplevelId: number) => number;
export const setOutputSize: (w: number, h: number) => void;
export const setDisplayScale: (scale: number) => void;
export const setDesktopMode: (enabled: boolean) => void;
export const setPhoneMode: (enabled: boolean) => void;
/** Points the native OH_LOG file sink at the logs directory. */
export const initAppLog: (dirPath: string) => void;
/** Removes all native-*.log files managed by the native log sink. */
export const clearNativeLog: () => void;
export const findToplevelAt: (px: number, py: number) => number;
export const raiseToplevel: (toplevelId: number) => void;
export const createRenderer: (toplevelId: number, surfaceId: BigInt) => void;
export const resizeRenderer: (toplevelId: number, width: number, height: number) => void;
/** Requests a Wayland redraw while retaining the current NativeWindow/EGL surface. */
export const refreshRenderer: (toplevelId: number) => void;
export const destroyRenderer: (toplevelId: number) => void;
export const sendPointerEvent: (toplevelId: number, action: number, px: number, py: number, button: number, rawDeltaX?: number, rawDeltaY?: number, fromMouse?: boolean) => void;
export const sendKeyEvent: (toplevelId: number, evdevCode: number, pressed: boolean) => void;
export const sendScrollEvent: (toplevelId: number, axis: number, value: number, scrollStep: number, px: number, py: number) => void;
export const notifyToplevelResize: (toplevelId: number, w: number, h: number) => void;
export const takeWindowMask: (toplevelId: number) => { w: number, h: number, buffer: ArrayBuffer } | null;
export const setToplevelVisible: (toplevelId: number, visible: boolean) => void;
export const getProcessList: () => Array<{
  pid: number;
  name: string;
  path: string;
  state: string;
  sessionId: string;
}>;
export const killProcess: (pid: number) => boolean;
export const initGameController: () => number;
export const cleanupGameController: () => void;
export const isGamepadConnected: () => boolean;
export const getGamepadCount: () => number;
export const setGamepadButtonCallback: (
  callback: (buttonCode: number, pressed: boolean) => void) => void;
export const setGamepadAxisCallback: (
  callback: (axisType: number, x: number, y: number) => void) => void;
export const setGamepadDeviceCallback: (callback: (connected: boolean) => void) => void;
export const runMmapTests: () => string;
export const termRun: (cols: number, rows: number, cb: (data: ArrayBuffer) => void, onExit: () => void) => number;
export const termSend: (data: ArrayBuffer) => void;
export const termResize: (cols: number, rows: number) => void;
export const termClose: () => void;
/** 宿主输入法预上屏文本 (拼音组合) -> Wine text-input preedit。 */
export const wineTextInputPreedit: (text: string) => boolean;
/** 宿主输入法提交文本 (中文等任意 Unicode) -> Wine text-input commit。 */
export const wineTextInputCommit: (text: string) => boolean;
/** Wine 侧 text-input 是否已 enable (即是否已 enter 且可接收 commit)。 */
export const wineTextInputEnabled: () => boolean;
/** 宿主键盘打开/关闭时切换 text-input 协议激活。 */
export const wineTextInputSetArmed: (armed: boolean) => void;
