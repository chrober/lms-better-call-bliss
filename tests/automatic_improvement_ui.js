const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const template = fs.readFileSync('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html', 'utf8');
const start = template.indexOf('    function automaticImprovementState(');
const end = template.indexOf('    function synchronizeControls()', start);
assert(start >= 0 && end > start, 'automatic improvement state is available');
const context = {};
vm.runInNewContext(template.slice(start, end), context);
const state = context.automaticImprovementState;
assert.strictEqual(state(true, true, false).showThreshold, false);
assert.strictEqual(state(true, false, true).showThreshold, true);
assert.strictEqual(state(true, false, false).invalid, true);
assert.strictEqual(state(true, true, true).invalid, false);
assert.strictEqual(state(false, false, false).invalid, false);
console.log('PASS: automatic improvement goal controls');
