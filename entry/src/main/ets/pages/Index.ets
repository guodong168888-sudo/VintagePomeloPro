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

type CatalogFilter = 'builtin' | 'windows' | 'running' | 'favorite';

@Entry
@Component
struct Index {
  @StorageLink('overlayEditorRequest') @Watch('onOverlayEditorRequest') private overlayEditorRequest: string = '';
  @State private apps: AppDescriptor[] = [];
  @State private visibleApps: AppDescriptor[] = [];
  @State private searchQuery: string = '';
  @State private filter: CatalogFilter = 'builtin';
  @State private breakpoint: BreakpointType = 'lg';
  @State private sidebarCollapsed: boolean = false;
  @State private mobileSidebarVisible: boolean = false;
  @State private settings: GlobalSettings = AppSettingsStore.getInstance().getGlobalSettings();
  @State private engineState: EngineState = EngineState.STOPPED;
  @State private engineMessage: string = 'Wine 引擎未启动';
  @State private scanning: boolean = false;
  @State private runningAppIds: Set<string> = new Set<string>();
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

  onPageShow(): void {
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    this.refreshRunningState();
  }

  private onOverlayEditorRequest(): void {
    const raw = this.overlayEditorRequest;
    if (!raw) return;
    AppStorage.setOrCreate('overlayEditorRequest', '');
    try {
      const request = JSON.parse(raw) as Record<string, string>;
      router.pushUrl({
        url: 'pages/InputLayoutEditor',
        params: {
          profileId: request.profileId || 'default',
          profileName: request.profileName || '默认键鼠手柄',
          appId: request.appId || ''
        }
      });
    } catch (_) {
    }
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

  private refreshRunningState(): void {
    const running = AppSessionService.getInstance().getRunningAppIds();
    this.runningAppIds = running;
    this.visibleApps = this.filterApps(this.searchQuery, this.filter, running);
  }

  private filterApps(searchQuery: string, filter: CatalogFilter,
    running: Set<string> = this.runningAppIds): AppDescriptor[] {
    const query = searchQuery.trim().toLowerCase();
    return this.apps.filter((app: AppDescriptor) => {
      const normalized = normalizeLaunchPath(app.launchTarget.executable);
      if (filter === 'builtin' && app.source !== AppSource.BUILTIN) return false;
      if (filter === 'windows' && app.source !== AppSource.DOWNLOAD) return false;
      if (filter === 'running' && !running.has(app.id)) return false;
      if (filter === 'favorite' && !AppSettingsStore.getInstance().getAppSettings(app.id).favorite) return false;
      if (!query) return true;
      return app.title.toLowerCase().includes(query) || normalized.includes(query);
    });
  }

  private updateSearch(value: string): void {
    this.searchQuery = value;
    this.visibleApps = this.filterApps(value, this.filter);
  }

  private selectFilter(value: CatalogFilter): void {
    this.filter = value;
    this.visibleApps = this.filterApps(this.searchQuery, value);
    this.mobileSidebarVisible = false;
  }

  private filterTitle(): string {
    if (this.filter === 'builtin') return 'Wine 应用库';
    if (this.filter === 'windows') return 'Windows 程序';
    if (this.filter === 'running') return '运行中的应用';
    if (this.filter === 'favorite') return '收藏的应用';
    return 'Wine 应用库';
  }

  private filterDescription(): string {
    if (this.filter === 'builtin') return 'Wine 桌面、系统工具与内建测试程序';
    if (this.filter === 'windows') return '来自 Download/com.vintage.pomelopro/games';
    if (this.filter === 'running') return '点击卡片可恢复，长按可关闭会话';
    if (this.filter === 'favorite') return '已收藏的内建应用和 Windows 程序';
    return this.engineMessage;
  }

  private emptyTitle(): string {
    if (this.searchQuery.trim()) return '没有匹配的应用';
    if (this.filter === 'favorite') return '还没有收藏应用';
    if (this.filter === 'running') return '当前没有运行中的应用';
    if (this.filter === 'windows') return '尚未发现 Windows 程序';
    return '未找到内建应用';
  }

  private emptyDescription(): string {
    if (this.searchQuery.trim()) return '请更换关键词，或清除搜索后查看当前分类的全部内容';
    if (this.filter === 'favorite') return '在应用设置中开启收藏后，应用会显示在这里';
    if (this.filter === 'running') return '启动 Wine 桌面或程序后，可在这里恢复或关闭会话';
    if (this.filter === 'windows') return '将程序放入 Download/com.vintage.pomelopro/games，应用会自动扫描';
    return '安装包中的内建应用清单为空，请检查应用资源';
  }

  private emptyIcon(): Resource {
    if (this.filter === 'favorite') return $r('sys.symbol.star');
    if (this.filter === 'running') return $r('sys.symbol.play_fill');
    if (this.filter === 'windows') return $r('sys.symbol.folder');
    return $r('sys.symbol.house_fill');
  }

  private emptyActionLabel(): string {
    if (this.searchQuery.trim()) return '清除搜索';
    if (this.filter === 'windows') return '重新扫描';
    return '';
  }

  private handleEmptyAction(): void {
    if (this.searchQuery.trim()) {
      this.updateSearch('');
      return;
    }
    if (this.filter === 'windows') this.rescan();
  }

  private gridColumns(): string {
    if (this.settings.viewMode === ViewMode.COMPACT || this.breakpoint === 'sm') return '1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return this.settings.viewMode === ViewMode.LARGE ? '1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr';
    return this.settings.viewMode === ViewMode.LARGE ? '1fr 1fr' : '1fr 1fr 1fr';
  }

  private compactGridColumns(): string {
    if (this.breakpoint === 'sm') return '1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return '1fr 1fr 1fr';
    return '1fr 1fr';
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
    const running = this.runningAppIds.has(app.id);
    promptAction.showDialog({
      title: app.title,
      message: '请选择操作',
      buttons: [
        { text: running ? '关闭运行中的程序' : (app.available ? '启动或恢复' : '重新关联'), color: running ? '#D94848' : '#5569D8' },
        { text: '应用设置', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') }
      ]
    }).then((result) => {
      if (result.index === 0) {
        if (running) {
          const session = AppSessionService.getInstance().findByAppId(app.id);
          if (session) AppSessionService.getInstance().stop(session);
          this.refreshRunningState();
        } else if (app.available) this.launch(app); else this.openAppSettings(app);
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
  private NavItem(label: string, value: CatalogFilter, icon: Resource, mobile: boolean = false) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(19)
        .fontColor([this.filter === value ? $r('app.color.accent') : $r('app.color.text_secondary')])
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
    .id('library-nav-' + value)
    .onClick(() => this.selectFilter(value))
  }

  @Builder
  private SideBar(mobile: boolean = false) {
    Column() {
      Row() {
        if (!this.sidebarCollapsed || mobile) {
          Column({ space: 3 }) {
            Text('旧柚Pro').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(this.apps.length + ' 个程序 · 左滑收起').fontSize(11).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(mobile ? $r('sys.symbol.xmark') : (this.sidebarCollapsed ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left')))
            .fontSize(16).fontColor([$r('app.color.text_primary')])
        }
          .width(44).height(44)
          .backgroundColor($r('app.color.search_background'))
          .border({ width: 1, color: '#12000000' })
          .onClick((): void => {
            if (mobile) this.mobileSidebarVisible = false;
            else this.sidebarCollapsed = !this.sidebarCollapsed;
          })
      }.width('100%').height(64)

      if (!this.sidebarCollapsed || mobile) {
        AppSearchBar({
          value: this.searchQuery,
          onValueChange: (value: string): void => { this.updateSearch(value); }
        })
        Button('重新扫描').width('100%').height(48).fontSize(13).fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary')).borderRadius(16)
          .id('library-rescan')
          .onClick(() => this.rescan())
          .margin({ top: 10, bottom: 18 })
      }

      Column({ space: 4 }) {
        this.NavItem('收藏', 'favorite', $r('sys.symbol.star'), mobile)
        this.NavItem('内建应用', 'builtin', $r('sys.symbol.house_fill'), mobile)
        this.NavItem('Windows 程序', 'windows', $r('sys.symbol.folder'), mobile)
        this.NavItem('运行中', 'running', $r('sys.symbol.play_fill'), mobile)
      }.width('100%')

      Blank()
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.gearshape')).fontSize(19).fontColor([$r('app.color.text_secondary')])
        if (!this.sidebarCollapsed || mobile) {
          Text('系统设置').fontSize(14).fontColor($r('app.color.text_primary'))
        }
      }
      .width('100%').height(44).padding({ left: 15 }).borderRadius(12)
      .onClick(() => router.pushUrl({ url: 'pages/SystemSettings' }))
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.info_circle')).fontSize(19).fontColor([$r('app.color.text_secondary')])
        if (!this.sidebarCollapsed || mobile) {
          Text('帮助').fontSize(14).fontColor($r('app.color.text_primary'))
        }
      }.width('100%').height(44).padding({ left: 15 })
        .onClick((): void => { router.pushUrl({ url: 'pages/HelpCenter' }); })
    }
    .width(mobile ? 304 : (this.sidebarCollapsed ? 72 : 264))
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
          Text(this.filterTitle())
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.filterDescription()).fontSize(13).fontColor(this.engineState === EngineState.ERROR ? '#B42318' : $r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(17).fontColor([$r('app.color.text_primary')]) }
            .width(48).height(48).backgroundColor(this.settings.viewMode === ViewMode.GRID ? $r('app.color.selected_background') : $r('app.color.search_background')).onClick(() => this.setViewMode(ViewMode.GRID))
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(17).fontColor([$r('app.color.text_primary')]) }
            .width(48).height(48).backgroundColor(this.settings.viewMode === ViewMode.COMPACT ? $r('app.color.selected_background') : $r('app.color.search_background')).onClick(() => this.setViewMode(ViewMode.COMPACT))
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.rectangle_grid_1x2')).fontSize(17).fontColor([$r('app.color.text_primary')]) }
            .width(48).height(48).backgroundColor(this.settings.viewMode === ViewMode.LARGE ? $r('app.color.selected_background') : $r('app.color.search_background')).onClick(() => this.setViewMode(ViewMode.LARGE))
        }
      }.width('100%')
      if (this.breakpoint === 'sm' || this.breakpoint === 'md') {
        AppSearchBar({
          value: this.searchQuery,
          onValueChange: (value: string): void => { this.updateSearch(value); }
        })
      }
      if (this.breakpoint === 'md') {
        this.FilterBar()
      }
    }
    .width('100%')
    // The wide layout has no second search row.  Keep its header deliberately
    // compact so that the first application row starts in the visible area.
    .height((this.breakpoint === 'lg' || this.breakpoint === 'xl') ? 64 : 88)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private FilterBar() {
    Row({ space: 8 }) {
      Button('内建').height(48).layoutWeight(1).borderRadius(16)
        .backgroundColor(this.filter === 'builtin' ? $r('app.color.selected_background') : $r('app.color.search_background'))
        .fontColor($r('app.color.text_primary')).onClick(() => this.selectFilter('builtin'))
      Button('Windows').height(48).layoutWeight(1).borderRadius(16)
        .backgroundColor(this.filter === 'windows' ? $r('app.color.selected_background') : $r('app.color.search_background'))
        .fontColor($r('app.color.text_primary')).onClick(() => this.selectFilter('windows'))
      Button('运行中').height(48).layoutWeight(1).borderRadius(16)
        .backgroundColor(this.filter === 'running' ? $r('app.color.selected_background') : $r('app.color.search_background'))
        .fontColor($r('app.color.text_primary')).onClick(() => this.selectFilter('running'))
      Button('收藏').height(48).layoutWeight(1).borderRadius(16)
        .backgroundColor(this.filter === 'favorite' ? $r('app.color.selected_background') : $r('app.color.search_background'))
        .fontColor($r('app.color.text_primary')).onClick(() => this.selectFilter('favorite'))
    }.width('100%').id('library-filter-bar')
  }

  @Builder
  private AppGrid(items: AppDescriptor[]) {
    Grid() {
      ForEach(items, (app: AppDescriptor): void => {
        GridItem() {
          AppCard({
            app: app,
            viewMode: this.settings.viewMode,
            running: this.runningAppIds.has(app.id),
            useGlassEffect: this.settings.useGlassEffect,
            resolvedDisplayMode: AppSessionService.getInstance().resolveMode(app, this.settings),
            onLaunch: (target: AppDescriptor): void => { this.launch(target); },
            onSettings: (target: AppDescriptor): void => { this.openAppSettings(target); },
            onLongPress: (target: AppDescriptor): void => { this.showAppLongPressMenu(target); }
          })
        }
      }, (app: AppDescriptor): string => app.id)
    }
    .columnsTemplate(this.settings.viewMode === ViewMode.COMPACT ? this.compactGridColumns() : this.gridColumns())
    .columnsGap(16)
    .rowsGap(this.settings.viewMode === ViewMode.COMPACT ? 12 : 16)
    .width('100%')
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
      } else if (this.visibleApps.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph(this.emptyIcon()).fontSize(48).fontColor([$r('app.color.text_secondary')])
          Text(this.emptyTitle()).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.emptyDescription()).fontSize(13).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          if (this.emptyActionLabel()) {
            Button(this.emptyActionLabel()).height(48).borderRadius(24).id('library-empty-action')
              .onClick((): void => this.handleEmptyAction())
          }
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            this.AppGrid(this.visibleApps)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
          .padding({ top: 2, bottom: this.breakpoint === 'sm' ? 76 : 20 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .id('library-scroll-filtered')
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding({ left: this.breakpoint === 'sm' ? 16 : 28, right: this.breakpoint === 'sm' ? 16 : 28, top: 16 })
  }

  @Builder
  private BottomItem(label: string, icon: Resource, active: boolean, onClick: () => void) {
    Button() {
      Column({ space: 3 }) {
        SymbolGlyph(icon).fontSize(18).fontColor([active ? $r('app.color.accent') : $r('app.color.text_secondary')])
        Text(label).fontSize(10).fontColor(active ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      }
    }
    .layoutWeight(1).height(56).borderRadius(16)
    .backgroundColor(active ? $r('app.color.selected_background') : '#00000000')
    .onClick(onClick)
  }

  @Builder
  private BottomBar() {
    Row() {
      this.BottomItem('内建', $r('sys.symbol.house_fill'), this.filter === 'builtin', () => this.selectFilter('builtin'))
      this.BottomItem('收藏', $r('sys.symbol.star'), this.filter === 'favorite', () => this.selectFilter('favorite'))
      this.BottomItem('运行中', $r('sys.symbol.play_fill'), this.filter === 'running', () => this.selectFilter('running'))
      this.BottomItem('菜单', $r('sys.symbol.list_bullet'), this.mobileSidebarVisible, () => this.mobileSidebarVisible = true)
      this.BottomItem('设置', $r('sys.symbol.gearshape'), false, () => router.pushUrl({ url: 'pages/SystemSettings' }))
    }
    .height(72).width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
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
      if (this.breakpoint === 'sm') {
        this.BottomBar()
      }
      if (this.breakpoint === 'sm' && this.mobileSidebarVisible) {
        Row() {
          this.SideBar(true)
          Column().layoutWeight(1).height('100%').backgroundColor('#55000000')
            .onClick((): void => { this.mobileSidebarVisible = false; })
        }.width('100%').height('100%').alignItems(VerticalAlign.Top)
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
    .gesture(PanGesture({ fingers: 1 })
      .onActionEnd((event: GestureEvent): void => {
        if (this.breakpoint !== 'sm') return;
        if (event.offsetX > 64) this.mobileSidebarVisible = true;
        else if (event.offsetX < -64) this.mobileSidebarVisible = false;
      }))
  }
}
