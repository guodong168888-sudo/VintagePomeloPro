import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { InputProfile, createDefaultInputProfile } from '../model/AppModels';

const STORE_NAME = 'vintage_pomelo_input_profiles';
const PROFILES_KEY = 'profiles_v1';

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
        values.forEach((value: InputProfile) => this.profiles.set(value.id, value));
      } catch (_) {
      }
    }
    if (!this.profiles.has('default')) this.profiles.set('default', createDefaultInputProfile());
  }

  getProfile(id: string): InputProfile {
    return this.profiles.get(id) ?? this.profiles.get('default') ?? createDefaultInputProfile();
  }

  async saveProfile(profile: InputProfile): Promise<void> {
    this.profiles.set(profile.id, profile);
    if (!this.store) return;
    const values: InputProfile[] = [];
    this.profiles.forEach((value: InputProfile) => values.push(value));
    await this.store.put(PROFILES_KEY, JSON.stringify(values));
    await this.store.flush();
  }
}
