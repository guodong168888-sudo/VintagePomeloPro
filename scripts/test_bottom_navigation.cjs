#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '/apps/harmony/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const file = path.join(root, 'entry/src/main/ets/model/BottomNavigationLayout.ets');
const exportsValue = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsValue });
const layout = exportsValue.bottomNavigationLayout;
for (const landscape of [false, true]) {
  for (const inset of [0, 12, 24, 48, -3, NaN]) {
    const value = layout(landscape, inset);
    assert.equal(value.barHeight, 56);
    assert(value.bottomMargin >= (Number.isFinite(inset) ? Math.max(0, inset) : 0));
    assert.equal(value.containerHeight, value.barHeight + value.bottomMargin + 12);
    assert.equal(value.contentInset, value.containerHeight + 8);
  }
}
const page = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
const tab = page.slice(page.indexOf('private PhoneNavigationTab('), page.indexOf('private PhoneNavigationContents('));
assert(tab.includes(".height('100%')"));
assert(tab.includes('.justifyContent(FlexAlign.Center)'));
assert(tab.includes('.alignItems(HorizontalAlign.Center)'));
assert(!/\.height\(\d+\)/.test(tab));
assert(page.includes('return bottomNavigationLayout(this.isPhoneLandscape(), this.navBarInsetVp).contentInset;'));
console.log('Bottom navigation: slot ownership, shared inset and portrait/landscape safe-area tests passed');
