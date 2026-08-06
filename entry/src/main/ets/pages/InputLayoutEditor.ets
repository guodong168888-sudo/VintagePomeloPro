import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  ControlElement,
  ControlElementShape,
  ControlElementType,
  InputBinding,
  InputBindingKind,
  InputProfile,
  ThemeMode,
  cloneInputProfile,
  createControlElement,
  createDefaultInputProfile,
  keyBinding,
  MOUSE_LEFT_BUTTON,
  MOUSE_RIGHT_BUTTON,
  MOUSE_MIDDLE_BUTTON
} from '../model/AppModels';
import { KEY_NAME_OPTIONS, keyNameLabel } from '../common/EvdevKeyNames';
import { VirtualInputOverlay } from '../components/VirtualInputOverlay';
import { InputProfileService } from '../service/InputProfileService';
import { AppSettingsStore } from '../service/AppSettingsStore';

interface PickerOption {
  label: string;
  name: string;
  kind: InputBindingKind;
  code: number;
}

interface ElementPatch {
  x?: number;
  y?: number;
  scale?: number;
  text?: string;
  shape?: ControlElementShape;
  toggleSwitch?: boolean;
  opacity?: number;
  bindings?: InputBinding[];
  keyList?: number[];
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function elementTypeLabel(type: ControlElementType): string {
  if (type === ControlElementType.D_PAD) return '方向键';
  if (type === ControlElementType.STICK) return '摇杆';
  if (type === ControlElementType.TRACKPAD) return '触摸板';
  if (type === ControlElementType.RANGE_BUTTON) return '滚动键';
  return '按钮';
}

/**
 * Winlator 风格的全屏画布输入编辑器。元素使用归一化坐标自由排布：
 * 点按选中、单指拖动、双指缩放，选中后在属性面板编辑绑定/形状/透明度。
 */
@Entry
@Component
struct InputLayoutEditor {
  @State private profile: InputProfile = createDefaultInputProfile();
  @State private profileId: string = 'default';
  @State private profileName: string = '默认输入方案';
  @State private appId: string = '';
  @State private baseProfileId: string = 'default';
  @State private previewW: number = 0;
  @State private previewH: number = 0;
  @State private selectedElementId: string = '';
  @State private previewRevision: number = 0;
  @State private showPropertyPanel: boolean = false;
  @State private pickerOpen: boolean = false;
  @State private pickerTargetSlot: number = -1;
  @State private pickerTargetKeyList: boolean = false;
  @State private customKeyText: string = '';
  @State private returnAbilityName: string = '';
  @State private returnSessionId: string = '';
  @State private returnToplevelId: string = '0';
  @State private safeAreaTop: number = 0;
  @State private safeAreaBottom: number = 0;
  @State private safeAreaLeft: number = 0;
  @State private safeAreaRight: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private originalOrientation: window.Orientation = window.Orientation.UNSPECIFIED;
  private originalLayoutFullScreen: boolean = false;
  private hasOriginalWindowLayout: boolean = false;
  private orientationRestored: boolean = false;
  private returnScheduled: boolean = false;
  private editorWindowRef: window.Window | null = null;
  private avoidAreaCallback: (data: window.AvoidAreaOptions) => void = (): void => {};

  aboutToAppear(): void {
    const params = (router.getParams() ?? {}) as Record<string, string>;
    this.profileId = params.profileId ?? 'default';
    this.profileName = params.profileName ?? '默认输入方案';
    this.appId = params.appId ?? '';
    this.baseProfileId = params.baseProfileId ?? 'default';
    this.returnAbilityName = params.returnAbilityName ?? '';
    this.returnSessionId = params.returnSessionId ?? '';
    this.returnToplevelId = params.returnToplevelId ?? '0';
    this.enterImmersive();
    InputProfileService.getInstance().initialize(this.context).then((): void => {
      this.profile = InputProfileService.getInstance().ensureProfile(this.profileId, this.profileName, this.baseProfileId);
      this.profileName = this.profile.name;
      this.previewRevision++;
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.editorWindowRef) {
      try {
        this.editorWindowRef.off('avoidAreaChange', this.avoidAreaCallback);
      } catch (_) {
      }
      this.editorWindowRef = null;
    }
    if (!this.orientationRestored) this.restoreEditorWindow();
    this.resumeWineAbility();
  }

  private async enterImmersive(): Promise<void> {
    try {
      const editorWindow = await window.getLastWindow(this.context);
      this.originalOrientation = editorWindow.getPreferredOrientation();
      this.originalLayoutFullScreen = editorWindow.getWindowProperties().isLayoutFullScreen;
      this.hasOriginalWindowLayout = true;
      await editorWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED);
      await editorWindow.setWindowLayoutFullScreen(true);
      try {
        await editorWindow.setSpecificSystemBarEnabled('status', false);
        await editorWindow.setSpecificSystemBarEnabled('navigationIndicator', false);
      } catch (_) {
        await editorWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          isStatusBarLightIcon: true,
          isNavigationBarLightIcon: true
        });
      }
      this.refreshSafeAreas(editorWindow);
      this.editorWindowRef = editorWindow;
      this.avoidAreaCallback = (): void => {
        this.refreshSafeAreas(editorWindow);
      };
      try {
        editorWindow.on('avoidAreaChange', this.avoidAreaCallback);
      } catch (_) {
      }
      setTimeout((): void => { this.refreshSafeAreas(editorWindow); }, 180);
    } catch (_) {
    }
  }

  private refreshSafeAreas(editorWindow: window.Window): void {
    try {
      const systemAvoid = editorWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutAvoid = editorWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const navigationAvoid = editorWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.safeAreaTop = Math.max(systemAvoid.topRect.height, cutoutAvoid.topRect.height);
      this.safeAreaBottom = Math.max(systemAvoid.bottomRect.height, cutoutAvoid.bottomRect.height,
        navigationAvoid.bottomRect.height);
      this.safeAreaLeft = Math.max(systemAvoid.leftRect.width, cutoutAvoid.leftRect.width);
      this.safeAreaRight = Math.max(systemAvoid.rightRect.width, cutoutAvoid.rightRect.width);
    } catch (_) {
      this.safeAreaTop = 0;
      this.safeAreaBottom = 0;
      this.safeAreaLeft = 0;
      this.safeAreaRight = 0;
    }
  }

  private async restoreEditorWindow(): Promise<void> {
    if (this.orientationRestored) return;
    this.orientationRestored = true;
    try {
      const editorWindow = await window.getLastWindow(this.context);
      await editorWindow.setPreferredOrientation(this.originalOrientation);
      try {
        if (this.hasOriginalWindowLayout) {
          await editorWindow.setWindowLayoutFullScreen(this.originalLayoutFullScreen);
        }
      } catch (_) {
      }
      try {
        await editorWindow.setWindowSystemBarEnable(['status']);
      } catch (_) {
      }
      try {
        await editorWindow.setSpecificSystemBarEnabled('status', true);
      } catch (_) {
      }
      try {
        await editorWindow.setSpecificSystemBarEnabled('navigationIndicator', false);
      } catch (_) {
      }
      try {
        const settings = AppSettingsStore.getInstance().getGlobalSettings();
        let useLightIcons = settings.themeMode === ThemeMode.DARK;
        if (settings.themeMode === ThemeMode.SYSTEM) {
          useLightIcons = this.context.config.colorMode ===
            ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        }
        await editorWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          isStatusBarLightIcon: useLightIcons,
          isNavigationBarLightIcon: useLightIcons
        });
      } catch (_) {
      }
      this.safeAreaTop = 0;
      this.safeAreaBottom = 0;
      this.safeAreaLeft = 0;
      this.safeAreaRight = 0;
    } catch (_) {
    }
  }

  private async finishEditor(): Promise<void> {
    await this.restoreEditorWindow();
    router.back();
    this.resumeWineAbility();
  }

  private resumeWineAbility(): void {
    if (this.returnScheduled) return;
    if (this.returnAbilityName !== 'DesktopAbility') return;
    this.returnScheduled = true;
    const want: Want = {
      bundleName: 'com.vintage.pomelopro',
      abilityName: this.returnAbilityName,
      parameters: {
        sessionId: this.returnSessionId,
        toplevelId: Number(this.returnToplevelId) || 0
      }
    };
    setTimeout((): void => {
      this.context.startAbility(want).catch((): void => {});
    }, 80);
  }

  private selectedElement(): ControlElement | null {
    const elements = this.profile.elements;
    for (let index = 0; index < elements.length; index++) {
      if (elements[index].id === this.selectedElementId) return elements[index];
    }
    return null;
  }

  private updateProfile(mutator: (elements: ControlElement[]) => ControlElement[]): void {
    const next = cloneInputProfile(this.profile);
    next.elements = mutator(next.elements ?? []);
    this.profile = next;
    this.previewRevision++;
  }

  private moveElement(id: string, x: number, y: number): void {
    this.updateProfile((elements: ControlElement[]): ControlElement[] =>
      elements.map((element: ControlElement): ControlElement =>
        element.id === id ? this.withElement(element, { x: x, y: y }) : element));
  }

  private scaleElement(id: string, scale: number): void {
    this.updateProfile((elements: ControlElement[]): ControlElement[] =>
      elements.map((element: ControlElement): ControlElement =>
        element.id === id ? this.withElement(element, { scale: scale }) : element));
  }

  private updateSelectedElement(mutator: (element: ControlElement) => ControlElement): void {
    const id = this.selectedElementId;
    this.updateProfile((elements: ControlElement[]): ControlElement[] =>
      elements.map((element: ControlElement): ControlElement =>
        element.id === id ? mutator(element) : element));
  }

  private withElement(element: ControlElement, patch: ElementPatch): ControlElement {
    return {
      id: element.id,
      type: element.type,
      shape: patch.shape ?? element.shape,
      x: patch.x ?? element.x,
      y: patch.y ?? element.y,
      scale: patch.scale ?? element.scale,
      opacity: patch.opacity ?? element.opacity,
      bindings: patch.bindings ?? element.bindings,
      toggleSwitch: patch.toggleSwitch ?? element.toggleSwitch,
      text: patch.text ?? element.text,
      iconId: element.iconId,
      visible: element.visible,
      keyList: patch.keyList ?? element.keyList
    };
  }

  /** 画布使用窗口内可用区域（顶部提示栏与底部操作栏之间，右侧留给属性面板）。 */
  private canvasHeight(): number {
    return Math.max(240, this.previewH - 240);
  }

  private canvasWidth(): number {
    const reserved = 300;
    const maxWidth = Math.max(300, this.previewW - reserved - 48);
    return Math.max(160, maxWidth);
  }

  private canvasLeft(): number {
    const reserved = 300;
    const freeWidth = Math.max(0, this.previewW - reserved);
    return Math.max(12, (freeWidth - this.canvasWidth()) / 2 + 12);
  }

  private canvasTop(): number {
    return Math.max(140, (this.previewH - this.canvasHeight()) / 2);
  }

  private elementPixelWidth(element: ControlElement): number {
    if (element.type === ControlElementType.TRACKPAD) return 150 * (element.scale ?? 1);
    if (element.type === ControlElementType.RANGE_BUTTON) return 44 * (element.scale ?? 1);
    if (element.type === ControlElementType.D_PAD) return 132 * (element.scale ?? 1);
    if (element.type === ControlElementType.STICK) return 120 * (element.scale ?? 1);
    return 56 * (element.scale ?? 1);
  }

  private elementPixelHeight(element: ControlElement): number {
    if (element.type === ControlElementType.TRACKPAD) return 100 * (element.scale ?? 1);
    if (element.type === ControlElementType.RANGE_BUTTON) return 180 * (element.scale ?? 1);
    return this.elementPixelWidth(element);
  }

  private elementsOverlap(left: ControlElement, right: ControlElement): boolean {
    const halfWidth = (this.elementPixelWidth(left) + this.elementPixelWidth(right)) / 2;
    const halfHeight = (this.elementPixelHeight(left) + this.elementPixelHeight(right)) / 2;
    const dx = Math.abs(left.x - right.x) * this.canvasWidth();
    const dy = Math.abs(left.y - right.y) * this.canvasHeight();
    return dx < halfWidth && dy < halfHeight;
  }

  private overlapWarning(): string {
    const element = this.selectedElement();
    if (!element) return '';
    const elements = this.profile.elements;
    for (let index = 0; index < elements.length; index++) {
      const other = elements[index];
      if (other.id === element.id || !other.visible) continue;
      if (this.elementsOverlap(element, other)) {
        const label = other.text.length > 0 ? other.text : '未命名控件';
        return '与「' + label + '」重叠，请拖动错开';
      }
    }
    return '';
  }

  private defaultBindings(type: ControlElementType): InputBinding[] {
    if (type === ControlElementType.D_PAD || type === ControlElementType.STICK) {
      return [keyBinding(17), keyBinding(32), keyBinding(31), keyBinding(30)];
    }
    if (type === ControlElementType.BUTTON) return [keyBinding(57)];
    return [];
  }

  private addElement(type: ControlElementType): void {
    const element = createControlElement(type, 0.5, 0.5, elementTypeLabel(type), this.defaultBindings(type));
    this.updateProfile((elements: ControlElement[]): ControlElement[] => {
      const next = elements.slice();
      next.push(element);
      return next;
    });
    this.selectedElementId = element.id;
    this.showPropertyPanel = true;
  }

  private removeSelectedElement(): void {
    const id = this.selectedElementId;
    if (!id) return;
    this.updateProfile((elements: ControlElement[]): ControlElement[] =>
      elements.filter((element: ControlElement): boolean => element.id !== id));
    this.selectedElementId = '';
    this.showPropertyPanel = false;
  }

  private duplicateSelectedElement(): void {
    const source = this.selectedElement();
    if (!source) return;
    const copy = createControlElement(source.type, Math.min(0.95, source.x + 0.04), Math.min(0.95, source.y + 0.04),
      source.text, source.bindings, source.shape, source.scale, source.toggleSwitch, source.keyList);
    copy.opacity = source.opacity;
    this.updateProfile((elements: ControlElement[]): ControlElement[] => {
      const next = elements.slice();
      next.push(copy);
      return next;
    });
    this.selectedElementId = copy.id;
  }

  private reset(): void {
    const defaults = createDefaultInputProfile();
    this.profile = cloneInputProfile(defaults);
    this.profile.id = this.profileId;
    this.profile.name = this.profileName;
    this.selectedElementId = '';
    this.showPropertyPanel = false;
    this.previewRevision++;
    promptAction.showToast({ message: '已恢复默认模板' });
  }

  private async save(): Promise<void> {
    const saved = cloneInputProfile(this.profile);
    saved.id = this.profileId;
    saved.name = this.profileName;
    await InputProfileService.getInstance().saveProfile(saved);
    if (this.appId) {
      const current = AppSettingsStore.getInstance().getAppSettings(this.appId);
      await AppSettingsStore.getInstance().saveAppSettings({
        appId: current.appId,
        customTitle: current.customTitle,
        customCover: current.customCover,
        favorite: current.favorite,
        box64Preset: current.box64Preset,
        executable: current.executable,
        arguments: current.arguments,
        workingDirectory: current.workingDirectory,
        displayModeOverride: current.displayModeOverride,
        inputProfileId: this.profile.id,
        prefixId: current.prefixId
      });
    }
    promptAction.showToast({ message: '输入方案已保存' });
    await this.finishEditor();
  }

  private setBindingSlot(slotIndex: number, binding: InputBinding): void {
    this.updateSelectedElement((element: ControlElement): ControlElement => {
      const bindings = element.bindings.slice();
      while (bindings.length <= slotIndex) {
        bindings.push({ kind: InputBindingKind.NONE, code: 0 });
      }
      bindings[slotIndex] = binding;
      return this.withElement(element, { bindings: bindings });
    });
  }

  private addRangeKey(code: number): void {
    this.updateSelectedElement((element: ControlElement): ControlElement => {
      const keyList = element.keyList ?? [];
      if (keyList.indexOf(code) >= 0 || keyList.length >= 8) return element;
      const next = keyList.slice();
      next.push(code);
      return this.withElement(element, {
        keyList: next,
        bindings: next.length > 0 ? [keyBinding(next[0])] : []
      });
    });
  }

  private removeRangeKey(code: number): void {
    this.updateSelectedElement((element: ControlElement): ControlElement => {
      const keyList = (element.keyList ?? []).filter((value: number): boolean => value !== code);
      return this.withElement(element, {
        keyList: keyList,
        bindings: keyList.length > 0 ? [keyBinding(keyList[0])] : []
      });
    });
  }

  private pickerOptions(): PickerOption[] {
    const options: PickerOption[] = [
      { label: '无绑定', name: 'NONE', kind: InputBindingKind.NONE, code: 0 },
      { label: '鼠标左键', name: 'MOUSE_LEFT_BUTTON', kind: InputBindingKind.MOUSE, code: MOUSE_LEFT_BUTTON },
      { label: '鼠标右键', name: 'MOUSE_RIGHT_BUTTON', kind: InputBindingKind.MOUSE, code: MOUSE_RIGHT_BUTTON },
      { label: '鼠标中键', name: 'MOUSE_MIDDLE_BUTTON', kind: InputBindingKind.MOUSE, code: MOUSE_MIDDLE_BUTTON }
    ];
    for (let index = 0; index < KEY_NAME_OPTIONS.length; index++) {
      const option = KEY_NAME_OPTIONS[index];
      options.push({ label: option.label, name: option.name, kind: InputBindingKind.KEY, code: option.code });
    }
    return options;
  }

  private applyPickerSelection(option: PickerOption): void {
    if (this.pickerTargetKeyList && option.kind === InputBindingKind.KEY && option.code > 0) {
      this.addRangeKey(option.code);
    } else if (this.pickerTargetSlot >= 0) {
      this.setBindingSlot(this.pickerTargetSlot, {
        kind: option.kind, code: option.code
      });
    }
    this.pickerOpen = false;
    this.pickerTargetSlot = -1;
    this.pickerTargetKeyList = false;
  }

  private applyCustomKey(): void {
    const parsed = Number(this.customKeyText.trim());
    if (!parsed || Number.isNaN(parsed) || parsed <= 0) {
      promptAction.showToast({ message: '请输入有效的键码（如 57=空格、17=W）' });
      return;
    }
    if (this.pickerTargetSlot >= 0) {
      this.setBindingSlot(this.pickerTargetSlot, keyBinding(Math.round(parsed)));
      this.pickerOpen = false;
      this.pickerTargetSlot = -1;
    } else if (this.pickerTargetKeyList) {
      this.addRangeKey(Math.round(parsed));
      this.pickerOpen = false;
      this.pickerTargetKeyList = false;
    }
    this.customKeyText = '';
  }

  private openSlotPicker(slotIndex: number): void {
    this.pickerTargetSlot = slotIndex;
    this.pickerTargetKeyList = false;
    this.pickerOpen = true;
  }

  private openKeyListPicker(): void {
    this.pickerTargetSlot = -1;
    this.pickerTargetKeyList = true;
    this.pickerOpen = true;
  }

  private bindingLabel(binding: InputBinding | undefined): string {
    if (!binding || binding.kind === InputBindingKind.NONE || binding.code <= 0) return '未绑定';
    if (binding.kind === InputBindingKind.MOUSE) {
      if (binding.code === MOUSE_LEFT_BUTTON) return '鼠标左键';
      if (binding.code === MOUSE_RIGHT_BUTTON) return '鼠标右键';
      if (binding.code === MOUSE_MIDDLE_BUTTON) return '鼠标中键';
      return '鼠标 ' + binding.code.toString();
    }
    return keyNameLabel(binding.code);
  }

  // ---- 编辑器 UI ----

  @Builder
  private FloatingButton(icon: string, accent: string, action: () => void, id: string, size: number = 38) {
    Text(icon).fontSize(size >= 44 ? 18 : 15).fontColor(accent).width(size).height(size)
      .textAlign(TextAlign.Center)
      .backgroundColor('#E8181818').borderRadius(size / 2).border({ width: 1.5, color: accent })
      .shadow({ radius: 4, color: '#88000000' })
      .id(id).onClick(action)
  }

  @Builder
  private ToolbarChip(label: string, accent: string, action: () => void, id: string) {
    Text(label).fontSize(12).fontColor('#FFFFFFFF').padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor('#E8181818').borderRadius(16).border({ width: 1, color: accent })
      .id(id).onClick(action)
  }

  @Builder
  private AddElementBar() {
    Row({ space: 8 }) {
      Text('添加').fontSize(12).fontColor('#FFFFFF88')
      this.ToolbarChip('按钮', '#FF2196F3', (): void => this.addElement(ControlElementType.BUTTON), 'editor-add-button')
      this.ToolbarChip('方向键', '#FF4CAF50', (): void => this.addElement(ControlElementType.D_PAD), 'editor-add-dpad')
      this.ToolbarChip('摇杆', '#FF8BC34A', (): void => this.addElement(ControlElementType.STICK), 'editor-add-stick')
      this.ToolbarChip('触摸板', '#FFFFB74D', (): void => this.addElement(ControlElementType.TRACKPAD), 'editor-add-trackpad')
      this.ToolbarChip('滚动键', '#FF64B5F6', (): void => this.addElement(ControlElementType.RANGE_BUTTON), 'editor-add-range')
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#AA111111').borderRadius(20).border({ width: 1, color: '#44FFFFFF' })
  }

  @Builder
  private ActionBar() {
    Row({ space: 8 }) {
      this.FloatingButton('✕', '#FFFF5252', (): void => { this.finishEditor(); }, 'input-layout-back')
      this.FloatingButton('↺', '#FFFFB74D', (): void => { this.reset(); }, 'input-layout-reset')
      this.FloatingButton('⧉', '#FFAB47BC', (): void => { this.duplicateSelectedElement(); }, 'input-layout-duplicate')
      this.FloatingButton('🗑', '#FFFF5252', (): void => { this.removeSelectedElement(); }, 'input-layout-delete')
      Text('✓').fontSize(18).fontColor('#FFFFFFFF').width(44).height(44).textAlign(TextAlign.Center)
        .backgroundColor('#FF2979FF').borderRadius(22).border({ width: 1.5, color: '#FFFFFFFF' })
        .shadow({ radius: 6, color: '#66000000' })
        .id('input-layout-save').onClick((): void => { this.save(); })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#AA111111').borderRadius(22).border({ width: 1, color: '#44FFFFFF' })
  }

  @Builder
  private ShapeChip(label: string, shape: ControlElementShape) {
    Text(label).fontSize(11).fontColor(this.selectedElement()?.shape === shape ? '#FFFFFFFF' : '#FFFFFF99')
      .padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor(this.selectedElement()?.shape === shape ? '#335C8DFF' : '#18FFFFFF')
      .borderRadius(14).border({ width: 1, color: this.selectedElement()?.shape === shape ? '#FF64B5F6' : '#33FFFFFF' })
      .onClick((): void => {
        this.updateSelectedElement((element: ControlElement): ControlElement => this.withElement(element, { shape: shape }));
      })
  }

  @Builder
  private BindingSlots() {
    if (this.selectedElementId.length > 0) {
      if (this.selectedElement()?.type === ControlElementType.D_PAD ||
        this.selectedElement()?.type === ControlElementType.STICK) {
        Column({ space: 6 }) {
          Text('方向绑定（上/右/下/左）').fontSize(11).fontColor('#FFFFFFAA').width('100%')
          ForEach([0, 1, 2, 3], (slot: number): void => {
            Row({ space: 8 }) {
              Text(['上', '右', '下', '左'][slot]).fontSize(11).fontColor('#FFFFFF88').width(24)
              Text(this.bindingLabel(this.selectedElement()?.bindings[slot])).fontSize(12).fontColor('#FFFFFFFF')
                .layoutWeight(1).textAlign(TextAlign.Center)
                .padding({ top: 7, bottom: 7 }).backgroundColor('#335C8DFF')
                .borderRadius(10).border({ width: 1, color: '#55FFFFFF' })
                .onClick((): void => this.openSlotPicker(slot))
            }.width('100%')
          }, (slot: number): string => slot.toString())
        }.width('100%')
      } else if (this.selectedElement()?.type === ControlElementType.BUTTON) {
        Column({ space: 6 }) {
          Text('按键绑定（最多 4 个，同时按下）').fontSize(11).fontColor('#FFFFFFAA').width('100%')
          ForEach([0, 1, 2, 3], (slot: number): void => {
            Row({ space: 8 }) {
              Text(this.bindingLabel(this.selectedElement()?.bindings[slot])).fontSize(12).fontColor('#FFFFFFFF')
                .layoutWeight(1).textAlign(TextAlign.Center)
                .padding({ top: 7, bottom: 7 }).backgroundColor('#335C8DFF')
                .borderRadius(10).border({ width: 1, color: '#55FFFFFF' })
                .onClick((): void => this.openSlotPicker(slot))
            }.width('100%')
          }, (slot: number): string => slot.toString())
        }.width('100%')
      } else if (this.selectedElement()?.type === ControlElementType.RANGE_BUTTON) {
        Column({ space: 6 }) {
          Text('可选键列表（滑动选键，点按发送）').fontSize(11).fontColor('#FFFFFFAA').width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.selectedElement()?.keyList ?? [], (code: number): void => {
              Text(keyNameLabel(code) + ' ✕').fontSize(11).fontColor('#FFFFFFFF')
                .padding({ left: 9, right: 9, top: 6, bottom: 6 }).margin({ right: 6, bottom: 6 })
                .backgroundColor('#33404040').borderRadius(12).border({ width: 1, color: '#55FFFFFF' })
                .onClick((): void => this.removeRangeKey(code))
            }, (code: number): string => code.toString())
          }.width('100%')
          Text('＋ 添加键').fontSize(11).fontColor('#FF64B5F6')
            .padding({ left: 9, right: 9, top: 6, bottom: 6 })
            .backgroundColor('#18FFFFFF').borderRadius(12).border({ width: 1, color: '#55FFFFFF' })
            .onClick((): void => this.openKeyListPicker())
        }.width('100%')
      } else if (this.selectedElement()?.type === ControlElementType.TRACKPAD) {
        Text('触摸板不绑定按键：按住滑动移动鼠标，轻点发送左键。')
          .fontSize(11).fontColor('#FFFFFF88').width('100%')
      }
    }
  }

  @Builder
  private PropertyPanel() {
    if (this.selectedElementId.length > 0) {
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Row({ space: 7 }) {
              Text('▣').fontSize(12).fontColor('#FF64B5F6').fontWeight(FontWeight.Bold)
              Text('元素设置 · ' + elementTypeLabel(this.selectedElement()?.type ?? ControlElementType.BUTTON)).fontSize(13)
                .fontColor('#FFFFFFFF').fontWeight(FontWeight.Medium)
            }
            .layoutWeight(1)
            Text('✕').fontSize(14).fontColor('#FFFF5252').onClick((): void => { this.showPropertyPanel = false; })
          }
          .width('100%').height(28)
          if (this.overlapWarning().length > 0) {
            Text(this.overlapWarning()).fontSize(11).fontColor('#FFFF5252').width('100%')
          }
          Text('文字标签').fontSize(11).fontColor('#FFFFFFAA').width('100%')
          TextInput({ text: this.selectedElement()?.text ?? '', placeholder: '显示文字（可留空）' })
            .height(36).fontSize(12).fontColor('#FFFFFFFF')
            .backgroundColor('#22FFFFFF').borderRadius(8)
            .maxLength(12)
            .onChange((value: string): void => {
              this.updateSelectedElement((current: ControlElement): ControlElement => this.withElement(current, { text: value }));
            })
          Text('形状').fontSize(11).fontColor('#FFFFFFAA').width('100%')
          Row({ space: 8 }) {
            this.ShapeChip('圆形', ControlElementShape.CIRCLE)
            this.ShapeChip('方形', ControlElementShape.SQUARE)
            this.ShapeChip('圆角矩形', ControlElementShape.ROUND_RECT)
            this.ShapeChip('矩形', ControlElementShape.RECT)
          }.width('100%')
          if (this.selectedElement()?.type === ControlElementType.BUTTON ||
            this.selectedElement()?.type === ControlElementType.RANGE_BUTTON) {
            Row({ space: 8 }) {
              Text('开关模式').fontSize(11).fontColor('#FFFFFFAA')
              Text(this.selectedElement()?.toggleSwitch ? '开' : '关').fontSize(11)
                .fontColor(this.selectedElement()?.toggleSwitch ? '#FF64B5F6' : '#FFFFFF88')
                .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                .backgroundColor(this.selectedElement()?.toggleSwitch ? '#335C8DFF' : '#18FFFFFF')
                .borderRadius(12).border({ width: 1, color: '#44FFFFFF' })
                .onClick((): void => {
                  this.updateSelectedElement((current: ControlElement): ControlElement =>
                    this.withElement(current, { toggleSwitch: !current.toggleSwitch }));
                })
            }.width('100%')
          }
          Text('缩放 ' + Math.round((this.selectedElement()?.scale ?? 1) * 100) + '%')
            .fontSize(11).fontColor('#FFFFFFAA').width('100%')
          Slider({ value: (this.selectedElement()?.scale ?? 1) * 100, min: 50, max: 200, step: 5, style: SliderStyle.OutSet })
            .width('100%').blockColor('#FF64B5F6').selectedColor('#FF64B5F6').trackColor('#FFFFFF22')
            .onChange((value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.scaleElement(this.selectedElementId, value / 100);
              }
            })
          Row({ space: 8 }) {
            Text('透明度 ' + ((this.selectedElement()?.opacity ?? -1) >= 0 ?
              Math.round(this.selectedElement()?.opacity ?? 70) : 100) + '%')
              .fontSize(11).fontColor('#FFFFFFAA')
            Text((this.selectedElement()?.opacity ?? -1) >= 0 ? '自定义' : '继承方案')
              .fontSize(11).fontColor((this.selectedElement()?.opacity ?? -1) >= 0 ? '#FF64B5F6' : '#FFFFFF88')
              .padding({ left: 9, right: 9, top: 6, bottom: 6 })
              .backgroundColor((this.selectedElement()?.opacity ?? -1) >= 0 ? '#335C8DFF' : '#18FFFFFF')
              .borderRadius(12).border({ width: 1, color: '#44FFFFFF' })
              .onClick((): void => {
                this.updateSelectedElement((current: ControlElement): ControlElement =>
                  this.withElement(current, { opacity: current.opacity >= 0 ? -1 : 70 }));
              })
          }.width('100%')
          if ((this.selectedElement()?.opacity ?? -1) >= 0) {
            Slider({ value: this.selectedElement()?.opacity ?? 70, min: 10, max: 100, step: 5, style: SliderStyle.OutSet })
              .width('100%').blockColor('#FFAB47BC').selectedColor('#FFAB47BC').trackColor('#FFFFFF22')
              .onChange((value: number, mode: SliderChangeMode): void => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.updateSelectedElement((current: ControlElement): ControlElement =>
                    this.withElement(current, { opacity: value }));
                }
              })
          }
          this.BindingSlots()
          Text('提示：拖动元素调整位置，双指捏合缩放；删除/复制按钮在下方操作栏。')
            .fontSize(10).fontColor('#FFFFFF88').width('100%')
        }
        .width('100%').padding(14)
      }
      .width(280)
      .constraintSize({ maxHeight: Math.max(200, this.previewH - 150) })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor('#EE111111').borderRadius(14).border({ width: 1, color: '#44FFFFFF' })
      .position({ x: Math.max(8, this.previewW - 288), y: 64 }).zIndex(100).id('vintage-layout-config')
    }
  }

  @Builder
  private KeyPicker() {
    Column({ space: 10 }) {
      Row() {
        Text(this.pickerTargetKeyList ? '添加可选键' : '选择绑定键').fontSize(14)
          .fontColor('#FFFFFFFF').fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('✕').fontSize(16).fontColor('#FFFF5252').onClick((): void => {
          this.pickerOpen = false;
          this.pickerTargetSlot = -1;
          this.pickerTargetKeyList = false;
        })
      }.width('100%')
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.pickerOptions(), (option: PickerOption): void => {
            Row({ space: 10 }) {
              Text(option.label).fontSize(13).fontColor('#FFFFFFFF').layoutWeight(1)
              Text(option.name).fontSize(10).fontColor('#FFFFFF77')
            }
            .width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .backgroundColor('#22FFFFFF').borderRadius(10)
            .onClick((): void => this.applyPickerSelection(option))
          }, (option: PickerOption): string => option.kind + ':' + option.code.toString())
        }.width('100%')
      }
      .constraintSize({ maxHeight: this.previewH * 0.52 })
      .scrollBar(BarState.Off)
      Row({ space: 8 }) {
        TextInput({ text: this.customKeyText, placeholder: '自定义键码（如 57）' })
          .height(36).layoutWeight(1).fontSize(12).fontColor('#FFFFFFFF')
          .backgroundColor('#22FFFFFF').borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string): void => { this.customKeyText = value; })
        Text('应用').fontSize(12).fontColor('#FF64B5F6').padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#335C8DFF').borderRadius(12)
          .onClick((): void => this.applyCustomKey())
      }.width('100%')
    }
    .width(320).padding(16)
    .backgroundColor('#EE15151F').borderRadius(16).border({ width: 1, color: '#55FFFFFF' })
    .position({ x: '50%', y: '50%' }).translate({ x: '-50%', y: '-50%' }).zIndex(200)
  }

  build() {
    Column() {
      if (this.safeAreaTop > 0) {
        Row().width('100%').height(this.safeAreaTop + 'px').backgroundColor('#FF000000')
      }
      Stack() {
        Column().width('100%').height('100%').backgroundColor('#FF1A1A2E')
        Stack() {
          VirtualInputOverlay({
            profile: this.profile,
            renderRevision: this.previewRevision,
            interactive: false,
            hideToolbar: true,
            editMode: true,
            selectedElementId: this.selectedElementId,
            onElementMove: (id: string, x: number, y: number): void => this.moveElement(id, x, y),
            onElementScale: (id: string, scale: number): void => this.scaleElement(id, scale),
            onElementSelected: (id: string): void => {
              this.selectedElementId = id;
              this.showPropertyPanel = id.length > 0;
            }
          })
            .width('100%').height('100%')
          Text('当前画面画布')
            .fontSize(10).fontColor('#FFFFFF66').padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#44000000').borderRadius(6)
            .position({ x: 8, y: 6 }).id('editor-canvas-label')
        }
        .width(this.canvasWidth()).height(this.canvasHeight())
        .border({ width: 1, color: '#33FFFFFF' }).borderRadius(8)
        .position({ x: this.canvasLeft(), y: this.canvasTop() })
        .id('editor-canvas')
        Column({ space: 6 }) {
          Text('点按选中 · 拖动移动 · 双指缩放 · 位置与缩放实时预览')
            .fontSize(10).fontColor('#FFFFFF88').padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#66000000').borderRadius(6)
            .id('editor-hint')
        }
        .position({ x: 16, y: 14 }).alignItems(HorizontalAlign.Start)
        Row({ space: 12 }) {
          this.AddElementBar()
          this.ActionBar()
        }
        .position({ x: '50%', y: '100%' }).translate({ x: '-50%', y: -64 })
        .zIndex(120)
        if (this.showPropertyPanel && this.selectedElementId.length > 0) {
          this.PropertyPanel()
        }
        if (this.pickerOpen) {
          Column().width('100%').height('100%').backgroundColor('#66000000')
            .onClick((): void => {
              this.pickerOpen = false;
              this.pickerTargetSlot = -1;
              this.pickerTargetKeyList = false;
            })
          this.KeyPicker()
        }
      }
      .width('100%').height('100%')
      .onAreaChange((_oldValue: Area, area: Area): void => {
        this.previewW = area.width as number;
        this.previewH = area.height as number;
      })
    }
    .width('100%').height('100%').backgroundColor('#FF1A1A2E')
  }
}
