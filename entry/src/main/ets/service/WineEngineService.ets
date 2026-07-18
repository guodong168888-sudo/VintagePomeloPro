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
  canTransitionEngineState
} from '../model/AppModels';
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

export type EngineStateListener = (state: EngineState, message: string) => void;

function pathExists(path: string): boolean {
  try {
    fs.accessSync(path);
    return true;
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
  private homeDirectory: string = '';
  private listeners: Set<EngineStateListener> = new Set<EngineStateListener>();
  private waiters: Array<(ready: boolean) => void> = [];
  private callbackInstalled: boolean = false;

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

  async ensureReady(mode: DisplayMode, homeDirectory: string): Promise<boolean> {
    if (!this.context) return false;
    if (this.state === EngineState.READY && this.mode === mode) return true;
    if (this.state === EngineState.PREPARING && this.mode === mode) return this.waitForReady();

    if (this.state !== EngineState.STOPPED && this.mode !== mode) {
      this.setState(EngineState.SWITCHING, '正在切换显示模式');
      await this.stopAll();
    }

    this.mode = mode;
    this.homeDirectory = homeDirectory;
    this.setState(EngineState.PREPARING, '正在准备 Wine 引擎');

    try {
      await this.ensureRuntimeInstalled();
      WineWindowManager.getInstance().setDisplayMode(mode);
      const serverReady = testNapi.startServer(SOCK) as boolean;
      if (!serverReady) {
        this.setState(EngineState.ERROR, 'Wayland 服务启动失败');
        this.finishWaiters(false);
        return false;
      }
      testNapi.launchClient(BOX64, [], SOCK, WINE_BIN + ':' + WINE_LIB, homeDirectory);
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
    const singleAppRoot = this.mode === DisplayMode.SINGLE_APP;
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

  async stopAll(): Promise<void> {
    try {
      testNapi.stopAll();
    } catch (_) {
    }
    this.finishWaiters(false);
    this.mode = null;
    this.setState(EngineState.STOPPED, 'Wine 引擎已停止');
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 250));
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
      }, 90000);
    });
  }

  private finishWaiters(ready: boolean): void {
    const pending = this.waiters;
    this.waiters = [];
    pending.forEach((resolve: (ready: boolean) => void) => resolve(ready));
  }

  private handleNativeState(raw: string): void {
    const separator = raw.indexOf(':');
    const value = separator >= 0 ? raw.substring(separator + 1) : raw;
    if (value === 'wine-ready' || value === 'wine-running') {
      this.setState(EngineState.READY, value === 'wine-running' ? 'Windows 程序运行中' : 'Wine 引擎已就绪');
      this.finishWaiters(true);
    } else if (value === 'wineserver-starting' || value === 'wineboot-starting') {
      this.setState(EngineState.PREPARING, value === 'wineboot-starting' ? '正在初始化 Wine 环境' : '正在启动 Wine 服务');
    } else if (value === 'wine-failed' || value === 'wineboot-failed' || value === 'wineserver-failed') {
      this.setState(EngineState.ERROR, 'Wine 启动失败');
      this.finishWaiters(false);
    } else if (value === 'exited' && (testNapi.getProcessList() as NativeProcessInfo[]).length === 0) {
      this.setState(EngineState.READY, 'Wine 引擎已就绪');
    }
  }

  private setState(state: EngineState, message: string): void {
    if (!canTransitionEngineState(this.state, state)) {
      hilog.warn(DOMAIN, TAG, 'unexpected engine transition %{public}s -> %{public}s', this.state, state);
    }
    this.state = state;
    this.message = message;
    this.listeners.forEach((listener: EngineStateListener) => listener(state, message));
  }

  private async ensureRuntimeInstalled(): Promise<void> {
    if (pathExists(PREFIX_MARKER)) return;
    if (!this.context) throw new Error('Ability context unavailable');
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
      if (!pathExists(WINE_ROOT)) fs.mkdirSync(WINE_ROOT, true);
      await zlib.decompressFile(temporaryZip, WINE_ROOT, {});
      if (!pathExists(PREFIX_MARKER)) throw new Error('Wine runtime marker missing');
    } finally {
      this.context.resourceManager.closeRawFdSync('wine-data.zip');
      try { fs.unlinkSync(temporaryZip); } catch (_) {}
    }
  }
}
