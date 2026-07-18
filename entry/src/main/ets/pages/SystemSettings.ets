import router from '@ohos.router';
import { BreakpointSystem, BreakpointType } from '../common/BreakpointSystem';
import { DisplayMode, GlobalSettings, ThemeMode, ViewMode, createDefaultGlobalSettings } from '../model/AppModels';
import { ThemeSettingsService } from '../service/ThemeSettingsService';
import { WineEngineService } from '../service/WineEngineService';
import { GamepadManager } from '../service/GamepadManager';
import { WineWindowManager } from '../service/WineWindowManager';
import { AppSessionService } from '../service/AppSessionService';

type SettingsSection = 'display' | 'appearance' | 'input' | 'engine' | 'about';

@Entry
@Component
struct SystemSettingsPage {
  @State private settings: GlobalSettings = createDefaultGlobalSettings();
  @State private breakpoint: BreakpointType = 'lg';
  @State private section: SettingsSection = 'display';
  private callback: ((value: BreakpointType) => void) | null = null;

  aboutToAppear(): void {
    this.settings = ThemeSettingsService.getInstance().getSettings();
    BreakpointSystem.initialize();
    this.callback = (value: BreakpointType): void => {
      this.breakpoint = value;
    };
    BreakpointSystem.subscribe(this.callback);
  }

  aboutToDisappear(): void {
    if (this.callback) BreakpointSystem.unsubscribe(this.callback);
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
    theme: ThemeMode = this.settings.themeMode): void {
    this.settings = {
      defaultDisplayMode: mode,
      viewMode: view,
      themeMode: theme,
      useGlassEffect: glass,
      usePageBackground: background,
      showVirtualControls: controls,
      autoHideVirtualControls: autoHide,
      controlOpacity: opacity,
      gamepadDeadzone: deadzone,
      outputScale: scale
    };
    GamepadManager.getInstance().setDeadzone(deadzone);
    WineWindowManager.getInstance().setOutputScalePercent(scale);
    ThemeSettingsService.getInstance().update(this.settings);
  }

  private updateTheme(theme: ThemeMode): void {
    this.update(this.settings.defaultDisplayMode, this.settings.viewMode,
      this.settings.useGlassEffect, this.settings.usePageBackground,
      this.settings.showVirtualControls, this.settings.autoHideVirtualControls,
      this.settings.controlOpacity, this.settings.gamepadDeadzone,
      this.settings.outputScale, theme);
  }

  private restoreDefaults(): void {
    const defaults = createDefaultGlobalSettings();
    this.settings = defaults;
    GamepadManager.getInstance().setDeadzone(defaults.gamepadDeadzone);
    WineWindowManager.getInstance().setOutputScalePercent(defaults.outputScale);
    ThemeSettingsService.getInstance().update(defaults);
  }

  @Builder
  private SectionButton(label: string, section: SettingsSection, icon: string) {
    Row({ space: 12 }) {
      Text(icon).fontSize(18).fontColor($r('app.color.text_primary'))
      Text(label).fontSize(14).fontColor($r('app.color.text_primary'))
        .fontWeight(this.section === section ? FontWeight.Medium : FontWeight.Regular)
    }
      .width('100%').height(46).padding({ left: 14, right: 14 }).borderRadius(14)
      .backgroundColor(this.section === section ? $r('app.color.selected_background') : $r('app.color.search_background'))
      .onClick(() => this.section = section)
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
  private Content() {
    Column({ space: 14 }) {
      if (this.section === 'display') {
        Column({ space: 16 }) {
          Text('Windows 显示').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text('全局默认模式').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 8 }) {
            Button('桌面模式').layoutWeight(1).height(40).borderRadius(14)
              .backgroundColor(this.settings.defaultDisplayMode === DisplayMode.DESKTOP ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.defaultDisplayMode === DisplayMode.DESKTOP ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.update(DisplayMode.DESKTOP))
            Button('单应用全屏').layoutWeight(1).height(40).borderRadius(14)
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
      } else if (this.section === 'appearance') {
        Column({ space: 16 }) {
          Text('外观').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text('主题').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 8 }) {
            Button('跟随系统').layoutWeight(1).height(40).borderRadius(14)
              .backgroundColor(this.settings.themeMode === ThemeMode.SYSTEM ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.themeMode === ThemeMode.SYSTEM ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.updateTheme(ThemeMode.SYSTEM))
            Button('浅色').layoutWeight(1).height(40).borderRadius(14)
              .backgroundColor(this.settings.themeMode === ThemeMode.LIGHT ? $r('app.color.accent') : $r('app.color.search_background'))
              .fontColor(this.settings.themeMode === ThemeMode.LIGHT ? '#FFFFFFFF' : $r('app.color.text_primary'))
              .onClick(() => this.updateTheme(ThemeMode.LIGHT))
            Button('深色').layoutWeight(1).height(40).borderRadius(14)
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
      } else if (this.section === 'input') {
        Column({ space: 16 }) {
          Text('输入与控制').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          this.SwitchRow('虚拟键鼠与手柄', '为 Windows 桌面和单应用会话显示覆盖层', this.settings.showVirtualControls, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, value))
          this.SwitchRow('自动隐藏', '连接实体键盘鼠标或手柄后收起覆盖层', this.settings.autoHideVirtualControls, (value: boolean): void => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, value))
          Text('控制层透明度 ' + this.settings.controlOpacity + '%').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Slider({ value: this.settings.controlOpacity, min: 25, max: 100, step: 1 }).onChange((value: number) => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, this.settings.autoHideVirtualControls, value))
          Text('手柄死区 ' + this.settings.gamepadDeadzone + '%').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Slider({ value: this.settings.gamepadDeadzone, min: 0, max: 40, step: 1 }).onChange((value: number) => this.update(this.settings.defaultDisplayMode, this.settings.viewMode, this.settings.useGlassEffect, this.settings.usePageBackground, this.settings.showVirtualControls, this.settings.autoHideVirtualControls, this.settings.controlOpacity, value))
          Button('编辑虚拟按键布局').height(42).borderRadius(14)
            .backgroundColor($r('app.color.search_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => router.pushUrl({ url: 'pages/InputLayoutEditor' }))
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else if (this.section === 'engine') {
        Column({ space: 16 }) {
          Text('Wine 引擎').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Text(WineEngineService.getInstance().getMessage()).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          Button('停止全部 Windows 会话').height(42).borderRadius(14)
            .backgroundColor($r('app.color.search_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => AppSessionService.getInstance().stopAll())
          Button('重置 Wine prefix').height(42).borderRadius(14)
            .backgroundColor('#25D94848')
            .fontColor('#D94848')
            .onClick(() => AlertDialog.show({ title: '重置 Wine 环境', message: '这会删除当前 Wine prefix 中的应用数据。', primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '重置', fontColor: '#D94848', action: (): void => { AppSessionService.getInstance().resetPrefix(); } } }))
        }
        .width('100%')
        .padding(22)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      } else {
        Column({ space: 12 }) {
          Text('Vintage Pomelo Pro').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('Wine 作为按需启动的 Windows 兼容引擎。').fontSize(13).fontColor($r('app.color.text_secondary'))
          Text('当前阶段：主工程架构、应用目录、双显示模式和统一输入路由。').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(24)
        .backgroundColor($r('app.color.card_glass_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(20)
      }
    }.width('100%')
  }

  build() {
    Column() {
      Row() {
        Button('‹').type(ButtonType.Circle).width(38).height(38)
          .backgroundColor($r('app.color.search_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => router.back())
        Column({ space: 3 }) {
          Text('系统设置').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('调整显示模式、外观、输入和 Wine 引擎行为。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('恢复默认').height(38).borderRadius(14)
          .backgroundColor($r('app.color.search_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.restoreDefaults())
      }
      .height(78)
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      if (this.breakpoint === 'lg' || this.breakpoint === 'xl') {
        Row({ space: 22 }) {
          Column({ space: 5 }) {
            this.SectionButton('显示模式', 'display', '▣')
            this.SectionButton('外观', 'appearance', '◐')
            this.SectionButton('输入与手柄', 'input', '⌨')
            this.SectionButton('Wine 引擎', 'engine', 'W')
            this.SectionButton('关于', 'about', 'i')
          }
          .width(230)
          .height('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_glass_background'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .borderRadius(20)
          Scroll() { this.Content() }.layoutWeight(1).height('100%').scrollBar(BarState.Auto)
        }.layoutWeight(1).width('100%').padding({ left: 20, right: 20, bottom: 20 })
      } else {
        Column({ space: 12 }) {
          Scroll() {
            Row({ space: 8 }) {
              Button('显示').height(38).borderRadius(14)
                .backgroundColor(this.section === 'display' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'display' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.section = 'display')
              Button('外观').height(38).borderRadius(14)
                .backgroundColor(this.section === 'appearance' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'appearance' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.section = 'appearance')
              Button('输入').height(38).borderRadius(14)
                .backgroundColor(this.section === 'input' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'input' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.section = 'input')
              Button('引擎').height(38).borderRadius(14)
                .backgroundColor(this.section === 'engine' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'engine' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.section = 'engine')
              Button('关于').height(38).borderRadius(14)
                .backgroundColor(this.section === 'about' ? $r('app.color.accent') : $r('app.color.search_background'))
                .fontColor(this.section === 'about' ? '#FFFFFFFF' : $r('app.color.text_primary'))
                .onClick(() => this.section = 'about')
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          Scroll() { this.Content() }.layoutWeight(1).scrollBar(BarState.Auto)
        }.layoutWeight(1).width('100%').padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
