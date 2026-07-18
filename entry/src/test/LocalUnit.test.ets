import { describe, it, expect } from '@ohos/hypium';
import { chooseCoverFileName, chooseExecutablePath } from '../main/ets/model/AppCatalogRules';
import {
  AppSource,
  DisplayMode,
  EngineState,
  canTransitionEngineState,
  normalizeLaunchPath,
  resolveDisplayMode,
  stableAppId
} from '../main/ets/model/AppModels';

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
  });
}
