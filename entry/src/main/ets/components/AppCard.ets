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
          Text(this.app.source === AppSource.BUILTIN ? 'W' : 'EXE')
            .fontSize(this.app.source === AppSource.BUILTIN ? 46 : 24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFFFF')
          Text(this.app.source === AppSource.BUILTIN ? 'Vintage Pomelo Wine' : 'Windows Program')
            .fontSize(11)
            .fontColor('#DFFFFFFF')
        }
        .width('100%')
        .height(height)
        .justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 140, colors: [['#6157E8', 0], ['#2C8EDB', 0.52], ['#20B99A', 1]] })
      }

      Row({ space: 5 }) {
        this.Badge(this.app.source === AppSource.BUILTIN ? '内建' : 'Wine', '#CC343B4D')
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

      Button('···')
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor('#00000000')
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
        this.Cover(88)
        this.TitleRow()
      }
      .height(88)
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
    } else {
      Column() {
        this.Cover(this.viewMode === ViewMode.LARGE ? 236 : 176)
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
    }
  }
}
