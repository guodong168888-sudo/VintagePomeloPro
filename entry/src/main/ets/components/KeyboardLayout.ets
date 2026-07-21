/**
 * PC keyboard used by the mapping editor.  This is the VintagePomelo layout
 * migrated to WineHua, with Linux evdev values instead of SDL scan codes so
 * the value selected here is exactly the value passed to Wine's input router.
 */
export interface KeyboardKey {
  code: number;
  label: string;
  subLabel?: string;
  width?: number;
}

export type KeyboardKeySelected = (evdevCode: number, label: string) => void;

const FUNCTION_ROW: KeyboardKey[] = [
  { code: 1, label: 'Esc' }, { code: 59, label: 'F1' }, { code: 60, label: 'F2' },
  { code: 61, label: 'F3' }, { code: 62, label: 'F4' }, { code: 63, label: 'F5' },
  { code: 64, label: 'F6' }, { code: 65, label: 'F7' }, { code: 66, label: 'F8' },
  { code: 67, label: 'F9' }, { code: 68, label: 'F10' }, { code: 87, label: 'F11' }, { code: 88, label: 'F12' }
];
const NUMBER_ROW: KeyboardKey[] = [
  { code: 41, label: '`', subLabel: '~' }, { code: 2, label: '1', subLabel: '!' }, { code: 3, label: '2', subLabel: '@' },
  { code: 4, label: '3', subLabel: '#' }, { code: 5, label: '4', subLabel: '$' }, { code: 6, label: '5', subLabel: '%' },
  { code: 7, label: '6', subLabel: '^' }, { code: 8, label: '7', subLabel: '&' }, { code: 9, label: '8', subLabel: '*' },
  { code: 10, label: '9', subLabel: '(' }, { code: 11, label: '0', subLabel: ')' }, { code: 12, label: '-', subLabel: '_' },
  { code: 13, label: '=', subLabel: '+' }, { code: 14, label: 'Back', width: 1.55 }
];
const QWERTY_ROW: KeyboardKey[] = [
  { code: 15, label: 'Tab', width: 1.3 }, { code: 16, label: 'Q' }, { code: 17, label: 'W' }, { code: 18, label: 'E' },
  { code: 19, label: 'R' }, { code: 20, label: 'T' }, { code: 21, label: 'Y' }, { code: 22, label: 'U' },
  { code: 23, label: 'I' }, { code: 24, label: 'O' }, { code: 25, label: 'P' }, { code: 26, label: '[' },
  { code: 27, label: ']' }, { code: 43, label: '\\', width: 1.2 }
];
const ASDF_ROW: KeyboardKey[] = [
  { code: 58, label: 'Caps', width: 1.5 }, { code: 30, label: 'A' }, { code: 31, label: 'S' }, { code: 32, label: 'D' },
  { code: 33, label: 'F' }, { code: 34, label: 'G' }, { code: 35, label: 'H' }, { code: 36, label: 'J' },
  { code: 37, label: 'K' }, { code: 38, label: 'L' }, { code: 39, label: ';', subLabel: ':' }, { code: 40, label: "'", subLabel: '"' },
  { code: 28, label: 'Enter', width: 1.8 }
];
const ZXCV_ROW: KeyboardKey[] = [
  { code: 42, label: 'Shift', width: 2 }, { code: 44, label: 'Z' }, { code: 45, label: 'X' }, { code: 46, label: 'C' },
  { code: 47, label: 'V' }, { code: 48, label: 'B' }, { code: 49, label: 'N' }, { code: 50, label: 'M' },
  { code: 51, label: ',', subLabel: '<' }, { code: 52, label: '.', subLabel: '>' }, { code: 53, label: '/', subLabel: '?' },
  { code: 54, label: 'Shift', width: 2.3 }
];
const CONTROL_ROW: KeyboardKey[] = [
  { code: 29, label: 'Ctrl', width: 1.3 }, { code: 125, label: 'Win' }, { code: 56, label: 'Alt' },
  { code: 57, label: 'Space', width: 6 }, { code: 100, label: 'Alt' }, { code: 126, label: 'Win' },
  { code: 139, label: 'Menu' }, { code: 97, label: 'Ctrl', width: 1.3 }
];
const EDIT_ROWS: KeyboardKey[][] = [
  [{ code: 99, label: 'PrtSc' }, { code: 70, label: 'ScrLk' }, { code: 119, label: 'Pause' }],
  [{ code: 110, label: 'Ins' }, { code: 102, label: 'Home' }, { code: 104, label: 'PgUp' }],
  [{ code: 111, label: 'Del' }, { code: 107, label: 'End' }, { code: 109, label: 'PgDn' }]
];
const ARROW_ROWS: KeyboardKey[][] = [
  [{ code: 103, label: '↑' }],
  [{ code: 105, label: '←' }, { code: 108, label: '↓' }, { code: 106, label: '→' }]
];
const NUMPAD_ROWS: KeyboardKey[][] = [
  [{ code: 69, label: 'Num' }, { code: 98, label: '/' }, { code: 55, label: '*' }, { code: 74, label: '-' }],
  [{ code: 71, label: '7' }, { code: 72, label: '8' }, { code: 73, label: '9' }, { code: 78, label: '+' }],
  [{ code: 75, label: '4' }, { code: 76, label: '5' }, { code: 77, label: '6' }, { code: 78, label: '+' }],
  [{ code: 79, label: '1' }, { code: 80, label: '2' }, { code: 81, label: '3' }, { code: 96, label: 'Enter' }],
  [{ code: 82, label: '0', width: 2 }, { code: 83, label: '.' }, { code: 96, label: 'Enter' }]
];

@Component
export struct KeyboardLayout {
  @Prop selectedEvdevCode: number = -1;
  onKeySelected: KeyboardKeySelected = (): void => {};
  private readonly keySize: number = 30;
  private readonly gap: number = 3;

  @Builder
  private Key(key: KeyboardKey) {
    Button({ type: ButtonType.Normal }) {
      Column() {
        if (key.subLabel) Text(key.subLabel).fontSize(7)
          .fontColor(this.selectedEvdevCode === key.code ? '#FFFFFFFF' : $r('app.color.text_secondary'))
        Text(key.label).fontSize(key.label.length > 4 ? 8 : 11).fontWeight(FontWeight.Medium)
          .fontColor(this.selectedEvdevCode === key.code ? '#FFFFFFFF' : $r('app.color.text_primary'))
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    }
    .width(this.keySize * (key.width ?? 1) + this.gap * ((key.width ?? 1) - 1))
    .height(this.keySize)
    .borderRadius(6)
    .backgroundColor(this.selectedEvdevCode === key.code ? $r('app.color.accent') : $r('app.color.keyboard_key_background'))
    .border({ width: 1, color: this.selectedEvdevCode === key.code ? $r('app.color.accent') : $r('app.color.keyboard_key_border') })
    .shadow({ radius: 2, color: '#20000000', offsetY: 1 })
    .onClick((): void => this.onKeySelected(key.code, key.label))
  }

  @Builder
  private KeyRow(keys: KeyboardKey[]) {
    Row({ space: this.gap }) { ForEach(keys, (key: KeyboardKey): void => this.Key(key), (key: KeyboardKey, index: number): string => key.code + '-' + index) }
  }

  build() {
    Row({ space: 14 }) {
      Column({ space: this.gap }) {
        this.KeyRow(FUNCTION_ROW)
        this.KeyRow(NUMBER_ROW)
        this.KeyRow(QWERTY_ROW)
        this.KeyRow(ASDF_ROW)
        this.KeyRow(ZXCV_ROW)
        this.KeyRow(CONTROL_ROW)
      }
      Column({ space: this.gap }) {
        ForEach(EDIT_ROWS, (row: KeyboardKey[]): void => this.KeyRow(row))
        Row().height(this.keySize)
        ForEach(ARROW_ROWS, (row: KeyboardKey[]): void => this.KeyRow(row))
      }
      Column({ space: this.gap }) { ForEach(NUMPAD_ROWS, (row: KeyboardKey[]): void => this.KeyRow(row)) }
    }
    .padding(10)
    .backgroundColor($r('app.color.keyboard_background'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.keyboard_key_border') })
  }
}
