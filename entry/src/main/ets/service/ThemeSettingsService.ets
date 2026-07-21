import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { GlobalSettings, ThemeMode } from '../model/AppModels';
import { AppSettingsStore } from './AppSettingsStore';

export type ThemeSettingsListener = (settings: GlobalSettings) => void;

export class ThemeSettingsService {
  private static instance: ThemeSettingsService | null = null;
  private listeners: Set<ThemeSettingsListener> = new Set<ThemeSettingsListener>();
  private context: common.UIAbilityContext | null = null;

  static getInstance(): ThemeSettingsService {
    if (!ThemeSettingsService.instance) ThemeSettingsService.instance = new ThemeSettingsService();
    return ThemeSettingsService.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    await AppSettingsStore.getInstance().initialize(context);
    this.applyColorMode(AppSettingsStore.getInstance().getGlobalSettings().themeMode);
  }

  getSettings(): GlobalSettings {
    return AppSettingsStore.getInstance().getGlobalSettings();
  }

  async update(settings: GlobalSettings): Promise<void> {
    const previousTheme = AppSettingsStore.getInstance().getGlobalSettings().themeMode;
    if (previousTheme !== settings.themeMode) {
      this.applyColorMode(settings.themeMode);
    }
    await AppSettingsStore.getInstance().saveGlobalSettings(settings);
    this.listeners.forEach((listener: ThemeSettingsListener) => listener(settings));
  }

  subscribe(listener: ThemeSettingsListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: ThemeSettingsListener): void {
    this.listeners.delete(listener);
  }

  private applyColorMode(mode: ThemeMode): void {
    if (!this.context) return;
    let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === ThemeMode.LIGHT) colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    if (mode === ThemeMode.DARK) colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      this.context.getApplicationContext().setColorMode(colorMode);
    } catch (_) {
    }
  }
}
