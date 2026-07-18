import { common } from '@kit.AbilityKit';
import { Environment, fileIo as fs } from '@kit.CoreFileKit';
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
  displayMode: string;
}

interface BuiltinCatalogFile {
  version: number;
  apps: BuiltinCatalogItem[];
}

const CATALOG_RAWFILE = 'builtin_apps/catalog.json';
const APPLICATION_DIRECTORY = 'com.vintage.pomelopro';
const GAMES_DIRECTORY = 'games';

function exists(path: string): boolean {
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

  static getInstance(): AppCatalogService {
    if (!AppCatalogService.instance) AppCatalogService.instance = new AppCatalogService();
    return AppCatalogService.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  getLibraryRoot(): string {
    try {
      return joinPath(Environment.getUserDownloadDir(), APPLICATION_DIRECTORY);
    } catch (_) {
      const savedPath = AppSettingsStore.getInstance().getLibraryPath().replace(/\/$/, '');
      return savedPath.endsWith('/' + APPLICATION_DIRECTORY) ? savedPath : '';
    }
  }

  getWineHomeDirectory(): string {
    try {
      return Environment.getUserDownloadDir();
    } catch (_) {
      return '/storage/Users/currentUser/Download';
    }
  }

  getGamesDirectory(): string {
    const root = this.getLibraryRoot();
    return root ? joinPath(root, GAMES_DIRECTORY) : '';
  }

  async authorizeLibrary(): Promise<string> {
    let path = '';
    try {
      path = joinPath(Environment.getUserDownloadDir(), APPLICATION_DIRECTORY);
    } catch (_) {
      return '';
    }
    const gamesPath = joinPath(path, GAMES_DIRECTORY);
    if (!exists(gamesPath)) fs.mkdirSync(gamesPath, true);
    await AppSettingsStore.getInstance().saveLibraryPath(path);
    return path;
  }

  async scan(): Promise<AppDescriptor[]> {
    const merged: AppDescriptor[] = [];
    const builtins = this.loadBuiltins();
    builtins.forEach((item: AppDescriptor) => merged.push(item));

    const gamesPath = this.getGamesDirectory();
    if (gamesPath && isDirectory(gamesPath)) {
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
      const mode = item.displayMode === DisplayMode.SINGLE_APP ? DisplayMode.SINGLE_APP : DisplayMode.DESKTOP;
      const id = item.id || stableAppId(AppSource.BUILTIN, item.launchParams.executable);
      const settings = AppSettingsStore.getInstance().getAppSettings(id);
      const target: LaunchTarget = {
        kind: kind,
        executable: settings.executable || item.launchParams.executable,
        arguments: settings.arguments.length > 0 ? settings.arguments : item.launchParams.arguments ?? [],
        workingDirectory: settings.workingDirectory || (item.launchParams.workingDirectory ?? '')
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
        { id: 'builtin-desktop', title: 'Wine 桌面', launchKind: 'wine-desktop', launchParams: { executable: 'explorer.exe' }, cover: '', displayMode: 'desktop' },
        { id: 'builtin-winecfg', title: 'Wine 配置', launchKind: 'wine-system', launchParams: { executable: 'winecfg.exe' }, cover: '', displayMode: 'desktop' },
        { id: 'builtin-control', title: '控制面板', launchKind: 'wine-system', launchParams: { executable: 'control.exe' }, cover: '', displayMode: 'desktop' },
        { id: 'builtin-taskmgr', title: '任务管理器', launchKind: 'wine-system', launchParams: { executable: 'taskmgr.exe' }, cover: '', displayMode: 'desktop' },
        { id: 'builtin-regedit', title: '注册表编辑器', launchKind: 'wine-system', launchParams: { executable: 'regedit.exe' }, cover: '', displayMode: 'desktop' },
        { id: 'builtin-cmd', title: '命令提示符', launchKind: 'wine-system', launchParams: { executable: 'cmd.exe' }, cover: '', displayMode: 'desktop' }
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
