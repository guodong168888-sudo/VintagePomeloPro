import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  AppDescriptor,
  ControlBarDirection,
  DisplayMode,
  GlobalSettings,
  ViewMode,
  cloneVirtualMouseConfig,
  createDefaultAppSettings,
  createDefaultGlobalSettings
} from '../model/AppModels';

const STORE_NAME = 'vintage_pomelo_pro';
const GLOBAL_KEY = 'global_settings_v1';
const APP_SETTINGS_KEY = 'app_settings_v1';
const LIBRARY_PATH_KEY = 'library_path_v1';
const CATALOG_CACHE_KEY = 'catalog_cache_v1';

export class AppSettingsStore {
  private static instance: AppSettingsStore | null = null;
  private store: preferences.Preferences | null = null;
  private appSettings: Map<string, AppSettings> = new Map<string, AppSettings>();
  private globalSettings: GlobalSettings = createDefaultGlobalSettings();
  private libraryPath: string = '';

  static getInstance(): AppSettingsStore {
    if (!AppSettingsStore.instance) AppSettingsStore.instance = new AppSettingsStore();
    return AppSettingsStore.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store) return;
    this.store = await preferences.getPreferences(context, STORE_NAME);
    this.loadGlobal();
    this.loadApps();
    this.libraryPath = this.store.getSync(LIBRARY_PATH_KEY, '') as string;
  }

  private loadGlobal(): void {
    if (!this.store) return;
    const raw = this.store.getSync(GLOBAL_KEY, '') as string;
    if (!raw) return;
    try {
      const stored = JSON.parse(raw) as GlobalSettings;
      const defaults = createDefaultGlobalSettings();
      this.globalSettings = {
        defaultDisplayMode: stored.defaultDisplayMode ?? defaults.defaultDisplayMode,
        desktopInputProfileId: stored.desktopInputProfileId ?? defaults.desktopInputProfileId,
        viewMode: stored.viewMode ?? defaults.viewMode,
        themeMode: stored.themeMode ?? defaults.themeMode,
        useGlassEffect: stored.useGlassEffect ?? defaults.useGlassEffect,
        usePageBackground: stored.usePageBackground ?? defaults.usePageBackground,
        pageBackgroundUri: stored.pageBackgroundUri ?? defaults.pageBackgroundUri,
        virtualInputEnabled: stored.virtualInputEnabled ?? defaults.virtualInputEnabled,
        showVirtualControls: stored.showVirtualControls ?? defaults.showVirtualControls,
        autoHideVirtualControls: stored.autoHideVirtualControls ?? defaults.autoHideVirtualControls,
        controlBarDirection: stored.controlBarDirection ?? ControlBarDirection.AUTO,
        virtualMouseConfig: cloneVirtualMouseConfig(stored.virtualMouseConfig ?? defaults.virtualMouseConfig),
        controlOpacity: stored.controlOpacity ?? defaults.controlOpacity,
        gamepadDeadzone: stored.gamepadDeadzone ?? defaults.gamepadDeadzone,
        outputScale: stored.outputScale ?? defaults.outputScale
      };
    } catch (_) {
      this.globalSettings = createDefaultGlobalSettings();
    }
  }

  private loadApps(): void {
    if (!this.store) return;
    const raw = this.store.getSync(APP_SETTINGS_KEY, '') as string;
    if (!raw) return;
    try {
      const values = JSON.parse(raw) as AppSettings[];
      values.forEach((value: AppSettings) => this.appSettings.set(value.appId, this.normalizeAppSettings(value)));
    } catch (_) {
      this.appSettings.clear();
    }
  }

  private normalizeAppSettings(value: AppSettings): AppSettings {
    const defaults = createDefaultAppSettings(value.appId);
    return {
      appId: value.appId,
      customTitle: value.customTitle ?? defaults.customTitle,
      customCover: value.customCover ?? defaults.customCover,
      favorite: value.favorite ?? defaults.favorite,
      executable: value.executable ?? defaults.executable,
      arguments: value.arguments ?? defaults.arguments,
      workingDirectory: value.workingDirectory ?? defaults.workingDirectory,
      displayModeOverride: value.displayModeOverride ?? defaults.displayModeOverride,
      inputProfileId: value.inputProfileId ?? defaults.inputProfileId,
      prefixId: value.prefixId ?? defaults.prefixId
    };
  }

  getGlobalSettings(): GlobalSettings {
    return this.globalSettings;
  }

  async saveGlobalSettings(value: GlobalSettings): Promise<void> {
    this.globalSettings = value;
    if (!this.store) return;
    await this.store.put(GLOBAL_KEY, JSON.stringify(value));
    await this.store.flush();
  }

  async setViewMode(value: ViewMode): Promise<void> {
    const current = this.globalSettings;
    await this.saveGlobalSettings({
      defaultDisplayMode: current.defaultDisplayMode,
      desktopInputProfileId: current.desktopInputProfileId,
      viewMode: value,
      themeMode: current.themeMode,
      useGlassEffect: current.useGlassEffect,
      usePageBackground: current.usePageBackground,
      pageBackgroundUri: current.pageBackgroundUri,
      virtualInputEnabled: current.virtualInputEnabled,
      showVirtualControls: current.showVirtualControls,
      autoHideVirtualControls: current.autoHideVirtualControls,
      controlBarDirection: current.controlBarDirection,
      virtualMouseConfig: cloneVirtualMouseConfig(current.virtualMouseConfig),
      controlOpacity: current.controlOpacity,
      gamepadDeadzone: current.gamepadDeadzone,
      outputScale: current.outputScale
    });
  }

  async setDefaultDisplayMode(value: DisplayMode): Promise<void> {
    const current = this.globalSettings;
    await this.saveGlobalSettings({
      defaultDisplayMode: value,
      desktopInputProfileId: current.desktopInputProfileId,
      viewMode: current.viewMode,
      themeMode: current.themeMode,
      useGlassEffect: current.useGlassEffect,
      usePageBackground: current.usePageBackground,
      pageBackgroundUri: current.pageBackgroundUri,
      virtualInputEnabled: current.virtualInputEnabled,
      showVirtualControls: current.showVirtualControls,
      autoHideVirtualControls: current.autoHideVirtualControls,
      controlBarDirection: current.controlBarDirection,
      virtualMouseConfig: cloneVirtualMouseConfig(current.virtualMouseConfig),
      controlOpacity: current.controlOpacity,
      gamepadDeadzone: current.gamepadDeadzone,
      outputScale: current.outputScale
    });
  }

  getAppSettings(appId: string): AppSettings {
    return this.appSettings.get(appId) ?? createDefaultAppSettings(appId);
  }

  async saveAppSettings(value: AppSettings): Promise<void> {
    this.appSettings.set(value.appId, this.normalizeAppSettings(value));
    if (!this.store) return;
    const values: AppSettings[] = [];
    this.appSettings.forEach((item: AppSettings) => values.push(item));
    await this.store.put(APP_SETTINGS_KEY, JSON.stringify(values));
    await this.store.flush();
  }

  async removeAppSettings(appId: string): Promise<void> {
    this.appSettings.delete(appId);
    if (!this.store) return;
    const values: AppSettings[] = [];
    this.appSettings.forEach((item: AppSettings) => values.push(item));
    await this.store.put(APP_SETTINGS_KEY, JSON.stringify(values));
    await this.store.flush();
  }

  getLibraryPath(): string {
    return this.libraryPath;
  }

  getCatalogCache(): AppDescriptor[] {
    if (!this.store) return [];
    const raw = this.store.getSync(CATALOG_CACHE_KEY, '') as string;
    if (!raw) return [];
    try {
      return JSON.parse(raw) as AppDescriptor[];
    } catch (_) {
      return [];
    }
  }

  async saveCatalogCache(apps: AppDescriptor[]): Promise<void> {
    if (!this.store) return;
    await this.store.put(CATALOG_CACHE_KEY, JSON.stringify(apps));
    await this.store.flush();
  }

  async removeCachedApp(appId: string): Promise<void> {
    const apps = this.getCatalogCache().filter((item: AppDescriptor) => item.id !== appId);
    await this.saveCatalogCache(apps);
    await this.removeAppSettings(appId);
  }

  async saveLibraryPath(path: string): Promise<void> {
    this.libraryPath = path;
    if (!this.store) return;
    await this.store.put(LIBRARY_PATH_KEY, path);
    await this.store.flush();
  }
}
