const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const template = fs.readFileSync('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html', 'utf8').replace(/\r\n/g, '\n');
for (const token of ['RESULT_RETRY', 'RESULT_SPACING', 'RESULT_GUIDANCE_NOTE', 'RESULT_ADDED_SPACING', 'RESULT_ADDED_EXTENSION', 'RESULT_ADDED_BRIDGE', 'RESULT_NO_ADDITIONS']) {
  assert.ok(template.includes('PLUGIN_BETTERCALLBLISS_' + token), `missing localized result text ${token}`);
}
const strings = fs.readFileSync('BetterCallBliss/strings.txt', 'utf8');
const blocks = new Map();
for (const match of strings.matchAll(/^([A-Z][A-Z0-9_]+)\s*\n\tEN\t([^\n]*)\n\tDE\t([^\n]*)/gm)) {
  blocks.set(match[1], {EN: match[2], DE: match[3]});
}
const ids = new Map();
for (const match of template.matchAll(/<span id="bea-i18n-([^"]+)">\[% "(\w+)" \| string \| html %\]<\/span>/g)) {
  ids.set(match[1], match[2]);
}
const helper = template.match(/function extrasText\(key\) \{[\s\S]*?\n    \}/)[0];
const formatter = template.match(/function extrasFormat\(key\) \{[\s\S]*?\n    \}/)[0];
const notes = template.match(/function updateAdditionNotes\(purpose, mode, preserve\) \{[\s\S]*?\n    \}\n\n    function updateGapContextNote/)[0]
  .replace(/\n\n    function updateGapContextNote$/, '');
for (const lang of ['EN', 'DE']) {
  const context = {
    document: {getElementById(id) {
      const token = ids.get(id.replace('bea-i18n-', ''));
      const block = blocks.get(token);
      return block ? {textContent: block[lang]} : null;
    }},
    additionPurposeNote: {}, additionAmountNote: {}, orderingPolicyNote: {},
    automaticNote: {}, extendPlaylistNote: {},
    spacingGoal: {checked: true}, smoothingGoal: {checked: true}
  };
  vm.createContext(context);
  vm.runInContext(helper + '\n' + formatter + '\n' + notes, context);
  context.updateAdditionNotes('automatic_improvement', 'none', true);
  assert.match(context.additionPurposeNote.textContent,
    lang === 'DE' ? /Abstandstitel.*und.*Übergänge/ : /spacing.*and.*transitions/);
  context.updateAdditionNotes('extend_playlist', 'target_duration', false);
  assert.match(context.additionAmountNote.textContent, lang === 'DE' ? /Toleranzen/ : /tolerances/);
  const size = context.extrasFormat('FINAL_SIZE', 8, 4, 12);
  assert.match(size, lang === 'DE' ? /8 Ausgangstitel \+ 4 zusätzliche Titel = 12 Titel/ : /8 source tracks \+ 4 additions = 12 tracks/);
}
console.log('Extras dynamic localization: ok');
