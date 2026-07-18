#!/usr/bin/env node

const assert = require('node:assert/strict');
const path = require('node:path');

const outputDirectory = process.argv[2];
if (!outputDirectory) {
  throw new Error('compiled model directory is required');
}

const models = require(path.resolve(outputDirectory, 'AppModels.js'));
const rules = require(path.resolve(outputDirectory, 'AppCatalogRules.js'));

assert.equal(rules.catalogFileName('D:/Games/Demo/Game.exe'), 'Game.exe');
assert.equal(rules.catalogNameWithoutExtension('Game.EXE'), 'Game');
assert.equal(
  rules.chooseExecutablePath('/games/Demo', [
    '/games/Demo/setup.exe',
    '/games/Demo/Demo.exe',
    '/games/Demo/bin/helper.exe'
  ]),
  '/games/Demo/Demo.exe'
);
assert.equal(
  rules.chooseExecutablePath('/games/Demo', [
    '/games/Demo/setup.exe',
    '/games/Demo/crashreporter.exe',
    '/games/Demo/Game.exe'
  ]),
  '/games/Demo/Game.exe'
);
assert.equal(
  rules.chooseExecutablePath('/games/Demo', [
    '/games/Demo/Game.exe',
    '/games/Demo/Launcher.exe'
  ]),
  ''
);
assert.equal(
  rules.chooseExecutablePath('/games/Demo', ['/games/Demo/setup.exe']),
  ''
);
assert.equal(
  rules.chooseCoverFileName(['readme.txt', 'folder.png', 'cover.jpg']),
  'cover.jpg'
);
assert.equal(
  rules.chooseCoverFileName(['folder.webp', 'screenshot.png']),
  'folder.webp'
);

assert.equal(models.normalizeLaunchPath(' C:\\Games\\Demo\\Game.EXE '), 'c:/games/demo/game.exe');
assert.equal(
  models.stableAppId(models.AppSource.DOWNLOAD, 'C:\\Games\\Demo\\Game.EXE'),
  models.stableAppId(models.AppSource.DOWNLOAD, 'c:/games/demo/game.exe')
);
assert.equal(
  models.resolveDisplayMode(null, models.DisplayMode.DESKTOP),
  models.DisplayMode.DESKTOP
);
assert.equal(
  models.resolveDisplayMode(models.DisplayMode.SINGLE_APP, models.DisplayMode.DESKTOP),
  models.DisplayMode.SINGLE_APP
);
assert.equal(
  models.canTransitionEngineState(models.EngineState.STOPPED, models.EngineState.PREPARING),
  true
);
assert.equal(
  models.canTransitionEngineState(models.EngineState.PREPARING, models.EngineState.READY),
  true
);
assert.equal(
  models.canTransitionEngineState(models.EngineState.READY, models.EngineState.PREPARING),
  false
);

console.log('catalog/model unit tests: 15 passed');
