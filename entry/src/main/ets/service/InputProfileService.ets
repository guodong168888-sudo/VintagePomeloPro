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

  ensureProfile(id: string, name: string): InputProfile {
    const profile = this.profiles.get(id);
    if (profile && profile.schemaVersion === INPUT_PROFILE_SCHEMA_VERSION) return this.cloneProfile(profile);
    const base = this.profiles.get('default') ?? createDefaultInputProfile();
    return this.cloneProfile(base, id, name);
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
