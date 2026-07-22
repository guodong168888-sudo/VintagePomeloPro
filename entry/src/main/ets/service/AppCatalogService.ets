import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import util from '@ohos.util';
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
  chooseExecutablePath
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
const APPLICATION_DIRECTORY = 'com.vintage.pomelopro';
const GAMES_DIRECTORY = 'games';
const DOWNLOAD_LIBRARY_URI = 'file://docs/storage/Users/currentUser/Download/com.vintage.pomelopro';

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
      return new fileUri.FileUri(DOWNLOAD_LIBRARY_URI).path;
    } catch (_) {
      return '';
    }
  }

  getWineHomeDirectory(): string {
    const gamesPath = this.ensureGamesDirectory();
    if (gamesPath) return this.getLibraryRoot();
    return '/storage/Users/currentUser/Download/' + APPLICATION_DIRECTORY;
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
    return this.ensureGamesDirectory().length > 0;
  }

  private ensureGamesDirectory(): string {
    const libraryRoot = this.getLibraryRoot();
    if (!libraryRoot) return '';
    const gamesPath = joinPath(libraryRoot, GAMES_DIRECTORY);
    try {
      // 与 VintagePomelo 一致，分两级创建且不传非标准 recursive 参数。
      if (!isDirectory(libraryRoot)) fs.mkdirSync(libraryRoot);
      if (!isDirectory(gamesPath)) fs.mkdirSync(gamesPath);
      return isDirectory(gamesPath) ? gamesPath : '';
    } catch (_) {
      return '';
    }
  }

  /** 兼容旧调用方；实际行为仅为确保专用目录存在，不弹授权。 */
  async authorizeLibrary(): Promise<string> {
    const gamesPath = this.ensureGamesDirectory();
    return gamesPath ? this.getLibraryRoot() : '';
  }

  async scan(): Promise<AppDescriptor[]> {
    const merged: AppDescriptor[] = [];
    const builtins = this.loadBuiltins();
    builtins.forEach((item: AppDescriptor) => merged.push(item));

    const gamesPath = this.ensureGamesDirectory();
    if (gamesPath) {
      const external = this.scanExternal(gamesPath);
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
      cached.available = exists(cached.launchTarget.executable);
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
      } else if (name.toLowerCase().endsWith('.exe')) {
        result.push(this.createExternalApp(path, gamesPath, withoutExtension(name), ''));
      }
    });
    return result;
  }

  private createDirectoryApp(directory: string): AppDescriptor | null {
    const candidates = this.collectExecutables(directory, 0);
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

  private collectExecutables(directory: string, depth: number): string[] {
    const result: string[] = [];
    if (depth > 5) return result;
    let names: string[] = [];
    try {
      names = fs.listFileSync(directory);
    } catch (_) {
      return result;
    }
    names.forEach((name: string) => {
      const path = joinPath(directory, name);
      if (isDirectory(path)) {
        const nested = this.collectExecutables(path, depth + 1);
        nested.forEach((item: string) => result.push(item));
      } else if (name.toLowerCase().endsWith('.exe')) {
        result.push(path);
      }
    });
    return result;
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
