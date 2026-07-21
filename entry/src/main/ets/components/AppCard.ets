import { AppDescriptor, AppSource, DisplayMode, ViewMode } from '../model/AppModels';

@Component
export struct AppCard {
  @Prop app: AppDescriptor;
  @Prop viewMode: ViewMode = ViewMode.GRID;
  @Prop running: boolean = false;
  @Prop useGlassEffect: boolean = true;
  @Prop resolvedDisplayMode: DisplayMode = DisplayMode.DESKTOP;
  @State private pressed: boolean = false;
  onLaunch: (app: AppDescriptor) => void = (_app: AppDescriptor): void => {};
  onSettings: (app: AppDescriptor) => void = (_app: AppDescriptor): void => {};
  onLongPress: (app: AppDescriptor) => void = (_app: AppDescriptor): void => {};

  private coverSource(): string {
    return this.app.coverPath.startsWith('file://') ? this.app.coverPath : 'file://' + this.app.coverPath;
  }

  private modeText(): string {
    return this.resolvedDisplayMode === DisplayMode.SINGLE_APP ? '单应用' : '桌面';
  }

  private builtinSymbol(): Resource {
    if (this.app.id === 'builtin-desktop') return $r('sys.symbol.rectangle_grid_1x2');
    if (this.app.id === 'builtin-explorer') return $r('sys.symbol.folder');
    if (this.app.id === 'builtin-winecfg' || this.app.id === 'builtin-control') return $r('sys.symbol.gearshape');
    if (this.app.id === 'builtin-taskmgr') return $r('sys.symbol.list_bullet');
    if (this.app.id === 'builtin-regedit') return $r('sys.symbol.square_grid_2x2');
    if (this.app.id === 'builtin-cmd') return $r('sys.symbol.chevron_right');
    if (this.app.id === 'builtin-graphics-smoke') return $r('sys.symbol.rectangle_grid_1x2');
    if (this.app.id === 'builtin-audio-smoke') return $r('sys.symbol.play_fill');
    return $r('sys.symbol.rectangle_grid_1x2');
  }

  private handleCardTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) this.pressed = true;
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = false;
  }

  @Builder
  private Badge(text: string, color: string) {
    Text(text)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFFFF')
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(color)
      .borderRadius(10)
  }

  @Builder
  private Cover(height: number) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.app.coverPath.length > 0) {
        Image(this.coverSource())
          .width('100%')
          .height(height)
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column({ space: 8 }) {
          if (this.app.source === AppSource.BUILTIN) {
            SymbolGlyph(this.builtinSymbol()).fontSize(58).fontColor(['#FFF8FAFF'])
          } else {
            Text('Windows 程序')
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#FFF8FAFF')
              .padding({ left: 13, right: 13, top: 8, bottom: 8 })
              .backgroundColor('#2CFFFFFF').borderRadius(16)
            Text('Download / games').fontSize(11).fontColor('#E3F0FAFF')
          }
        }
        .width('100%')
        .height(height)
        .justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 140, colors: [['#3952B8', 0], ['#257FC8', 0.52], ['#168E83', 1]] })
      }

      Row({ space: 5 }) {
        this.Badge(this.app.source === AppSource.BUILTIN ? '内建' : 'Download', '#CC343B4D')
        this.Badge(this.modeText(), '#CC4E68D8')
        if (this.running) {
          this.Badge('运行中', '#CC22A06B')
        }
        if (!this.app.available) {
          this.Badge('不可用', '#CCD64C4C')
        }
      }
      .padding(8)
    }
    .width(this.viewMode === ViewMode.COMPACT ? 120 : '100%')
    .height(height)
    .clip(true)
  }

  @Builder
  private TitleRow() {
    Row() {
      Column({ space: 3 }) {
        Text(this.app.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.app.launchTarget.executable)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.gearshape')).fontSize(16).fontColor([$r('app.color.text_secondary')])
      }
        .width(48)
        .height(48)
        .backgroundColor('#00000000')
        .id('wine-app-settings-' + this.app.id)
        .onClick(() => {
          this.onSettings(this.app);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 9, bottom: 10 })
  }

  build() {
    if (this.viewMode === ViewMode.COMPACT) {
      Row() {
        this.Cover(104)
        this.TitleRow()
      }
      .height(104)
      .width('100%')
      .backgroundColor(this.useGlassEffect ? $r('app.color.card_glass_background') : $r('app.color.card_background'))
      .backgroundBlurStyle(this.useGlassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .borderRadius(this.useGlassEffect ? 16 : 8)
      .clip(true)
      .shadow({ radius: 10, color: '#18000000', offsetX: 0, offsetY: 4 })
      .opacity(this.app.available ? 1 : 0.62)
      .scale({ x: this.pressed ? 0.985 : 1, y: this.pressed ? 0.985 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => this.handleCardTouch(event))
      .onClick(() => this.onLaunch(this.app))
      .gesture(LongPressGesture().onAction(() => this.onLongPress(this.app)))
      .id('wine-app-card-' + this.app.id)
    } else {
      Column() {
        this.Cover(this.viewMode === ViewMode.LARGE ? 220 : 168)
        this.TitleRow()
      }
      .width('100%')
      .backgroundColor(this.useGlassEffect ? $r('app.color.card_glass_background') : $r('app.color.card_background'))
      .backgroundBlurStyle(this.useGlassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .borderRadius(this.useGlassEffect ? 16 : 8)
      .clip(true)
      .shadow({ radius: 10, color: '#18000000', offsetX: 0, offsetY: 5 })
      .opacity(this.app.available ? 1 : 0.62)
      .scale({ x: this.pressed ? 0.985 : 1, y: this.pressed ? 0.985 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => this.handleCardTouch(event))
      .onClick(() => this.onLaunch(this.app))
      .gesture(LongPressGesture().onAction(() => this.onLongPress(this.app)))
      .id('wine-app-card-' + this.app.id)
    }
  }
}
