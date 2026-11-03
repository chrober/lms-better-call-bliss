const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/settings/bettercallbliss.html', 'utf8');
for (const id of ['preview_history_limit', 'preview_history_days']) {
  assert.match(html, new RegExp('<input[^>]*class="[^"]*optional-number-autosize[^"]*"[^>]*id="' + id + '"'), id + ' participates in autosizing');
}
const match = html.match(/function sizeOptionalNumberFields\(\) \{[\s\S]*?\n  \}/);
assert.ok(match, 'settings page provides dynamic optional-number sizing');
const listeners = {};
const inputs = [
  { placeholder: 'Automatisch', value: '', style: {}, addEventListener: (name, fn) => { listeners[name] = fn; } },
  { placeholder: 'Very long future translation', value: '1', style: {}, addEventListener() {} }
];
const context = {
  document: { querySelectorAll: selector => { assert.strictEqual(selector, 'input.optional-number-autosize'); return inputs; }, createElement: () => ({ getContext: () => ({ measureText: t => ({width: t.length * 10}) }) }) },
  window: { getComputedStyle: () => ({font: '15px sans-serif', paddingLeft: '0px', paddingRight: '0px', borderLeftWidth: '0px', borderRightWidth: '0px'}) }
};
vm.runInNewContext(match[0] + '\nsizeOptionalNumberFields();', context);
assert.ok(parseFloat(inputs[1].style.width) > parseFloat(inputs[0].style.width), 'longer translations get a wider field');
assert.ok(parseFloat(inputs[0].style.width) > 110, 'placeholder leaves room for the number controls');
assert.strictEqual(inputs[0].style.maxWidth, '100%', 'width remains constrained by the container');
inputs[0].value = '12345678901234567890';
listeners.input();
assert.ok(parseFloat(inputs[0].style.width) > 200, 'field also accommodates a longer entered value');
console.log('Better Call Bliss optional number widths: ok');
