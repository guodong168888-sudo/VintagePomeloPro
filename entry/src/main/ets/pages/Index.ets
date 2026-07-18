import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppSearchBar } from '../components/SearchBar';
import { AppCard } from '../components/AppCard';
import { BreakpointSystem, BreakpointType } from '../common/BreakpointSystem';
import {
  AppDescriptor,
  AppSource,
  EngineState,
  GlobalSettings,
  LaunchKind,
  RuntimeSession,
  ViewMode,
  normalizeLaunchPath
} from '../model/AppModels';
import { AppCatalogService } from '../service/AppCatalogService';
import { AppSessionService, LaunchConflictKind } from '../service/AppSessionService';
import { AppSettingsStore } from '../service/AppSettingsStore';
import { LauncherAdapterRegistry } from '../service/LauncherAdapterRegistry';
import { ThemeSettingsListener, ThemeSettingsService } from '../service/ThemeSettingsService';
import { WineEngineService } from '../service/WineEngineService';
import { WineWindowManager } from '../service/WineWindowManager';
import { GamepadManager } from '../service/GamepadManager';
import { InputProfileService } from '../service/InputProfileService';

type CatalogFilter = 'all' | 'builtin' | 'windows' | 'running';

@Entry
@Component
struct Index {
  @State private apps: AppDescriptor[] = [];
  @State private searchQuery: string = '';
  @State private filter: CatalogFilter = 'all';
  @State private breakpoint: BreakpointType = 'lg';
  @State private sidebarCollapsed: boolean = false;
  @State private settings: GlobalSettings = AppSettingsStore.getInstance().getGlobalSettings();
  @State private engineState: EngineState = EngineState.STOPPED;
  @State private engineMessage: string = 'Wine 引擎未启动';
  @State private scanning: boolean = false;
  @State private runningPaths: Set<string> = new Set<string>();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private breakpointCallback: ((value: BreakpointType) => void) | null = null;
  private engineCallback: ((state: EngineState, message: string) => void) | null = null;
  private settingsCallback: ThemeSettingsListener | null = null;
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.initialize();
    BreakpointSystem.initialize();
    this.breakpointCallback = (value: BreakpointType): void => {
      this.breakpoint = value;
    };
    BreakpointSystem.subscribe(this.breakpointCallback);
    this.engineCallback = (state: EngineState, message: string): void => {
      this.engineState = state;
      this.engineMessage = message;
      this.refreshRunningState();
    };
    WineEngineService.getInstance().subscribe(this.engineCallback);
    this.refreshTimer = setInterval(() => this.refreshRunningState(), 1500);
  }

  aboutToDisappear(): void {
    if (this.breakpointCallback) BreakpointSystem.unsubscribe(this.breakpointCallback);
    if (this.engineCallback) WineEngineService.getInstance().unsubscribe(this.engineCallback);
    if (this.settingsCallback) ThemeSettingsService.getInstance().unsubscribe(this.settingsCallback);
    if (this.refreshTimer >= 0) clearInterval(this.refreshTimer);
  }

  private async initialize(): Promise<void> {
    await ThemeSettingsService.getInstance().initialize(this.context);
    this.settings = ThemeSettingsService.getInstance().getSettings();
    WineWindowManager.getInstance().setOutputScalePercent(this.settings.outputScale);
    this.settingsCallback = (settings: GlobalSettings): void => {
      this.settings = settings;
      WineWindowManager.getInstance().setOutputScalePercent(settings.outputScale);
    };
    ThemeSettingsService.getInstance().subscribe(this.settingsCallback);
    AppCatalogService.getInstance().initialize(this.context);
    AppSessionService.getInstance().initialize(this.context);
    LauncherAdapterRegistry.getInstance().initialize(this.context);
    WineEngineService.getInstance().initialize(this.context);
    await InputProfileService.getInstance().initialize(this.context);
    GamepadManager.getInstance().initialize(this.settings.gamepadDeadzone);
    await this.rescan();
  }

  private async rescan(): Promise<void> {
    this.scanning = true;
    this.apps = await AppCatalogService.getInstance().scan();
    this.refreshRunningState();
    this.scanning = false;
  }

  private async authorizeDirectory(): Promise<void> {
    try {
      const root = await AppCatalogService.getInstance().authorizeLibrary();
      if (root.length > 0) {
        promptAction.showToast({ message: '已授权专用 games 目录' });
        await this.rescan();
      }
    } catch (_) {
      promptAction.showToast({ message: '目录授权未完成' });
    }
  }

  private refreshRunningState(): void {
    this.runningPaths = AppSessionService.getInstance().getRunningPaths();
  }

  private filteredApps(): AppDescriptor[] {
    const query = this.searchQuery.trim().toLowerCase();
    return this.apps.filter((app: AppDescriptor) => {
      const normalized = normalizeLaunchPath(app.launchTarget.executable);
      if (this.filter === 'builtin' && app.source !== AppSource.BUILTIN) return false;
      if (this.filter === 'windows' && app.source !== AppSource.DOWNLOAD) return false;
      if (this.filter === 'running' && !this.runningPaths.has(normalized)) return false;
      if (!query) return true;
      return app.title.toLowerCase().includes(query) || normalized.includes(query);
    });
  }

  private gridColumns(): string {
    if (this.settings.viewMode === ViewMode.COMPACT || this.breakpoint === 'sm') return '1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return this.settings.viewMode === ViewMode.LARGE ? '1fr 1fr 1fr' : '1fr 1fr 1fr 1fr';
    return this.settings.viewMode === ViewMode.LARGE ? '1fr 1fr' : '1fr 1fr 1fr';
  }

  private async launch(app: AppDescriptor): Promise<void> {
    if (!app.available) {
      promptAction.showToast({ message: '程序不可用，请重新关联可执行文件' });
      return;
    }
    const conflict = AppSessionService.getInstance().getLaunchConflict(app, this.settings);
    if (conflict !== LaunchConflictKind.NONE) {
      AlertDialog.show({
        title: conflict === LaunchConflictKind.DISPLAY_MODE ? '切换显示模式' : '启动另一个应用',
        message: conflict === LaunchConflictKind.DISPLAY_MODE ?
          '当前 Windows 会话使用另一种显示模式。继续将关闭当前会话并重建 Wayland 显示，Wine prefix 不会重置。' :
          '单应用模式同时只运行一个 Windows 程序。继续将关闭当前程序并启动所选应用。',
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: {
          value: '关闭并切换',
          fontColor: '#D94848',
          action: (): void => { this.switchAndLaunch(app); }
        }
      });
      return;
    }
    await this.doLaunch(app, false);
  }

  private async switchAndLaunch(app: AppDescriptor): Promise<void> {
    await this.doLaunch(app, true);
  }

  private async doLaunch(app: AppDescriptor, switchMode: boolean): Promise<void> {
    const root = AppCatalogService.getInstance().getWineHomeDirectory();
    let session: RuntimeSession | null = null;
    if (switchMode) {
      session = await AppSessionService.getInstance().switchModeAndLaunch(app, this.settings, root);
    } else {
      session = await LauncherAdapterRegistry.getInstance().launch(app, this.settings, root);
    }
    if (!session && (app.launchTarget.kind === LaunchKind.WINE_EXE ||
      app.launchTarget.kind === LaunchKind.WINE_SYSTEM ||
      app.launchTarget.kind === LaunchKind.WINE_DESKTOP)) {
      promptAction.showToast({ message: WineEngineService.getInstance().getMessage() });
    }
    this.refreshRunningState();
  }

  private openAppSettings(app: AppDescriptor): void {
    router.pushUrl({ url: 'pages/AppSettings', params: { appId: app.id } });
  }

  private showAppLongPressMenu(app: AppDescriptor): void {
    promptAction.showDialog({
      title: app.title,
      message: '请选择操作',
      buttons: [
        { text: app.available ? '启动或恢复' : '重新关联', color: '#5569D8' },
        { text: '应用设置', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') }
      ]
    }).then((result) => {
      if (result.index === 0) {
        if (app.available) this.launch(app); else this.openAppSettings(app);
      } else if (result.index === 1) {
        this.openAppSettings(app);
      }
    }).catch((_error: Error) => {});
  }

  private async setViewMode(mode: ViewMode): Promise<void> {
    await AppSettingsStore.getInstance().setViewMode(mode);
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
  }

  @Builder
  private NavItem(label: string, value: CatalogFilter, icon: string) {
    Row({ space: 12 }) {
      Text(icon).fontSize(19).fontColor($r('app.color.text_primary'))
      if (!this.sidebarCollapsed) {
        Text(label).fontSize(14).fontColor($r('app.color.text_primary'))
          .fontWeight(this.filter === value ? FontWeight.Medium : FontWeight.Normal)
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 15, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.filter === value ? $r('app.color.selected_background') : '#00000000')
    .onClick(() => this.filter = value)
  }

  @Builder
  private SideBar() {
    Column() {
      Row() {
        if (!this.sidebarCollapsed) {
          Column({ space: 3 }) {
            Text('Vintage Pomelo Pro').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(this.apps.length + ' 个程序').fontSize(11).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        Button(this.sidebarCollapsed ? '›' : '‹').type(ButtonType.Circle).width(34).height(34)
          .backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary'))
          .onClick(() => this.sidebarCollapsed = !this.sidebarCollapsed)
      }.width('100%').height(58)

      if (!this.sidebarCollapsed) {
        AppSearchBar({
          value: this.searchQuery,
          onValueChange: (value: string): void => { this.searchQuery = value; }
        })
        Row({ space: 8 }) {
          Button('重新扫描').layoutWeight(1).height(36).fontSize(12).borderRadius(18)
            .onClick(() => this.rescan())
          Button('目录授权').layoutWeight(1).height(36).fontSize(12).borderRadius(18)
            .onClick(() => this.authorizeDirectory())
        }.margin({ top: 10, bottom: 16 })
      }

      Column({ space: 4 }) {
        this.NavItem('全部应用', 'all', '▦')
        this.NavItem('内建应用', 'builtin', '◆')
        this.NavItem('Windows 程序', 'windows', '⊞')
        this.NavItem('运行中', 'running', '▶')
      }.width('100%')

      Blank()
      Row({ space: 12 }) {
        Text('⚙').fontSize(19).fontColor($r('app.color.text_primary'))
        if (!this.sidebarCollapsed) {
          Text('系统设置').fontSize(14).fontColor($r('app.color.text_primary'))
        }
      }
      .width('100%').height(44).padding({ left: 15 }).borderRadius(12)
      .onClick(() => router.pushUrl({ url: 'pages/SystemSettings' }))
      Row({ space: 12 }) {
        Text('?').fontSize(19).fontColor($r('app.color.text_primary'))
        if (!this.sidebarCollapsed) {
          Text('帮助').fontSize(14).fontColor($r('app.color.text_primary'))
        }
      }.width('100%').height(44).padding({ left: 15 })
        .onClick((): void => {
          AlertDialog.show({
          title: '帮助',
          message: '将 Windows 程序放入 Download/com.vintage.pomelopro/games。每个一级目录会生成一张卡，目录内存在多个候选 EXE 时可在卡片设置中关联。',
          confirm: { value: '知道了', action: (): void => {} }
          });
        })
    }
    .width(this.sidebarCollapsed ? 86 : 278)
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.sidebar_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
  }

  @Builder
  private Header() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(this.filter === 'running' ? '运行中的应用' : 'Windows 应用库')
            .fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.engineMessage).fontSize(11).fontColor(this.engineState === EngineState.ERROR ? '#D94848' : $r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Row({ space: 4 }) {
          Button('▦').type(ButtonType.Circle).width(36).height(36).backgroundColor(this.settings.viewMode === ViewMode.GRID ? $r('app.color.selected_background') : '#00000000').onClick(() => this.setViewMode(ViewMode.GRID))
          Button('☷').type(ButtonType.Circle).width(36).height(36).backgroundColor(this.settings.viewMode === ViewMode.COMPACT ? $r('app.color.selected_background') : '#00000000').onClick(() => this.setViewMode(ViewMode.COMPACT))
          Button('▣').type(ButtonType.Circle).width(36).height(36).backgroundColor(this.settings.viewMode === ViewMode.LARGE ? $r('app.color.selected_background') : '#00000000').onClick(() => this.setViewMode(ViewMode.LARGE))
        }
      }.width('100%')
      if (this.breakpoint === 'sm' || this.breakpoint === 'md') {
        AppSearchBar({
          value: this.searchQuery,
          onValueChange: (value: string): void => { this.searchQuery = value; }
        })
      }
    }.width('100%')
  }

  @Builder
  private Library() {
    Column() {
      this.Header()
      if (this.scanning) {
        Row({ space: 10 }) {
          LoadingProgress().width(20).height(20)
          Text('正在扫描应用目录…').fontColor($r('app.color.text_secondary'))
        }.margin({ top: 22 })
      } else if (this.filteredApps().length === 0) {
        Column({ space: 12 }) {
          Text('▦').fontSize(52).fontColor($r('app.color.text_secondary'))
          Text('这里还没有应用').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text('授权 Download/com.vintage.pomelopro/games 后重新扫描').fontSize(13).fontColor($r('app.color.text_secondary'))
          Button('授权目录').borderRadius(20).onClick(() => this.authorizeDirectory())
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.filteredApps(), (app: AppDescriptor) => {
            GridItem() {
              AppCard({
                app: app,
                viewMode: this.settings.viewMode,
                running: this.runningPaths.has(normalizeLaunchPath(app.launchTarget.executable)),
                useGlassEffect: this.settings.useGlassEffect,
                resolvedDisplayMode: AppSessionService.getInstance().resolveMode(app, this.settings),
                onLaunch: (target: AppDescriptor): void => { this.launch(target); },
                onSettings: (target: AppDescriptor): void => { this.openAppSettings(target); },
                onLongPress: (target: AppDescriptor): void => { this.showAppLongPressMenu(target); }
              })
            }
          }, (app: AppDescriptor) => app.id)
        }
        .columnsTemplate(this.gridColumns())
        .columnsGap(16)
        .rowsGap(16)
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 20, bottom: this.breakpoint === 'sm' || this.breakpoint === 'md' ? 76 : 20 })
        .scrollBar(BarState.Auto)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding({ left: 24, right: 24, top: 22 })
  }

  @Builder
  private BottomBar() {
    Row() {
      Button('全部').layoutWeight(1).backgroundColor(this.filter === 'all' ? $r('app.color.selected_background') : '#00000000').onClick(() => this.filter = 'all')
      Button('内建').layoutWeight(1).backgroundColor(this.filter === 'builtin' ? $r('app.color.selected_background') : '#00000000').onClick(() => this.filter = 'builtin')
      Button('Windows').layoutWeight(1).backgroundColor(this.filter === 'windows' ? $r('app.color.selected_background') : '#00000000').onClick(() => this.filter = 'windows')
      Button('运行中').layoutWeight(1).backgroundColor(this.filter === 'running' ? $r('app.color.selected_background') : '#00000000').onClick(() => this.filter = 'running')
      Button('设置').layoutWeight(1).backgroundColor('#00000000').onClick(() => router.pushUrl({ url: 'pages/SystemSettings' }))
    }
    .height(64).width('100%').padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.card_glass_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .align(Alignment.Bottom)
  }

  build() {
    Stack() {
      Row() {
        if (this.breakpoint === 'lg' || this.breakpoint === 'xl') {
          this.SideBar()
        }
        this.Library()
      }.width('100%').height('100%')
      if (this.breakpoint === 'sm' || this.breakpoint === 'md') {
        this.BottomBar()
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
