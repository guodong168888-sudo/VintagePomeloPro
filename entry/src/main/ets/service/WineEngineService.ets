import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import testNapi from 'libentry.so';
import {
  DisplayMode,
  EngineState,
  NativeLaunchResult,
  NativeProcessInfo,
  ScreenOrientationSetting,
  WinePresentationMode,
  canTransitionEngineState
} from '../model/AppModels';
import { AppSettingsStore } from './AppSettingsStore';
import { WineWindowManager } from './WineWindowManager';

const DOMAIN = 0x0000;
const TAG = 'WineEngine';
const FILES_BASE = '/data/storage/el2/base/files';
const WINE_ROOT = FILES_BASE + '/wine';
const WINE_BIN = WINE_ROOT + '/bin';
const WINE_LIB = WINE_BIN + '/x86_64-unix';
const BOX64 = WINE_BIN + '/box64';
const SOCK = FILES_BASE + '/.wine/wine-wayland';
const PREFIX_MARKER = WINE_ROOT + '/share/wine/wine.inf';
const RUNTIME_VERSION_RAWFILE = 'wine_runtime.version';
const RUNTIME_VERSION_MARKER = WINE_ROOT + '/.winehua-runtime-version';
// Runtime extraction and prefix configuration are versioned independently.
// A new wine-data.zip may require wineboot to refresh an existing prefix, but
// the user's prefix and Download games must remain intact.
const PREFIX_RUNTIME_VERSION_MARKER = FILES_BASE + '/.wine/.winehua-prefix-runtime-version';
// Native wineboot allows up to 8 minutes on slow ARM devices, followed by a
// registry flush window. Keep a margin so a valid first-run/update operation
// is not reported as failed while it is still making progress.
const ENGINE_READY_TIMEOUT_MS = 10 * 60 * 1000;

interface RuntimePathRequirement {
  path: string;
  label: string;
  directory?: boolean;
}

const REQUIRED_RUNTIME_PATHS: RuntimePathRequirement[] = [
  { path: PREFIX_MARKER, label: 'share/wine/wine.inf' },
  { path: WINE_BIN + '/explorer.exe', label: 'bin/explorer.exe' },
  { path: WINE_BIN + '/Alarm01.wav', label: 'bin/Alarm01.wav' },
  { path: WINE_BIN + '/guest_gfx/winehua-guest-gfx.env', label: 'bin/guest_gfx/winehua-guest-gfx.env' },
  { path: WINE_BIN + '/guest_gfx/lib/libEGL.so', label: 'bin/guest_gfx/lib/libEGL.so' },
  { path: WINE_BIN + '/guest_gfx/lib/dri/virtio_gpu_dri.so', label: 'bin/guest_gfx/lib/dri/virtio_gpu_dri.so' },
  { path: WINE_BIN + '/x86_64-windows', label: 'bin/x86_64-windows', directory: true },
  { path: WINE_BIN + '/i386-windows', label: 'bin/i386-windows', directory: true }
];

export type EngineStateListener = (state: EngineState, message: string) => void;

function pathExists(path: string): boolean {
  try {
    return !!fs.accessSync(path);
  } catch (_) {
    return false;
  }
}

function pathMatchesRequirement(item: RuntimePathRequirement): boolean {
  if (!pathExists(item.path)) return false;
  if (!item.directory) return true;
  try {
    return fs.statSync(item.path).isDirectory();
  } catch (_) {
    return false;
  }
}

export class WineEngineService {
  private static instance: WineEngineService | null = null;
  private context: common.UIAbilityContext | null = null;
  private state: EngineState = EngineState.STOPPED;
  private message: string = 'Wine 引擎未启动';
  private mode: DisplayMode | null = null;
  private presentationMode: WinePresentationMode | null = null;
  private homeDirectory: string = '';
  private listeners: Set<EngineStateListener> = new Set<EngineStateListener>();
  private waiters: Array<(ready: boolean) => void> = [];
  private callbackInstalled: boolean = false;
  private restartPromise: Promise<boolean> | null = null;
  private prefixRefreshRequired: boolean = false;
  private pendingPrefixVersion: Uint8Array = new Uint8Array(0);

  static getInstance(): WineEngineService {
    if (!WineEngineService.instance) WineEngineService.instance = new WineEngineService();
    return WineEngineService.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    if (this.callbackInstalled) return;
    this.callbackInstalled = true;
    testNapi.setStateCallback((raw: string) => this.handleNativeState(raw));
  }

  getState(): EngineState {
    return this.state;
  }

  getMessage(): string {
    return this.message;
  }

  getMode(): DisplayMode | null {
    return this.mode;
  }

  getPresentationMode(): WinePresentationMode | null {
    return this.presentationMode;
  }

  isReady(): boolean {
    return this.state === EngineState.READY;
  }

  subscribe(listener: EngineStateListener): void {
    this.listeners.add(listener);
    listener(this.state, this.message);
  }

  unsubscribe(listener: EngineStateListener): void {
    this.listeners.delete(listener);
  }

  async ensureReady(mode: DisplayMode, presentationMode: WinePresentationMode,
    homeDirectory: string): Promise<boolean> {
    if (!this.context) return false;
    if (this.state === EngineState.READY && this.mode === mode &&
      this.presentationMode === presentationMode) return true;
    if (this.state === EngineState.PREPARING && this.mode === mode &&
      this.presentationMode === presentationMode) return this.waitForReady();

    if (this.state !== EngineState.STOPPED &&
      (this.mode !== mode || this.presentationMode !== presentationMode)) {
      this.setState(EngineState.SWITCHING, '正在切换显示模式');
      await this.stopAll();
    }

    this.mode = mode;
    this.presentationMode = presentationMode;
    this.homeDirectory = homeDirectory;
    this.setState(EngineState.PREPARING, '正在准备 Wine 引擎');

    try {
      const bundledRuntimeVersion = this.getBundledRuntimeVersion();
      const prefixRefreshRequired = await this.ensureRuntimeInstalled(bundledRuntimeVersion);
      this.prefixRefreshRequired = prefixRefreshRequired;
      this.pendingPrefixVersion = prefixRefreshRequired ? bundledRuntimeVersion : new Uint8Array(0);
      WineWindowManager.getInstance().setPresentationMode(presentationMode);
      if (presentationMode !== WinePresentationMode.MANAGED_WINDOWS) {
        const orientation = AppSettingsStore.getInstance().getGlobalSettings().desktopOrientation
          ?? ScreenOrientationSetting.SENSOR_LANDSCAPE;
        // This must happen before startServer/launchClient. A later ArkUI
        // window resize can correct the surface, but cannot prevent the first
        // Wayland desktop frame from being created at the old orientation.
        WineWindowManager.getInstance().prepareOutputForOrientation(orientation);
      }
      const serverReady = testNapi.startServer(SOCK) as boolean;
      if (!serverReady) {
        this.setState(EngineState.ERROR, 'Wayland 服务启动失败');
        this.finishWaiters(false);
        return false;
      }
      // The native launcher runs wineboot --init for a new prefix and
      // wineboot --update when this runtime version has not configured it yet.
      testNapi.launchClient(BOX64, [], SOCK, WINE_BIN + ':' + WINE_LIB,
        homeDirectory, prefixRefreshRequired);
      return this.waitForReady();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'ensureReady failed: %{public}s', JSON.stringify(error));
      this.setState(EngineState.ERROR, 'Wine 引擎准备失败');
      this.finishWaiters(false);
      return false;
    }
  }

  launchExecutable(executable: string, argumentsValue: string[] = []): NativeLaunchResult {
    if (this.state !== EngineState.READY) {
      return { pid: -1, sessionId: '', reused: false };
    }
    const singleAppRoot = this.presentationMode === WinePresentationMode.SINGLE_APP;
    if (singleAppRoot) WineWindowManager.getInstance().prepareSingleAppComposition();
    return testNapi.runWineExe(
      WINE_BIN,
      SOCK,
      WINE_BIN + ':' + WINE_LIB,
      executable,
      this.homeDirectory,
      argumentsValue,
      singleAppRoot
    ) as NativeLaunchResult;
  }

  /**
   * Desktop root 被用户关闭后，只重启 Wine explorer shell。
   * 不调用 stopAll，因而不会中断桌面模式中仍在运行的其它 Windows 程序。
   */
  restartDesktopShell(): NativeLaunchResult {
    if (this.state !== EngineState.READY ||
      this.presentationMode !== WinePresentationMode.DESKTOP) {
      return { pid: -1, sessionId: '', reused: false };
    }
    // Initial desktop startup uses Wine's `explorer` program name.  Reusing
    // that same form is essential after users close the shell; `explorer.exe`
    // is not guaranteed to resolve from a reconstructed Wayland session.
    return this.launchExecutable('explorer', [
      WineWindowManager.getInstance().getDesktopShellArgument()
    ]);
  }

  async stopAll(): Promise<void> {
    try {
      testNapi.stopAll();
    } catch (_) {
    }
    this.finishWaiters(false);
    await this.waitForNativeShutdown();
    this.mode = null;
    this.presentationMode = null;
    this.setState(EngineState.STOPPED, 'Wine 引擎已停止');
    // Leave a small socket-settle window after the process list becomes empty.
    // Restarting the Wayland server immediately can otherwise race the old
    // wine-wayland socket teardown on slower ARM tablets.
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 300));
  }

  /**
   * Rebuild Wine/Wayland services without deleting the prefix. Concurrent UI
   * requests share one operation so two taps cannot start competing servers.
   */
  async restart(mode: DisplayMode, presentationMode: WinePresentationMode,
    homeDirectory: string): Promise<boolean> {
    if (this.restartPromise) return this.restartPromise;
    const operation = this.performRestart(mode, presentationMode, homeDirectory);
    this.restartPromise = operation;
    const ready = await operation;
    if (this.restartPromise === operation) this.restartPromise = null;
    return ready;
  }

  private async performRestart(mode: DisplayMode, presentationMode: WinePresentationMode,
    homeDirectory: string): Promise<boolean> {
    if (this.state !== EngineState.STOPPED) {
      this.setState(EngineState.SWITCHING, '正在重新启动 Wine 引擎');
    }
    await this.stopAll();
    return this.ensureReady(mode, presentationMode, homeDirectory);
  }

  private async waitForNativeShutdown(): Promise<void> {
    for (let attempt = 0; attempt < 50; attempt++) {
      let processes: NativeProcessInfo[] = [];
      try { processes = testNapi.getProcessList() as NativeProcessInfo[]; } catch (_) {}
      if (processes.length === 0) return;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 100));
    }
    hilog.warn(DOMAIN, TAG, 'native process list did not settle before restart timeout');
  }

  async switchDisplaySession(): Promise<void> {
    if (this.state === EngineState.READY || this.state === EngineState.PREPARING) {
      this.setState(EngineState.SWITCHING, '正在切换显示模式');
    }
    await this.stopAll();
  }

  async resetPrefix(): Promise<void> {
    await this.stopAll();
    testNapi.resetWinePrefix();
    this.setState(EngineState.STOPPED, 'Wine 环境已重置');
  }

  private waitForReady(): Promise<boolean> {
    if (this.state === EngineState.READY) return Promise.resolve(true);
    if (this.state === EngineState.ERROR) return Promise.resolve(false);
    return new Promise<boolean>((resolve: (ready: boolean) => void) => {
      let completed = false;
      const finish = (ready: boolean): void => {
        if (completed) return;
        completed = true;
        resolve(ready);
      };
      this.waiters.push(finish);
      setTimeout(() => {
        if (!completed && this.state !== EngineState.READY) {
          this.waiters = this.waiters.filter((waiter: (ready: boolean) => void) => waiter !== finish);
          this.setState(EngineState.ERROR, 'Wine 引擎准备超时');
          finish(false);
        }
      }, ENGINE_READY_TIMEOUT_MS);
    });
  }

  private finishWaiters(ready: boolean): void {
    const pending = this.waiters;
    this.waiters = [];
    pending.forEach((resolve: (ready: boolean) => void) => resolve(ready));
  }

  private handleNativeState(raw: string): void {
    const separator = raw.indexOf(':');
    const processScoped = separator > 0;
    const value = separator >= 0 ? raw.substring(separator + 1) : raw;
    if (value === 'wine-ready' || value === 'wine-running') {
      if (value === 'wine-ready' && this.prefixRefreshRequired) {
        // Do not claim a refreshed prefix until native wineboot completed and
        // the marker is durable. A failed write deliberately leaves the
        // marker stale so the next launch retries the refresh.
        if (!this.writeVersionMarker(PREFIX_RUNTIME_VERSION_MARKER, this.pendingPrefixVersion)) {
          this.setState(EngineState.ERROR, 'Wine 环境配置结果保存失败');
          this.finishWaiters(false);
          return;
        }
        this.prefixRefreshRequired = false;
        this.pendingPrefixVersion = new Uint8Array(0);
      }
      this.setState(EngineState.READY, value === 'wine-running' ? 'Windows 程序运行中' : 'Wine 引擎已就绪');
      this.finishWaiters(true);
    } else if (value === 'wineserver-starting' || value === 'wineboot-starting') {
      this.setState(EngineState.PREPARING, value === 'wineboot-starting' ? '正在初始化 Wine 环境' : '正在启动 Wine 服务');
    } else if (value === 'wine-failed' && processScoped && this.state === EngineState.READY) {
      // runWineExe reports a process-scoped failure as "-1:wine-failed".
      // The engine and Wayland server are still usable; AppSessionService
      // already rejects the failed NativeLaunchResult for that one card.
      hilog.warn(DOMAIN, TAG, 'Windows program launch failed while engine remains ready: %{public}s', raw);
    } else if (value === 'wine-failed' || value === 'wineboot-failed' || value === 'wineserver-failed') {
      this.setState(EngineState.ERROR, 'Wine 启动失败');
      this.finishWaiters(false);
    } else if (value === 'exited' && (testNapi.getProcessList() as NativeProcessInfo[]).length === 0) {
      if (this.state === EngineState.PREPARING || this.state === EngineState.SWITCHING) {
        // appspawn wrapper processes may exit while wineboot/services continue
        // in broker-spawned children. The native launch coordinator emits an
        // explicit ready/failure result; the six-minute waiter remains the
        // bounded fallback when that result never arrives.
        hilog.info(DOMAIN, TAG, 'transient zero-process exit while %{public}s; waiting for launch result', this.state);
      } else if (this.state !== EngineState.STOPPED) {
        this.setState(EngineState.STOPPED, 'Wine 引擎已停止');
      }
    }
  }

  private setState(state: EngineState, message: string): void {
    if (!canTransitionEngineState(this.state, state)) {
      hilog.warn(DOMAIN, TAG, 'unexpected engine transition %{public}s -> %{public}s', this.state, state);
    }
    hilog.info(DOMAIN, TAG, 'engine state %{public}s -> %{public}s: %{public}s', this.state, state, message);
    this.state = state;
    this.message = message;
    this.listeners.forEach((listener: EngineStateListener) => listener(state, message));
  }

  private getMissingRuntimePaths(): string[] {
    const missing: string[] = [];
    REQUIRED_RUNTIME_PATHS.forEach((item: RuntimePathRequirement) => {
      if (!pathMatchesRequirement(item)) missing.push(item.label);
    });
    return missing;
  }

  private getBundledRuntimeVersion(): Uint8Array {
    if (!this.context) return new Uint8Array(0);
    return this.context.resourceManager.getRawFileContentSync(RUNTIME_VERSION_RAWFILE);
  }

  private versionMarkerMatches(path: string, expected: Uint8Array): boolean {
    if (expected.byteLength === 0 || !pathExists(path)) return false;
    let input: fs.File | null = null;
    try {
      const stat = fs.statSync(path);
      if (stat.size !== expected.byteLength) return false;
      input = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(expected.byteLength);
      const length = fs.readSync(input.fd, buffer, { length: expected.byteLength });
      if (length !== expected.byteLength) return false;
      const actual = new Uint8Array(buffer);
      for (let index = 0; index < expected.byteLength; index++) {
        if (actual[index] !== expected[index]) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (input) {
        try { fs.closeSync(input); } catch (_) {}
      }
    }
  }

  private runtimeVersionMatches(expected: Uint8Array): boolean {
    return this.versionMarkerMatches(RUNTIME_VERSION_MARKER, expected);
  }

  private prefixVersionMatches(expected: Uint8Array): boolean {
    return this.versionMarkerMatches(PREFIX_RUNTIME_VERSION_MARKER, expected);
  }

  private writeVersionMarker(path: string, expected: Uint8Array): boolean {
    let output: fs.File | null = null;
    try {
      output = fs.openSync(path,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const buffer = new ArrayBuffer(expected.byteLength);
      new Uint8Array(buffer).set(expected);
      fs.writeSync(output.fd, buffer, { length: expected.byteLength });
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'write version marker failed path=%{public}s error=%{public}s',
        path, JSON.stringify(error));
      return false;
    } finally {
      if (output) {
        try { fs.closeSync(output); } catch (_) {}
      }
    }
  }

  private async ensureRuntimeInstalled(bundledVersion: Uint8Array): Promise<boolean> {
    const missingBefore = this.getMissingRuntimePaths();
    const versionMatches = this.runtimeVersionMatches(bundledVersion);
    const prefixMatches = this.prefixVersionMatches(bundledVersion);
    if (missingBefore.length === 0 && versionMatches) {
      if (prefixMatches) return false;
      // Upgrade path for versions released before the prefix marker existed:
      // when the extracted runtime itself did not change and the prefix is
      // complete, adopt it as the baseline. Running wineboot --update here
      // would make every existing user pay a multi-minute migration for no
      // runtime change. A future runtime-content hash change still refreshes.
      let prefixInitialized = false;
      try { prefixInitialized = testNapi.checkWinePrefix() as boolean; } catch (_) {}
      if (prefixInitialized) {
        hilog.info(DOMAIN, TAG, 'adopting initialized prefix for unchanged runtime version');
        if (!this.writeVersionMarker(PREFIX_RUNTIME_VERSION_MARKER, bundledVersion)) {
          throw new Error('Unable to persist Wine prefix baseline marker');
        }
        return false;
      }
      return true;
    }
    if (!this.context) throw new Error('Ability context unavailable');
    hilog.warn(DOMAIN, TAG,
      'runtime refresh required, extracting wine-data.zip, runtimeVersionMatch=%{public}s '
        + 'prefixVersionMatch=%{public}s missing=%{public}s',
      versionMatches ? 'true' : 'false', prefixMatches ? 'true' : 'false', missingBefore.join(','));
    const rawFd = this.context.resourceManager.getRawFdSync('wine-data.zip');
    const temporaryZip = FILES_BASE + '/wine-data.zip';
    try {
      const output = fs.openSync(temporaryZip, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const chunkSize = 4 * 1024 * 1024;
      const buffer = new ArrayBuffer(chunkSize);
      let position = rawFd.offset;
      const end = rawFd.offset + rawFd.length;
      while (position < end) {
        const requested = Math.min(chunkSize, end - position);
        const length = fs.readSync(rawFd.fd, buffer, { offset: position, length: requested });
        if (length <= 0) break;
        fs.writeSync(output.fd, buffer, { length: length });
        position += length;
      }
      fs.closeSync(output);
      try {
        fs.mkdirSync(WINE_ROOT, true);
      } catch (_) {}
      await zlib.decompressFile(temporaryZip, WINE_ROOT, {});
      const missingAfter = this.getMissingRuntimePaths();
      if (missingAfter.length > 0) {
        throw new Error('Wine runtime incomplete after extract: ' + missingAfter.join(', '));
      }
      if (!this.writeVersionMarker(RUNTIME_VERSION_MARKER, bundledVersion)) {
        throw new Error('Unable to persist Wine runtime version marker');
      }
    } finally {
      this.context.resourceManager.closeRawFdSync('wine-data.zip');
      try { fs.unlinkSync(temporaryZip); } catch (_) {}
    }
    return true;
  }
}
