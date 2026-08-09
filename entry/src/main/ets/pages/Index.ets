import { common, ConfigurationConstant } from '@kit.AbilityKit';
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
  ThemeMode,
  ViewMode,
  normalizeLaunchPath,
  resolveRunningAppIds
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
import { WineEngineBlockingOverlay } from '../components/WineEngineBlockingOverlay';
import { DeviceCapabilityPolicy } from '../common/DeviceCapabilityPolicy';
import { LengthMetrics, window } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import {
  applyStatusOnlyImmersiveShell,
  getMiniTitleContentTopInset,
  getStatusOnlyWindowInsets,
  observeStatusOnlyWindowInsets
} from '../common/StatusOnlyImmersiveShell';
import {
  DividerMode,
  DividerShowType,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';

type CatalogFilter = 'builtin' | 'windows' | 'running' | 'favorite';

const PHONE_NAV_BUILTIN: number = 0;
const PHONE_NAV_WINDOWS: number = 1;
const PHONE_NAV_FAVORITE: number = 2;
const PHONE_NAV_RUNNING: number = 3;
const DEVICE_SDK_API_VERSION: number = (() => {
  try {
    return deviceInfo.sdkApiVersion as number;
  } catch (_) {
    return 0;
  }
})();
const SUPPORTS_HDS_FLOATING: boolean =
  canIUse('SystemCapability.UIDesign.HDSComponent.Core') && DEVICE_SDK_API_VERSION >= 23;
const HDS_MATERIAL_TYPE_IMMERSIVE: number = 101;
const HDS_MATERIAL_LEVEL_EXQUISITE: number = 0;
@Entry
@Component
struct Index {
  @StorageLink('overlayEditorRequest') @Watch('onOverlayEditorRequest') private overlayEditorRequest: string = '';
  @StorageLink('libraryTitleButtonInsetVp') private titleButtonInsetVp: number = 0;
  @State private apps: AppDescriptor[] = [];
  @State private visibleApps: AppDescriptor[] = [];
  @State private searchQuery: string = '';
  @State private filter: CatalogFilter = 'builtin';
  @State private breakpoint: BreakpointType = 'lg';
  @State private sidebarCollapsed: boolean = false;
  @State private settings: GlobalSettings = AppSettingsStore.getInstance().getGlobalSettings();
  @State private engineState: EngineState = EngineState.STOPPED;
  @State private engineMessage: string = 'Wine 引擎未启动';
  @State private scanning: boolean = false;
  @State private refreshing: boolean = false;
  @State private runningAppIds: Set<string> = new Set<string>();
  @State private phoneNavIndex: number = PHONE_NAV_BUILTIN;
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  @State private titleContentTopInsetVp: number = 40;
  @State private statusBarHeightVp: number = 0;
  @State private navBarInsetVp: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private phoneNavController: HdsTabsController = new HdsTabsController();
  private builtinScroller: Scroller = new Scroller();
  private windowsScroller: Scroller = new Scroller();
  private favoriteScroller: Scroller = new Scroller();
  private runningScroller: Scroller = new Scroller();
  private breakpointCallback: ((value: BreakpointType) => void) | null = null;
  private engineCallback: ((state: EngineState, message: string) => void) | null = null;
  private settingsCallback: ThemeSettingsListener | null = null;
  private refreshTimer: number = -1;
  private disposeWindowInsetObserver: (() => void) | null = null;
  private catalogInitialized: boolean = false;
  // 启动请求串行队列：后续点击加入队列，条件满足（会话建立/明确失败）后
  // 依次放行，不再用“正在处理上一次启动”拒绝用户，也不会被一次未完成的
  // 启动永久锁死（每次启动都以真实事件终止）。
  private launchChain: Promise<void> = Promise.resolve();

  private isPhone(): boolean {
    return DeviceCapabilityPolicy.isPhoneDevice() || this.breakpoint === 'xs' || this.breakpoint === 'sm';
  }

  private isNarrowPhone(): boolean {
    return this.breakpoint === 'xs';
  }

  private isPhoneLandscape(): boolean {
    return DeviceCapabilityPolicy.isPhoneDevice() && this.viewportWidth > this.viewportHeight && this.viewportHeight > 0;
  }

  private usesDarkAppearance(): boolean {
    if (this.settings.themeMode === ThemeMode.DARK) return true;
    if (this.settings.themeMode === ThemeMode.LIGHT) return false;
    try {
      return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (_) {
      return false;
    }
  }

  private navigationTitleBackground(scrolled: boolean): string {
    // Match VintagePomelo's HDS glass alpha. The page surface remains visible
    // below the title instead of becoming a white opaque strip.
    if (this.usesDarkAppearance()) return scrolled ? '#80121821' : '#26121821';
    return scrolled ? '#99FFFFFF' : '#18FFFFFF';
  }

  private navigationControlBackground(): string {
    return this.usesDarkAppearance() ? '#30FFFFFF' : '#28FFFFFF';
  }

  private navigationTitleColor(): string {
    return this.usesDarkAppearance() ? '#F4F7FB' : '#182431';
  }

  private contentPadding(): number {
    if (this.isPhoneLandscape()) return 12;
    if (this.breakpoint === 'xs') return 10;
    if (this.breakpoint === 'sm') return 16;
    if (this.breakpoint === 'md') return 20;
    return 28;
  }

  // The HDS title is an overlay. Put its height into the scroll content so
  // the initial gap moves away with the first swipe instead of staying fixed.
  private phoneTitleBarScrollInset(): number {
    return this.titleContentTopInsetVp;
  }

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
    this.stopWindowInsetObserver();
  }

  onPageShow(): void {
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
    if (this.catalogInitialized) {
      // Wine/File Explorer can add, rename or remove programs while this page
      // is hidden. Reconcile the catalog whenever it becomes visible again.
      void this.rescan();
    } else {
      this.refreshRunningState();
    }
    void this.applyPageWindowShell();
  }

  onPageHide(): void {
    this.stopWindowInsetObserver();
  }

  private async applyPageWindowShell(): Promise<void> {
    try {
      const pageWindow = await window.getLastWindow(this.context);
      await applyStatusOnlyImmersiveShell(pageWindow);
      this.startWindowInsetObserver(pageWindow);
    } catch (_) {
    }
  }

  private refreshPageInsets(pageWindow: window.Window): void {
    this.titleContentTopInsetVp = getMiniTitleContentTopInset(pageWindow);
    // Wide layouts do not render HDS MINI. Offset them by the physical status
    // inset only, independently from the narrow-layout title height.
    const insets = getStatusOnlyWindowInsets(pageWindow);
    this.statusBarHeightVp = insets.top;
    this.navBarInsetVp = insets.bottom;
  }

  private startWindowInsetObserver(pageWindow: window.Window): void {
    this.stopWindowInsetObserver();
    this.disposeWindowInsetObserver = observeStatusOnlyWindowInsets(pageWindow, () => {
      this.refreshPageInsets(pageWindow);
    });
  }

  private stopWindowInsetObserver(): void {
    if (this.disposeWindowInsetObserver) {
      this.disposeWindowInsetObserver();
      this.disposeWindowInsetObserver = null;
    }
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
          appId: request.appId || '',
          baseProfileId: request.baseProfileId || 'default',
          returnAbilityName: request.returnAbilityName || '',
          returnSessionId: request.returnSessionId || '',
          returnToplevelId: request.returnToplevelId || '0'
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
    await AppCatalogService.getInstance().initialize(this.context);
    AppSessionService.getInstance().initialize(this.context);
    LauncherAdapterRegistry.getInstance().initialize(this.context);
    WineEngineService.getInstance().initialize(this.context);
    await InputProfileService.getInstance().initialize(this.context);
    GamepadManager.getInstance().initialize(this.settings.gamepadDeadzone);
    await this.rescan();
    this.catalogInitialized = true;
  }

  private async rescan(): Promise<void> {
    if (this.scanning) return;
    this.scanning = true;
    try {
      this.apps = await AppCatalogService.getInstance().scan();
      this.refreshRunningState();
    } finally {
      this.scanning = false;
    }
  }

  private async refreshFromPull(): Promise<void> {
    // Refresh's two-way binding updates `refreshing` before onRefreshing is
    // invoked. Keep it separate from the actual scan mutex; sharing one flag
    // made rescan() observe itself as already running and return forever with
    // the refresh indicator still active.
    this.refreshing = true;
    try {
      await this.rescan();
    } finally {
      this.refreshing = false;
    }
  }

  private refreshRunningState(): void {
    const sessionService = AppSessionService.getInstance();
    const running = resolveRunningAppIds(this.apps, sessionService.getRunningAppIds(),
      sessionService.getRunningPaths());
    this.runningAppIds = running;
    this.visibleApps = this.filterApps(this.searchQuery, this.filter, running);
  }

  private pageBackgroundSource(): string {
    const value = this.settings.pageBackgroundUri;
    // DocumentViewPicker may return file://, datashare:// or another
    // provider URI. Preserve provider schemes; blindly prefixing file://
    // makes the selected image fail to load and leaves a solid white surface
    // below the translucent HDS title bar.
    if (value.indexOf('://') > 0) {
      return value;
    }
    return value.length > 0 ? 'file://' + value : '';
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

  private phoneNavIndexForFilter(value: CatalogFilter): number {
    if (value === 'windows') return PHONE_NAV_WINDOWS;
    if (value === 'favorite') return PHONE_NAV_FAVORITE;
    if (value === 'running') return PHONE_NAV_RUNNING;
    return PHONE_NAV_BUILTIN;
  }

  private phoneFilterForIndex(index: number): CatalogFilter | null {
    if (index === PHONE_NAV_BUILTIN) return 'builtin';
    if (index === PHONE_NAV_WINDOWS) return 'windows';
    if (index === PHONE_NAV_FAVORITE) return 'favorite';
    if (index === PHONE_NAV_RUNNING) return 'running';
    return null;
  }

  private selectFilter(value: CatalogFilter, syncPhoneNavigation: boolean = true): void {
    this.filter = value;
    this.visibleApps = this.filterApps(this.searchQuery, value);
    if (syncPhoneNavigation && this.isPhone()) {
      const index = this.phoneNavIndexForFilter(value);
      if (index !== this.phoneNavIndex) {
        this.phoneNavIndex = index;
        this.phoneNavController.changeIndex(index);
      }
    }
    if (value === 'windows' && this.catalogInitialized) void this.rescan();
  }

  private openSidebarPage(url: string): void {
    router.pushUrl({ url });
  }

  private filterTitle(): string {
    if (this.filter === 'builtin') return '内建应用';
    if (this.filter === 'windows') return 'Windows 程序';
    if (this.filter === 'running') return '运行中的应用';
    if (this.filter === 'favorite') return '收藏的应用';
    return '内建应用';
  }

  private filterDescription(): string {
    if (this.filter === 'builtin') return '系统工具与内建测试程序';
    if (this.filter === 'windows') {
      const catalog = AppCatalogService.getInstance();
      return catalog.isGamesDirectoryReady() ?
        '来自 Download/com.vintage.pomelopro/games' :
        '游戏目录尚未建立，点击创建并完成一次系统确认';
    }
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
    if (this.filter === 'windows') {
      const catalog = AppCatalogService.getInstance();
      if (!catalog.isGamesDirectoryReady()) {
        return '系统需要一次确认来建立 Download/com.vintage.pomelopro，之后应用会自动创建 games';
      }
      return '将程序放入 Download/com.vintage.pomelopro/games，应用会自动扫描';
    }
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
    if (this.filter === 'windows') {
      return AppCatalogService.getInstance().isGamesDirectoryReady() ? '重新扫描' : '创建游戏目录';
    }
    return '';
  }

  private handleEmptyAction(): void {
    if (this.searchQuery.trim()) {
      this.updateSearch('');
      return;
    }
    if (this.filter === 'windows') {
      if (AppCatalogService.getInstance().isGamesDirectoryReady()) {
        void this.rescan();
      } else {
        void this.prepareGamesDirectory();
      }
    }
  }

  private async prepareGamesDirectory(): Promise<void> {
    if (this.scanning) return;
    this.scanning = true;
    try {
      const status = await AppCatalogService.getInstance().provisionGamesDirectory();
      this.apps = await AppCatalogService.getInstance().scan();
      this.refreshRunningState();
      promptAction.showToast({
        message: status.ready ? '游戏目录已创建' : '未能创建游戏目录：' + status.error
      });
    } finally {
      this.scanning = false;
    }
  }

  private gridColumns(): string {
    if (this.settings.viewMode === ViewMode.COMPACT) return '1fr';
    // VintagePomelo keeps cover cards in two columns on phones. A single
    // flexible column makes one icon fill almost the entire compact window.
    if (this.isPhoneLandscape()) return '1fr 1fr';
    if (this.isPhone()) return '1fr 1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return '1fr 1fr 1fr 1fr 1fr';
    return '1fr 1fr 1fr';
  }

  private catalogScroller(filter: CatalogFilter): Scroller {
    if (filter === 'windows') return this.windowsScroller;
    if (filter === 'favorite') return this.favoriteScroller;
    if (filter === 'running') return this.runningScroller;
    return this.builtinScroller;
  }

  private phoneNavigationScrollers(): Scroller[] {
    return [this.builtinScroller, this.windowsScroller, this.favoriteScroller, this.runningScroller];
  }

  private compactGridColumns(): string {
    if (this.isPhoneLandscape()) return '1fr 1fr';
    if (this.isPhone()) return '1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return '1fr 1fr 1fr';
    return '1fr 1fr';
  }

  private largeGridColumns(): string {
    if (this.isPhoneLandscape()) return '1fr 1fr';
    if (this.isPhone()) return '1fr';
    if (this.breakpoint === 'md') return '1fr 1fr';
    if (this.breakpoint === 'xl') return '1fr 1fr 1fr';
    return '1fr 1fr';
  }

  private phoneGridItemMinHeight(): number {
    // Grid can under-measure an auto-height card while a narrow two-column
    // layout is settling. Reserve the cover, fixed title row and shadow inset
    // explicitly so the following row can never paint over this card.
    if (this.settings.viewMode === ViewMode.COMPACT) return 120;
    const coverHeight = this.settings.viewMode === ViewMode.LARGE ? 196 : 120;
    return coverHeight + 71 + 16;
  }

  private launch(app: AppDescriptor): Promise<void> {
    if (!app.available) {
      this.openAppSettings(app, true);
      return Promise.resolve();
    }
    const conflict = AppSessionService.getInstance().getLaunchConflict(app, this.settings);
    if (conflict !== LaunchConflictKind.NONE) {
      AlertDialog.show({
        title: '切换显示模式',
        message: '当前 Windows 会话使用另一种显示模式。继续将关闭当前会话并重建 Wayland 显示，Wine prefix 不会重置。',
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: {
          value: '关闭并切换',
          fontColor: '#D94848',
          action: (): void => { this.switchAndLaunch(app); }
        }
      });
      return Promise.resolve();
    }
    return this.enqueueLaunch(app, false);
  }

  private switchAndLaunch(app: AppDescriptor): Promise<void> {
    return this.enqueueLaunch(app, true);
  }

  private enqueueLaunch(app: AppDescriptor, switchMode: boolean): Promise<void> {
    const run = this.launchChain.then((): Promise<void> => this.doLaunch(app, switchMode));
    // 单次启动失败不能污染队列：后续点击仍按序执行。
    this.launchChain = run.catch((): void => {});
    return run;
  }

  private async doLaunch(app: AppDescriptor, switchMode: boolean): Promise<void> {
    const root = AppCatalogService.getInstance().getWineHomeDirectory();
    if (!root && (app.launchTarget.kind === LaunchKind.WINE_EXE ||
      app.launchTarget.kind === LaunchKind.WINE_SYSTEM ||
      app.launchTarget.kind === LaunchKind.WINE_DESKTOP)) {
      promptAction.showToast({
        message: '无法创建 Download/com.vintage.pomelopro/games，请点击 Windows 程序中的重新扫描重试'
      });
      this.refreshRunningState();
      return;
    }
    let session: RuntimeSession | null = null;
    try {
      if (switchMode) {
        session = await AppSessionService.getInstance().switchModeAndLaunch(app, this.settings, root);
      } else {
        session = await LauncherAdapterRegistry.getInstance().launch(app, this.settings, root);
      }
      if (!session && (app.launchTarget.kind === LaunchKind.WINE_EXE ||
        app.launchTarget.kind === LaunchKind.WINE_SYSTEM ||
        app.launchTarget.kind === LaunchKind.WINE_DESKTOP)) {
        const engineMessage = WineEngineService.getInstance().getMessage();
        promptAction.showToast({
          message: engineMessage === 'Wine 引擎已就绪' ? '程序启动失败，请稍后重试' : engineMessage
        });
      }
    } catch (_) {
      promptAction.showToast({ message: '程序启动异常，请稍后重试' });
    } finally {
      this.refreshRunningState();
    }
  }

  private isEngineBusy(): boolean {
    return this.engineState === EngineState.PREPARING || this.engineState === EngineState.SWITCHING;
  }

  private openAppSettings(app: AppDescriptor, selectExecutable: boolean = false): void {
    router.pushUrl({
      url: 'pages/AppSettings',
      params: { appId: app.id, selectExecutable: selectExecutable ? 'true' : 'false' }
    });
  }

  private showAppLongPressMenu(app: AppDescriptor): void {
    const running = this.runningAppIds.has(app.id);
    if (app.source === AppSource.DOWNLOAD && !app.available) {
      promptAction.showDialog({
        title: app.title,
        message: '主程序已不存在，可重新关联或只删除卡片记录（不会删除任何文件）',
        buttons: [
          { text: '重新关联', color: '#5569D8' },
          { text: '应用设置', color: $r('sys.color.ohos_id_color_text_primary') },
          { text: '删除卡片', color: '#D94848' }
        ]
      }).then((result) => {
        if (result.index === 0) this.openAppSettings(app, true);
        else if (result.index === 1) this.openAppSettings(app);
        else if (result.index === 2) this.confirmDeleteUnavailableApp(app);
      }).catch((_error: Error) => {});
      return;
    }
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
          AppSessionService.getInstance().stopApp(app);
          this.refreshRunningState();
        } else if (app.available) this.launch(app); else this.openAppSettings(app, true);
      } else if (result.index === 1) {
        this.openAppSettings(app);
      }
    }).catch((_error: Error) => {});
  }

  private confirmDeleteUnavailableApp(app: AppDescriptor): void {
    AlertDialog.show({
      title: '删除卡片记录',
      message: `将从旧柚 Pro 中移除“${app.title}”卡片，不会删除 games 目录中的任何文件。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#D94848',
        action: (): void => { this.deleteUnavailableApp(app); }
      }
    });
  }

  private async deleteUnavailableApp(app: AppDescriptor): Promise<void> {
    if (app.source !== AppSource.DOWNLOAD || app.available) return;
    await AppSettingsStore.getInstance().removeCachedApp(app.id);
    this.apps = this.apps.filter((item: AppDescriptor): boolean => item.id !== app.id);
    this.refreshRunningState();
    promptAction.showToast({ message: '卡片记录已删除' });
  }

  private async setViewMode(mode: ViewMode): Promise<void> {
    await AppSettingsStore.getInstance().setViewMode(mode);
    this.settings = AppSettingsStore.getInstance().getGlobalSettings();
  }

  private showViewModeMenu(): void {
    promptAction.showActionMenu({
      title: '卡片视图',
      buttons: [
        { text: (this.settings.viewMode === ViewMode.GRID ? '✓ ' : '') + '网格封面', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: (this.settings.viewMode === ViewMode.COMPACT ? '✓ ' : '') + '紧凑列表', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: (this.settings.viewMode === ViewMode.LARGE ? '✓ ' : '') + '大封面', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result) => {
      if (result.index === 0) this.setViewMode(ViewMode.GRID);
      else if (result.index === 1) this.setViewMode(ViewMode.COMPACT);
      else if (result.index === 2) this.setViewMode(ViewMode.LARGE);
    }).catch(() => {});
  }

  private phoneViewModeIcon(): Resource {
    if (this.settings.viewMode === ViewMode.COMPACT) return $r('sys.symbol.list_bullet');
    if (this.settings.viewMode === ViewMode.LARGE) return $r('sys.symbol.rectangle_grid_1x2');
    return $r('sys.symbol.square_grid_2x2');
  }

  private phoneNavigationMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [
        {
          content: {
            label: '系统设置',
            icon: $r('sys.symbol.gearshape'),
            action: (): void => { this.openSidebarPage('pages/SystemSettings'); }
          }
        },
        {
          content: {
            label: '切换卡片视图',
            icon: this.phoneViewModeIcon(),
            action: (): void => { this.showViewModeMenu(); }
          }
        },
        {
          content: {
            label: '帮助中心',
            icon: $r('sys.symbol.info_circle'),
            action: (): void => { this.openSidebarPage('pages/HelpCenter'); }
          }
        }
      ],
      maxCount: 3
    };
  }

  private phoneBottomInset(): number {
    if (this.isPhoneLandscape()) return 72;
    return this.isNarrowPhone() ? 80 : 84;
  }

  @Builder
  private NavItem(label: string, value: CatalogFilter, icon: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(19)
        .fontColor([this.filter === value ? $r('app.color.accent') : $r('app.color.text_secondary')])
      if (!this.sidebarCollapsed) {
        Text(label).fontSize(14).fontColor($r('app.color.text_primary'))
          .fontWeight(this.filter === value ? FontWeight.Medium : FontWeight.Normal)
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 15, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.filter === value ? $r('app.color.selected_background') : '#00000000')
    .id('library-nav-' + value)
    .onClick(() => this.selectFilter(value))
  }

  @Builder
  private SideBar() {
    Column() {
      Row() {
        if (!this.sidebarCollapsed) {
          Column({ space: this.isNarrowPhone() ? 2 : 3 }) {
            Text('旧柚Pro').fontSize(this.isNarrowPhone() ? 16 : 18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(this.apps.length + ' 个程序').fontSize(this.isNarrowPhone() ? 9 : 11).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.sidebarCollapsed ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
            .fontSize(16).fontColor([$r('app.color.text_primary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.search_background'))
          .border({ width: 1, color: '#12000000' })
          .id('library-toggle-sidebar')
          .onClick((): void => {
            this.sidebarCollapsed = !this.sidebarCollapsed;
          })
      }.width('100%').height(64)

      if (!this.sidebarCollapsed) {
        AppSearchBar({
          value: this.searchQuery,
          heightVp: 48,
          onValueChange: (value: string): void => { this.updateSearch(value); }
        })
        Button('重新扫描').width('100%').height(48).fontSize(13).fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.search_background')).fontColor($r('app.color.text_primary')).borderRadius(16)
          .id('library-rescan')
          .onClick(() => this.rescan())
          .margin({ top: 10, bottom: 18 })
      }

      Scroll() {
        Column() {
          Column({ space: 4 }) {
            this.NavItem('收藏', 'favorite', $r('sys.symbol.star'))
            this.NavItem('内建应用', 'builtin', $r('sys.symbol.house_fill'))
            this.NavItem('Windows 程序', 'windows', $r('sys.symbol.folder'))
            this.NavItem('运行中', 'running', $r('sys.symbol.play_fill'))
          }.width('100%')

          Blank()
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.gearshape')).fontSize(19).fontColor([$r('app.color.text_secondary')])
            if (!this.sidebarCollapsed) {
              Text('系统设置').fontSize(14).fontColor($r('app.color.text_primary'))
            }
          }
          .width('100%').height(48).padding({ left: 15 }).borderRadius(12)
          .id('library-open-system-settings')
          .onClick((): void => this.openSidebarPage('pages/SystemSettings'))
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.info_circle')).fontSize(19).fontColor([$r('app.color.text_secondary')])
            if (!this.sidebarCollapsed) {
              Text('帮助').fontSize(14).fontColor($r('app.color.text_primary'))
            }
          }.width('100%').height(48).padding({ left: 15 })
            .id('library-open-help')
            .onClick((): void => { this.openSidebarPage('pages/HelpCenter'); })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width(this.sidebarCollapsed ? 72 : 264)
    .height('100%')
    .padding({
      left: this.isNarrowPhone() ? 10 : 16,
      right: this.isNarrowPhone() ? 10 : 16,
      top: this.isNarrowPhone() ? 10 : 16,
      bottom: Math.max(this.isNarrowPhone() ? 10 : 16, this.navBarInsetVp)
    })
    .backgroundColor($r('app.color.sidebar_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
  }

  @Builder
  private Header() {
    Column({ space: 12 }) {
      if (!this.isPhone()) {
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
          .id('library-view-modes')
          // Keep the complete system-reported title-button area. PC window
          // managers add spacing between the maximize/minimize/close nodes
          // that is not always included in TitleButtonRect.width.
          .margin({ right: this.titleButtonInsetVp > 0 ? this.titleButtonInsetVp + 24 : 0 })
        }.width('100%')
      }
      if (this.breakpoint === 'md') {
        AppSearchBar({
          value: this.searchQuery,
          heightVp: 48,
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
    .height(this.isPhone() ? (this.isPhoneLandscape() ? 52 : 60) :
      ((this.breakpoint === 'lg' || this.breakpoint === 'xl') ? 64 :
        (this.breakpoint === 'md' ? 172 : 112)))
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
          this.CatalogCard(app)
        }
        // Shadows extend beyond the card's measured bounds. Without this
        // inset Grid clips the last row's rounded bottom edge and shadow.
        .padding({ left: 4, right: 4, top: 4, bottom: 12 })
        .constraintSize({ minHeight: this.isPhone() ? this.phoneGridItemMinHeight() : 0 })
      }, (app: AppDescriptor): string => app.id)
    }
    .columnsTemplate(this.settings.viewMode === ViewMode.COMPACT ? this.compactGridColumns() :
      (this.settings.viewMode === ViewMode.LARGE ? this.largeGridColumns() : this.gridColumns()))
    .columnsGap(8)
    .rowsGap(this.isPhone() ? 8 : 4)
    .width('100%')
  }

  @Builder
  private CatalogCard(app: AppDescriptor) {
    AppCard({
      app: app,
      viewMode: this.settings.viewMode,
      running: this.runningAppIds.has(app.id),
      useGlassEffect: this.settings.useGlassEffect,
      narrowPhone: this.isPhone(),
      onLaunch: (target: AppDescriptor): void => { this.launch(target); },
      onSettings: (target: AppDescriptor): void => { this.openAppSettings(target); },
      onLongPress: (target: AppDescriptor): void => { this.showAppLongPressMenu(target); }
    })
  }

  /**
   * Give every catalog filter its own ArkUI branch and scroll identity.
   * Reusing one non-empty Grid made ForEach keep the previous category until
   * an empty branch (usually Favorites) forced the node tree to be recreated.
   */
  @Builder
  private CatalogScroll(items: AppDescriptor[], filter: CatalogFilter) {
    Scroll(this.catalogScroller(filter)) {
      Column() {
        this.AppGrid(items)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Start)
      // Keep the last row above the phone navigation gesture area and the
      // overlaid bottom bar. The extra inset is harmless on tablet layouts.
      .padding({
        top: this.isPhone() ? this.phoneTitleBarScrollInset() : 2,
        bottom: this.isPhone() ? this.phoneBottomInset() : Math.max(36, this.navBarInsetVp)
      })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .id('library-scroll-' + filter)
  }

  @Builder
  private EmptyLibraryState() {
    Column({ space: 12 }) {
      SymbolGlyph(this.emptyIcon()).fontSize(this.isNarrowPhone() ? 34 : 48)
        .fontColor([$r('app.color.text_secondary')])
      Text(this.emptyTitle()).fontSize(this.isNarrowPhone() ? 16 : 20)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(this.emptyDescription()).fontSize(this.isNarrowPhone() ? 11 : 13)
        .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: this.isNarrowPhone() ? 240 : 420 })
      if (this.emptyActionLabel()) {
        Button(this.emptyActionLabel()).height(48).borderRadius(24).id('library-empty-action')
          .onClick((): void => this.handleEmptyAction())
      }
    }
    .layoutWeight(1)
    .justifyContent(this.isPhone() ? FlexAlign.Start : FlexAlign.Center)
    .padding({ top: this.isNarrowPhone() ? 18 : (this.breakpoint === 'sm' ? 30 : 0),
      bottom: Math.max(this.isNarrowPhone() ? 72 : (this.breakpoint === 'sm' ? 96 : 0), this.navBarInsetVp) })
  }

  @Builder
  private CatalogEmptyScroll(filter: CatalogFilter) {
    Scroll(this.catalogScroller(filter)) {
      Column() {
        this.EmptyLibraryState()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        top: this.isPhone() ? this.phoneTitleBarScrollInset() : 2,
        bottom: this.isPhone() ? this.phoneBottomInset() : Math.max(36, this.navBarInsetVp)
      })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .id('library-empty-scroll-' + filter)
  }

  @Builder
  private WindowsRefreshContent() {
    Refresh({ refreshing: $$this.refreshing }) {
      if (this.scanning) {
        Row({ space: 10 }) {
          LoadingProgress().width(20).height(20)
          Text('正在扫描应用目录…').fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.visibleApps.length === 0) {
        this.CatalogEmptyScroll('windows')
      } else {
        this.CatalogScroll(this.visibleApps, 'windows')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing((): void => { void this.refreshFromPull(); })
    .id('windows-library-refresh')
  }

  @Builder
  private Library() {
    Column() {
      if (!this.isPhone()) {
        this.Header()
      }
      if (this.filter === 'windows') {
        this.WindowsRefreshContent()
      } else if (this.scanning) {
        Row({ space: 10 }) {
          LoadingProgress().width(20).height(20)
          Text('正在扫描应用目录…').fontColor($r('app.color.text_secondary'))
        }.margin({ top: this.isNarrowPhone() ? 12 : 22 })
      } else if (this.visibleApps.length === 0) {
        this.CatalogEmptyScroll(this.filter)
      } else if (this.filter === 'builtin') {
        this.CatalogScroll(this.visibleApps, 'builtin')
      } else if (this.filter === 'running') {
        this.CatalogScroll(this.visibleApps, 'running')
      } else {
        this.CatalogScroll(this.visibleApps, 'favorite')
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding({
      left: this.contentPadding(),
      right: this.contentPadding(),
      top: this.isPhone() ? 0 : 16
    })
  }

  @Builder
  private PhoneNavigationTab(label: string, icon: Resource, index: number) {
    Column({ space: 1 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.phoneNavIndex === index ? $r('app.color.accent') : $r('app.color.text_secondary')])
      Text(label)
        .fontSize(10)
        .fontWeight(this.phoneNavIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.phoneNavIndex === index ? $r('app.color.accent') : $r('app.color.text_secondary'))
        .maxLines(1)
    }
    .width('100%')
    // Keep the custom content within the compact HDS tab slot. The previous
    // 64vp slot became a 224px bar on the tablet density and made the bottom
    // navigation look vertically misaligned.
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .id('library-nav-tab-' + index)
  }

  @Builder
  private PhoneNavigationContents() {
    TabContent() { Column() }
      .tabBar(this.PhoneNavigationTab('内建', $r('sys.symbol.house_fill'), PHONE_NAV_BUILTIN))
    TabContent() { Column() }
      .tabBar(this.PhoneNavigationTab('Windows', $r('sys.symbol.folder'), PHONE_NAV_WINDOWS))
    TabContent() { Column() }
      .tabBar(this.PhoneNavigationTab('收藏', $r('sys.symbol.star'), PHONE_NAV_FAVORITE))
    TabContent() { Column() }
      .tabBar(this.PhoneNavigationTab('运行中', $r('sys.symbol.play_fill'), PHONE_NAV_RUNNING))
  }

  @Builder
  private PhoneNavigation() {
    HdsTabs({
      barPosition: BarPosition.End,
      index: this.phoneNavIndex,
      controller: this.phoneNavController
    }) {
      this.PhoneNavigationContents()
    }
    .vertical(false)
    .barHeight(48)
    .scrollable(false)
    .barOverlap(true)
    .divider({ mode: DividerMode.FOLLOW_SCROLL })
    .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .barFloatingStyle({
      barBottomMargin: Math.max(this.isPhoneLandscape() ? 10 : 14, this.navBarInsetVp),
      barSideMargin: this.isPhoneLandscape() ? 24 : 20,
      gradientMask: { maskColor: $r('app.color.page_background') },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      adaptToHandedness: false,
      thermoCtrl: true
    })
    .onChange((index: number): void => {
      const target = this.phoneFilterForIndex(index);
      if (target === null) return;
      this.phoneNavIndex = index;
      this.selectFilter(target, false);
    })
    .width('100%')
    .height(this.isPhoneLandscape() ? 72 : 80)
    .id('library-bottom-bar')
  }

  @Builder
  private PhoneLibraryNavigation() {
    HdsNavigation() {
      this.Library()
    }
    .mode(NavigationMode.Stack)
    .titleBar({
      padding: { start: LengthMetrics.vp(14), end: LengthMetrics.vp(14) },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: SUPPORTS_HDS_FLOATING ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR : ScrollEffectType.GRADUAL_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(SUPPORTS_HDS_FLOATING ? 96 : 68)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: this.navigationTitleBackground(false)
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
            },
            backIconStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.navigationTitleBackground(true)
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
            },
            backIconStyle: {
              backgroundColor: this.navigationControlBackground(),
              iconColor: $r('app.color.text_primary')
            }
          }
        },
        systemMaterialEffect: SUPPORTS_HDS_FLOATING ? {
          materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
          materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
        } : undefined
      },
      content: {
        title: {
          mainTitle: '旧柚Pro',
          subTitle: this.filterTitle()
        },
        menu: this.phoneNavigationMenu(),
        divider: { showType: DividerShowType.OFF }
      },
      avoidLayoutSafeArea: true,
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .hideToolBar(true)
    .systemBarStyle(
      { statusBarContentColor: this.navigationTitleColor() },
      { statusBarContentColor: this.navigationTitleColor() }
    )
    .width('100%')
    .height('100%')
    .backgroundColor('#00FFFFFF')
    .bindToScrollable(this.phoneNavigationScrollers())
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .id('library-phone-navigation')
  }

  @Builder
  private PageSurface() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.settings.usePageBackground && this.settings.pageBackgroundUri.length > 0) {
        Image(this.pageBackgroundSource())
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(0.72)
          .hitTestBehavior(HitTestMode.None)
          .id('library-page-background')
      }
      Row() {
        if (!this.isPhone() && (this.breakpoint === 'lg' || this.breakpoint === 'xl')) {
          this.SideBar()
        }
        if (this.isPhone()) {
          this.PhoneLibraryNavigation()
        } else {
          this.Library()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.isPhone() ? 0 : this.statusBarHeightVp + 16 })
      if (this.isPhone()) {
        this.PhoneNavigation()
      }
      WineEngineBlockingOverlay()
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.viewportWidth = area.width as number;
      this.viewportHeight = area.height as number;
      BreakpointSystem.updateFromWidth(this.viewportWidth);
    })
  }

  build() {
    Stack() {
      this.PageSurface()
    }
    .width('100%').height('100%')
  }
}
