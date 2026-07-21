import { describe, it, expect } from '@ohos/hypium';
import { chooseCoverFileName, chooseExecutablePath } from '../main/ets/model/AppCatalogRules';
import {
  AppSource,
  ControlBarDirection,
  DEFAULT_VIRTUAL_MOUSE_CONFIG,
  DisplayMode,
  EngineState,
  VirtualKey,
  canTransitionEngineState,
  cloneVirtualMouseConfig,
  createDefaultGlobalSettings,
  createDefaultInputProfile,
  normalizeLaunchPath,
  resolveDisplayMode,
  resolveInputProfileId,
  resolveVirtualKeyMapping,
  stableAppId
} from '../main/ets/model/AppModels';
import { InputStateTracker } from '../main/ets/service/InputStateTracker';
import { InputEventGate } from '../main/ets/service/InputEventGate';

export default function localUnitTest() {
  describe('WineEngineApplicationArchitecture', () => {
    it('selectsDirectoryNamedExecutableFirst', 0, () => {
      const chosen = chooseExecutablePath('/games/Foo Game', [
        '/games/Foo Game/setup.exe',
        '/games/Foo Game/FooGame.exe',
        '/games/Foo Game/tools.exe'
      ]);
      expect(chosen).assertEqual('/games/Foo Game/FooGame.exe');
    });

    it('rejectsAmbiguousExecutableSelection', 0, () => {
      const chosen = chooseExecutablePath('/games/Unknown', [
        '/games/Unknown/client.exe', '/games/Unknown/launcher.exe'
      ]);
      expect(chosen).assertEqual('');
    });

    it('excludesInstallerWhenOnlyOneRunnableCandidateRemains', 0, () => {
      const chosen = chooseExecutablePath('/games/Unknown', [
        '/games/Unknown/setup.exe', '/games/Unknown/play.exe'
      ]);
      expect(chosen).assertEqual('/games/Unknown/play.exe');
    });

    it('doesNotSelectInstallerAsTheMainExecutable', 0, () => {
      expect(chooseExecutablePath('/games/SetupOnly', ['/games/SetupOnly/setup.exe'])).assertEqual('');
    });

    it('usesCoverBeforeFolderArt', 0, () => {
      expect(chooseCoverFileName(['folder.png', 'Cover.JPG'])).assertEqual('Cover.JPG');
    });

    it('normalizesPathForSingletonAndStableId', 0, () => {
      expect(normalizeLaunchPath(' C:\\Games\\Foo\\FOO.EXE ')).assertEqual('c:/games/foo/foo.exe');
      expect(stableAppId(AppSource.DOWNLOAD, 'C:\\Games\\Foo.exe'))
        .assertEqual(stableAppId(AppSource.DOWNLOAD, 'c:/games/foo.exe'));
    });

    it('resolvesPerAppDisplayModeOverride', 0, () => {
      expect(resolveDisplayMode(null, DisplayMode.DESKTOP)).assertEqual(DisplayMode.DESKTOP);
      expect(resolveDisplayMode(DisplayMode.SINGLE_APP, DisplayMode.DESKTOP)).assertEqual(DisplayMode.SINGLE_APP);
    });

    it('validatesEngineStateMachine', 0, () => {
      expect(canTransitionEngineState(EngineState.STOPPED, EngineState.PREPARING)).assertTrue();
      expect(canTransitionEngineState(EngineState.PREPARING, EngineState.READY)).assertTrue();
      expect(canTransitionEngineState(EngineState.PREPARING, EngineState.SWITCHING)).assertTrue();
      expect(canTransitionEngineState(EngineState.STOPPED, EngineState.READY)).assertFalse();
    });

    it('placesShoulderControlsOnTheirPhysicalControllerSides', 0, () => {
      const layout = createDefaultInputProfile().layoutLandscape;
      expect(layout.leftTrigger.centerX < 0.5).assertTrue();
      expect(layout.leftBumper.centerX < 0.5).assertTrue();
      expect(layout.rightBumper.centerX > 0.5).assertTrue();
      expect(layout.rightTrigger.centerX > 0.5).assertTrue();
      expect(layout.leftTrigger.centerY < layout.direction.centerY).assertTrue();
      expect(layout.rightTrigger.centerY < layout.action.centerY).assertTrue();
    });

    it('usesVintageControlBarAndFullScreenMouseDefaults', 0, () => {
      const settings = createDefaultGlobalSettings();
      expect(settings.controlBarDirection).assertEqual(ControlBarDirection.AUTO);
      expect(settings.virtualMouseConfig.mouseSensitivity).assertEqual(100);
      expect(settings.virtualMouseConfig.doubleClickInterval).assertEqual(100);
      expect(settings.virtualMouseConfig.showCursor).assertTrue();
    });

    it('clonesVirtualMouseSettingsWithoutSharingMutableState', 0, () => {
      const cloned = cloneVirtualMouseConfig(DEFAULT_VIRTUAL_MOUSE_CONFIG);
      cloned.mouseSensitivity = 180;
      expect(DEFAULT_VIRTUAL_MOUSE_CONFIG.mouseSensitivity).assertEqual(100);
      expect(cloned.mouseSensitivity).assertEqual(180);
    });

    it('resolvesDesktopAndPerGameInputProfilesExplicitly', 0, () => {
      expect(resolveInputProfileId('default', 'desktop-custom')).assertEqual('desktop-custom');
      expect(resolveInputProfileId('app-game', 'desktop-custom')).assertEqual('app-game');
      expect(resolveInputProfileId('', '')).assertEqual('default');
    });

    it('appliesEditedVirtualKeyMappingAtRuntime', 0, () => {
      const profile = createDefaultInputProfile();
      const changed = profile.virtualKeyMappings.map((mapping) => mapping.virtualKey === VirtualKey.BUTTON_A ?
        { virtualKey: mapping.virtualKey, evdevCode: 28, keyLabel: 'Enter' } : mapping);
      expect(resolveVirtualKeyMapping(changed, VirtualKey.BUTTON_A, 57)).assertEqual(28);
    });

    it('keepsSharedVirtualKeyPressedUntilEverySourceReleases', 0, () => {
      const tracker = new InputStateTracker();
      expect(tracker.pressKey('touch-a', 28)).assertTrue();
      expect(tracker.pressKey('gamepad-a', 28)).assertFalse();
      expect(tracker.releaseKey('touch-a', 28)).assertFalse();
      expect(tracker.releaseKey('gamepad-a', 28)).assertTrue();
      expect(tracker.snapshot().heldKeys).assertEqual(0);
    });

    it('releasesPointersKeysAndButtonsOnSessionCancellation', 0, () => {
      const tracker = new InputStateTracker();
      tracker.markPointer('pointer-1');
      tracker.pressKey('pointer-1', 57);
      tracker.pressButton('pointer-1', 272);
      const released = tracker.releaseAll();
      expect(released.keys[0]).assertEqual(57);
      expect(released.buttons[0]).assertEqual(272);
      expect(tracker.snapshot().activePointers).assertEqual(0);
      expect(tracker.snapshot().heldKeys).assertEqual(0);
      expect(tracker.snapshot().heldButtons).assertEqual(0);
    });

    it('routesOnePhysicalActionThroughOnlyOnePointerChannel', 0, () => {
      const gate = new InputEventGate(320);
      expect(gate.shouldHandleTouch(2, 1, 1000)).assertTrue();
      expect(gate.shouldHandleMouse(2, 1, 1001)).assertFalse();
      expect(gate.shouldHandleTouch(1, 3, 2000)).assertFalse();
      expect(gate.shouldHandleMouse(1, 3, 2000)).assertTrue();
    });

    it('suppressesUnknownSyntheticMouseAfterTouch', 0, () => {
      const gate = new InputEventGate(320);
      expect(gate.shouldHandleTouch(0, 0, 1000)).assertTrue();
      expect(gate.shouldHandleMouse(0, 0, 1200)).assertFalse();
      expect(gate.shouldHandleMouse(0, 0, 1400)).assertTrue();
    });
  });
}
