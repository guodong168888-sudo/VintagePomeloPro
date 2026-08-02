import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import util from '@ohos.util';
import bundleManager from '@ohos.bundle.bundleManager';
import {
  AppDescriptor,
  AppSettings,
  AppSource,
  DisplayMode,
  LaunchKind,
  LaunchTarget,
  stableAppId
} from '../model/AppModels';
import { AppSettingsStore } from './AppSettingsStore';
import {
  catalogFileName,
  catalogNameWithoutExtension,
  chooseCoverFileName,
  chooseExecutablePath,
  isWindowsLaunchTarget,
  shouldRetainMissingCachedCard
} from '../model/AppCatalogRules';

interface BuiltinLaunchParams {
  executable: string;
  arguments?: string[];
  workingDirectory?: string;
}

interface BuiltinCatalogItem {
  id: string;
  title: string;
  launchKind: string;
  launchParams: BuiltinLaunchParams;
  cover: string;
  displayMode?: string;
}

interface BuiltinCatalogFile {
  version: number;
  apps: BuiltinCatalogItem[];
}

const CATALOG_RAWFILE = 'builtin_apps/catalog.json';
const GAMES_DIRECTORY = 'games';
const DOMAIN = 0x0000;
const TAG = 'AppCatalog';

// The Download/<bundleName> directory is app-scoped and system-owned. Resolve
// the bundle name from the API at runtime (same approach as VintagePomelo)
// instead of hardcoding it, so the library path can never drift from the
// installed bundle identity.
let cachedDownloadLibraryRoot = '';

function resolveDownloadLibraryRoot(): string {
  if (cachedDownloadLibraryRoot) return cachedDownloadLibraryRoot;
  try {
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const uri = `file://docs/storage/Users/currentUser/Download/${bundleInfo.name}`;
    cachedDownloadLibraryRoot = new fileUri.FileUri(uri).path;
  } catch (_) {
    cachedDownloadLibraryRoot = '';
  }
  return cachedDownloadLibraryRoot;
}

export interface GamesDirectoryStatus {
  root: string;
  games: string;
  ready: boolean;
  error: string;
}

function exists(path: string): boolean {
  if (!path || path.trim().length === 0) return false;
  try {
    fs.accessSync(path);
    return true;
  } catch (_) {
    return false;
  }
}

function isDirectory(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory();
  } catch (_) {
    return false;
  }
}

function describeFileError(error: Object): string {
  try {
    const failure = error as BusinessError;
    if (failure.message) return failure.message + ' (' + failure.code.toString() + ')';
  } catch (_) {
  }
  try {
    const encoded = JSON.stringify(error);
    if (encoded && encoded !== '{}') return encoded;
  } catch (_) {
  }
  return 'filesystem operation failed';
}

/**
 * Create one directory and verify the result. The docs-backed Download
 * provider creates app-scoped children reliably with a direct mkdir, but its
 * recursive mkdir path fails when the bundle directory does not exist yet.
 * ensureGamesDirectory deliberately calls this once for the bundle directory
 * and then once for games/, matching the platform/VintagePomelo pattern.
 */
function ensureDirectory(path: string): string {
  if (!path || path.trim().length === 0) return 'resolved path is empty';
  try {
    const existing = fs.statSync(path);
    return existing.isDirectory() ? '' : 'path exists but is not a directory';
  } catch (_) {
  }
  try {
    fs.mkdirSync(path);
  } catch (error) {
    // Another process may have created it between stat and mkdir.
    try {
      const created = fs.statSync(path);
      if (created.isDirectory()) return '';
    } catch (_) {
    }
    return describeFileError(error);
  }
  try {
    const created = fs.statSync(path);
    return created.isDirectory() ? '' : 'created path is not a directory';
  } catch (error) {
    return describeFileError(error);
  }
}

/**
 * mkdir can succeed while the mount is read-only or the directory is
 * otherwise unusable. Probe with a real create/delete so "ready" means the
 * games directory can actually hold game files.
 */
function verifyDirectoryWritable(dir: string): string {
  const probe = joinPath(dir, '.winehua_write_probe');
  try {
    const output = fs.openSync(probe,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(output.fd, 'ok');
    } finally {
      fs.closeSync(output);
    }
    try {
      fs.unlinkSync(probe);
    } catch (_) {
    }
    return '';
  } catch (error) {
    return describeFileError(error);
  }
}

function fileName(path: string): string {
  return catalogFileName(path);
}

function withoutExtension(name: string): string {
  return catalogNameWithoutExtension(name);
}

function joinPath(parent: string, child: string): string {
  return parent.endsWith('/') ? parent + child : parent + '/' + child;
}

export class AppCatalogService {
  private static instance: AppCatalogService | null = null;
  private context: common.UIAbilityContext | null = null;
  private apps: AppDescriptor[] = [];
  private libraryRoot: string = '';
  private directoryStatus: GamesDirectoryStatus = {
    root: '',
    games: '',
    ready: false,
    error: 'games directory has not been checked'
  };

  static getInstance(): AppCatalogService {
    if (!AppCatalogService.instance) AppCatalogService.instance = new AppCatalogService();
    return AppCatalogService.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.libraryRoot = this.directLibraryRoot();
    this.ensureGamesDirectory();
  }

  getLibraryRoot(): string {
    if (this.libraryRoot) return this.libraryRoot;
    return this.directLibraryRoot();
  }

  private directLibraryRoot(): string {
    try {
      return resolveDownloadLibraryRoot();
    } catch (_) {
      return '';
    }
  }

  getWineHomeDirectory(): string {
    const status = this.ensureGamesDirectory();
    // Never hand Wine an unverified HOME. Starting with a guessed path makes
    // the engine fail later and hides the actual storage error from the user.
    return status.ready ? status.root : '';
  }

  getGamesDirectory(): string {
    const root = this.getLibraryRoot();
    return root ? joinPath(root, GAMES_DIRECTORY) : '';
  }

  /**
   * games 是应用自己约定并创建的 Download 子目录，不是用户挑选的外部
   * 目录。扫描时直接确保它存在，既不申请整个 Download 权限，也不把
   * “目录授权”暴露成用户操作。
   */
  isGamesDirectoryReady(): boolean {
    return this.ensureGamesDirectory().ready;
  }

  getGamesDirectoryStatus(): GamesDirectoryStatus {
    const status = this.ensureGamesDirectory();
    return {
      root: status.root,
      games: status.games,
      ready: status.ready,
      error: status.error
    };
  }

  getGamesDirectoryError(): string {
    return this.ensureGamesDirectory().error;
  }

  /**
   * Returns every supported Windows launch target below one card's game
   * directory. The result is deliberately constrained to the app-owned games
   * library: re-association must not become a shortcut to an arbitrary file in
   * the system picker.
   */
  getGameLaunchTargetCandidates(directory: string): string[] {
    const status = this.ensureGamesDirectory();
    if (!status.ready || !this.isPathInsideDirectory(directory, status.games)) return [];
    const normalizedDirectory = directory.replace(/\\/g, '/').replace(/\/+$/, '');
    const normalizedGames = status.games.replace(/\\/g, '/').replace(/\/+$/, '');
    // Standalone files placed directly in games/ form their own root-level
    // cards. Do not let one such card browse into every sibling game's folder.
    return this.collectLaunchTargets(directory, normalizedDirectory !== normalizedGames);
  }

  ensureGamesDirectory(): GamesDirectoryStatus {
    const libraryRoot = this.getLibraryRoot();
    const gamesPath = joinPath(libraryRoot, GAMES_DIRECTORY);
    if (!libraryRoot) {
      this.directoryStatus = {
        root: '',
        games: '',
        ready: false,
        error: 'Download library path could not be resolved'
      };
      hilog.error(DOMAIN, TAG, 'Download library path could not be resolved');
      return this.directoryStatus;
    }

    const rootError = ensureDirectory(libraryRoot);
    if (rootError) {
      this.directoryStatus = {
        root: libraryRoot,
        games: gamesPath,
        ready: false,
        error: 'library: ' + rootError
      };
      hilog.error(DOMAIN, TAG, 'Failed to prepare Download library %{public}s: %{public}s',
        libraryRoot, rootError);
      return this.directoryStatus;
    }

    const gamesError = ensureDirectory(gamesPath);
    if (gamesError) {
      this.directoryStatus = {
        root: libraryRoot,
        games: gamesPath,
        ready: false,
        error: 'games: ' + gamesError
      };
      hilog.error(DOMAIN, TAG, 'Failed to prepare games directory %{public}s: %{public}s',
        gamesPath, gamesError);
      return this.directoryStatus;
    }

    const writeError = verifyDirectoryWritable(gamesPath);
    if (writeError) {
      this.directoryStatus = {
        root: libraryRoot,
        games: gamesPath,
        ready: false,
        error: 'games-writable: ' + writeError
      };
      hilog.error(DOMAIN, TAG, 'Games directory is not writable %{public}s: %{public}s',
        gamesPath, writeError);
      return this.directoryStatus;
    }

    this.directoryStatus = { root: libraryRoot, games: gamesPath, ready: true, error: '' };
    hilog.info(DOMAIN, TAG, 'Download games directory ready: %{public}s', gamesPath);
    return this.directoryStatus;
  }

  /** 兼容旧调用方；实际行为仅为确保专用目录存在，不弹授权。 */
  async authorizeLibrary(): Promise<string> {
    const status = this.ensureGamesDirectory();
    return status.ready ? status.root : '';
  }

  /**
   * Public Download does not allow an application to recreate its own first
   * level directory with raw file I/O after that directory was removed.
   * DocumentPicker DOWNLOAD mode is the platform-supported provisioning path:
   * the user confirms once, the system recreates Download/<bundle>, and this
   * service can then create games/ normally.
   */
  async provisionGamesDirectory(): Promise<GamesDirectoryStatus> {
    const current = this.ensureGamesDirectory();
    if (current.ready) return current;
    if (!this.context) {
      this.directoryStatus = {
        root: current.root,
        games: current.games,
        ready: false,
        error: 'application context is not initialized'
      };
      return this.directoryStatus;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris = await documentPicker.save(options);
      if (uris.length === 0 || !uris[0]) {
        this.directoryStatus = {
          root: current.root,
          games: current.games,
          ready: false,
          error: 'system Download provisioning returned no directory'
        };
        return this.directoryStatus;
      }
      const provisionedRoot = new fileUri.FileUri(uris[0]).path.replace(/\/+$/, '');
      const expectedRoot = resolveDownloadLibraryRoot().replace(/\/+$/, '');
      if (provisionedRoot !== expectedRoot) {
        this.directoryStatus = {
          root: expectedRoot,
          games: joinPath(expectedRoot, GAMES_DIRECTORY),
          ready: false,
          error: 'system returned an unexpected Download directory'
        };
        return this.directoryStatus;
      }
      this.libraryRoot = provisionedRoot;
      cachedDownloadLibraryRoot = provisionedRoot;
      hilog.info(DOMAIN, TAG, 'System provisioned Download library: %{public}s', provisionedRoot);
      return this.ensureGamesDirectory();
    } catch (error) {
      this.directoryStatus = {
        root: current.root,
        games: current.games,
        ready: false,
        error: 'system Download provisioning: ' + describeFileError(error as Object)
      };
      hilog.warn(DOMAIN, TAG, 'System Download provisioning was not completed: %{public}s',
        this.directoryStatus.error);
      return this.directoryStatus;
    }
  }

  async scan(): Promise<AppDescriptor[]> {
    const merged: AppDescriptor[] = [];
    const builtins = this.loadBuiltins();
    builtins.forEach((item: AppDescriptor) => merged.push(item));

    const directoryStatus = this.ensureGamesDirectory();
    if (directoryStatus.ready) {
      const external = this.scanExternal(directoryStatus.games);
      external.forEach((item: AppDescriptor) => merged.push(item));
    }

    const currentIds: Set<string> = new Set<string>();
    merged.forEach((item: AppDescriptor) => currentIds.add(item.id));
    AppSettingsStore.getInstance().getCatalogCache().forEach((cached: AppDescriptor) => {
      if (cached.source !== AppSource.DOWNLOAD || currentIds.has(cached.id)) return;
      const settings = AppSettingsStore.getInstance().getAppSettings(cached.id);
      cached.title = settings.customTitle || cached.title;
      cached.coverPath = settings.customCover || cached.coverPath;
      cached.launchTarget.executable = settings.executable || cached.launchTarget.executable;
      cached.launchTarget.arguments = settings.arguments;
      cached.launchTarget.workingDirectory = settings.workingDirectory || cached.launchTarget.workingDirectory;
      cached.displayModeOverride = settings.displayModeOverride;
      const directoryStillExists = isDirectory(cached.directory);
      const executableStillExists = exists(cached.launchTarget.executable);
      const normalizedDirectory = cached.directory.replace(/\\/g, '/').replace(/\/+$/, '');
      const normalizedGames = directoryStatus.games.replace(/\\/g, '/').replace(/\/+$/, '');
      // A deleted game folder must disappear on the next scan. Directory
      // cards remain only when their folder still exists, so users can choose
      // a replacement launcher after an EXE was renamed or removed. A loose
      // executable directly under games/ has no distinct folder and is
      // removed as soon as that executable disappears.
      if (!shouldRetainMissingCachedCard(directoryStillExists, executableStillExists,
        normalizedDirectory === normalizedGames)) return;
      cached.available = executableStillExists;
      merged.push(cached);
    });

    merged.sort((left: AppDescriptor, right: AppDescriptor) => {
      if (left.source !== right.source) return left.source === AppSource.BUILTIN ? -1 : 1;
      return left.title.localeCompare(right.title);
    });
    this.apps = merged;
    await AppSettingsStore.getInstance().saveCatalogCache(merged.filter((item: AppDescriptor) => item.source === AppSource.DOWNLOAD));
    return merged;
  }

  getApps(): AppDescriptor[] {
    return this.apps;
  }

  search(query: string, source: AppSource | null, runningPaths: Set<string>): AppDescriptor[] {
    const value = query.trim().toLowerCase();
    return this.apps.filter((app: AppDescriptor) => {
      if (source && app.source !== source) return false;
      if (source === null && value === '__running__') {
        return runningPaths.has(app.launchTarget.executable.toLowerCase());
      }
      if (!value) return true;
      return app.title.toLowerCase().includes(value) ||
        app.launchTarget.executable.toLowerCase().includes(value);
    });
  }

  private loadBuiltins(): AppDescriptor[] {
    let catalog: BuiltinCatalogFile = this.defaultCatalog();
    try {
      if (this.context) {
        const bytes = this.context.resourceManager.getRawFileContentSync(CATALOG_RAWFILE);
        const decoder = util.TextDecoder.create('utf-8', { fatal: false });
        const text = decoder.decodeWithStream(bytes, { stream: false });
        catalog = JSON.parse(text) as BuiltinCatalogFile;
      }
    } catch (_) {
      catalog = this.defaultCatalog();
    }

    const result: AppDescriptor[] = [];
    catalog.apps.forEach((item: BuiltinCatalogItem) => {
      const kind = this.parseLaunchKind(item.launchKind);
      // PC/2-in-1 hosts expose each Wine program as its own ArkUI window.
      // Hiding the tablet-only shell card prevents an explicit desktop launch
      // while keeping File Explorer and every other system tool available.
      if (kind === LaunchKind.WINE_DESKTOP &&
        AppSettingsStore.getInstance().usesManagedWineWindows()) return;
      // A built-in manifest may request single-app explicitly. Otherwise it
      // follows the global desktop default. PC/2-in-1 hosts present that mode
      // as independent managed Wine windows rather than a singleton window.
      const mode: DisplayMode | null = item.displayMode === DisplayMode.SINGLE_APP ?
        DisplayMode.SINGLE_APP : null;
      const id = item.id || stableAppId(AppSource.BUILTIN, item.launchParams.executable);
      const settings = AppSettingsStore.getInstance().getAppSettings(id);
      // Built-ins are part of the Wine runtime.  Their executable and working
      // directory are manifest-owned: an old editable setting must never turn
      // a system card into an arbitrary EXE shortcut.
      const target: LaunchTarget = {
        kind: kind,
        executable: item.launchParams.executable,
        arguments: item.launchParams.arguments ?? [],
        workingDirectory: item.launchParams.workingDirectory ?? ''
      };
      result.push({
        id: id,
        title: settings.customTitle || item.title,
        source: AppSource.BUILTIN,
        directory: '',
        coverPath: settings.customCover || item.cover,
        available: target.executable.length > 0,
        launchTarget: target,
        displayModeOverride: settings.displayModeOverride ?? mode
      });
    });
    return result;
  }

  private defaultCatalog(): BuiltinCatalogFile {
    return {
      version: 1,
      apps: [
        { id: 'builtin-desktop', title: 'Wine 桌面', launchKind: 'wine-desktop', launchParams: { executable: 'explorer.exe' }, cover: '' },
        { id: 'builtin-explorer', title: '文件资源管理器', launchKind: 'wine-system', launchParams: { executable: 'explorer.exe', arguments: ['Z:\\'] }, cover: '' },
        { id: 'builtin-winecfg', title: 'Wine 配置', launchKind: 'wine-system', launchParams: { executable: 'winecfg.exe' }, cover: '' },
        { id: 'builtin-control', title: '控制面板', launchKind: 'wine-system', launchParams: { executable: 'control.exe' }, cover: '' },
        { id: 'builtin-taskmgr', title: '任务管理器', launchKind: 'wine-system', launchParams: { executable: 'taskmgr.exe' }, cover: '' },
        { id: 'builtin-regedit', title: '注册表编辑器', launchKind: 'wine-system', launchParams: { executable: 'regedit.exe' }, cover: '' },
        { id: 'builtin-cmd', title: '命令提示符', launchKind: 'wine-system', launchParams: { executable: 'wineconsole.exe', arguments: ['cmd.exe'] }, cover: '' },
        { id: 'builtin-graphics-smoke', title: '图形测试', launchKind: 'wine-system', launchParams: { executable: 'winehua_graphics_smoke.exe' }, cover: '' },
        { id: 'builtin-dxvk-cube', title: 'DXVK 立方体测试', launchKind: 'wine-system', launchParams: {
          executable: 'C:\\smoke\\x64\\winehua_d3d_switch_cube.exe', arguments: ['--d3d11'],
          workingDirectory: 'C:\\smoke\\x64' }, cover: '' },
        { id: 'builtin-audio-smoke', title: '音频测试', launchKind: 'wine-system', launchParams: { executable: 'winehua_audio_smoke.exe' }, cover: '' }
      ]
    };
  }

  private parseLaunchKind(value: string): LaunchKind {
    if (value === LaunchKind.WINE_DESKTOP) return LaunchKind.WINE_DESKTOP;
    if (value === LaunchKind.WINE_SYSTEM) return LaunchKind.WINE_SYSTEM;
    if (value === LaunchKind.HARMONY_ABILITY) return LaunchKind.HARMONY_ABILITY;
    if (value === LaunchKind.NATIVE_TOOL) return LaunchKind.NATIVE_TOOL;
    if (value === LaunchKind.OTHER_ENGINE) return LaunchKind.OTHER_ENGINE;
    return LaunchKind.WINE_EXE;
  }

  private scanExternal(gamesPath: string): AppDescriptor[] {
    const result: AppDescriptor[] = [];
    let names: string[] = [];
    try {
      names = fs.listFileSync(gamesPath);
    } catch (_) {
      return result;
    }

    names.forEach((name: string) => {
      const path = joinPath(gamesPath, name);
      if (isDirectory(path)) {
        const app = this.createDirectoryApp(path);
        if (app) result.push(app);
      } else if (isWindowsLaunchTarget(name)) {
        result.push(this.createExternalApp(path, gamesPath, withoutExtension(name), ''));
      }
    });
    return result;
  }

  private createDirectoryApp(directory: string): AppDescriptor | null {
    const candidates = this.collectLaunchTargets(directory);
    const automaticExecutable = this.chooseExecutable(directory, candidates);
    const cached = AppSettingsStore.getInstance().getCatalogCache()
      .find((item: AppDescriptor) => item.directory === directory);
    const id = cached?.id ?? stableAppId(AppSource.DOWNLOAD, automaticExecutable || directory);
    const settings = AppSettingsStore.getInstance().getAppSettings(id);
    // An explicit user choice remains authoritative even when the file was moved.
    // This lets the catalog expose an unavailable card that can be re-associated.
    const executable = settings.executable || automaticExecutable;
    const title = settings.customTitle || fileName(directory);
    const cover = settings.customCover || this.findCover(directory);
    return this.createExternalApp(executable, directory, title, cover, settings, id);
  }

  private createExternalApp(executable: string, directory: string, defaultTitle: string,
    defaultCover: string, provided?: AppSettings, providedId?: string): AppDescriptor {
    const id = providedId ?? stableAppId(AppSource.DOWNLOAD, executable);
    const settings = provided ?? AppSettingsStore.getInstance().getAppSettings(id);
    const target: LaunchTarget = {
      kind: LaunchKind.WINE_EXE,
      executable: settings.executable || executable,
      arguments: settings.arguments,
      workingDirectory: settings.workingDirectory || directory
    };
    return {
      id: id,
      title: settings.customTitle || defaultTitle,
      source: AppSource.DOWNLOAD,
      directory: directory,
      coverPath: settings.customCover || defaultCover,
      available: exists(target.executable),
      launchTarget: target,
      displayModeOverride: settings.displayModeOverride
    };
  }

  private isPathInsideDirectory(path: string, directory: string): boolean {
    const normalizedPath = path.replace(/\\/g, '/').replace(/\/+$/, '');
    const normalizedDirectory = directory.replace(/\\/g, '/').replace(/\/+$/, '');
    return normalizedPath === normalizedDirectory || normalizedPath.startsWith(normalizedDirectory + '/');
  }

  private collectLaunchTargets(directory: string, recursive: boolean = true): string[] {
    const result: string[] = [];
    let entries: string[] = [];
    try {
      // listFileSync returns paths relative to the supplied directory. Using
      // its recursive mode avoids the former five-level traversal ceiling, so
      // launchers nested under game data directories are discoverable too.
      entries = recursive ? fs.listFileSync(directory, { recursion: true }) : fs.listFileSync(directory);
    } catch (_) {
      return result;
    }
    entries.forEach((relativePath: string) => {
      const relative = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');
      // listFileSync is specified to return relative paths. Rejecting parent
      // components defensively keeps this picker rooted in its game card even
      // if a provider ever returns an unexpected entry.
      if (!relative || relative.split('/').some((part: string) => part === '..')) return;
      const path = joinPath(directory, relative);
      if (isWindowsLaunchTarget(path) && !isDirectory(path) && exists(path)) result.push(path);
    });
    return result.sort((left: string, right: string) => left.toLowerCase().localeCompare(right.toLowerCase()));
  }

  private chooseExecutable(directory: string, candidates: string[]): string {
    return chooseExecutablePath(directory, candidates);
  }

  private findCover(directory: string): string {
    let names: string[] = [];
    try {
      names = fs.listFileSync(directory);
    } catch (_) {
      return '';
    }
    const cover = chooseCoverFileName(names);
    return cover ? joinPath(directory, cover) : '';
  }
}
