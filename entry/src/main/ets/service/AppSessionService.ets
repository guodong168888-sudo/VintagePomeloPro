import { common, Want } from '@kit.AbilityKit';
import testNapi from 'libentry.so';
import {
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
  resolveLaunchDisplayMode,
  resolveWinePresentationMode
} from '../model/AppModels';
import { WineEngineService } from './WineEngineService';
import { WineWindowManager } from './WineWindowManager';
import { InputOverlayWindowCoordinator } from './InputOverlayWindowCoordinator';
import { AppSettingsStore } from './AppSettingsStore';

export enum LaunchConflictKind {
  NONE = 'none',
  DISPLAY_MODE = 'display-mode',
  SINGLE_APP = 'single-app'
}

interface PendingToplevelAssociation {
  sessionId: string;
  clientPid: number;
  toplevelId: number;
}

const DESKTOP_SESSION_ID = 'desktop';
const DESKTOP_APP_ID = 'builtin-desktop';
const DESKTOP_EXECUTABLE = 'explorer.exe';

export class AppSessionService {
  private static instance: AppSessionService | null = null;
  private context: common.UIAbilityContext | null = null;
  private sessions: Map<string, RuntimeSession> = new Map<string, RuntimeSession>();
  private pendingToplevels: PendingToplevelAssociation[] = [];

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
    if (requestedPresentation === WinePresentationMode.SINGLE_APP && engine.isReady()) {
      const requestedPath = normalizeLaunchPath(app.launchTarget.executable);
      const running = this.getRunningPaths();
      let hasDifferentPath = false;
      running.forEach((path: string) => {
        if (path !== requestedPath) hasDifferentPath = true;
      });
      if (hasDifferentPath) return LaunchConflictKind.SINGLE_APP;
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
      const settlingDesktop = await this.waitForDesktopRoot(8);
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

    const ready = await WineEngineService.getInstance().ensureReady(mode, presentationMode, homeDirectory);
    if (!ready) return null;

    if (presentationMode === WinePresentationMode.DESKTOP) {
      const desktopSession = await this.ensureDesktopSession();
      if (!desktopSession) return null;
      if (app.launchTarget.kind === LaunchKind.WINE_DESKTOP) return desktopSession;
    }

    const result = WineEngineService.getInstance().launchExecutable(
      app.launchTarget.executable, app.launchTarget.arguments,
      app.launchTarget.workingDirectory) as NativeLaunchResult;
    if (!result || result.pid <= 0) return null;
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
    return session;
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
    } else {
      if (session.toplevelId <= 0) return;
      const want: Want = {
        bundleName: 'com.vintage.pomelopro',
        abilityName: 'SingleAppAbility',
        parameters: { toplevelId: session.toplevelId, sessionId: session.sessionId }
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
      const shouldResumeSingleApp = matched.toplevelId === 0 && toplevelId > 0 &&
        matched.displayMode === DisplayMode.SINGLE_APP;
      if (matched.pid <= 0 && clientPid > 0) matched.pid = clientPid;
      if (sessionId === DESKTOP_SESSION_ID || matched.toplevelId === 0) matched.toplevelId = toplevelId;
      matched.state = SessionState.RUNNING;
      if (shouldResumeSingleApp) {
        this.resume(matched).catch((_error: Error): void => {});
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
    // On ARM phones/tablets the first Explorer surface can arrive well after
    // appspawn accepted the process, especially during first prefix setup or
    // a slow Explorer desktop-root handoff. Ten seconds made the first card fail while a retry a
    // moment later succeeded. Keep the wait bounded but cover the slow path.
    return this.waitForDesktopRoot(120);
  }

  /** 等待 explorer surface 关联为 desktop root；不创建或重置任何 Wine 资源。 */
  private async waitForDesktopRoot(rounds: number): Promise<RuntimeSession | null> {
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
    const pending = session;
    for (let index = 0; index < rounds; index++) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout((): void => resolve(), 250);
      });
      session = this.syncDesktopSessionFromNative();
      if (session && session.toplevelId > 0) {
        if (!WineWindowManager.getInstance().isDesktopAbilityForeground(session.toplevelId)) await this.resume(session);
        return session;
      }
    }
    return session ?? pending ?? null;
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
    return this.upsertDesktopSession(nativeSession.toplevelId, nativeSession.pid);
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
    removed.forEach((id: string) => this.sessions.delete(id));
  }
}
