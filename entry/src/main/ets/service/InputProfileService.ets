import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { GamepadButtonMapping, InputProfile, VirtualControlDescriptor, createDefaultInputProfile } from '../model/AppModels';

const STORE_NAME = 'vintage_pomelo_input_profiles';
const PROFILES_KEY = 'profiles_v1';

export class InputProfileService {
  private static instance: InputProfileService | null = null;
  private store: preferences.Preferences | null = null;
  private profiles: Map<string, InputProfile> = new Map<string, InputProfile>();

  private cloneProfile(profile: InputProfile, profileId?: string, profileName?: string): InputProfile {
    const defaults = createDefaultInputProfile();
    return {
      id: profileId ?? profile.id,
      name: profileName ?? profile.name,
      buttonOpacity: profile.buttonOpacity,
      stickDeadzone: profile.stickDeadzone,
      gamepadMappings: (profile.gamepadMappings ?? defaults.gamepadMappings)
        .map((mapping: GamepadButtonMapping): GamepadButtonMapping => ({
          id: mapping.id,
          label: mapping.label,
          buttonCode: mapping.buttonCode,
          evdevCode: mapping.evdevCode
        })),
      controls: profile.controls.map((control: VirtualControlDescriptor): VirtualControlDescriptor => ({
        id: control.id,
        label: control.label,
        kind: control.kind,
        evdevCode: control.evdevCode,
        xPercent: control.xPercent,
        yPercent: control.yPercent,
        size: control.size,
        opacity: control.opacity
      }))
    };
  }

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
    const profile = this.profiles.get(id) ?? this.profiles.get('default') ?? createDefaultInputProfile();
    return this.cloneProfile(profile);
  }

  ensureProfile(id: string, name: string): InputProfile {
    const profile = this.profiles.get(id);
    if (profile) return this.cloneProfile(profile);
    const base = this.profiles.get('default') ?? createDefaultInputProfile();
    return this.cloneProfile(base, id, name);
  }

  async saveProfile(profile: InputProfile): Promise<void> {
    const normalized = this.cloneProfile(profile);
    this.profiles.set(normalized.id, normalized);
    if (!this.store) return;
    const values: InputProfile[] = [];
    this.profiles.forEach((value: InputProfile) => values.push(this.cloneProfile(value)));
    await this.store.put(PROFILES_KEY, JSON.stringify(values));
    await this.store.flush();
  }
}
