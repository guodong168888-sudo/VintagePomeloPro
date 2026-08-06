import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import bundleManager from '@ohos.bundle.bundleManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import {
  INPUT_PROFILE_SCHEMA_VERSION,
  InputProfile,
  cloneInputProfile,
  createDefaultInputProfile,
  createInputProfileFromTemplate,
  exportProfileToIcpJson,
  importProfileFromIcpJson
} from '../model/AppModels';

const STORE_NAME = 'vintage_pomelo_input_profiles';
const PROFILES_KEY = 'profiles_v6';
const INPUT_PROFILE_DIRECTORY = 'input_profiles';
const DOMAIN = 0x0000;
const TAG = 'InputProfile';

/**
 * v6 起输入方案改为 Winlator 风格的元素化任意排布模型。旧 v5 分组模型
 * 直接替换：非 v6 数据加载时丢弃，不迁移、不保留只读兼容。
 */
export class InputProfileService {
  private static instance: InputProfileService | null = null;
  private store: preferences.Preferences | null = null;
  private profiles: Map<string, InputProfile> = new Map<string, InputProfile>();

  static getInstance(): InputProfileService {
    if (!InputProfileService.instance) InputProfileService.instance = new InputProfileService();
    return InputProfileService.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store) return;
    this.store = await preferences.getPreferences(context, STORE_NAME);
    const raw = this.store.getSync(PROFILES_KEY, '') as string;
    if (raw) {
      try {
        const values = JSON.parse(raw) as InputProfile[];
        values.forEach((value: InputProfile): void => {
          if (value && value.schemaVersion === INPUT_PROFILE_SCHEMA_VERSION) {
            this.profiles.set(value.id, value);
          }
        });
      } catch (_) {
      }
    }

    let changed = false;
    if (!this.profiles.has('default')) {
      this.profiles.set('default', createDefaultInputProfile());
      changed = true;
    }
    if (changed) await this.persistProfiles();
  }

  getProfile(id: string): InputProfile {
    const profile = this.profiles.get(id) ?? this.profiles.get('default') ?? createDefaultInputProfile();
    return this.cloneProfile(profile);
  }

  getProfiles(): InputProfile[] {
    const values: InputProfile[] = [];
    this.profiles.forEach((profile: InputProfile): void => {
      values.push(this.cloneProfile(profile));
    });
    values.sort((left: InputProfile, right: InputProfile): number => {
      if (left.id === 'default') return -1;
      if (right.id === 'default') return 1;
      return left.name.localeCompare(right.name);
    });
    return values;
  }

  getDesktopProfiles(): InputProfile[] {
    return this.getProfiles().filter((profile: InputProfile): boolean => !profile.id.startsWith('app-'));
  }

  hasDesktopProfile(id: string): boolean {
    return id.length > 0 && !id.startsWith('app-') && this.profiles.has(id);
  }

  hasProfile(id: string): boolean {
    return this.profiles.has(id);
  }

  ensureProfile(id: string, name: string, baseProfileId: string = 'default'): InputProfile {
    const profile = this.profiles.get(id);
    if (profile && profile.schemaVersion === INPUT_PROFILE_SCHEMA_VERSION) return this.cloneProfile(profile);
    const base = this.profiles.get(baseProfileId) ?? this.profiles.get('default') ?? createDefaultInputProfile();
    return this.cloneProfile(base, id, name);
  }

  async duplicateProfile(sourceId: string, name: string): Promise<InputProfile> {
    const source = this.profiles.get(sourceId) ?? this.profiles.get('default') ?? createDefaultInputProfile();
    let suffix = Date.now().toString(36);
    let id = 'desktop-' + suffix;
    let collision = 1;
    while (this.profiles.has(id)) {
      id = 'desktop-' + suffix + '-' + collision.toString();
      collision++;
    }
    const profile = this.cloneProfile(source, id, name.trim() || '桌面输入方案');
    await this.saveProfile(profile);
    return this.cloneProfile(profile);
  }

  async removeProfile(id: string): Promise<boolean> {
    if (id === 'default' || !this.profiles.has(id)) return false;
    this.profiles.delete(id);
    await this.persistProfiles();
    return true;
  }

  async saveProfile(profile: InputProfile): Promise<void> {
    const normalized = this.cloneProfile(profile);
    this.profiles.set(normalized.id, normalized);
    await this.persistProfiles();
  }

  /**
   * 从模板新建输入方案。id 自动生成，名称允许与现有方案重复。
   */
  async createProfileFromTemplate(name: string, templateId: string): Promise<InputProfile> {
    let suffix = Date.now().toString(36);
    let id = 'desktop-' + suffix;
    let collision = 1;
    while (this.profiles.has(id)) {
      id = 'desktop-' + suffix + '-' + collision.toString();
      collision++;
    }
    const profile = createInputProfileFromTemplate(id, name.trim() || '桌面输入方案', templateId);
    await this.saveProfile(profile);
    return this.cloneProfile(profile);
  }

  /**
   * 把默认方案重置为通用模板，其它方案不受影响。
   */
  async resetDefaultProfile(): Promise<InputProfile> {
    const profile = createDefaultInputProfile();
    await this.saveProfile(profile);
    return this.cloneProfile(profile);
  }

  /**
   * 导出方案为 Winlator 兼容 .icp JSON 文本。
   */
  exportProfileToIcp(profileId: string): string {
    const profile = this.getProfile(profileId);
    return exportProfileToIcpJson(profile);
  }

  /**
   * 导入 .icp JSON 并保存为新方案；返回导入后的方案。
   */
  async importProfileFromIcp(json: string, profileName?: string): Promise<InputProfile> {
    let suffix = Date.now().toString(36);
    let id = 'desktop-' + suffix;
    let collision = 1;
    while (this.profiles.has(id)) {
      id = 'desktop-' + suffix + '-' + collision.toString();
      collision++;
    }
    const profile = importProfileFromIcpJson(json, id, profileName);
    await this.saveProfile(profile);
    return this.cloneProfile(profile);
  }

  /**
   * 把方案导出到 Download/<bundle>/input_profiles/<name>.icp，返回文件路径。
   */
  async exportProfileToFile(profileId: string): Promise<string> {
    const json = this.exportProfileToIcp(profileId);
    const directory = this.resolveInputProfileDirectory();
    if (!directory) throw new Error('无法解析 Download 输入方案目录');
    const safeName = this.sanitizeFileName(this.getProfile(profileId).name);
    const target = directory.endsWith('/') ? directory + safeName + '.icp' : directory + '/' + safeName + '.icp';
    this.ensureDirectory(directory);
    const output = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(output.fd, json);
    } finally {
      fs.closeSync(output);
    }
    hilog.info(DOMAIN, TAG, 'Exported input profile to %{public}s', target);
    return target;
  }

  private cloneProfile(profile: InputProfile, profileId?: string, profileName?: string): InputProfile {
    return cloneInputProfile(profile, profileId, profileName);
  }

  private async persistProfiles(): Promise<void> {
    if (!this.store) return;
    const values: InputProfile[] = [];
    this.profiles.forEach((value: InputProfile): void => {
      values.push(cloneInputProfile(value));
    });
    await this.store.put(PROFILES_KEY, JSON.stringify(values));
    await this.store.flush();
  }

  private resolveInputProfileDirectory(): string {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const uri = `file://docs/storage/Users/currentUser/Download/${bundleInfo.name}/${INPUT_PROFILE_DIRECTORY}`;
      return new fileUri.FileUri(uri).path;
    } catch (_) {
      return '';
    }
  }

  private ensureDirectory(path: string): boolean {
    try {
      const existing = fs.statSync(path);
      return existing.isDirectory();
    } catch (_) {
    }
    try {
      fs.mkdirSync(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  private sanitizeFileName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim();
    return (cleaned.length > 0 ? cleaned : 'input-profile').slice(0, 48);
  }
}
