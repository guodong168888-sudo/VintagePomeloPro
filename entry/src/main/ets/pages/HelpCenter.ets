import router from '@ohos.router';
import { BreakpointSystem, BreakpointType } from '../common/BreakpointSystem';
import { DeviceCapabilityPolicy } from '../common/DeviceCapabilityPolicy';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

type HelpCategory = 'start' | 'library' | 'controls' | 'runtime';
const HDS_MATERIAL_TYPE_IMMERSIVE: number = 101;
const HDS_MATERIAL_LEVEL_EXQUISITE: number = 0;

interface HelpTopic {
  id: string;
  category: HelpCategory;
  icon: Resource;
  title: string;
  description: string;
  details: string;
}

interface HelpSectionData {
  id: HelpCategory;
  title: string;
  icon: Resource;
}

/**
 * Wine application's equivalent of VintagePomelo's embedded FAQ framework.
 * It deliberately uses multiple actionable topic cards instead of a one-shot
 * alert dialog so new runtime and input help can grow without changing routes.
 */
@Entry
@Component
struct HelpCenter {
  @StorageLink('libraryTitleButtonInsetVp') private titleButtonInsetVp: number = 0;
  @State private expandedTopicId: string = '';
  @State private breakpoint: BreakpointType = 'lg';
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  private breakpointCallback: ((value: BreakpointType) => void) | null = null;
  private helpScroller: Scroller = new Scroller();
  private readonly topics: HelpTopic[] = [
    {
      id: 'getting-started', category: 'start', icon: $r('sys.symbol.info_circle'),
      title: '开始使用 Wine 应用库', description: '了解内建工具、Windows 程序和运行状态。',
      details: '首页不会自动启动 Wine。点击需要 Wine 的卡片后才会准备运行环境；再次点击运行中的卡片可恢复现有会话。'
    },
    {
      id: 'download-library', category: 'library', icon: $r('sys.symbol.folder'),
      title: '添加 Download 中的 Windows 程序', description: '程序会从固定 games 目录自动扫描，无需目录授权。',
      details: '将 EXE 文件或游戏文件夹放入 Download/com.vintage.pomelopro/games。每个一级目录或根目录 EXE 会成为一张应用卡片；可在应用设置中选择主 EXE 与封面。'
    },
    {
      id: 'built-in-tools', category: 'library', icon: $r('sys.symbol.rectangle_grid_1x2'),
      title: '内建工具与 Windows 程序分开显示', description: 'Wine 桌面、配置、任务管理器等不会与 Download 应用混在一起。',
      details: '手机使用底部分类栏切换“内建”和“Windows”，平板与 PC 使用左侧导航。文件被移动后会保留不可用卡片，方便重新关联或删除记录。'
    },
    {
      id: 'virtual-controls', category: 'controls', icon: $r('sys.symbol.gamecontroller'),
      title: '虚拟手柄、鼠标与布局编辑', description: '顶部图标可收起或展开控制层，齿轮进入布局编辑。',
      details: '布局编辑器沿用 VintagePomelo 的方向、动作、辅助三组模型。方向组只能选择十字键或摇杆之一；可拖动分组、调整分组大小、透明度和按键显隐。'
    },
    {
      id: 'touch-modes', category: 'controls', icon: $r('sys.symbol.hand_tap'),
      title: '直触与全屏虚拟鼠标怎么选', description: '直触适合点按控件，虚拟鼠标适合精确拖动和桌面操作。',
      details: '直触模式在手指位置发送鼠标点击，双指滑动用于滚轮；打开右上角虚拟鼠标后，整块屏幕会像触摸板一样相对移动光标，轻点左键、双指轻点右键。'
    },
    {
      id: 'desktop-single', category: 'runtime', icon: $r('sys.symbol.arrow_clockwise'),
      title: '桌面模式与单应用模式', description: '同一 Wine 会话可按应用选择显示方式。',
      details: '桌面模式保留完整 Explorer 桌面和多窗口；单应用模式一次只运行一个 Windows 程序。切换模式时会重建显示会话，但不会重置 Wine prefix。'
    },
    {
      id: 'troubleshooting', category: 'runtime', icon: $r('sys.symbol.gearshape'),
      title: '程序无法启动时怎么办', description: '先检查卡片状态、主 EXE 与 Wine 引擎提示。',
      details: '在应用卡片的设置中重新关联 EXE，确认文件仍在 games 目录。若 Wine 会话卡住，可到系统设置的 Wine 引擎页停止全部 Windows 会话后重试。'
    },
    {
      id: 'first-start', category: 'runtime', icon: $r('sys.symbol.clock'),
      title: '第一次启动为什么比较慢', description: '首次使用会解压 Wine、创建 prefix 并准备图形与音频环境。',
      details: '初始化期间应用会锁定 Wine 画面并显示进度提示。请保持应用在前台，不要重复点击卡片；首次完成后，后续启动会直接复用已准备好的运行环境。'
    },
    {
      id: 'phone-layout', category: 'start', icon: $r('sys.symbol.rectangle_grid_1x2'),
      title: '手机横竖屏与小窗怎么操作', description: '手机使用顶部菜单和底部分类，大屏自动切换左侧导航。',
      details: '竖屏和横屏会根据可用宽度重新排布卡片。顶部菜单可打开系统设置、帮助和卡片视图；底部导航用于切换内建应用、Windows 程序、收藏和运行中。'
    }
  ];
  private readonly sections: HelpSectionData[] = [
    { id: 'start', title: '快速开始', icon: $r('sys.symbol.info_circle') },
    { id: 'library', title: '应用库', icon: $r('sys.symbol.folder') },
    { id: 'controls', title: '输入与控制', icon: $r('sys.symbol.gamecontroller') },
    { id: 'runtime', title: '运行与排障', icon: $r('sys.symbol.gearshape') }
  ];

  aboutToAppear(): void {
    BreakpointSystem.initialize();
    this.breakpointCallback = (value: BreakpointType): void => { this.breakpoint = value; };
    BreakpointSystem.subscribe(this.breakpointCallback);
  }

  aboutToDisappear(): void {
    if (this.breakpointCallback) BreakpointSystem.unsubscribe(this.breakpointCallback);
  }

  private isNarrowPhone(): boolean {
    return this.breakpoint === 'xs';
  }

  private isPhoneLandscape(): boolean {
    return DeviceCapabilityPolicy.isPhoneDevice() && this.viewportWidth > this.viewportHeight && this.viewportHeight > 0;
  }

  private helpContentMaxWidth(): number {
    if (this.breakpoint === 'xl') return 1120;
    if (this.breakpoint === 'lg') return 980;
    if (this.breakpoint === 'md') return 840;
    return 100000;
  }

  private helpSidePadding(): number {
    if (this.isNarrowPhone()) return 12;
    if (this.breakpoint === 'sm') return 16;
    if (this.breakpoint === 'md') return 20;
    return 28;
  }

  private helpTopInset(): number {
    if (this.breakpoint === 'xs' || this.breakpoint === 'sm') return 8;
    if (this.breakpoint === 'md') return 10;
    return 12;
  }

  private titleButtonMargin(): number {
    return this.titleButtonInsetVp > 0 ? this.titleButtonInsetVp + 44 : 0;
  }

  private sectionTopics(category: HelpCategory): HelpTopic[] {
    return this.topics.filter((topic: HelpTopic): boolean => topic.category === category);
  }

  @Builder
  private TopicCard(topic: HelpTopic) {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph(topic.icon).fontSize(19).fontColor([$r('app.color.accent')])
        Column({ space: 4 }) {
          Text(topic.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).width('100%')
          Text(topic.description).fontSize(11).fontColor($r('app.color.text_secondary'))
            .lineHeight(17).maxLines(2).width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph(this.expandedTopicId === topic.id ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(18).fontColor([$r('app.color.text_secondary')])
      }
      .width('100%').padding(16)
      if (this.expandedTopicId === topic.id) {
        Text(topic.details).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
          .padding({ left: 47, right: 16, bottom: 16 })
      }
    }
    .width('100%').backgroundColor($r('app.color.card_glass_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK).borderRadius(16)
    .border({ width: 1, color: '#28FFFFFF' })
    .onClick((): void => { this.expandedTopicId = this.expandedTopicId === topic.id ? '' : topic.id; })
  }

  @Builder
  private HelpSection(section: HelpSectionData) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph(section.icon).fontSize(21).fontColor([$r('app.color.accent')])
        Text(section.title).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
      }.width('100%')
      Column({ space: 10 }) {
        ForEach(this.sectionTopics(section.id), (topic: HelpTopic): void => {
          this.TopicCard(topic)
        }, (topic: HelpTopic): string => topic.id)
      }.width('100%')
    }.width('100%')
  }

  build() {
    Stack() {
      HdsNavigation() {
        Scroll(this.helpScroller) {
        Column({ space: 24 }) {
          ForEach(this.sections, (section: HelpSectionData): void => {
            this.HelpSection(section)
          }, (section: HelpSectionData): string => section.id)

          Button('打开系统设置').width('100%').height(48).borderRadius(16)
            .backgroundColor($r('app.color.accent')).fontColor('#FFFFFFFF')
            .onClick((): void => { router.pushUrl({ url: 'pages/SystemSettings' }); })
        }
        // Scroll content must be allowed to grow beyond the viewport. A fixed
        // 100% height makes the last topic render under the bottom inset.
        .width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        .padding({
          left: this.helpSidePadding(), right: this.helpSidePadding(),
          top: this.helpTopInset(), bottom: this.isNarrowPhone() ? 32 : 48
        })
        .constraintSize({ maxWidth: this.helpContentMaxWidth() })
        .alignSelf(ItemAlign.Start)
      }
      .width('100%').height('100%').scrollBar(BarState.Auto)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        padding: { start: LengthMetrics.vp(14), end: LengthMetrics.vp(14 + this.titleButtonMargin()) },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(this.isPhoneLandscape() ? 56 : 84)
          },
          originalStyle: {
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('app.color.text_primary'),
                subTitleColor: $r('app.color.text_secondary')
              },
              menuStyle: {
                iconColor: $r('app.color.text_primary')
              },
              backIconStyle: {
                iconColor: $r('app.color.text_primary')
              }
            }
          },
          scrollEffectStyle: {
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('app.color.text_primary'),
                subTitleColor: $r('app.color.text_secondary')
              },
              menuStyle: {
                iconColor: $r('app.color.text_primary')
              },
              backIconStyle: {
                iconColor: $r('app.color.text_primary')
              }
            }
          },
          systemMaterialEffect: {
            materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
            materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
          }
        },
        content: {
          title: {
            mainTitle: '帮助中心',
            subTitle: this.isPhoneLandscape() ? undefined : 'Wine 应用库、输入控制与 Windows 会话使用指南'
          },
          divider: { showType: DividerShowType.OFF }
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideToolBar(true)
      .bindToScrollable([this.helpScroller])
      .width('100%').height('100%')
      .backgroundColor('#00FFFFFF')
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onAreaChange((_oldValue: Area, area: Area): void => {
      this.viewportWidth = area.width as number;
      this.viewportHeight = area.height as number;
      BreakpointSystem.updateFromWidth(this.viewportWidth);
    })
  }
}
