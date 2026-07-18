import { InputRouter } from '../service/InputRouter';

interface VirtualKeyboardKey {
  label: string;
  evdevCode: number;
  weight: number;
}

const KEY_ROWS: VirtualKeyboardKey[][] = [
  [
    { label: 'Esc', evdevCode: 1, weight: 1.3 },
    { label: 'F1', evdevCode: 59, weight: 1 }, { label: 'F2', evdevCode: 60, weight: 1 },
    { label: 'F3', evdevCode: 61, weight: 1 }, { label: 'F4', evdevCode: 62, weight: 1 },
    { label: 'F5', evdevCode: 63, weight: 1 }, { label: 'F6', evdevCode: 64, weight: 1 },
    { label: 'F7', evdevCode: 65, weight: 1 }, { label: 'F8', evdevCode: 66, weight: 1 },
    { label: 'F9', evdevCode: 67, weight: 1 }, { label: 'F10', evdevCode: 68, weight: 1 },
    { label: 'F11', evdevCode: 87, weight: 1 }, { label: 'F12', evdevCode: 88, weight: 1 }
  ],
  [
    { label: '`', evdevCode: 41, weight: 1 }, { label: '1', evdevCode: 2, weight: 1 },
    { label: '2', evdevCode: 3, weight: 1 }, { label: '3', evdevCode: 4, weight: 1 },
    { label: '4', evdevCode: 5, weight: 1 }, { label: '5', evdevCode: 6, weight: 1 },
    { label: '6', evdevCode: 7, weight: 1 }, { label: '7', evdevCode: 8, weight: 1 },
    { label: '8', evdevCode: 9, weight: 1 }, { label: '9', evdevCode: 10, weight: 1 },
    { label: '0', evdevCode: 11, weight: 1 }, { label: '-', evdevCode: 12, weight: 1 },
    { label: '=', evdevCode: 13, weight: 1 }, { label: 'Backspace', evdevCode: 14, weight: 2 }
  ],
  [
    { label: 'Tab', evdevCode: 15, weight: 1.5 }, { label: 'Q', evdevCode: 16, weight: 1 },
    { label: 'W', evdevCode: 17, weight: 1 }, { label: 'E', evdevCode: 18, weight: 1 },
    { label: 'R', evdevCode: 19, weight: 1 }, { label: 'T', evdevCode: 20, weight: 1 },
    { label: 'Y', evdevCode: 21, weight: 1 }, { label: 'U', evdevCode: 22, weight: 1 },
    { label: 'I', evdevCode: 23, weight: 1 }, { label: 'O', evdevCode: 24, weight: 1 },
    { label: 'P', evdevCode: 25, weight: 1 }, { label: '[', evdevCode: 26, weight: 1 },
    { label: ']', evdevCode: 27, weight: 1 }, { label: '\\', evdevCode: 43, weight: 1.5 }
  ],
  [
    { label: 'Caps', evdevCode: 58, weight: 1.8 }, { label: 'A', evdevCode: 30, weight: 1 },
    { label: 'S', evdevCode: 31, weight: 1 }, { label: 'D', evdevCode: 32, weight: 1 },
    { label: 'F', evdevCode: 33, weight: 1 }, { label: 'G', evdevCode: 34, weight: 1 },
    { label: 'H', evdevCode: 35, weight: 1 }, { label: 'J', evdevCode: 36, weight: 1 },
    { label: 'K', evdevCode: 37, weight: 1 }, { label: 'L', evdevCode: 38, weight: 1 },
    { label: ';', evdevCode: 39, weight: 1 }, { label: "'", evdevCode: 40, weight: 1 },
    { label: 'Enter', evdevCode: 28, weight: 2.2 }
  ],
  [
    { label: 'Shift', evdevCode: 42, weight: 2.3 }, { label: 'Z', evdevCode: 44, weight: 1 },
    { label: 'X', evdevCode: 45, weight: 1 }, { label: 'C', evdevCode: 46, weight: 1 },
    { label: 'V', evdevCode: 47, weight: 1 }, { label: 'B', evdevCode: 48, weight: 1 },
    { label: 'N', evdevCode: 49, weight: 1 }, { label: 'M', evdevCode: 50, weight: 1 },
    { label: ',', evdevCode: 51, weight: 1 }, { label: '.', evdevCode: 52, weight: 1 },
    { label: '/', evdevCode: 53, weight: 1 }, { label: 'Shift', evdevCode: 54, weight: 2.3 }
  ],
  [
    { label: 'Ctrl', evdevCode: 29, weight: 1.4 }, { label: 'Alt', evdevCode: 56, weight: 1.4 },
    { label: 'Space', evdevCode: 57, weight: 6 }, { label: '←', evdevCode: 105, weight: 1 },
    { label: '↑', evdevCode: 103, weight: 1 }, { label: '↓', evdevCode: 108, weight: 1 },
    { label: '→', evdevCode: 106, weight: 1 }
  ]
];

@Component
export struct VirtualKeyboard {
  @Prop opacityValue: number = 92;
  onClose: () => void = (): void => {};

  private sendKey(key: VirtualKeyboardKey, event: TouchEvent): void {
    if (event.type === TouchType.Down) InputRouter.getInstance().sendKey(key.evdevCode, true);
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      InputRouter.getInstance().sendKey(key.evdevCode, false);
    }
  }

  @Builder
  private Key(key: VirtualKeyboardKey) {
    Button(key.label)
      .layoutWeight(key.weight)
      .height(34)
      .padding(0)
      .fontSize(key.label.length > 3 ? 9 : 12)
      .fontColor('#FFFFFFFF')
      .backgroundColor('#D52B303A')
      .borderRadius(7)
      .onTouch((event: TouchEvent) => this.sendKey(key, event))
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('PC 键盘').fontSize(11).fontColor('#DFFFFFFF').layoutWeight(1)
        Button('收起').height(25).fontSize(10).borderRadius(13).onClick(() => this.onClose())
      }.width('100%').height(28)
      ForEach(KEY_ROWS, (row: VirtualKeyboardKey[], rowIndex: number) => {
        Row({ space: 4 }) {
          ForEach(row, (key: VirtualKeyboardKey) => {
            this.Key(key)
          }, (key: VirtualKeyboardKey) => key.label + '-' + key.evdevCode)
        }.width('100%')
      }, (_row: VirtualKeyboardKey[], rowIndex: number) => rowIndex.toString())
    }
    .width('96%')
    .padding(8)
    .opacity(this.opacityValue / 100)
    .backgroundColor('#E620232A')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(14)
    .border({ width: 1, color: '#44FFFFFF' })
    .hitTestBehavior(HitTestMode.Block)
    .align(Alignment.Bottom)
    .margin({ bottom: 10 })
  }
}
