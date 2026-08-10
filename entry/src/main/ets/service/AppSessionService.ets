import { common, Want } from '@kit.AbilityKit';
import { hilog } from './LogService';
import testNapi from 'libentry.so';
import {
  BOX64_PRESET_DEFAULT,
  AppDescriptor,
  DisplayMode,
  EngineState,
  GlobalSettings,
  LaunchKind,
  NativeLaunchResult,
  NativeProcessInfo,
  NativeWineSessionInfo,
  RuntimeSession,
  SessionState,
  WinePresentationMode,
  normalizeCatalogLaunchIdentity,
  normalizeLaunchPath,
  resolveBox64PresetEnv,
  resolveLaunchDisplayMode,
  resolveWinePresentationMode
} from '../model/AppModels';
import { WineEngineService } from './WineEngineService';
import { WineWindowManager } from './WineWindowManager';
import { InputOverlayWindowCoordinator } from './InputOverlayWindowCoordinator';
import { AppSettingsStore } from './AppSettingsStore';

const DOMAIN = 0x0000;

export enum LaunchConflictKind {
  NONE = 'none',
  DISPLAY_MODE = 'display-mode'
}

interface PendingToplevelAssociation {
  sessionId: string;
  clientPid: number;
  toplevelId: number;
}

const DESKTOP_SESSION_ID = 'desktop';
const DESKTOP_APP_ID = 'builtin-desktop';
const DESKTOP_EXECUTABLE = 'explorer.exe';

interface PendingLaunchRequest {
  app: AppDescriptor;
  settings: GlobalSettings;
  mode: DisplayMode;
  presentationMode: WinePresentationMode;
  homeDirectory: string;
  resolve: (result: RuntimeSession | null) => void;
}
export class AppSessionService {
  private static instance: AppSessionService | null = null;
  private context: common.UIAbilityContext | null = null;
  private sessions: Map<string, RuntimeSession> = new Map<string, RuntimeSession>();
  private pendingToplevels: PendingToplevelAssociation[] = [];
  private desktopRootWaiters: Array<(session: RuntimeSession | null) => void> = [];

  static getInstance(): AppSessionService {
    if (!AppSessionService.instance) AppSessionService.instance = new AppSessionService();
    return AppSessionService.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    WineWindowManager.getInstance().setSessionAssociationCallback(
      (sessionId: string, clientPid: number, toplevelId: number): void => {
        this.associateToplevel(sessionId, clientPid, toplevelId);
      });
    // 引擎明确失败/停止是桌面根等待的终止信号：条件被破坏，立即放行等待者。
    WineEngineService.getInstance().subscribe((state: EngineState): void => {
      if (state === EngineState.ERROR || state === EngineState.STOPPED) {
        this.settleDesktopRootWaiters(null);
      }
    });
  }

  resolveMode(app: AppDescriptor, settings: GlobalSettings): DisplayMode {
    return resolveLaunchDisplayMode(app.launchTarget.kind, app.displayModeOverride,
      settings.defaultDisplayMode);
  }

  resolvePresentationMode(app: AppDescriptor, settings: GlobalSettings): WinePresentationMode {
    return resolveWinePresentationMode(app.launchTarget.kind, this.resolveMode(app, settings),
      AppSettingsStore.getInstance().usesManagedWineWindows());
  }

  hasModeConflict(app: AppDescriptor, settings: GlobalSettings): boolean {
    return this.getLaunchConflict(app, settings) === LaunchConflictKind.DISPLAY_MODE;
  }

  getLaunchConflict(app: AppDescriptor, settings: GlobalSettings): LaunchConflictKind {
    if (app.launchTarget.kind !== LaunchKind.WINE_EXE &&
      app.launchTarget.kind !== LaunchKind.WINE_SYSTEM &&
      app.launchTarget.kind !== LaunchKind.WINE_DESKTOP) {
      return LaunchConflictKind.NONE;
    }
    const engine = WineEngineService.getInstance();
    const currentMode = engine.getMode();
    const currentPresentation = engine.getPresentationMode();
    if (!currentMode || !currentPresentation || engine.getState() === EngineState.STOPPED) {
      return LaunchConflictKind.NONE;
    }
    const requestedMode = this.resolveMode(app, settings);
    const requestedPresentation = this.resolvePresentationMode(app, settings);
    if ((currentMode !== requestedMode || currentPresentation !== requestedPresentation) &&
      engine.getState() !== EngineState.STOPPED) {
      return LaunchConflictKind.DISPLAY_MODE;
    }
    return LaunchConflictKind.NONE;
  }

  async launch(app: AppDescriptor, settings: GlobalSettings, homeDirectory: string): Promise<RuntimeSession | null> {
    if (!app.available) return null;
    // PC/2-in-1 uses one Harmony window per Wine toplevel. The explicit
    // explorer desktop target is tablet-only and must not create a blue shell
    // window (or a hidden desktop process) on a managed-window host.
    if (app.launchTarget.kind === LaunchKind.WINE_DESKTOP &&
      AppSettingsStore.getInstance().usesManagedWineWindows()) return null;
    if ((app.launchTarget.kind === LaunchKind.WINE_EXE ||
      app.launchTarget.kind === LaunchKind.WINE_SYSTEM ||
      app.launchTarget.kind === LaunchKind.WINE_DESKTOP) &&
      app.launchTarget.executable.trim().length === 0) return null;
    const mode = this.resolveMode(app, settings);
    const presentationMode = this.resolvePresentationMode(app, settings);

    // “Wine 桌面”不是普通可执行文件：先检查实际 desktop root 是否仍存在。
    // root 已被关闭时只补启 explorer desktop，不重置 prefix，也不结束其它窗口。
    if (app.launchTarget.kind === LaunchKind.WINE_DESKTOP &&
      presentationMode === WinePresentationMode.DESKTOP) {
      const engine = WineEngineService.getInstance();
      const wasDesktopReady = engine.isReady() &&
        engine.getPresentationMode() === WinePresentationMode.DESKTOP;
      const ready = await engine.ensureReady(mode, presentationMode, homeDirectory);
      if (!ready) return null;
      const currentDesktop = this.syncDesktopSessionFromNative();
      if (currentDesktop && currentDesktop.toplevelId > 0) {
        // The root event already starts the singleton DesktopAbility. Calling
        // startAbility again here creates a visible PC desktop pop-up on every
        // first launch; only explicitly restore a stopped/background ability.
        if (!WineWindowManager.getInstance().isDesktopAbilityForeground(currentDesktop.toplevelId)) {
          await this.resume(currentDesktop);
        } else {
          // The singleton DesktopAbility is already the visible host for this
          // root. Calling startAbility again on PC creates a second mission/
          // popup even though the Wine session is unchanged.
          try { testNapi.activateWineSession(currentDesktop.sessionId); } catch (_) {}
          try { testNapi.raiseToplevel(currentDesktop.toplevelId); } catch (_) {}
        }
        return currentDesktop;
      }
      // 首次启动时 native launch thread 正在创建 explorer，不能抢跑出第二个 shell。
      if (!wasDesktopReady) return this.ensureDesktopSession();
      // 已就绪引擎也给短暂的 surface 重建留出时间；稳定缺 root 才恢复 shell。
      const settlingDesktop = await this.waitForDesktopRoot();
      if (settlingDesktop && settlingDesktop.toplevelId > 0) return settlingDesktop;
      const restarted = engine.restartDesktopShell();
      if (!restarted || restarted.pid <= 0) return null;
      return this.ensureDesktopSession();
    }
    let existing = this.findByAppId(app.id);
    if (!existing) {
      existing = this.findByExecutable(app.launchTarget.executable);
      // The desktop shell is also explorer.exe, but it is not a File Explorer
      // window.  Do not let path-singleton reuse turn the system Explorer card
      // into a no-op that merely raises the desktop root.
      if (existing && existing.sessionId === DESKTOP_SESSION_ID && app.id !== DESKTOP_APP_ID) {
        existing = null;
      }
    }
    if (existing) {
      await this.resume(existing);
      return existing;
    }


    // 程序/游戏：事件驱动启动。
    // - 引擎已 READY 且模式匹配 → 直接启动；
    // - 未就绪 → 挂到引擎 READY 事件，由"桌面就绪"事件触发真正启动，
    //   避免 ensureReady 返回后继续执行造成的竞态（桌面会话未入表、
    //   DesktopAbility startAbility 阻塞等）。
    const engine = WineEngineService.getInstance();
    if (engine.isReady() && engine.getPresentationMode() === presentationMode) {
      return this.launchReady(app, settings, mode, presentationMode, homeDirectory);
    }
    return this.deferLaunchUntilReady(app, settings, mode, presentationMode, homeDirectory);
  }

  private async launchReady(app: AppDescriptor, settings: GlobalSettings,
    mode: DisplayMode, presentationMode: WinePresentationMode,
    homeDirectory: string): Promise<RuntimeSession | null> {
    const engine = WineEngineService.getInstance();
    if (engine.getState() !== EngineState.READY ||
      engine.getPresentationMode() !== presentationMode) {
      // 状态在检查后变化：重新走事件队列。
      return this.deferLaunchUntilReady(app, settings, mode, presentationMode, homeDirectory);
    }

    if (presentationMode === WinePresentationMode.DESKTOP) {
      // 游戏/程序：引擎已 READY（桌面根已注册）。只做轻量窗口激活，
      // 绝不 await resume()/startAbility——冷启动时 DesktopAbility 正由
      // desktop_root 事件启动，startAbility 可能阻塞导致启动永久挂起。
      const desktopSession = this.syncDesktopSessionFromNative();
      if (desktopSession && desktopSession.toplevelId > 0) {
        try { testNapi.activateWineSession(desktopSession.sessionId); } catch (_) {}
        try { testNapi.raiseToplevel(desktopSession.toplevelId); } catch (_) {}
      } else {
        hilog.warn(DOMAIN, '[SESS]', 'desktop session not tracked yet; continuing program launch');
      }
    }

    // 每游戏兼容性预设优先于全局预设；'default' 表示跟随全局。
    const appSettings = AppSettingsStore.getInstance().getAppSettings(app.id);
    const presetId = appSettings.box64Preset !== BOX64_PRESET_DEFAULT
      ? appSettings.box64Preset : settings.box64Preset;
    const envOverrides = resolveBox64PresetEnv(presetId);
    const result = WineEngineService.getInstance().launchExecutable(
      app.launchTarget.executable, app.launchTarget.arguments,
      app.launchTarget.workingDirectory, envOverrides) as NativeLaunchResult;
    if (!result || result.pid <= 0) {
      hilog.error(DOMAIN, '[SESS]', 'launch: runWineExe FAILED app=%{public}s exe=%{public}s state=%{public}s',
        app.id, app.launchTarget.executable, engine.getState());
      return null;
    }
    hilog.info(DOMAIN, '[SESS]', 'launch: spawned app=%{public}s pid=%{public}d session=%{public}s',
      app.id, result.pid, result.sessionId);
    const session: RuntimeSession = {
      sessionId: result.sessionId || 'wine-' + result.pid,
      appId: app.id,
      executable: app.launchTarget.executable,
      pid: result.pid,
      displayMode: mode,
      presentationMode: presentationMode,
      state: SessionState.RUNNING,
      toplevelId: 0,
      startedAt: Date.now()
    };
    if (result.reused) {
      const nativeSession = testNapi.getWineSession(result.sessionId) as NativeWineSessionInfo | null;
      if (nativeSession) session.toplevelId = nativeSession.toplevelId;
      testNapi.activateWineSession(result.sessionId);
    }
    this.sessions.set(session.sessionId, session);
    this.resolvePendingToplevel(session);
    // created 事件可能早于会话入表到达；若关联仍缺失，直接从 native 会话补
    // toplevelId，保证二次点击 resume 能唤起窗口而不是静默 no-op。
    if (session.toplevelId <= 0) {
      try {
        const nativeSession = testNapi.getWineSession(session.sessionId) as NativeWineSessionInfo | null;
        if (nativeSession && nativeSession.toplevelId > 0) {
          session.toplevelId = nativeSession.toplevelId;
          hilog.info(DOMAIN, '[SESS]', 'launch: native toplevel fallback sid=%{public}s tl=%{public}d',
            session.sessionId, session.toplevelId);
        }
      } catch (_) {
      }
    }
    return session;
  }

  private pendingLaunches: Array<PendingLaunchRequest> = [];
  private pendingLaunchListenerInstalled: boolean = false;
  private drainingPendingLaunches: boolean = false;

  private ensurePendingLaunchListener(): void {
    if (this.pendingLaunchListenerInstalled) return;
    this.pendingLaunchListenerInstalled = true;
    let sawPreparing = false;
    WineEngineService.getInstance().subscribe((state: EngineState): void => {
      if (state === EngineState.PREPARING || state === EngineState.SWITCHING) sawPreparing = true;

      if (state === EngineState.READY) {
        this.drainPendingLaunches();
      } else if (sawPreparing && (state === EngineState.ERROR || state === EngineState.STOPPED)) {
        // 只有引擎真实经过启动后失败/停止才拒绝挂起请求；初始 STOPPED 快照
        // 只是引擎即将启动，不能把请求直接放弃。
        const pending = this.pendingLaunches.splice(0);
        pending.forEach((req: PendingLaunchRequest) => req.resolve(null));
      }
    });
  }

  private deferLaunchUntilReady(app: AppDescriptor, settings: GlobalSettings,
    mode: DisplayMode, presentationMode: WinePresentationMode,
    homeDirectory: string): Promise<RuntimeSession | null> {
    return new Promise<RuntimeSession | null>((resolve: (result: RuntimeSession | null) => void): void => {
      this.pendingLaunches.push({ app, settings, mode, presentationMode, homeDirectory, resolve });

      this.ensurePendingLaunchListener();
      // 触发引擎启动（不 await）；引擎 READY 事件会驱动队列真正执行。
      WineEngineService.getInstance().ensureReady(mode, presentationMode, homeDirectory).catch(() => {});
      // 竞态兜底：若已经就绪立即排水。
      if (WineEngineService.getInstance().isReady()) this.drainPendingLaunches();
    });
  }

  private drainPendingLaunches(): void {
    if (this.drainingPendingLaunches) return;
    this.drainingPendingLaunches = true;
    const pending = this.pendingLaunches.splice(0);

    for (const req of pending) {
      this.launchReady(req.app, req.settings, req.mode, req.presentationMode, req.homeDirectory)
        .then((session: RuntimeSession | null) => req.resolve(session))
        .catch(() => req.resolve(null));
    }
    this.drainingPendingLaunches = false;
  }

  async switchModeAndLaunch(app: AppDescriptor, settings: GlobalSettings, homeDirectory: string): Promise<RuntimeSession | null> {
    this.sessions.clear();
    this.pendingToplevels = [];
    await WineEngineService.getInstance().switchDisplaySession();
    return this.launch(app, settings, homeDirectory);
  }

  async resume(session: RuntimeSession): Promise<void> {
    if (!this.context) return;
    try { testNapi.activateWineSession(session.sessionId); } catch (_) {}
    if (session.toplevelId <= 0) {
      // ArkTS 侧关联可能因 created 事件缺 sessionId 而丢失，从 native 会话补回。
      try {
        const nativeSession = testNapi.getWineSession(session.sessionId) as NativeWineSessionInfo | null;
        if (nativeSession && nativeSession.toplevelId > 0) {
          session.toplevelId = nativeSession.toplevelId;
          hilog.info(DOMAIN, '[SESS]', 'resume: native toplevel fallback sid=%{public}s tl=%{public}d',
            session.sessionId, session.toplevelId);
        }
      } catch (_) {
      }
    }
    if (session.toplevelId > 0) {
      try { testNapi.raiseToplevel(session.toplevelId); } catch (_) {}
    }
    if (session.presentationMode === WinePresentationMode.DESKTOP) {
      if (session.toplevelId <= 0) return;
      const want: Want = {
        bundleName: 'com.vintage.pomelopro',
        abilityName: 'DesktopAbility',
        parameters: { toplevelId: session.toplevelId }
      };
      await this.context.startAbility(want);
    } else if (session.presentationMode === WinePresentationMode.MANAGED_WINDOWS) {
      if (session.toplevelId <= 0) return;
      const managedWindow = WineWindowManager.getInstance().getWindow(session.toplevelId);
      if (managedWindow) {
        await managedWindow.showWindow();
        return;
      }
      const want: Want = {
        bundleName: 'com.vintage.pomelopro',
        abilityName: 'WineWindowAbility',
        parameters: { toplevelId: session.toplevelId }
      };
      await this.context.startAbility(want);
    }
  }

  stop(session: RuntimeSession): void {
    if (session.pid > 0 && !testNapi.stopWineSession(session.sessionId)) testNapi.killProcess(session.pid);
    session.state = SessionState.STOPPED;
    this.sessions.delete(session.sessionId);
  }

  /** Stop a card even when its ArkTS session was lost but native Wine still
   * reports the process. This is also the fallback used by the running filter. */
  stopApp(app: AppDescriptor): boolean {
    const session = this.findByAppId(app.id);
    if (session) {
      this.stop(session);
      return true;
    }
    const expectedPath = normalizeCatalogLaunchIdentity(app.launchTarget.executable);
    if (expectedPath.length === 0) return false;
    let stopped = false;
    this.getNativeProcesses().forEach((process: NativeProcessInfo): void => {
      if (process.state !== 'running' ||
        normalizeCatalogLaunchIdentity(process.path) !== expectedPath) return;
      let processStopped = false;
      try {
        if (process.sessionId && process.sessionId.length > 0) {
          processStopped = testNapi.stopWineSession(process.sessionId);
        }
      } catch (_) {
        processStopped = false;
      }
      if (!processStopped) {
        try { processStopped = testNapi.killProcess(process.pid); } catch (_) { processStopped = false; }
      }
      stopped = processStopped || stopped;
    });
    return stopped;
  }

  async stopAll(): Promise<void> {
    this.sessions.clear();
    this.pendingToplevels = [];
    await InputOverlayWindowCoordinator.getInstance().setVisible(false);
    await WineEngineService.getInstance().stopAll();
  }

  async restartEngine(mode: DisplayMode, homeDirectory: string): Promise<boolean> {
    this.sessions.clear();
    this.pendingToplevels = [];
    await InputOverlayWindowCoordinator.getInstance().setVisible(false);
    const presentationMode = resolveWinePresentationMode(LaunchKind.WINE_EXE, mode,
      AppSettingsStore.getInstance().usesManagedWineWindows());
    return WineEngineService.getInstance().restart(mode, presentationMode, homeDirectory);
  }

  async resetPrefix(): Promise<void> {
    this.sessions.clear();
    this.pendingToplevels = [];
    await InputOverlayWindowCoordinator.getInstance().setVisible(false);
    await WineEngineService.getInstance().resetPrefix();
  }

  getSessions(): RuntimeSession[] {
    this.reconcile();
    const result: RuntimeSession[] = [];
    this.sessions.forEach((session: RuntimeSession) => result.push(session));
    return result;
  }

  getSession(sessionId: string): RuntimeSession | null {
    this.reconcile();
    return this.sessions.get(sessionId) ?? null;
  }

  getRunningPaths(): Set<string> {
    const result: Set<string> = new Set<string>();
    this.reconcile();
    this.sessions.forEach((session: RuntimeSession) => {
      if (session.state !== SessionState.STOPPED && session.state !== SessionState.ERROR) {
        result.add(normalizeLaunchPath(session.executable));
      }
    });
    this.getNativeProcesses().forEach((process: NativeProcessInfo) => {
      if (process.state === 'running' && !process.path.startsWith('@engine/')) {
        result.add(normalizeLaunchPath(process.path));
      }
    });
    return result;
  }

  getRunningAppIds(): Set<string> {
    const result: Set<string> = new Set<string>();
    this.reconcile();
    this.sessions.forEach((session: RuntimeSession) => {
      if (session.state !== SessionState.STOPPED && session.state !== SessionState.ERROR) {
        result.add(session.appId);
      }
    });
    return result;
  }

  findByAppId(appId: string): RuntimeSession | null {
    this.reconcile();
    let found: RuntimeSession | null = null;
    this.sessions.forEach((session: RuntimeSession) => {
      if (session.appId === appId && session.state !== SessionState.STOPPED) found = session;
    });
    return found;
  }

  findByExecutable(path: string): RuntimeSession | null {
    const normalized = normalizeLaunchPath(path);
    this.reconcile();
    let found: RuntimeSession | null = null;
    this.sessions.forEach((session: RuntimeSession) => {
      if (normalizeLaunchPath(session.executable) === normalized && session.state !== SessionState.STOPPED) found = session;
    });
    return found;
  }

  associateToplevel(sessionId: string, clientPid: number, toplevelId: number): void {
    if (!sessionId && clientPid <= 0) {
      hilog.warn(DOMAIN, '[SESS]', 'associateToplevel with empty sessionId/clientPid tl=%{public}d (created event lacks identity)',
        toplevelId);
    }
    let matched: RuntimeSession | null = sessionId ? this.sessions.get(sessionId) ?? null : null;
    if (!matched && clientPid > 0) {
      this.sessions.forEach((session: RuntimeSession) => {
        if (session.pid === clientPid) matched = session;
      });
    }
    if (!matched && sessionId === DESKTOP_SESSION_ID &&
      WineEngineService.getInstance().getPresentationMode() === WinePresentationMode.DESKTOP) {
      matched = this.upsertDesktopSession(toplevelId, clientPid);
    }
    if (matched) {
      if (matched.pid <= 0 && clientPid > 0) matched.pid = clientPid;
      if (sessionId === DESKTOP_SESSION_ID || matched.toplevelId === 0) matched.toplevelId = toplevelId;
      matched.state = SessionState.RUNNING;
      if (sessionId === DESKTOP_SESSION_ID && matched.toplevelId > 0) {
        this.settleDesktopRootWaiters(matched);
      }
    } else if (toplevelId > 0) {
      this.pendingToplevels.push({ sessionId: sessionId, clientPid: clientPid, toplevelId: toplevelId });
      if (this.pendingToplevels.length > 16) this.pendingToplevels.shift();
    }
  }

  private resolvePendingToplevel(session: RuntimeSession): void {
    let matchIndex = -1;
    for (let index = 0; index < this.pendingToplevels.length; index++) {
      const pending = this.pendingToplevels[index];
      if ((pending.sessionId && pending.sessionId === session.sessionId) ||
        (pending.clientPid > 0 && pending.clientPid === session.pid)) {
        session.toplevelId = pending.toplevelId;
        matchIndex = index;
        break;
      }
    }
    if (matchIndex >= 0) this.pendingToplevels.splice(matchIndex, 1);
  }

  private getNativeProcesses(): NativeProcessInfo[] {
    try {
      return testNapi.getProcessList() as NativeProcessInfo[];
    } catch (_) {
      return [];
    }
  }

  private async ensureDesktopSession(): Promise<RuntimeSession | null> {
    // 桌面根注册事件或引擎失败信号是唯二的终止条件；首次 prefix 初始化慢
    // 只会让等待更久，不会把“还在正常初始化”误判成失败。
    return this.waitForDesktopRoot();
  }

  /** 等待 explorer surface 关联为 desktop root；不创建或重置任何 Wine 资源。
   *  事件驱动：root 注册（created 事件或状态同步发现）即成功放行，引擎
   *  ERROR/STOPPED 即明确失败；不依赖固定秒数轮询。 */
  private async waitForDesktopRoot(): Promise<RuntimeSession | null> {
    const existing = this.sessions.get(DESKTOP_SESSION_ID) ?? null;
    if (existing && existing.toplevelId > 0) {
      if (!WineWindowManager.getInstance().isDesktopAbilityForeground(existing.toplevelId)) await this.resume(existing);
      return existing;
    }
    let session = this.syncDesktopSessionFromNative();
    if (session && session.toplevelId > 0) {
      if (!WineWindowManager.getInstance().isDesktopAbilityForeground(session.toplevelId)) await this.resume(session);
      return session;
    }
    return new Promise<RuntimeSession | null>((resolve: (result: RuntimeSession | null) => void): void => {
      const finish = (result: RuntimeSession | null): void => {
        const index = this.desktopRootWaiters.indexOf(finish);
        if (index >= 0) this.desktopRootWaiters.splice(index, 1);
        resolve(result);
      };
      this.desktopRootWaiters.push(finish);
      // 订阅后再查一次，避免 root 在“检查”与“订阅”之间注册而漏掉事件。
      const recheck = this.syncDesktopSessionFromNative();
      if (recheck && recheck.toplevelId > 0) {
        finish(recheck);
        return;
      }
      const engineState = WineEngineService.getInstance().getState();
      if (engineState !== EngineState.READY &&
        engineState !== EngineState.PREPARING &&
        engineState !== EngineState.SWITCHING) {
        finish(null);
      }
    });
  }

  private syncDesktopSessionFromNative(): RuntimeSession | null {
    let nativeSession: NativeWineSessionInfo | null = null;
    try {
      nativeSession = testNapi.getWineSession(DESKTOP_SESSION_ID) as NativeWineSessionInfo | null;
    } catch (_) {
      nativeSession = null;
    }
    if (!nativeSession || nativeSession.pid <= 0) {
      const existing = this.sessions.get(DESKTOP_SESSION_ID) ?? null;
      if (existing && existing.toplevelId > 0 &&
        WineEngineService.getInstance().getState() === EngineState.READY) {
        return existing;
      }
      this.sessions.delete(DESKTOP_SESSION_ID);
      return null;
    }
    const session = this.upsertDesktopSession(nativeSession.toplevelId, nativeSession.pid);
    if (session.toplevelId > 0) this.settleDesktopRootWaiters(session);
    return session;
  }

  private settleDesktopRootWaiters(session: RuntimeSession | null): void {
    const waiters = this.desktopRootWaiters;
    this.desktopRootWaiters = [];
    waiters.forEach((resolve: (result: RuntimeSession | null) => void): void => resolve(session));
  }

  private upsertDesktopSession(toplevelId: number, pid: number): RuntimeSession {
    const existing = this.sessions.get(DESKTOP_SESSION_ID);
    if (existing) {
      if (pid > 0) existing.pid = pid;
      if (toplevelId > 0) existing.toplevelId = toplevelId;
      existing.state = SessionState.RUNNING;
      return existing;
    }
    const session: RuntimeSession = {
      sessionId: DESKTOP_SESSION_ID,
      appId: DESKTOP_APP_ID,
      executable: DESKTOP_EXECUTABLE,
      pid: pid > 0 ? pid : 0,
      displayMode: DisplayMode.DESKTOP,
      presentationMode: WinePresentationMode.DESKTOP,
      state: SessionState.RUNNING,
      toplevelId: toplevelId > 0 ? toplevelId : 0,
      startedAt: Date.now()
    };
    this.sessions.set(DESKTOP_SESSION_ID, session);
    this.resolvePendingToplevel(session);
    return session;
  }

  private reconcile(): void {
    if (WineEngineService.getInstance().getState() === EngineState.READY &&
      WineEngineService.getInstance().getPresentationMode() === WinePresentationMode.DESKTOP) {
      this.syncDesktopSessionFromNative();
    }
    const processes = this.getNativeProcesses();
    const activePids: Set<number> = new Set<number>();
    processes.forEach((process: NativeProcessInfo) => activePids.add(process.pid));
    const removed: string[] = [];
    this.sessions.forEach((session: RuntimeSession, id: string) => {
      if (session.pid > 0 && !activePids.has(session.pid)) removed.push(id);
      if (session.pid === 0 && WineEngineService.getInstance().getState() !== EngineState.READY) removed.push(id);
    });
    removed.forEach((id: string) => {
      const stale = this.sessions.get(id);
      hilog.info(DOMAIN, '[SESS]', 'reconcile removes session=%{public}s pid=%{public}d state=%{public}s',
        id, stale ? stale.pid : -1, stale ? stale.state : 'gone');
      this.sessions.delete(id);
    });
  }
}
