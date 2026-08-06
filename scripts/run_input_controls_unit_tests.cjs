#!/usr/bin/env node

// 虚拟输入控件 v6 模型单测。
// 用法：node scripts/run_input_controls_unit_tests.cjs <compiled-model-dir>
// compiled-model-dir 需包含 model/AppModels.js 与 common/EvdevKeyNames.js
// （由 tsc 编译 entry/src/main/ets 中的对应 .ets 得到）。

const assert = require('node:assert/strict');
const path = require('node:path');

const outputDirectory = process.argv[2];
if (!outputDirectory) {
  throw new Error('compiled model directory is required');
}

const models = require(path.resolve(outputDirectory, 'model/AppModels.js'));
const keynames = require(path.resolve(outputDirectory, 'common/EvdevKeyNames.js'));

// ---- 模板工厂 ----
assert.equal(models.INPUT_TEMPLATES.length, 3);
assert.equal(models.INPUT_PROFILE_SCHEMA_VERSION, 6);

const generic = models.createDefaultInputProfile();
assert.equal(generic.id, 'default');
assert.equal(generic.schemaVersion, 6);
assert.ok(generic.elements.length >= 8, '默认模板应包含至少 8 个元素');
assert.ok(generic.gamepadMappings.length >= 10, '默认手柄映射应保留');

const shooter = models.createInputProfileFromTemplate('p1', '射击方案', 'shooter');
assert.equal(shooter.name, '射击方案');
assert.equal(shooter.elements.length, 10);
assert.equal(shooter.elements[0].type, 'D_PAD');
assert.equal(shooter.elements[0].bindings.length, 4);
assert.equal(shooter.elements[0].bindings[0].kind, 'KEY');
assert.equal(shooter.elements[0].bindings[0].code, 17); // W
assert.equal(shooter.elements[1].type, 'TRACKPAD');
assert.ok(shooter.elements.some((e) => e.type === 'RANGE_BUTTON' && e.keyList.length >= 4));

const action = models.createInputProfileFromTemplate('p2', '动作方案', 'action');
assert.equal(action.elements[0].type, 'STICK');
assert.equal(action.elements[1].type, 'STICK');
assert.equal(action.elements[1].bindings[0].code, 103); // 上

// ---- 克隆与序列化往返 ----
const cloned = models.cloneInputProfile(generic);
assert.equal(JSON.stringify(cloned), JSON.stringify(generic));
const roundtrip = models.cloneInputProfile(JSON.parse(JSON.stringify(generic)));
assert.equal(roundtrip.elements.length, generic.elements.length);
assert.equal(roundtrip.overlayOpacity, generic.overlayOpacity);

// ---- 真实 Winlator GTA5 .icp 片段导入 ----
const gtaFragment = JSON.stringify({
  id: 16,
  name: 'GTA 5',
  cursorSpeed: 1,
  elements: [
    {
      type: 'BUTTON',
      shape: 'CIRCLE',
      bindings: ['MOUSE_LEFT_BUTTON', 'NONE', 'NONE', 'NONE'],
      scale: 1,
      x: 0.813,
      y: 0.733,
      toggleSwitch: false,
      text: '',
      iconId: 0
    },
    {
      type: 'BUTTON',
      shape: 'RECT',
      bindings: ['KEY_SHIFT_L', 'NONE', 'NONE', 'NONE'],
      scale: 1,
      x: 0.078,
      y: 0.088,
      toggleSwitch: true,
      text: '',
      iconId: 0
    },
    {
      type: 'STICK',
      shape: 'CIRCLE',
      bindings: ['KEY_W', 'KEY_D', 'KEY_S', 'KEY_A'],
      scale: 1,
      x: 0.107,
      y: 0.733,
      toggleSwitch: false,
      text: '',
      iconId: 0
    },
    {
      type: 'UNKNOWN_TYPE',
      shape: 'CIRCLE',
      bindings: ['KEY_Q'],
      scale: 1,
      x: 0.5,
      y: 0.5
    }
  ]
});

const imported = models.importProfileFromIcpJson(gtaFragment, 'desktop-test');
assert.equal(imported.schemaVersion, 6);
assert.equal(imported.name, 'GTA 5');
assert.equal(imported.elements.length, 3, '未知元素类型应跳过');
assert.equal(imported.elements[0].type, 'BUTTON');
assert.equal(imported.elements[0].bindings[0].kind, 'MOUSE');
assert.equal(imported.elements[0].bindings[0].code, 272);
assert.equal(imported.elements[0].shape, 'CIRCLE');
assert.equal(imported.elements[1].toggleSwitch, true);
assert.equal(imported.elements[1].bindings[0].code, 42); // Shift
assert.equal(imported.elements[2].type, 'STICK');
assert.deepEqual(imported.elements[2].bindings.map((b) => b.code), [17, 32, 31, 30]);

// ---- 导出为 .icp 兼容子集 ----
const exportedJson = models.exportProfileToIcpJson(shooter);
const exported = JSON.parse(exportedJson);
assert.equal(exported.name, '射击方案');
assert.equal(exported.cursorSpeed, 1);
assert.equal(exported.elements.length, shooter.elements.length);
assert.ok(exported.elements.every((e) =>
  e.bindings !== undefined && e.bindings.length === 4));
assert.equal(exported.elements[0].bindings[0], 'KEY_W');

const reimported = models.importProfileFromIcpJson(exportedJson, 'desktop-roundtrip');
assert.equal(reimported.elements.length, shooter.elements.length);
assert.equal(reimported.elements[0].type, 'D_PAD');
assert.deepEqual(reimported.elements[0].bindings.map((b) => b.code), [17, 32, 31, 30]);

// ---- 绑定名映射表 ----
assert.equal(keynames.evdevNameToBinding('KEY_W').code, 17);
assert.equal(keynames.evdevNameToBinding('KEY_W').kind, 'KEY');
assert.equal(keynames.evdevNameToBinding('MOUSE_LEFT_BUTTON').code, 272);
assert.equal(keynames.evdevNameToBinding('MOUSE_LEFT_BUTTON').kind, 'MOUSE');
assert.equal(keynames.evdevNameToBinding('KEY_SHIFT_L').code, 42);
assert.equal(keynames.evdevNameToBinding('KEY_ESCAPE').code, 1); // 别名
assert.equal(keynames.evdevNameToBinding('KEY_LEFTCTRL').code, 29); // 别名
assert.equal(keynames.evdevNameToBinding('NONE').kind, 'NONE');
assert.equal(keynames.evdevNameToBinding('KEY_NOT_EXIST').kind, 'NONE');
assert.equal(keynames.evdevNameToBinding('').kind, 'NONE');
assert.equal(keynames.bindingToEvdevName('KEY', 17), 'KEY_W');
assert.equal(keynames.bindingToEvdevName('MOUSE', 273), 'MOUSE_RIGHT_BUTTON');
assert.equal(keynames.bindingToEvdevName('KEY', 0), 'NONE');

// 全量映射表可解析：每个导出名都能导入回同一码
for (const option of keynames.KEY_NAME_OPTIONS) {
  const parsed = keynames.evdevNameToBinding(option.name);
  assert.equal(parsed.kind, 'KEY', option.name);
  assert.equal(parsed.code, option.code, option.name);
}

console.log('input controls v6 unit tests passed');
