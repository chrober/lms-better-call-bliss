const assert = require('assert');
const fs = require('fs');

const text = fs.readFileSync('BetterCallBliss/strings.txt', 'utf8');
function translation(token, language) {
  const match = text.match(new RegExp('(?:^|\\n)' + token + '\\r?\\n([\\s\\S]*?)(?=\\r?\\nPLUGIN_|$)'));
  assert(match, `Missing ${token}`);
  const line = match[1].split(/\r?\n/).find(value => new RegExp('^\\s*' + language + '\\s').test(value));
  assert(line, `Missing ${language} for ${token}`);
  return line.replace(/^\s*(EN|DE)\s+/, '');
}

for (const [token, en, de] of [
  ['PLUGIN_BETTERCALLBLISS_EXTRAS_JOB_OVERVIEW', 'Current and recent jobs', 'Aktuelle und letzte Aufträge'],
  ['PLUGIN_BETTERCALLBLISS_HISTORY_SECTION', 'Job history', 'Auftragsverlauf'],
  ['PLUGIN_BETTERCALLBLISS_EXTRAS_RUN_PREVIEW', 'Start job', 'Auftrag starten'],
  ['PLUGIN_BETTERCALLBLISS_EXTRAS_CANCEL_PREVIEW', 'Cancel job', 'Auftrag abbrechen'],
  ['PLUGIN_BETTERCALLBLISS_EXTRAS_ENABLE_PREVIEW', 'Enable for this job', 'Für diesen Auftrag aktivieren'],
]) {
  assert.strictEqual(translation(token, 'EN'), en, token);
  assert.strictEqual(translation(token, 'DE'), de, token);
}
for (const token of [
  'PLUGIN_BETTERCALLBLISS_EXTRAS_PREVIEW_PAUSED',
  'PLUGIN_BETTERCALLBLISS_EXTRAS_SCAN_PROBLEM',
  'PLUGIN_BETTERCALLBLISS_HISTORY_SECTION_DESC',
  'PLUGIN_BETTERCALLBLISS_HISTORY_LIMIT_DESC',
  'PLUGIN_BETTERCALLBLISS_HISTORY_SIZE_DESC',
  'PLUGIN_BETTERCALLBLISS_EXTRAS_CONNECTION_CHECK',
  'PLUGIN_BETTERCALLBLISS_EXTRAS_CANNOT_CONFIRM',
  'PLUGIN_BETTERCALLBLISS_EXTRAS_RESULT_NOTE',
]) {
  assert.doesNotMatch(translation(token, 'EN'), /\b(?:run|runs)\b/i, token);
  assert.doesNotMatch(translation(token, 'DE'), /\b(?:Lauf|Laufs|Läufe|Läufen)\b/i, token);
}
console.log('Better Call Bliss job terminology: ok');
