import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common } from '@kit.AbilityKit';
import {
  ButtonGroupPosition,
  DEFAULT_GAMEPAD_LAYOUT,
  DEFAULT_GAMEPAD_LAYOUT_PORTRAIT,
  DirectionControlMode,
  GamepadButtonMapping,
  FreeButtonsConfig,
  InputProfile,
  VirtualGamepadLayout,
  VirtualKeyConfig,
  VirtualKeyColorScheme,
  VirtualKeyMapping,
  cloneGamepadLayout,
  cloneFreeButtonsConfig,
  cloneVirtualKeyConfig,
  createDefaultInputProfile
} from '../model/AppModels';
import { VirtualInputOverlay } from '../components/VirtualInputOverlay';
import { InputProfileService } from '../service/InputProfileService';
import { AppSettingsStore } from '../service/AppSettingsStore';

type ButtonGroupKey = 'direction' | 'leftTrigger' | 'leftBumper' | 'action' |
  'rightBumper' | 'rightTrigger' | 'aux';

interface GroupDisplayInfo {
  key: ButtonGroupKey;
  label: string;
  color: string;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Direct adaptation of VintagePomelo's ButtonLayoutEditor.  Editing operates
 * on functional groups. Shoulder controls remain independently movable so the
 * default can mirror a physical controller without coupling them to ABXY.
 */
@Entry
@Component
struct InputLayoutEditor {
  @State private profile: InputProfile = createDefaultInputProfile();
  @State private profileId: string = 'default';
  @State private profileName: string = 'Vintage 默认手柄布局';
  @State private appId: string = '';
  @State private previewW: number = 0;
  @State private previewH: number = 0;
  @State private isPortrait: boolean = false;
  @State private selectedGroup: ButtonGroupKey | null = null;
  @State private showConfig: boolean = false;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private readonly groups: GroupDisplayInfo[] = [
    { key: 'direction', label: '方向', color: '#4CAF50' },
    { key: 'leftTrigger', label: 'LT', color: '#FFB74D' },
    { key: 'leftBumper', label: 'LB', color: '#FFCC80' },
    { key: 'action', label: '按键', color: '#2196F3' },
    { key: 'rightBumper', label: 'RB', color: '#90CAF9' },
    { key: 'rightTrigger', label: 'RT', color: '#64B5F6' },
    { key: 'aux', label: '辅助', color: '#FF9800' }
  ];

  aboutToAppear(): void {
    const params = (router.getParams() ?? {}) as Record<string, string>;
    this.profileId = params.profileId ?? 'default';
    this.profileName = params.profileName ?? (this.profileId === 'default' ? 'Vintage 默认手柄布局' : '应用专用布局');
    this.appId = params.appId ?? '';
    InputProfileService.getInstance().initialize(this.context).then((): void => {
      this.profile = InputProfileService.getInstance().ensureProfile(this.profileId, this.profileName);
      this.profileName = this.profile.name;
    }).catch(() => {});
  }

  private currentLayout(): VirtualGamepadLayout {
    return this.isPortrait ? this.profile.layoutPortrait : this.profile.layoutLandscape;
  }

  private config(): VirtualKeyConfig {
    return this.profile.virtualKeyConfig;
  }

  private replace(config: VirtualKeyConfig = this.profile.virtualKeyConfig,
    landscape: VirtualGamepadLayout = this.profile.layoutLandscape,
    portrait: VirtualGamepadLayout = this.profile.layoutPortrait,
    freeButtons: FreeButtonsConfig = this.profile.freeButtonsConfig): void {
    this.profile = {
      id: this.profile.id,
      name: this.profile.name,
      schemaVersion: 3,
      virtualKeyConfig: cloneVirtualKeyConfig(config),
      layoutLandscape: cloneGamepadLayout(landscape),
      layoutPortrait: cloneGamepadLayout(portrait, DEFAULT_GAMEPAD_LAYOUT_PORTRAIT),
      virtualKeyMappings: this.profile.virtualKeyMappings.map((item: VirtualKeyMapping): VirtualKeyMapping => ({ virtualKey: item.virtualKey, evdevCode: item.evdevCode, keyLabel: item.keyLabel })),
      gamepadMappings: this.profile.gamepadMappings.map((item: GamepadButtonMapping): GamepadButtonMapping => ({ id: item.id, label: item.label, buttonCode: item.buttonCode, evdevCode: item.evdevCode })),
      freeButtonsConfig: cloneFreeButtonsConfig(freeButtons)
    };
  }

  private groupPosition(key: ButtonGroupKey): ButtonGroupPosition {
    const layout = this.currentLayout();
    if (key === 'direction') return layout.direction;
    if (key === 'leftTrigger') return layout.leftTrigger;
    if (key === 'leftBumper') return layout.leftBumper;
    if (key === 'action') return layout.action;
    if (key === 'rightBumper') return layout.rightBumper;
    if (key === 'rightTrigger') return layout.rightTrigger;
    return layout.aux;
  }

  private groupSize(key: ButtonGroupKey): [number, number] {
    const config = this.config();
    if (key === 'direction') {
      const size = 60 * config.joystickSize / 100 * 2 + 20;
      return [size, size];
    }
    if (key === 'action') {
      return [140 * config.buttonSize / 100, 140 * config.buttonSize / 100];
    }
    if (key === 'leftTrigger' || key === 'leftBumper' ||
      key === 'rightBumper' || key === 'rightTrigger') {
      return [Math.max(48, 56 * config.buttonSize / 100), Math.max(48, 40 * config.buttonSize / 100)];
    }
    return [config.showButtonMenu ? 35 * config.buttonSize / 100 : 0, 35 * config.buttonSize / 100];
  }

  private moveGroup(key: ButtonGroupKey, centerX: number, centerY: number): void {
    const group = this.groupSize(key);
    const minX = this.previewW > 0 ? group[0] / (this.previewW * 2) : 0.05;
    const minY = this.previewH > 0 ? group[1] / (this.previewH * 2) : 0.05;
    const next: ButtonGroupPosition = { centerX: clamp(centerX, minX, 1 - minX), centerY: clamp(centerY, minY, 1 - minY) };
    if (this.isPortrait) {
      const portrait = cloneGamepadLayout(this.profile.layoutPortrait, DEFAULT_GAMEPAD_LAYOUT_PORTRAIT);
      if (key === 'direction') portrait.direction = next;
      else if (key === 'leftTrigger') portrait.leftTrigger = next;
      else if (key === 'leftBumper') portrait.leftBumper = next;
      else if (key === 'action') portrait.action = next;
      else if (key === 'rightBumper') portrait.rightBumper = next;
      else if (key === 'rightTrigger') portrait.rightTrigger = next;
      else portrait.aux = next;
      this.replace(this.config(), this.profile.layoutLandscape, portrait);
    } else {
      const landscape = cloneGamepadLayout(this.profile.layoutLandscape);
      if (key === 'direction') landscape.direction = next;
      else if (key === 'leftTrigger') landscape.leftTrigger = next;
      else if (key === 'leftBumper') landscape.leftBumper = next;
      else if (key === 'action') landscape.action = next;
      else if (key === 'rightBumper') landscape.rightBumper = next;
      else if (key === 'rightTrigger') landscape.rightTrigger = next;
      else landscape.aux = next;
      this.replace(this.config(), landscape, this.profile.layoutPortrait);
    }
  }

  private updateConfig(mutator: (config: VirtualKeyConfig) => void): void {
    const next = cloneVirtualKeyConfig(this.config());
    mutator(next);
    this.replace(next);
  }

  private reset(): void {
    const defaults = createDefaultInputProfile();
    this.replace(defaults.virtualKeyConfig, defaults.layoutLandscape, defaults.layoutPortrait);
    this.selectedGroup = null;
    promptAction.showToast({ message: '已恢复 VintagePomelo 默认布局' });
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
    promptAction.showToast({ message: '布局已保存' });
    router.back();
  }

  @Builder
  private DragHandle(info: GroupDisplayInfo) {
    Stack() {
      if (this.selectedGroup === info.key) {
        Column().width('100%').height('100%').border({ width: 2, color: info.color, style: BorderStyle.Dashed }).borderRadius(12)
      }
      Text(info.label).fontSize(10).fontColor(info.color).position({ x: '50%', y: '100%' }).translate({ x: '-50%', y: 3 })
    }
    .width(this.groupSize(info.key)[0]).height(this.groupSize(info.key)[1])
    .position({ x: this.previewW * this.groupPosition(info.key).centerX - this.groupSize(info.key)[0] / 2, y: this.previewH * this.groupPosition(info.key).centerY - this.groupSize(info.key)[1] / 2 })
    .gesture(PanGesture({ fingers: 1 })
      .onActionStart((): void => {
        this.selectedGroup = info.key;
        this.dragStartX = this.groupPosition(info.key).centerX;
        this.dragStartY = this.groupPosition(info.key).centerY;
      })
      .onActionUpdate((event: GestureEvent): void => {
        if (this.previewW <= 0 || this.previewH <= 0) return;
        this.moveGroup(info.key, this.dragStartX + event.offsetX / this.previewW, this.dragStartY + event.offsetY / this.previewH);
      }))
    .onClick((): void => { this.selectedGroup = info.key; })
  }

  @Builder
  private FloatingButton(icon: string, accent: string, action: () => void, id: string) {
    Text(icon).fontSize(16).fontColor(accent).width(36).height(36).textAlign(TextAlign.Center)
      .backgroundColor('#E8181818').borderRadius(18).border({ width: 1.5, color: accent }).shadow({ radius: 4, color: '#88000000' })
      .id(id).onClick(action)
  }

  @Builder
  private SliderRow(label: string, value: number, min: number, max: number, color: string, onChange: (value: number) => void) {
    Row({ space: 8 }) {
      Text(label + ' ' + value + '%').fontSize(11).fontColor('#FFFFFFCC').width(90)
      Slider({ value: value, min: min, max: max, step: 5, style: SliderStyle.OutSet }).layoutWeight(1)
        .blockColor(color).selectedColor(color).trackColor('#FFFFFF22').onChange(onChange)
    }.width('100%')
  }

  @Builder
  private ToggleChip(label: string, selected: boolean, onChange: () => void) {
    Text(label).fontSize(11).fontColor(selected ? '#FFFFFFFF' : '#FFFFFF99').padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor(selected ? '#335C8DFF' : '#18FFFFFF').borderRadius(14).border({ width: 1, color: selected ? '#FF64B5F6' : '#33FFFFFF' })
      .onClick(onChange)
  }

  @Builder
  private ConfigPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('虚拟按键设置').fontSize(13).fontColor('#FFFFFFFF').fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('✕').fontSize(14).fontColor('#FFFF5252').onClick((): void => { this.showConfig = false; })
      }.width('100%')
      Text('方向控制').fontSize(11).fontColor('#FFFFFFAA').width('100%')
      Row({ space: 8 }) {
        this.ToggleChip('十字键', this.config().dpadMode === DirectionControlMode.DPAD, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.dpadMode = DirectionControlMode.DPAD; }))
        this.ToggleChip('摇杆', this.config().dpadMode === DirectionControlMode.JOYSTICK, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.dpadMode = DirectionControlMode.JOYSTICK; }))
        if (this.config().dpadMode === DirectionControlMode.JOYSTICK) {
          this.ToggleChip('8 方向', this.config().eightDirectionJoystick, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.eightDirectionJoystick = !config.eightDirectionJoystick; }))
        }
      }.width('100%')
      Text('按键配色').fontSize(11).fontColor('#FFFFFFAA').width('100%')
      Row({ space: 8 }) {
        this.ToggleChip('蓝色', this.config().colorScheme === VirtualKeyColorScheme.DEFAULT, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.colorScheme = VirtualKeyColorScheme.DEFAULT; }))
        this.ToggleChip('高对比白色', this.config().colorScheme === VirtualKeyColorScheme.WHITE, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.colorScheme = VirtualKeyColorScheme.WHITE; }))
      }.width('100%')
      this.SliderRow('方向大小', this.config().joystickSize, 50, 200, '#FF4CAF50', (value: number): void => this.updateConfig((config: VirtualKeyConfig): void => { config.joystickSize = value; }))
      this.SliderRow('按键大小', this.config().buttonSize, 50, 200, '#FF2196F3', (value: number): void => this.updateConfig((config: VirtualKeyConfig): void => { config.buttonSize = value; }))
      this.SliderRow('方向透明', this.config().joystickTransparency, 0, 100, '#FF4CAF50', (value: number): void => this.updateConfig((config: VirtualKeyConfig): void => { config.joystickTransparency = value; }))
      this.SliderRow('按键透明', this.config().transparency, 0, 100, '#FF2196F3', (value: number): void => this.updateConfig((config: VirtualKeyConfig): void => { config.transparency = value; }))
      Text('按键映射与自由按键在应用设置中的“编辑按键映射与自由按键”里配置。').fontSize(10).fontColor('#FFFFFF88').width('100%')
      Text('显示按键').fontSize(11).fontColor('#FFFFFFAA').width('100%')
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          this.ToggleChip('A', this.config().showButtonA, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonA = !config.showButtonA; }))
          this.ToggleChip('B', this.config().showButtonB, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonB = !config.showButtonB; }))
          this.ToggleChip('X', this.config().showButtonX, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonX = !config.showButtonX; }))
          this.ToggleChip('Y', this.config().showButtonY, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonY = !config.showButtonY; }))
          this.ToggleChip('LB', this.config().showButtonL, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonL = !config.showButtonL; }))
          this.ToggleChip('RB', this.config().showButtonR, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonR = !config.showButtonR; }))
        }.width('100%')
        Row({ space: 6 }) {
          this.ToggleChip('菜单', this.config().showButtonMenu, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonMenu = !config.showButtonMenu; }))
          this.ToggleChip('LT', this.config().showButtonShift, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonShift = !config.showButtonShift; }))
          this.ToggleChip('RT', this.config().showButtonCtrl, (): void => this.updateConfig((config: VirtualKeyConfig): void => { config.showButtonCtrl = !config.showButtonCtrl; }))
        }.width('100%')
      }.width('100%')
    }
    .width(260).padding(14).backgroundColor('#EE111111').borderRadius(14).border({ width: 1, color: '#44FFFFFF' })
    .position({ x: 16, y: 64 }).id('vintage-layout-config')
  }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#FF1A1A2E')
      VirtualInputOverlay({ profile: this.profile, interactive: false, hideToolbar: true })
        .width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      if (this.previewW > 0) {
        ForEach(this.groups, (info: GroupDisplayInfo): void => this.DragHandle(info), (info: GroupDisplayInfo): string => info.key)
      }
      Text(this.isPortrait ? '竖屏布局' : '横屏布局').fontSize(11).fontColor('#FFFFFF66').padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#44000000').borderRadius(4).position({ x: 8, y: 8 }).id('vintage-layout-mode')
      Row({ space: 10 }) {
        ForEach(this.groups, (info: GroupDisplayInfo): void => {
          Row({ space: 4 }) {
            Circle().width(8).height(8).fill(info.color)
            Text(info.label).fontSize(11).fontColor(this.selectedGroup === info.key ? '#FFFFFFFF' : '#FFFFFFAA')
          }.padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(12)
            .backgroundColor(this.selectedGroup === info.key ? info.color + '55' : '#44000000').onClick((): void => { this.selectedGroup = info.key; })
        }, (info: GroupDisplayInfo): string => info.key)
      }.position({ x: '50%', y: '100%' }).translate({ x: '-50%', y: -36 })
      Row({ space: 8 }) {
        this.FloatingButton('✕', '#FFFF5252', (): void => { router.back(); }, 'input-layout-back')
        this.FloatingButton('↺', '#FFFFB74D', (): void => { this.reset(); }, 'input-layout-reset')
        this.FloatingButton('⊞', '#FF64B5F6', (): void => { this.showConfig = !this.showConfig; }, 'input-layout-config')
        this.FloatingButton('✓', '#FF81C784', () => { this.save(); }, 'input-layout-save')
      }.position({ x: '50%', y: 16 }).translate({ x: '-50%' })
      if (this.showConfig) this.ConfigPanel()
    }
    .width('100%').height('100%').backgroundColor('#FF000000')
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.previewW = area.width as number;
      this.previewH = area.height as number;
      this.isPortrait = this.previewH > this.previewW;
    })
  }
}
