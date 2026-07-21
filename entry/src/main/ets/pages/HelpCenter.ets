import router from '@ohos.router';

type HelpCategory = 'all' | 'start' | 'library' | 'controls' | 'runtime';

interface HelpTopic {
  id: string;
  category: HelpCategory;
  icon: Resource;
  title: string;
  description: string;
  details: string;
}

/**
 * Wine application's equivalent of VintagePomelo's embedded FAQ framework.
 * It deliberately uses multiple actionable topic cards instead of a one-shot
 * alert dialog so new runtime and input help can grow without changing routes.
 */
@Entry
@Component
struct HelpCenter {
  @State private category: HelpCategory = 'all';
  @State private expandedTopicId: string = '';
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
      details: '使用左侧“内建应用”和“Windows 程序”筛选项可快速切换。文件被移动后会保留不可用卡片，方便重新关联或删除记录。'
    },
    {
      id: 'virtual-controls', category: 'controls', icon: $r('sys.symbol.gamecontroller'),
      title: '虚拟手柄、鼠标与布局编辑', description: '顶部图标可收起或展开控制层，齿轮进入布局编辑。',
      details: '布局编辑器沿用 VintagePomelo 的方向、动作、辅助三组模型。方向组只能选择十字键或摇杆之一；可拖动分组、调整分组大小、透明度和按键显隐。'
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
    }
  ];

  private visibleTopics(): HelpTopic[] {
    return this.topics.filter((topic: HelpTopic): boolean => this.category === 'all' || topic.category === this.category);
  }

  @Builder
  private CategoryChip(label: string, value: HelpCategory, icon: Resource) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(icon).fontSize(15).fontColor([this.category === value ? '#FFFFFFFF' : $r('app.color.text_primary')])
        Text(label).fontSize(13).fontWeight(this.category === value ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.category === value ? '#FFFFFFFF' : $r('app.color.text_primary'))
      }
    }
    .height(42).padding({ left: 12, right: 12 }).borderRadius(14)
    .backgroundColor(this.category === value ? $r('app.color.accent') : $r('app.color.search_background'))
    .onClick((): void => { this.category = value; this.expandedTopicId = ''; })
  }

  @Builder
  private TopicCard(topic: HelpTopic) {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(topic.icon).fontSize(22).fontColor([$r('app.color.accent')])
        }
        .width(48).height(48).borderRadius(16).backgroundColor($r('app.color.selected_background'))
        Column({ space: 4 }) {
          Text(topic.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
          Text(topic.description).fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(18).maxLines(2).width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph(this.expandedTopicId === topic.id ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(18).fontColor([$r('app.color.text_secondary')])
      }
      if (this.expandedTopicId === topic.id) {
        Text(topic.details).fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
          .padding({ left: 4, right: 4, top: 2 })
      }
    }
    .width('100%').padding(16).backgroundColor($r('app.color.card_glass_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK).borderRadius(16)
    .onClick((): void => { this.expandedTopicId = this.expandedTopicId === topic.id ? '' : topic.id; })
  }

  build() {
    Column() {
      Row({ space: 14 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18).fontColor([$r('app.color.text_primary')])
        }
        .width(48).height(48).backgroundColor($r('app.color.search_background'))
        .id('help-center-back').onClick((): void => { router.back(); })
        Column({ space: 3 }) {
          Text('帮助中心').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('Wine 应用库、输入控制与 Windows 会话使用指南').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .height(64).width('100%').padding({ left: 16, right: 16, top: 4, bottom: 0 })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.info_circle')).fontSize(42).fontColor([$r('app.color.accent')])
            Text('需要一点帮助？').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text('按主题查找应用导入、虚拟控制和 Wine 运行方式。').fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 12, bottom: 4 })

          Scroll() {
            Row({ space: 8 }) {
              this.CategoryChip('全部', 'all', $r('sys.symbol.square_grid_2x2'))
              this.CategoryChip('开始使用', 'start', $r('sys.symbol.info_circle'))
              this.CategoryChip('应用库', 'library', $r('sys.symbol.folder'))
              this.CategoryChip('输入控制', 'controls', $r('sys.symbol.gamecontroller'))
              this.CategoryChip('运行与排障', 'runtime', $r('sys.symbol.gearshape'))
            }
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          Column({ space: 12 }) {
            ForEach(this.visibleTopics(), (topic: HelpTopic): void => this.TopicCard(topic), (topic: HelpTopic): string => topic.id)
          }.width('100%')

          Button('打开系统设置').width('100%').height(48).borderRadius(16)
            .backgroundColor($r('app.color.accent')).fontColor('#FFFFFFFF')
            .onClick((): void => { router.pushUrl({ url: 'pages/SystemSettings' }); })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Start)
        .padding({ left: 20, right: 20, top: 10, bottom: 28 })
        .constraintSize({ maxWidth: 960 })
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
