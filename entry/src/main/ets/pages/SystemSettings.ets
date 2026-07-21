import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common } from '@kit.AbilityKit';
import { BreakpointSystem, BreakpointType } from '../common/BreakpointSystem';
import {
  ControlBarDirection,
  DisplayMode,
  EngineState,
  GlobalSettings,
  InputProfile,
  ThemeMode,
  ViewMode,
  VirtualMouseConfig,
  cloneVirtualMouseConfig,
  createDefaultGlobalSettings
} from '../model/AppModels';
import { ThemeSettingsService } from '../service/ThemeSettingsService';
import { EngineStateListener, WineEngineService } from '../service/WineEngineService';
import { GamepadManager } from '../service/GamepadManager';
import { WineWindowManager } from '../service/WineWindowManager';
import { AppSessionService } from '../service/AppSessionService';
import { InputOverlayWindowCoordinator } from '../service/InputOverlayWindowCoordinator';
import { AppCatalogService } from '../service/AppCatalogService';
import { InputProfileService } from '../service/InputProfileService';

type SettingsSection = 'display' | 'appearance' | 'input' | 'engine' | 'about';

@Entry
@Component
struct SystemSettingsPage {
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private breakpoint: BreakpointType = 'lg';
  @State private section: SettingsSection = 'display';
  @State private engineMessage: string = 'Wine 引擎未启动';
  @State private engineBusy: boolean = false;
  @State private engineOperationMessage: string = '';
  @State private inputProfiles: InputProfile[] = [];
  private settingsScroller: Scroller = new Scroller();
  private callback: ((value: BreakpointType) => void) | null = null;
  private engineCallback: EngineStateListener | null = null;

  aboutToAppear(): void {
    this.settings = ThemeSettingsService.getInstance().getSettings();
    BreakpointSystem.initialize();
    this.callback = (value: BreakpointType): void => {
      this.breakpoint = value;
    };
    BreakpointSystem.subscribe(this.callback);
    this.engineCallback = (_state: EngineState, message: string): void => {
      this.engineMessage = message;
    };
    WineEngineService.getInstance().subscribe(this.engineCallback);
    this.loadInputProfiles();
  }

  onPageShow(): void {
    this.settings = ThemeSettingsService.getInstance().getSettings();
    this.loadInputProfiles();
  }

  private loadInputProfiles(): void {
    InputProfileService.getInstance().initialize(getContext(this) as common.UIAbilityContext).then((): void => {
      this.inputProfiles = InputProfileService.getInstance().getDesktopProfiles();
      if (!InputProfileService.getInstance().hasDesktopProfile(this.settings.desktopInputProfileId)) {
        this.selectDesktopProfile('default');
      }
    }).catch((): void => {});
  }

  aboutToDisappear(): void {
    if (this.callback) BreakpointSystem.unsubscribe(this.callback);
    if (this.engineCallback) WineEngineService.getInstance().unsubscribe(this.engineCallback);
  }

  onBackPress(): boolean {
    return this.engineBusy;
  }

  private async runEngineOperation(message: string, task: () => Promise<boolean>, successMessage: string): Promise<void> {
    if (this.engineBusy) return;
    this.engineBusy = true;
    this.engineOperationMessage = message;
    try {
      const succeeded = await task();
      promptAction.showToast({ message: succeeded ? successMessage : WineEngineService.getInstance().getMessage() });
    } catch (_) {
      promptAction.showToast({ message: 'Wine 引擎操作失败，请查看引擎状态' });
    } finally {
      this.engineBusy = false;
      this.engineOperationMessage = '';
    }
  }

  private restartEngine(): void {
    const engine = WineEngineService.getInstance();
    const mode = engine.getMode() ?? this.settings.defaultDisplayMode;
    const homeDirectory = AppCatalogService.getInstance().getWineHomeDirectory();
    this.runEngineOperation('正在关闭 Windows 会话并重建 Wine/Wayland 服务…',
      (): Promise<boolean> => AppSessionService.getInstance().restartEngine(mode, homeDirectory),
      'Wine 引擎已重新启动');
  }

  private stopEngine(): void {
    this.runEngineOperation('正在停止全部 Windows 会话…', async (): Promise<boolean> => {
      await AppSessionService.getInstance().stopAll();
      return true;
    }, 'Wine 引擎已停止');
  }

  private resetPrefix(): void {
    this.runEngineOperation('正在重置 Wine prefix，请勿退出应用…', async (): Promise<boolean> => {
      await AppSessionService.getInstance().resetPrefix();
      return true;
    }, 'Wine 环境已重置');
  }

  private update(mode: DisplayMode = this.settings.defaultDisplayMode,
    view: ViewMode = this.settings.viewMode,
    glass: boolean = this.settings.useGlassEffect,
    background: boolean = this.settings.usePageBackground,
    controls: boolean = this.settings.showVirtualControls,
    autoHide: boolean = this.settings.autoHideVirtualControls,
    opacity: number = this.settings.controlOpacity,
    deadzone: number = this.settings.gamepadDeadzone,
    scale: number = this.settings.outputScale,
    theme: ThemeMode = this.settings.themeMode,
    controlBarDirection: ControlBarDirection = this.settings.controlBarDirection,
    virtualMouseConfig: VirtualMouseConfig = cloneVirtualMouseConfig(this.settings.virtualMouseConfig),
    desktopInputProfileId: string = this.settings.desktopInputProfileId): void {
    this.settings = {
      defaultDisplayMode: mode,
      desktopInputProfileId: desktopInputProfileId || 'default',
      viewMode: view,
      themeMode: theme,
      useGlassEffect: glass,
      usePageBackground: background,
      showVirtualControls: controls,
      autoHideVirtualControls: autoHide,
      controlBarDirection: controlBarDirection,
      virtualMouseConfig: cloneVirtualMouseConfig(virtualMouseConfig),
      controlOpacity: opacity,
      gamepadDeadzone: deadzone,
      outputScale: scale
    };
    GamepadManager.getInstance().setDeadzone(deadzone);
    WineWindowManager.getInstance().setOutputScalePercent(scale);
    ThemeSettingsService.getInstance().update(this.settings);
    InputOverlayWindowCoordinator.getInstance().setOpacity(opacity);
    InputOverlayWindowCoordinator.getInstance().setControlsVisible(controls);
  }

  private updateTheme(theme: ThemeMode): void {
    this.update(this.settings.defaultDisplayMode, this.settings.viewMode,
      this.settings.useGlassEffect, this.settings.usePageBackground,
      this.settings.showVirtualControls, this.settings.autoHideVirtualControls,
      this.settings.controlOpacity, this.settings.gamepadDeadzone,
      this.settings.outputScale, theme);
  }

  private updateControlBarDirection(direction: ControlBarDirection): void {
    this.update(this.settings.defaultDisplayMode, this.settings.viewMode,
      this.settings.useGlassEffect, this.settings.usePageBackground,
      this.settings.showVirtualControls, this.settings.autoHideVirtualControls,
      this.settings.controlOpacity, this.settings.gamepadDeadzone,
      this.settings.outputScale, this.settings.themeMode, direction);
  }

  private updateVirtualMouse(sensitivity: number = this.settings.virtualMouseConfig.mouseSensitivity,
    showCursor: boolean = this.settings.virtualMouseConfig.showCursor): void {
    const mouse = cloneVirtualMouseConfig(this.settings.virtualMouseConfig);
    mouse.mouseSensitivity = Math.max(50, Math.min(200, Math.round(sensitivity / 10) * 10));
    mouse.showCursor = showCursor;
    this.update(this.settings.defaultDisplayMode, this.settings.viewMode,
      this.settings.useGlassEffect, this.settings.usePageBackground,
      this.settings.showVirtualControls, this.settings.autoHideVirtualControls,
      this.settings.controlOpacity, this.settings.gamepadDeadzone,
      this.settings.outputScale, this.settings.themeMode,
      this.settings.controlBarDirection, mouse);
  }

  private selectDesktopProfile(profileId: string): void {
    this.update(this.settings.defaultDisplayMode, this.settings.viewMode,
      this.settings.useGlassEffect, this.settings.usePageBackground,
      this.settings.showVirtualControls, this.settings.autoHideVirtualControls,
      this.settings.controlOpacity, this.settings.gamepadDeadzone,
      this.settings.outputScale, this.settings.themeMode,
      this.settings.controlBarDirection, this.settings.virtualMouseConfig, profileId);
  }

  private async saveDesktopProfileCopy(): Promise<void> {
    const service = InputProfileService.getInstance();
    const sourceId = this.settings.desktopInputProfileId || 'default';
    const number = this.inputProfiles.filter((profile: InputProfile): boolean => profile.id !== 'default').length + 1;
    const profile = await service.duplicateProfile(sourceId, '桌面方案 ' + number.toString());
    this.inputProfiles = service.getDesktopProfiles();
    this.selectDesktopProfile(profile.id);
    promptAction.showToast({ message: '已保存并切换到 ' + profile.name });
  }

  private restoreDefaults(): void {
    const defaults = createDefaultGlobalSettings();
    this.settings = defaults;
    GamepadManager.getInstance().setDeadzone(defaults.gamepadDeadzone);
    WineWindowManager.getInstance().setOutputScalePercent(defaults.outputScale);
    ThemeSettingsService.getInstance().update(defaults);
    InputOverlayWindowCoordinator.getInstance().setOpacity(defaults.controlOpacity);
    InputOverlayWindowCoordinator.getInstance().setControlsVisible(defaults.showVirtualControls);
  }

  @Builder
  private SectionButton(label: string, section: SettingsSection, icon: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(18).fontColor([$r('app.color.text_primary')])
      Text(label).fontSize(14).fontColor($r('app.color.text_primary'))
        .fontWeight(this.section === section ? FontWeight.Medium : FontWeight.Regular)
    }
      .width('100%').height(46).padding({ left: 14, right: 14 }).borderRadius(14)
      .backgroundColor(this.section === section ? $r('app.color.selected_background') : $r('app.color.search_background'))
      .onClick(() => this.selectSection(section))
  }

  private sectionIndex(section: SettingsSection): number {
    if (section === 'display') return 0;
    if (section === 'appearance') return 1;
    if (section === 'input') return 2;
    if (section === 'engine') return 3;
    return 4;
  }

  private sectionAt(index: number): SettingsSection {
    if (index <= 0) return 'display';
    if (index === 1) return 'appearance';
    if (index === 2) return 'input';
    if (index === 3) return 'engine';
    return 'about';
  }

  private selectSection(section: SettingsSection): void {
    this.section = section;
    try {
      this.settingsScroller.scrollToIndex(this.sectionIndex(section), true, ScrollAlign.START);
    } catch (_) {
    }
  }

  @Builder
  private SwitchRow(title: string, description: string, enabled: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(description).fontSize(11).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled }).onChange((value: boolean) => onChange(value))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor($r('app.color.search_background'))
    .borderRadius(14)
  }

  @Builder
  private ControlBarDirectionChip(label: string, direction: ControlBarDirection) {
    Button(label)
      .height(40)
      .padding({ left: 14, right: 14 })
      .borderRadius(20)
      .fontSize(13)
      .fontColor(this.settings.controlBarDirection === direction ? '#FFFFFFFF' : $r('app.color.text_primary'))
      .backgroundColor(this.settings.controlBarDirection === direction ? $r('app.color.accent') : $r('app.color.search_background'))
      .id('control-bar-direction-' + direction)
      .onClick((): void => this.updateControlBarDirection(direction))
  }

  private selectedProfileName(): string {
    const selected = this.inputProfiles.find((profile: InputProfile): boolean =>
      profile.id === this.settings.desktopInputProfileId);
    return selected?.name ?? 'Vintage 默认手柄布局';
  }

  @Builder
  private InputProfileChoice(profile: InputProfile) {
    Row({ space: 10 }) {
      SymbolGlyph(profile.id === this.settings.desktopInputProfileId ?
        $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(20)
        .fontColor([profile.id === this.settings.desktopInputProfileId ?
          $r('app.color.accent') : $r('app.color.text_secondary')])
      Column({ space: 3 }) {
        Text(profile.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(profile.id === 'default' ? '内建默认方案' : '已保存桌面方案')
          .fontSize(10).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (profile.id === this.settings.desktopInputProfileId) {
        Text('使用中').fontSize(11).fontColor($r('app.color.accent'))
      }
    }
    .width('100%').height(58).padding({ left: 12, right: 12 }).borderRadius(14)
    .backgroundColor(profile.id === this.settings.desktopInputProfileId ?
      $r('app.color.selected_background') : $r('app.color.search_background'))
    .id('desktop-input-profile-' + profile.id)
    .onClick((): void => this.selectDesktopProfile(profile.id))
  }

  @Builder
  private DesktopInputProfiles() {
    Column({ space: 9 }) {
      Text('桌面模式输入方案').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text('桌面模式可同时运行多个程序，因此统一使用这里选择的全局方案；单应用模式可以在应用设置中使用专用方案。')
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      ForEach(this.inputProfiles, (profile: InputProfile): void => {
        this.InputProfileChoice(profile)
      }, (profile: InputProfile): string => profile.id)
      Button('保存当前配置为新方案')
        .width('100%').height(48).borderRadius(14)
        .backgroundColor($r('app.color.selected_background')).fontColor($r('app.color.accent'))
        .id('save-desktop-input-profile')
        .onClick((): void => { this.saveDesktopProfileCopy(); })
    }
    .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
  }

  @Builder
  private InputLayoutEntry() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.gamecontroller')).fontSize(22).fontColor([$r('app.color.accent')])
      }
      .width(48).height(48).borderRadius(16).backgroundColor($r('app.color.selected_background'))
      Column({ space: 4 }) {
        Text('编辑当前桌面方案布局').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.selectedProfileName() + '：设置方向、ABXY、肩键与辅助键的位置、大小和透明度').fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([$r('app.color.text_secondary')])
    }
    .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
    .id('open-input-layout-editor')
    .onClick((): void => { router.pushUrl({
      url: 'pages/InputLayoutEditor',
      params: {
        profileId: this.settings.desktopInputProfileId || 'default',
        profileName: this.selectedProfileName(),
        baseProfileId: this.settings.desktopInputProfileId || 'default'
      }
    }); })
  }

  @Builder
  private KeyMappingEntry() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.keyboard')).fontSize(22).fontColor([$r('app.color.accent')])
      }
      .width(48).height(48).borderRadius(16).backgroundColor($r('app.color.selected_background'))
      Column({ space: 4 }) {
        Text('当前桌面方案按键映射').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.selectedProfileName() + '：修改虚拟按键实际键值，并配置固定手柄或自由按键。').fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([$r('app.color.text_secondary')])
    }
    .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
    .id('open-global-key-mapping')
    .onClick((): void => { router.pushUrl({
      url: 'pages/AdvancedKeyMapping',
      params: {
        profileId: this.settings.desktopInputProfileId || 'default',
        profileName: this.selectedProfileName(),
        baseProfileId: this.settings.desktopInputProfileId || 'default'
      }
    }); })
  }

  @Builder
  private Content(section: SettingsSection) {
    Column({ space: 14 }) {
      if (section === 'display') {
        Column({ space: 16 }) {
          Text('Windows 显示').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text('全局默认模式').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 8 }) {
            Button('桌面模式').layoutWeight(1).height(48).borderRadius(14)
              .backgroundColor(this.settings.defaultDisplayMode === DisplayMode.DESKTOP ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.defaultDisplayMode === DisplayMode.DESKTOP ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.update(DisplayMode.DESKTOP))
            Button('单应用全屏').layoutWeight(1).height(48).borderRadius(14)
              .backgroundColor(this.settings.defaultDisplayMode === DisplayMode.SINGLE_APP ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.defaultDisplayMode === DisplayMode.SINGLE_APP ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.update(DisplayMode.SINGLE_APP))
          }.width('100%')
          Text('应用可单独覆盖该设置；切换活动模式时会重建 Wayland 会话，但不会重置 Wine prefix。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Text('输出缩放 ' + this.settings.outputScale + '%').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Slider({ value: this.settings.outputScale, min: 75, max: 150, step: 5 }).onChange((value: number) => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, this.settings.autoHideVirtualControls, this.settings.controlOpacity, this.settings.gamepadDeadzone, value))
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else if (section === 'appearance') {
        Column({ space: 16 }) {
          Text('外观').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text('主题').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 8 }) {
            Button('跟随系统').layoutWeight(1).height(48).borderRadius(14)
              .backgroundColor(this.settings.themeMode === ThemeMode.SYSTEM ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.themeMode === ThemeMode.SYSTEM ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.updateTheme(ThemeMode.SYSTEM))
            Button('浅色').layoutWeight(1).height(48).borderRadius(14)
              .backgroundColor(this.settings.themeMode === ThemeMode.LIGHT ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.themeMode === ThemeMode.LIGHT ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.updateTheme(ThemeMode.LIGHT))
            Button('深色').layoutWeight(1).height(48).borderRadius(14)
              .backgroundColor(this.settings.themeMode === ThemeMode.DARK ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.themeMode === ThemeMode.DARK ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.updateTheme(ThemeMode.DARK))
          }.width('100%')
          this.SwitchRow('玻璃卡片', '默认使用 16vp 圆角和半透明材质', this.settings.useGlassEffect, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, value))
          this.SwitchRow('自定义页面背景', '默认关闭，避免影响应用封面可读性', this.settings.usePageBackground, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, value))
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else if (section === 'input') {
        Column({ space: 16 }) {
          Text('输入与控制').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          this.SwitchRow('显示虚拟按键', '只控制十字键、摇杆、ABXY 和肩键；全屏鼠标与右上角控制栏不受影响', this.settings.showVirtualControls, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, value))
          this.SwitchRow('外设接管时隐藏按键', '检测到实体键盘、鼠标或手柄操作后，仅隐藏虚拟按键', this.settings.autoHideVirtualControls, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, value))
          Column({ space: 10 }) {
            Text('控制栏方向').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            Text('自动会根据横竖屏切换；自动隐藏会在控制栏收起 3 秒后完全隐藏，点击右上角热区即可唤出。')
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.ControlBarDirectionChip('自动', ControlBarDirection.AUTO)
              this.ControlBarDirectionChip('横向', ControlBarDirection.HORIZONTAL)
              this.ControlBarDirectionChip('纵向', ControlBarDirection.VERTICAL)
              this.ControlBarDirectionChip('自动隐藏', ControlBarDirection.AUTO_HIDE)
            }.width('100%')
          }
          .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
          Column({ space: 10 }) {
            Text('全屏触摸板模式').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            Text('从 Wine 画面右上角手指图标切换。开启后单指相对移动鼠标、轻点左键；双指轻点右键、双指滑动滚轮。')
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            this.SwitchRow('显示触摸光标', '操作时短暂显示鼠标位置与点击反馈', this.settings.virtualMouseConfig.showCursor,
              (value: boolean): void => this.updateVirtualMouse(this.settings.virtualMouseConfig.mouseSensitivity, value))
            Text('滚动灵敏度 ' + this.settings.virtualMouseConfig.mouseSensitivity + '%')
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Slider({ value: this.settings.virtualMouseConfig.mouseSensitivity, min: 50, max: 200, step: 10 })
              .id('virtual-mouse-sensitivity')
              .onChange((value: number): void => this.updateVirtualMouse(value))
          }
          .width('100%').padding(14).backgroundColor($r('app.color.search_background')).borderRadius(14)
          Text('控制层透明度 ' + this.settings.controlOpacity + '%').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Slider({ value: this.settings.controlOpacity, min: 25, max: 100, step: 1 }).onChange((value: number) => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, this.settings.autoHideVirtualControls, value))
          Text('手柄死区 ' + this.settings.gamepadDeadzone + '%').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Slider({ value: this.settings.gamepadDeadzone, min: 0, max: 40, step: 1 }).onChange((value: number) => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, this.settings.autoHideVirtualControls, this.settings.controlOpacity, value))
          this.DesktopInputProfiles()
          this.InputLayoutEntry()
          this.KeyMappingEntry()
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else if (section === 'engine') {
        Column({ space: 16 }) {
          Text('Wine 引擎').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text(this.engineMessage).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          Button('重启 Wine 引擎').height(48).borderRadius(14)
            .backgroundColor($r('app.color.accent'))
            .fontColor('#FFFFFFFF')
            .enabled(!this.engineBusy)
            .id('wine-engine-restart')
            .onClick((): void => AlertDialog.show({
              title: '重启 Wine 引擎',
              message: '这会关闭所有 Windows 程序并重建 Wine 与 Wayland 服务，但不会删除 Wine prefix。重启期间画面将被锁定。',
              primaryButton: { value: '取消', action: (): void => {} },
              secondaryButton: { value: '立即重启', action: (): void => { this.restartEngine(); } }
            }))
          Button('停止全部 Windows 会话').height(48).borderRadius(14)
            .backgroundColor($r('app.color.search_background'))
            .fontColor($r('app.color.text_primary'))
            .enabled(!this.engineBusy)
            .id('wine-engine-stop-all')
            .onClick((): void => AlertDialog.show({
              title: '停止全部 Windows 会话',
              message: '正在运行的 Windows 程序会被关闭。',
              primaryButton: { value: '取消', action: (): void => {} },
              secondaryButton: { value: '停止', fontColor: '#D94848', action: (): void => { this.stopEngine(); } }
            }))
          Button('重置 Wine prefix').height(48).borderRadius(14)
            .backgroundColor('#25D94848')
            .fontColor('#D94848')
            .enabled(!this.engineBusy)
            .id('wine-engine-reset-prefix')
            .onClick(() => AlertDialog.show({ title: '重置 Wine 环境', message: '这会删除当前 Wine prefix 中的应用数据，且无法撤销。', primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '重置', fontColor: '#D94848', action: (): void => { this.resetPrefix(); } } }))
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else {
        Column({ space: 12 }) {
          Text('旧柚Pro').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('Wine 作为按需启动的 Windows 兼容引擎。').fontSize(13).fontColor($r('app.color.text_secondary'))
          Text('当前阶段：主工程架构、应用目录、双显示模式和统一输入路由。').fontSize(13).fontColor($r('app.color.text_secondary'))
          Button('打开帮助中心').height(48).borderRadius(14)
            .backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary'))
            .onClick((): void => { router.pushUrl({ url: 'pages/HelpCenter' }); })
        }
        .width('100%')
        .padding(24)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      }
    }.width('100%')
  }

  @Builder
  private SettingsList(maxWidth: number) {
    List({ space: 14, scroller: this.settingsScroller }) {
      ListItem() { this.Content('display') }.width('100%').id('settings-section-display')
      ListItem() { this.Content('appearance') }.width('100%').id('settings-section-appearance')
      ListItem() { this.Content('input') }.width('100%').id('settings-section-input')
      ListItem() { this.Content('engine') }.width('100%').id('settings-section-engine')
      ListItem() { this.Content('about') }.width('100%').id('settings-section-about')
    }
    .layoutWeight(1)
    .width('100%')
    .constraintSize({ maxWidth: maxWidth })
    .padding({ right: 10, bottom: 16 })
    .scrollBar(BarState.On)
    .scrollBarWidth(6)
    .scrollBarColor($r('app.color.accent'))
    .edgeEffect(EdgeEffect.Spring)
    .onScrollIndex((start: number): void => {
      this.section = this.sectionAt(start);
    })
    .id('system-settings-list')
  }

  build() {
    Stack() {
      Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18).fontColor([$r('app.color.text_primary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.search_background'))
          .onClick(() => router.back())
        Column({ space: 3 }) {
          Text('系统设置').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('调整显示模式、外观、输入和 Wine 引擎行为。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('恢复默认').height(48).borderRadius(14)
          .backgroundColor($r('app.color.search_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.restoreDefaults())
      }
      .height(64)
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 0 })

      if (this.breakpoint === 'lg' || this.breakpoint === 'xl') {
        Row({ space: 22 }) {
          Column({ space: 5 }) {
            this.SectionButton('显示模式', 'display', $r('sys.symbol.rectangle_grid_1x2'))
            this.SectionButton('外观', 'appearance', $r('sys.symbol.square_grid_2x2'))
            this.SectionButton('输入与手柄', 'input', $r('sys.symbol.list_bullet'))
            this.SectionButton('Wine 引擎', 'engine', $r('sys.symbol.arrow_clockwise'))
            this.SectionButton('关于', 'about', $r('sys.symbol.info_circle'))
          }
          .width(230)
          .height('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_glass_background'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .borderRadius(20)
          this.SettingsList(1080)
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 20, right: 20, top: 0, bottom: 20 })
      } else {
        Column({ space: 12 }) {
          Scroll() {
            Row({ space: 8 }) {
              Button('显示').height(48).borderRadius(14)
                .backgroundColor(this.section === 'display' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'display' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.selectSection('display'))
              Button('外观').height(48).borderRadius(14)
                .backgroundColor(this.section === 'appearance' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'appearance' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.selectSection('appearance'))
              Button('输入').height(48).borderRadius(14)
                .backgroundColor(this.section === 'input' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'input' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.selectSection('input'))
              Button('引擎').height(48).borderRadius(14)
                .backgroundColor(this.section === 'engine' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'engine' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.selectSection('engine'))
              Button('关于').height(48).borderRadius(14)
                .backgroundColor(this.section === 'about' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'about' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.selectSection('about'))
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          this.SettingsList(840)
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 0, bottom: 16 })
      }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_background'))

      if (this.engineBusy) {
        Column({ space: 14 }) {
          LoadingProgress().width(52).height(52).color('#FFFFFFFF')
          Text('Wine 引擎维护中').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          Text(this.engineOperationMessage).fontSize(13).fontColor('#DDE8F2FF').textAlign(TextAlign.Center).maxLines(3)
          Text('请保持应用在前台，完成前所有操作已锁定。').fontSize(11).fontColor('#AFC2D4FF')
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(32)
        .backgroundColor('#EE111827')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .hitTestBehavior(HitTestMode.Block)
        .focusable(true)
        .zIndex(10000)
        .id('wine-engine-operation-blocker')
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
