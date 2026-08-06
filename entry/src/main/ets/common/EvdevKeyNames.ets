/**
 * Winlator .icp 绑定名与本地注入码的映射表。
 *
 * .icp 使用形如 KEY_W / MOUSE_LEFT_BUTTON / NONE 的绑定名，而本工程
 * 的输入注入使用 Linux evdev 码（sendKey）与指针按钮码（sendPointer）。
 * 本模块只做名称转换，不依赖任何模型类型，避免循环引用。
 */

export interface NamedBinding {
  kind: string;
  code: number;
}

interface NamedKeyEntry {
  name: string;
  code: number;
}

interface KeyAliasEntry {
  alias: string;
  canonical: string;
}

const NAMED_KEYS: NamedKeyEntry[] = [
  { name: 'KEY_ESC', code: 1 },
  { name: 'KEY_1', code: 2 },
  { name: 'KEY_2', code: 3 },
  { name: 'KEY_3', code: 4 },
  { name: 'KEY_4', code: 5 },
  { name: 'KEY_5', code: 6 },
  { name: 'KEY_6', code: 7 },
  { name: 'KEY_7', code: 8 },
  { name: 'KEY_8', code: 9 },
  { name: 'KEY_9', code: 10 },
  { name: 'KEY_0', code: 11 },
  { name: 'KEY_MINUS', code: 12 },
  { name: 'KEY_EQUAL', code: 13 },
  { name: 'KEY_BACKSPACE', code: 14 },
  { name: 'KEY_TAB', code: 15 },
  { name: 'KEY_Q', code: 16 },
  { name: 'KEY_W', code: 17 },
  { name: 'KEY_E', code: 18 },
  { name: 'KEY_R', code: 19 },
  { name: 'KEY_T', code: 20 },
  { name: 'KEY_Y', code: 21 },
  { name: 'KEY_U', code: 22 },
  { name: 'KEY_I', code: 23 },
  { name: 'KEY_O', code: 24 },
  { name: 'KEY_P', code: 25 },
  { name: 'KEY_LEFTBRACE', code: 26 },
  { name: 'KEY_RIGHTBRACE', code: 27 },
  { name: 'KEY_ENTER', code: 28 },
  { name: 'KEY_CTRL_L', code: 29 },
  { name: 'KEY_A', code: 30 },
  { name: 'KEY_S', code: 31 },
  { name: 'KEY_D', code: 32 },
  { name: 'KEY_F', code: 33 },
  { name: 'KEY_G', code: 34 },
  { name: 'KEY_H', code: 35 },
  { name: 'KEY_J', code: 36 },
  { name: 'KEY_K', code: 37 },
  { name: 'KEY_L', code: 38 },
  { name: 'KEY_SEMICOLON', code: 39 },
  { name: 'KEY_APOSTROPHE', code: 40 },
  { name: 'KEY_GRAVE', code: 41 },
  { name: 'KEY_SHIFT_L', code: 42 },
  { name: 'KEY_BACKSLASH', code: 43 },
  { name: 'KEY_Z', code: 44 },
  { name: 'KEY_X', code: 45 },
  { name: 'KEY_C', code: 46 },
  { name: 'KEY_V', code: 47 },
  { name: 'KEY_B', code: 48 },
  { name: 'KEY_N', code: 49 },
  { name: 'KEY_M', code: 50 },
  { name: 'KEY_COMMA', code: 51 },
  { name: 'KEY_DOT', code: 52 },
  { name: 'KEY_SLASH', code: 53 },
  { name: 'KEY_SHIFT_R', code: 54 },
  { name: 'KEY_KP_ASTERISK', code: 55 },
  { name: 'KEY_ALT_L', code: 56 },
  { name: 'KEY_SPACE', code: 57 },
  { name: 'KEY_CAPSLOCK', code: 58 },
  { name: 'KEY_F1', code: 59 },
  { name: 'KEY_F2', code: 60 },
  { name: 'KEY_F3', code: 61 },
  { name: 'KEY_F4', code: 62 },
  { name: 'KEY_F5', code: 63 },
  { name: 'KEY_F6', code: 64 },
  { name: 'KEY_F7', code: 65 },
  { name: 'KEY_F8', code: 66 },
  { name: 'KEY_F9', code: 67 },
  { name: 'KEY_F10', code: 68 },
  { name: 'KEY_F11', code: 87 },
  { name: 'KEY_F12', code: 88 },
  { name: 'KEY_NUMLOCK', code: 69 },
  { name: 'KEY_SCROLLLOCK', code: 70 },
  { name: 'KEY_NUMPAD_7', code: 71 },
  { name: 'KEY_NUMPAD_8', code: 72 },
  { name: 'KEY_NUMPAD_9', code: 73 },
  { name: 'KEY_KP_MINUS', code: 74 },
  { name: 'KEY_NUMPAD_4', code: 75 },
  { name: 'KEY_NUMPAD_5', code: 76 },
  { name: 'KEY_NUMPAD_6', code: 77 },
  { name: 'KEY_KP_PLUS', code: 78 },
  { name: 'KEY_NUMPAD_1', code: 79 },
  { name: 'KEY_NUMPAD_2', code: 80 },
  { name: 'KEY_NUMPAD_3', code: 81 },
  { name: 'KEY_NUMPAD_0', code: 82 },
  { name: 'KEY_KP_DOT', code: 83 },
  { name: 'KEY_KP_ENTER', code: 96 },
  { name: 'KEY_CTRL_R', code: 97 },
  { name: 'KEY_KP_SLASH', code: 98 },
  { name: 'KEY_PRINT', code: 99 },
  { name: 'KEY_ALT_R', code: 100 },
  { name: 'KEY_HOME', code: 102 },
  { name: 'KEY_UP', code: 103 },
  { name: 'KEY_PAGEUP', code: 104 },
  { name: 'KEY_LEFT', code: 105 },
  { name: 'KEY_RIGHT', code: 106 },
  { name: 'KEY_END', code: 107 },
  { name: 'KEY_DOWN', code: 108 },
  { name: 'KEY_PAGEDOWN', code: 109 },
  { name: 'KEY_INSERT', code: 110 },
  { name: 'KEY_DELETE', code: 111 },
  { name: 'KEY_PAUSE', code: 119 }
];

const KEY_ALIASES: KeyAliasEntry[] = [
  { alias: 'KEY_ESCAPE', canonical: 'KEY_ESC' },
  { alias: 'KEY_LEFTSHIFT', canonical: 'KEY_SHIFT_L' },
  { alias: 'KEY_SHIFT_LEFT', canonical: 'KEY_SHIFT_L' },
  { alias: 'KEY_RIGHTSHIFT', canonical: 'KEY_SHIFT_R' },
  { alias: 'KEY_SHIFT_RIGHT', canonical: 'KEY_SHIFT_R' },
  { alias: 'KEY_LEFTCTRL', canonical: 'KEY_CTRL_L' },
  { alias: 'KEY_CTRL_LEFT', canonical: 'KEY_CTRL_L' },
  { alias: 'KEY_CONTROL_LEFT', canonical: 'KEY_CTRL_L' },
  { alias: 'KEY_RIGHTCTRL', canonical: 'KEY_CTRL_R' },
  { alias: 'KEY_CTRL_RIGHT', canonical: 'KEY_CTRL_R' },
  { alias: 'KEY_CONTROL_RIGHT', canonical: 'KEY_CTRL_R' },
  { alias: 'KEY_LEFTALT', canonical: 'KEY_ALT_L' },
  { alias: 'KEY_ALT_LEFT', canonical: 'KEY_ALT_L' },
  { alias: 'KEY_RIGHTALT', canonical: 'KEY_ALT_R' },
  { alias: 'KEY_ALT_RIGHT', canonical: 'KEY_ALT_R' },
  { alias: 'KEY_BACK', canonical: 'KEY_BACKSPACE' },
  { alias: 'KEY_DEL', canonical: 'KEY_DELETE' },
  { alias: 'KEY_FORWARD_DEL', canonical: 'KEY_DELETE' },
  { alias: 'KEY_PRINTSCREEN', canonical: 'KEY_PRINT' },
  { alias: 'KEY_SYSRQ', canonical: 'KEY_PRINT' },
  { alias: 'KEY_KP0', canonical: 'KEY_NUMPAD_0' },
  { alias: 'KEY_KP1', canonical: 'KEY_NUMPAD_1' },
  { alias: 'KEY_KP2', canonical: 'KEY_NUMPAD_2' },
  { alias: 'KEY_KP3', canonical: 'KEY_NUMPAD_3' },
  { alias: 'KEY_KP4', canonical: 'KEY_NUMPAD_4' },
  { alias: 'KEY_KP5', canonical: 'KEY_NUMPAD_5' },
  { alias: 'KEY_KP6', canonical: 'KEY_NUMPAD_6' },
  { alias: 'KEY_KP7', canonical: 'KEY_NUMPAD_7' },
  { alias: 'KEY_KP8', canonical: 'KEY_NUMPAD_8' },
  { alias: 'KEY_KP9', canonical: 'KEY_NUMPAD_9' },
  { alias: 'KEY_NUMERIC_0', canonical: 'KEY_NUMPAD_0' },
  { alias: 'KEY_NUMERIC_1', canonical: 'KEY_NUMPAD_1' },
  { alias: 'KEY_NUMERIC_2', canonical: 'KEY_NUMPAD_2' },
  { alias: 'KEY_NUMERIC_3', canonical: 'KEY_NUMPAD_3' },
  { alias: 'KEY_NUMERIC_4', canonical: 'KEY_NUMPAD_4' },
  { alias: 'KEY_NUMERIC_5', canonical: 'KEY_NUMPAD_5' },
  { alias: 'KEY_NUMERIC_6', canonical: 'KEY_NUMPAD_6' },
  { alias: 'KEY_NUMERIC_7', canonical: 'KEY_NUMPAD_7' },
  { alias: 'KEY_NUMERIC_8', canonical: 'KEY_NUMPAD_8' },
  { alias: 'KEY_NUMERIC_9', canonical: 'KEY_NUMPAD_9' },
  { alias: 'KEY_KP_MINUS', canonical: 'KEY_KP_MINUS' },
  { alias: 'KEY_KP_PLUS', canonical: 'KEY_KP_PLUS' },
  { alias: 'KEY_KP_DOT', canonical: 'KEY_KP_DOT' },
  { alias: 'KEY_KP_ENTER', canonical: 'KEY_KP_ENTER' },
  { alias: 'KEY_KP_SLASH', canonical: 'KEY_KP_SLASH' },
  { alias: 'KEY_KP_ASTERISK', canonical: 'KEY_KP_ASTERISK' },
  { alias: 'KEY_LEFT_BRACE', canonical: 'KEY_LEFTBRACE' },
  { alias: 'KEY_RIGHT_BRACE', canonical: 'KEY_RIGHTBRACE' }
];

const MOUSE_NAMES: NamedKeyEntry[] = [
  { name: 'MOUSE_LEFT_BUTTON', code: 272 },
  { name: 'MOUSE_RIGHT_BUTTON', code: 273 },
  { name: 'MOUSE_MIDDLE_BUTTON', code: 274 },
  { name: 'MOUSE_BACK_BUTTON', code: 275 },
  { name: 'MOUSE_FORWARD_BUTTON', code: 276 }
];

function canonicalKeyName(name: string): string {
  for (let index = 0; index < KEY_ALIASES.length; index++) {
    if (KEY_ALIASES[index].alias === name) return KEY_ALIASES[index].canonical;
  }
  return name;
}

function keyCodeByName(name: string): number {
  const canonical = canonicalKeyName(name);
  for (let index = 0; index < NAMED_KEYS.length; index++) {
    if (NAMED_KEYS[index].name === canonical) return NAMED_KEYS[index].code;
  }
  return 0;
}

function mouseCodeByName(name: string): number {
  for (let index = 0; index < MOUSE_NAMES.length; index++) {
    if (MOUSE_NAMES[index].name === name) return MOUSE_NAMES[index].code;
  }
  return 0;
}

/**
 * 把 .icp 绑定名转换为内部绑定。未知名称返回 NONE，保证导入容错。
 */
export function evdevNameToBinding(name: string): NamedBinding {
  const normalized = (name ?? '').trim().toUpperCase();
  if (normalized.length === 0 || normalized === 'NONE') {
    return { kind: 'NONE', code: 0 };
  }
  if (normalized.startsWith('MOUSE_')) {
    const mouse = mouseCodeByName(normalized);
    return mouse > 0 ? { kind: 'MOUSE', code: mouse } : { kind: 'NONE', code: 0 };
  }
  const code = keyCodeByName(normalized);
  return code > 0 ? { kind: 'KEY', code: code } : { kind: 'NONE', code: 0 };
}

/**
 * 把内部绑定转换为 .icp 导出名。无法识别的码返回 NONE。
 */
export function bindingToEvdevName(kind: string, code: number): string {
  if (kind === 'MOUSE') {
    for (let index = 0; index < MOUSE_NAMES.length; index++) {
      if (MOUSE_NAMES[index].code === code) return MOUSE_NAMES[index].name;
    }
    return 'NONE';
  }
  if (kind !== 'KEY' || code <= 0) return 'NONE';
  for (let index = 0; index < NAMED_KEYS.length; index++) {
    if (NAMED_KEYS[index].code === code) return NAMED_KEYS[index].name;
  }
  return 'NONE';
}

/**
 * 供绑定编辑 UI 使用的可显示键名列表（导出名 + 中文标签）。
 */
export interface KeyNameOption {
  name: string;
  code: number;
  label: string;
}

export const KEY_NAME_OPTIONS: KeyNameOption[] = [
  { name: 'KEY_A', code: 30, label: 'A' },
  { name: 'KEY_B', code: 48, label: 'B' },
  { name: 'KEY_C', code: 46, label: 'C' },
  { name: 'KEY_D', code: 32, label: 'D' },
  { name: 'KEY_E', code: 18, label: 'E' },
  { name: 'KEY_F', code: 33, label: 'F' },
  { name: 'KEY_G', code: 34, label: 'G' },
  { name: 'KEY_H', code: 35, label: 'H' },
  { name: 'KEY_I', code: 23, label: 'I' },
  { name: 'KEY_J', code: 36, label: 'J' },
  { name: 'KEY_K', code: 37, label: 'K' },
  { name: 'KEY_L', code: 38, label: 'L' },
  { name: 'KEY_M', code: 50, label: 'M' },
  { name: 'KEY_N', code: 49, label: 'N' },
  { name: 'KEY_O', code: 24, label: 'O' },
  { name: 'KEY_P', code: 25, label: 'P' },
  { name: 'KEY_Q', code: 16, label: 'Q' },
  { name: 'KEY_R', code: 19, label: 'R' },
  { name: 'KEY_S', code: 31, label: 'S' },
  { name: 'KEY_T', code: 20, label: 'T' },
  { name: 'KEY_U', code: 22, label: 'U' },
  { name: 'KEY_V', code: 47, label: 'V' },
  { name: 'KEY_W', code: 17, label: 'W' },
  { name: 'KEY_X', code: 45, label: 'X' },
  { name: 'KEY_Y', code: 21, label: 'Y' },
  { name: 'KEY_Z', code: 44, label: 'Z' },
  { name: 'KEY_0', code: 11, label: '0' },
  { name: 'KEY_1', code: 2, label: '1' },
  { name: 'KEY_2', code: 3, label: '2' },
  { name: 'KEY_3', code: 4, label: '3' },
  { name: 'KEY_4', code: 5, label: '4' },
  { name: 'KEY_5', code: 6, label: '5' },
  { name: 'KEY_6', code: 7, label: '6' },
  { name: 'KEY_7', code: 8, label: '7' },
  { name: 'KEY_8', code: 9, label: '8' },
  { name: 'KEY_9', code: 10, label: '9' },
  { name: 'KEY_F1', code: 59, label: 'F1' },
  { name: 'KEY_F2', code: 60, label: 'F2' },
  { name: 'KEY_F3', code: 61, label: 'F3' },
  { name: 'KEY_F4', code: 62, label: 'F4' },
  { name: 'KEY_F5', code: 63, label: 'F5' },
  { name: 'KEY_F6', code: 64, label: 'F6' },
  { name: 'KEY_F7', code: 65, label: 'F7' },
  { name: 'KEY_F8', code: 66, label: 'F8' },
  { name: 'KEY_F9', code: 67, label: 'F9' },
  { name: 'KEY_F10', code: 68, label: 'F10' },
  { name: 'KEY_F11', code: 87, label: 'F11' },
  { name: 'KEY_F12', code: 88, label: 'F12' },
  { name: 'KEY_ESC', code: 1, label: 'Esc' },
  { name: 'KEY_TAB', code: 15, label: 'Tab' },
  { name: 'KEY_CAPSLOCK', code: 58, label: 'CapsLock' },
  { name: 'KEY_SHIFT_L', code: 42, label: 'Shift' },
  { name: 'KEY_CTRL_L', code: 29, label: 'Ctrl' },
  { name: 'KEY_ALT_L', code: 56, label: 'Alt' },
  { name: 'KEY_SPACE', code: 57, label: '空格' },
  { name: 'KEY_ENTER', code: 28, label: 'Enter' },
  { name: 'KEY_BACKSPACE', code: 14, label: '退格' },
  { name: 'KEY_UP', code: 103, label: '↑' },
  { name: 'KEY_DOWN', code: 108, label: '↓' },
  { name: 'KEY_LEFT', code: 105, label: '←' },
  { name: 'KEY_RIGHT', code: 106, label: '→' },
  { name: 'KEY_HOME', code: 102, label: 'Home' },
  { name: 'KEY_END', code: 107, label: 'End' },
  { name: 'KEY_PAGEUP', code: 104, label: 'PgUp' },
  { name: 'KEY_PAGEDOWN', code: 109, label: 'PgDn' },
  { name: 'KEY_INSERT', code: 110, label: 'Insert' },
  { name: 'KEY_DELETE', code: 111, label: 'Delete' },
  { name: 'KEY_MINUS', code: 12, label: '-' },
  { name: 'KEY_EQUAL', code: 13, label: '=' },
  { name: 'KEY_LEFTBRACE', code: 26, label: '[' },
  { name: 'KEY_RIGHTBRACE', code: 27, label: ']' },
  { name: 'KEY_BACKSLASH', code: 43, label: '\\' },
  { name: 'KEY_SEMICOLON', code: 39, label: ';' },
  { name: 'KEY_APOSTROPHE', code: 40, label: "'" },
  { name: 'KEY_GRAVE', code: 41, label: '`' },
  { name: 'KEY_COMMA', code: 51, label: ',' },
  { name: 'KEY_DOT', code: 52, label: '.' },
  { name: 'KEY_SLASH', code: 53, label: '/' }
];

export function keyNameLabel(code: number): string {
  for (let index = 0; index < KEY_NAME_OPTIONS.length; index++) {
    if (KEY_NAME_OPTIONS[index].code === code) return KEY_NAME_OPTIONS[index].label;
  }
  const exported = bindingToEvdevName('KEY', code);
  return exported === 'NONE' ? '键 ' + code.toString() : exported.replace('KEY_', '');
}
