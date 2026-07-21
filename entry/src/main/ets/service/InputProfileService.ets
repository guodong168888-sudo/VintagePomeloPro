import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import {
  GamepadButtonMapping,
  InputProfile,
  VirtualKeyMapping,
  cloneFreeButtonsConfig,
  cloneGamepadLayout,
  cloneVirtualKeyConfig,
  createDefaultInputProfile,
  DEFAULT_GAMEPAD_LAYOUT_PORTRAIT
} from '../model/AppModels';

const STORE_NAME = 'vintage_pomelo_input_profiles';
const PROFILES_KEY = 'profiles_v2';
const INPUT_PROFILE_SCHEMA_VERSION = 3;

/**
 * Persists the VintagePomelo-compatible grouped layout contract.  Version one
 * stored independently movable controls, which cannot express the mutually
 * exclusive d-pad/joystick choice and is deliberately not carried forward.
 */
export class InputProfileService {
  private static instance: InputProfileService | null = null;
  private store: preferences.Preferences | null = null;
  private profiles: Map<string, InputProfile> = new Map<string, InputProfile>();

  static getInstance(): InputProfileService {
    if (!InputProfileService.instance) InputProfileService.instance = new InputProfileService();
    return InputProfileService.instance;
  }

  private cloneProfile(profile: InputProfile, profileId?: string, profileName?: string): InputProfile {
    const defaults = createDefaultInputProfile();
    return {
      id: profileId ?? profile.id,
      name: profileName ?? profile.name,
      schemaVersion: INPUT_PROFILE_SCHEMA_VERSION,
      virtualKeyConfig: cloneVirtualKeyConfig(profile.virtualKeyConfig ?? defaults.virtualKeyConfig),
      layoutLandscape: cloneGamepadLayout(profile.layoutLandscape ?? defaults.layoutLandscape),
      layoutPortrait: cloneGamepadLayout(profile.layoutPortrait ?? defaults.layoutPortrait, DEFAULT_GAMEPAD_LAYOUT_PORTRAIT),
      virtualKeyMappings: (profile.virtualKeyMappings ?? defaults.virtualKeyMappings)
        .map((mapping: VirtualKeyMapping): VirtualKeyMapping => ({
          virtualKey: mapping.virtualKey,
          evdevCode: mapping.evdevCode,
          keyLabel: mapping.keyLabel
        })),
      gamepadMappings: (profile.gamepadMappings ?? defaults.gamepadMappings)
        .map((mapping: GamepadButtonMapping): GamepadButtonMapping => ({
          id: mapping.id,
          label: mapping.label,
          buttonCode: mapping.buttonCode,
          evdevCode: mapping.evdevCode
        })),
      freeButtonsConfig: cloneFreeButtonsConfig(profile.freeButtonsConfig ?? defaults.freeButtonsConfig)
    };
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store) return;
    this.store = await preferences.getPreferences(context, STORE_NAME);
    const raw = this.store.getSync(PROFILES_KEY, '') as string;
    if (raw) {
      try {
        const values = JSON.parse(raw) as InputProfile[];
        values.forEach((value: InputProfile): void => {
          this.profiles.set(value.id, value);
        });
      } catch (_) {
      }
    }

    let changed = false;
    this.profiles.forEach((value: InputProfile, id: string): void => {
      if (value.schemaVersion !== INPUT_PROFILE_SCHEMA_VERSION ||
        !value.layoutLandscape.leftTrigger || !value.layoutLandscape.leftBumper ||
        !value.layoutLandscape.rightBumper || !value.layoutLandscape.rightTrigger) {
        // Version three separates all four shoulder controls while retaining
        // every existing direction/action/aux position and key mapping.
        this.profiles.set(id, this.cloneProfile(value));
        changed = true;
      }
    });
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

  private async persistProfiles(): Promise<void> {
    if (!this.store) return;
    const values: InputProfile[] = [];
    this.profiles.forEach((value: InputProfile): void => {
      values.push(this.cloneProfile(value));
    });
    await this.store.put(PROFILES_KEY, JSON.stringify(values));
    await this.store.flush();
  }
}
