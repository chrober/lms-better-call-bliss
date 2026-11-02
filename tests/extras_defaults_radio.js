const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const template = fs.readFileSync('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html', 'utf8');
const radios = [...template.matchAll(/<input\b[^>]*type="radio"[^>]*name="extras_defaults_source"[^>]*>/g)];
assert.strictEqual(radios.length, 2, 'defaults source has two radio inputs');
assert(radios.some(m => /value="plugin"/.test(m[0])));
assert(radios.some(m => /value="extras"/.test(m[0]) && /has_profile/.test(m[0])));
assert(!/<select\b[^>]*name="extras_defaults_source"/.test(template));

const start = template.indexOf('    var defaultsSources =');
const end = template.indexOf('    if (mainForm && submit)', start);
assert(start >= 0 && end > start, 'radio selection behavior exists');
const script = template.slice(start, end);

async function exercise(fail, unavailable = false) {
  const plugin = {value: 'plugin', checked: true, disabled: false};
  const extras = {value: 'extras', checked: false, disabled: unavailable};
  const controls = [plugin, extras];
  controls.forEach(c => { c.addEventListener = (_, fn) => { c.change = fn; }; });
  const status = {textContent: ''};
  const load = {disabled: false};
  const save = {disabled: false};
  let sent;
  const context = {
    document: {
      querySelectorAll: () => controls,
      getElementById: id => ({extras_defaults_selection_status: status,
        load_extras_defaults: load, save_extras_defaults: save})[id],
    },
    mainForm: {action: '/extras'}, window: {fetch: true},
    fetch: (_, options) => { sent = options.body; return fail
      ? Promise.reject(new Error('offline'))
      : Promise.resolve({ok: true, text: () => Promise.resolve('ok')}); },
    encodeURIComponent,
  };
  vm.runInNewContext(script, context);
  if (!unavailable) { plugin.checked = false; extras.checked = true; }
  (unavailable ? plugin : extras).change.call(unavailable ? plugin : extras);
  assert(controls.every(c => c.disabled), 'radio group is disabled while saving');
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(sent, 'select_extras_defaults=1&extras_defaults_source=' + (unavailable ? 'plugin' : 'extras'));
  assert(!plugin.disabled && extras.disabled === unavailable, 'prior disabled state is restored after saving');
  assert.strictEqual(plugin.checked, fail || unavailable, 'failed save restores prior selection');
  assert.strictEqual(extras.checked, !(fail || unavailable), 'successful save retains new selection');
  assert.match(status.textContent, fail ? /Could not save/ : /Selection saved/);
}
Promise.resolve().then(() => exercise(false)).then(() => exercise(true)).then(() => exercise(false, true))
  .then(() => console.log('PASS: radio persistence and failure recovery'))
  .catch(error => { console.error(error); process.exitCode = 1; });
