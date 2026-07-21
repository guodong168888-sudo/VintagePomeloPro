/**
 * Advanced mapping and free-button editor migrated from VintagePomelo.
 * It deliberately edits an InputProfile, so it works both for the global
 * default profile and the dedicated profile created by an individual game.
 */
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common, Want } from '@kit.AbilityKit';
import { KeyboardLayout } from '../components/KeyboardLayout';
import { VirtualInputOverlay } from '../components/VirtualInputOverlay';
import {
  FreeButton,
  FreeButtonsConfig,
  FreeButtonLayoutMode,
  InputProfile,
  VirtualKey,
  VirtualKeyMapping,
  cloneFreeButtonsConfig,
  createDefaultInputProfile,
  generateFreeButtonId
} from '../model/AppModels';
import { InputProfileService } from '../service/InputProfileService';
import { AppSettingsStore } from '../service/AppSettingsStore';

interface VirtualKeyInfo {
  key: VirtualKey;
  title: string;
  detail: string;
}

const VIRTUAL_KEYS: VirtualKeyInfo[] = [
  { key: VirtualKey.DPAD_UP, title: '方向上', detail: '↑ 方向' },
  { key: VirtualKey.DPAD_DOWN, title: '方向下', detail: '↓ 方向' },
  { key: VirtualKey.DPAD_LEFT, title: '方向左', detail: '← 方向' },
  { key: VirtualKey.DPAD_RIGHT, title: '方向右', detail: '→ 方向' },
  { key: VirtualKey.RIGHT_STICK_UP, title: '右摇杆上', detail: '默认 I' },
  { key: VirtualKey.RIGHT_STICK_DOWN, title: '右摇杆下', detail: '默认 K' },
  { key: VirtualKey.RIGHT_STICK_LEFT, title: '右摇杆左', detail: '默认 J' },
  { key: VirtualKey.RIGHT_STICK_RIGHT, title: '右摇杆右', detail: '默认 L' },
  { key: VirtualKey.BUTTON_A, title: 'A / 确认', detail: '默认 Space' },
  { key: VirtualKey.BUTTON_B, title: 'B / 返回', detail: '默认 X' },
  { key: VirtualKey.BUTTON_X, title: 'X', detail: '默认 A' },
  { key: VirtualKey.BUTTON_Y, title: 'Y', detail: '默认 S' },
  { key: VirtualKey.BUTTON_L, title: 'LB', detail: '默认 Q' },
  { key: VirtualKey.BUTTON_R, title: 'RB', detail: '默认 W' },
  { key: VirtualKey.BUTTON_MENU, title: '菜单', detail: '默认 Esc' },
  { key: VirtualKey.BUTTON_SHIFT, title: 'LT / 加速', detail: '默认 Shift' },
  { key: VirtualKey.BUTTON_CTRL, title: 'RT / 跳过', detail: '默认 Ctrl' }
];

@Entry
@Component
struct AdvancedKeyMappingPage {
  @State private profile: InputProfile = createDefaultInputProfile();
  @State private profileId: string = 'default';
  @State private profileName: string = 'Vintage 默认手柄布局';
  @State private appId: string = '';
  @State private baseProfileId: string = 'default';
  @State private tab: number = 0;
  @State private selectedKey: VirtualKey | null = null;
  @State private editingFreeIndex: number = -1;
  @State private showKeyPicker: boolean = false;
  @State private previewRevision: number = 0;
  @State private returnAbilityName: string = '';
  @State private returnSessionId: string = '';
  @State private returnToplevelId: string = '0';
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private returnScheduled: boolean = false;

  aboutToAppear(): void {
    const params = (router.getParams() ?? {}) as Record<string, string>;
    this.profileId = params.profileId ?? 'default';
    this.profileName = params.profileName ?? (this.profileId === 'default' ? 'Vintage 默认手柄布局' : '应用专用按键映射');
    this.appId = params.appId ?? '';
    this.baseProfileId = params.baseProfileId ?? 'default';
    this.returnAbilityName = params.returnAbilityName ?? '';
    this.returnSessionId = params.returnSessionId ?? '';
    this.returnToplevelId = params.returnToplevelId ?? '0';
    InputProfileService.getInstance().initialize(this.context).then((): void => {
      this.profile = InputProfileService.getInstance().ensureProfile(this.profileId, this.profileName, this.baseProfileId);
      this.profileName = this.profile.name;
      this.previewRevision++;
    }).catch((): void => {});
  }

  aboutToDisappear(): void {
    this.resumeWineAbility();
  }

  private mappingFor(key: VirtualKey): VirtualKeyMapping | undefined {
    return this.profile.virtualKeyMappings.find((mapping: VirtualKeyMapping): boolean => mapping.virtualKey === key);
  }

  private replaceMappings(mappings: VirtualKeyMapping[] = this.profile.virtualKeyMappings): void {
    this.setProfile(mappings, this.profile.freeButtonsConfig);
  }

  private setProfile(mappings: VirtualKeyMapping[], freeButtons: FreeButtonsConfig): void {
    this.profile = {
      id: this.profile.id,
      name: this.profile.name,
      schemaVersion: this.profile.schemaVersion,
      virtualKeyConfig: this.profile.virtualKeyConfig,
      layoutLandscape: this.profile.layoutLandscape,
      layoutPortrait: this.profile.layoutPortrait,
      virtualKeyMappings: mappings.map((mapping: VirtualKeyMapping): VirtualKeyMapping => ({
        virtualKey: mapping.virtualKey, evdevCode: mapping.evdevCode, keyLabel: mapping.keyLabel
      })),
      gamepadMappings: this.profile.gamepadMappings,
      freeButtonsConfig: cloneFreeButtonsConfig(freeButtons)
    };
    this.previewRevision++;
  }

  private finishEditor(): void {
    router.back();
    this.resumeWineAbility();
  }

  private resumeWineAbility(): void {
    if (this.returnScheduled) return;
    if (this.returnAbilityName !== 'DesktopAbility' && this.returnAbilityName !== 'SingleAppAbility') return;
    this.returnScheduled = true;
    const want: Want = {
      bundleName: 'com.vintage.pomelopro',
      abilityName: this.returnAbilityName,
      parameters: {
        sessionId: this.returnSessionId,
        toplevelId: Number(this.returnToplevelId) || 0
      }
    };
    setTimeout((): void => {
      this.context.startAbility(want).catch((): void => {});
    }, 80);
  }

  private setVirtualMapping(evdevCode: number, label: string): void {
    if (!this.selectedKey) {
      promptAction.showToast({ message: '请先选择左侧的虚拟按键' });
      return;
    }
    const mappings = this.profile.virtualKeyMappings.filter((mapping: VirtualKeyMapping): boolean => mapping.virtualKey !== this.selectedKey);
    mappings.push({ virtualKey: this.selectedKey, evdevCode: evdevCode, keyLabel: label });
    this.replaceMappings(mappings);
    promptAction.showToast({ message: this.selectedKey + ' → ' + label });
    this.selectedKey = null;
  }

  private setFreeEnabled(enabled: boolean): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    current.enabled = enabled;
    this.setProfile(this.profile.virtualKeyMappings, current);
  }

  private setFreeMode(mode: FreeButtonLayoutMode): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    current.layoutMode = mode;
    this.setProfile(this.profile.virtualKeyMappings, current);
  }

  private setRadialScale(value: number): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    current.radialScale = Math.round(value);
    this.setProfile(this.profile.virtualKeyMappings, current);
  }

  private setGamepadSpacing(value: number): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    current.gamepadSpacing = Math.round(value);
    this.setProfile(this.profile.virtualKeyMappings, current);
  }

  private addOrChangeFreeButton(evdevCode: number, label: string): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    if (this.editingFreeIndex >= 0 && current.buttons[this.editingFreeIndex]) {
      current.buttons[this.editingFreeIndex].evdevCode = evdevCode;
      current.buttons[this.editingFreeIndex].keyLabel = label;
    } else if (current.buttons.length < 8) {
      current.buttons.push({ id: generateFreeButtonId(), evdevCode: evdevCode, keyLabel: label });
      current.enabled = true;
    }
    this.setProfile(this.profile.virtualKeyMappings, current);
    this.editingFreeIndex = -1;
    this.showKeyPicker = false;
  }

  private removeFreeButton(index: number): void {
    const current = cloneFreeButtonsConfig(this.profile.freeButtonsConfig);
    current.buttons = current.buttons.filter((_button: FreeButton, itemIndex: number): boolean => itemIndex !== index);
    this.setProfile(this.profile.virtualKeyMappings, current);
  }

  private restoreDefaults(): void {
    const defaults = createDefaultInputProfile();
    this.profile = {
      id: this.profileId,
      name: this.profileName,
      schemaVersion: defaults.schemaVersion,
      virtualKeyConfig: defaults.virtualKeyConfig,
      layoutLandscape: defaults.layoutLandscape,
      layoutPortrait: defaults.layoutPortrait,
      virtualKeyMappings: defaults.virtualKeyMappings,
      gamepadMappings: defaults.gamepadMappings,
      freeButtonsConfig: defaults.freeButtonsConfig
    };
    this.previewRevision++;
    this.selectedKey = null;
    promptAction.showToast({ message: '已恢复 VintagePomelo 默认按键方案' });
  }

  private async save(): Promise<void> {
    await InputProfileService.getInstance().saveProfile(this.profile);
    if (this.appId) {
      const current = AppSettingsStore.getInstance().getAppSettings(this.appId);
      await AppSettingsStore.getInstance().saveAppSettings({
        appId: current.appId,
        customTitle: current.customTitle,
        customCover: current.customCover,
        favorite: current.favorite,
        executable: current.executable,
        arguments: current.arguments,
        workingDirectory: current.workingDirectory,
        displayModeOverride: current.displayModeOverride,
        inputProfileId: this.profile.id,
        prefixId: current.prefixId
      });
    }
    promptAction.showToast({ message: this.appId ? '已保存此应用专用按键方案' : '已保存全局默认按键方案' });
    this.finishEditor();
  }

  @Builder
  private Tab(label: string, index: number) {
    Text(label).fontSize(14).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.tab === index ? '#FFFFFFFF' : '#B8C4D8')
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .backgroundColor(this.tab === index ? '#FF2979FF' : '#18000000')
      .borderRadius(14)
      .onClick((): void => { this.tab = index; })
  }

  @Builder
  private VirtualKeyCell(info: VirtualKeyInfo) {
    Column({ space: 3 }) {
      Text(info.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.selectedKey === info.key ? '#FFFFFFFF' : $r('app.color.text_primary')).width('100%')
      Text(this.mappingFor(info.key)?.keyLabel ?? '未设置').fontSize(11).fontColor(this.selectedKey === info.key ? '#DCEBFF' : $r('app.color.accent')).width('100%')
    }
    .width('100%').padding(12).backgroundColor(this.selectedKey === info.key ? '#FF2979FF' : $r('app.color.search_background'))
    .borderRadius(14).onClick((): void => { this.selectedKey = info.key; })
  }

  @Builder
  private FixedMapping() {
    Row({ space: 16 }) {
      Scroll() {
        Column({ space: 8 }) {
          Text('虚拟按键').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Text('选择功能后，点击右侧完整 PC 键盘中的目标按键。').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          Grid() {
            ForEach(VIRTUAL_KEYS, (info: VirtualKeyInfo): void => {
              GridItem() { this.VirtualKeyCell(info) }
            }, (info: VirtualKeyInfo): string => info.key)
          }.columnsTemplate('1fr 1fr').columnsGap(8).rowsGap(8).width('100%')
        }.width('100%').padding({ bottom: 12 })
      }.width(300).scrollBar(BarState.Auto)
      Column({ space: 12 }) {
        Text(this.selectedKey ? '正在设置：' + (VIRTUAL_KEYS.find((item: VirtualKeyInfo): boolean => item.key === this.selectedKey)?.title ?? '') : '选择一个虚拟按键')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Text('键盘上的键值直接使用 Wine 的 Linux evdev 编码，不经过二次转换。').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        Scroll() { KeyboardLayout({ selectedEvdevCode: this.selectedKey ? (this.mappingFor(this.selectedKey)?.evdevCode ?? -1) : -1, onKeySelected: (code: number, label: string): void => this.setVirtualMapping(code, label) }) }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).layoutWeight(1).width('100%')
      }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  private FreeButtonRow(button: FreeButton, index: number) {
    Row({ space: 10 }) {
      Text((index + 1).toString()).fontSize(12).fontColor($r('app.color.text_secondary')).width(22)
      Column({ space: 2 }) {
        Text(button.keyLabel).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('evdev ' + button.evdevCode).fontSize(10).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button('改键').height(32).borderRadius(10).backgroundColor($r('app.color.selected_background')).fontColor($r('app.color.accent'))
        .onClick((): void => { this.editingFreeIndex = index; this.showKeyPicker = true; })
      Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#FFD94848']) }
        .width(32).height(32).backgroundColor('#12D94848').onClick((): void => this.removeFreeButton(index))
    }.width('100%').padding(12).backgroundColor($r('app.color.search_background')).borderRadius(14)
  }

  @Builder
  private KeyPicker() {
    Column({ space: 12 }) {
      Text('在完整 PC 键盘上选择一个按键').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Scroll() { KeyboardLayout({ selectedEvdevCode: -1, onKeySelected: (code: number, label: string): void => this.addOrChangeFreeButton(code, label) }) }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  private FreeMapping() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 10 }) {
          Text('自由按键模式').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Text('这是 VintagePomelo 的第二种覆盖层模式：用一组可选键映射替换固定手柄，而不是把固定手柄与自由键堆叠在同一屏幕。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Row() {
            Text('启用自由按键').fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.profile.freeButtonsConfig.enabled }).onChange((enabled: boolean): void => this.setFreeEnabled(enabled))
          }.width('100%').padding(12).backgroundColor($r('app.color.search_background')).borderRadius(14)
          Row({ space: 8 }) {
            Button('手柄模板').height(42).layoutWeight(1).borderRadius(12)
              .backgroundColor(this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.GAMEPAD ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.GAMEPAD ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick((): void => this.setFreeMode(FreeButtonLayoutMode.GAMEPAD))
            Button('环形模板').height(42).layoutWeight(1).borderRadius(12)
              .backgroundColor(this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.RADIAL ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.RADIAL ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick((): void => this.setFreeMode(FreeButtonLayoutMode.RADIAL))
          }.width('100%')
          if (this.profile.freeButtonsConfig.layoutMode === FreeButtonLayoutMode.GAMEPAD) {
            Text('手柄间距 ' + this.profile.freeButtonsConfig.gamepadSpacing + '%').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Slider({ value: this.profile.freeButtonsConfig.gamepadSpacing, min: 80, max: 150, step: 5 }).onChange((value: number): void => this.setGamepadSpacing(value))
          } else {
            Text('环形半径 ' + this.profile.freeButtonsConfig.radialScale + '%').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Slider({ value: this.profile.freeButtonsConfig.radialScale, min: 50, max: 200, step: 5 }).onChange((value: number): void => this.setRadialScale(value))
          }
        }.width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)
        Column({ space: 10 }) {
          Text('实时预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Stack() {
            Column().width('100%').height('100%').backgroundColor('#FF1A1A2E').borderRadius(16)
            VirtualInputOverlay({ profile: this.profile, renderRevision: this.previewRevision, interactive: false, hideToolbar: true }).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
          }.height(300).width('100%')
        }.width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)
        Column({ space: 8 }) {
          Text('自由按键 (' + this.profile.freeButtonsConfig.buttons.length + '/8)').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          ForEach(this.profile.freeButtonsConfig.buttons, (button: FreeButton, index: number): void => this.FreeButtonRow(button, index), (button: FreeButton): string => button.id)
          if (this.profile.freeButtonsConfig.buttons.length < 8) {
            Button('添加按键').width('100%').height(46).borderRadius(14).backgroundColor($r('app.color.selected_background')).fontColor($r('app.color.accent'))
              .id('key-mapping-add-free-button').onClick((): void => { this.editingFreeIndex = -1; this.showKeyPicker = true; })
          }
        }.width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)
      }.width('100%').constraintSize({ maxWidth: 1120 }).padding({ bottom: 24 })
    }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18).fontColor([$r('app.color.text_primary')]) }
          .width(48).height(48).backgroundColor($r('app.color.search_background')).id('key-mapping-back')
          .onClick((): void => this.finishEditor())
        Column({ space: 3 }) {
          Text('按键映射').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.appId ? '此应用专用输入方案：' + this.profileName : '全局默认输入方案：' + this.profileName).fontSize(11).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('恢复默认').height(44).borderRadius(14).backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary')).onClick((): void => this.restoreDefaults())
        Button('保存').height(44).borderRadius(14).backgroundColor($r('app.color.accent')).fontColor('#FFFFFFFF').margin({ left: 8 }).id('key-mapping-save').onClick((): void => { this.save(); })
      }.width('100%')
      Row({ space: 8 }) { this.Tab('固定手柄映射', 0); this.Tab('自由按键', 1) }.width('100%')
      if (this.tab === 0) this.FixedMapping()
      else this.FreeMapping()
    }
    .width('100%').height('100%').padding(20).backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showKeyPicker, this.KeyPicker(), { height: SheetSize.LARGE, dragBar: true, showClose: true, title: { title: this.editingFreeIndex >= 0 ? '修改自由按键' : '添加自由按键' } })
  }
}
