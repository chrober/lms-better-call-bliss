const assert = require('assert');
const fs = require('fs');
const source = fs.readFileSync('BetterCallBliss/strings.txt', 'utf8');
const blocks = new Map([...source.matchAll(/^(\w+)\n\tEN\t([^\n]*)\n\tDE\t([^\n]*)/gm)].map(m => [m[1], {EN:m[2], DE:m[3]}]));
const cases = [
  ['EXTRAS_DEFAULTS_NOTE', ['Use plugin defaults', 'Use saved Extras defaults'], ['Plugin-Standardwerte verwenden', 'Gespeicherte Extras-Standardwerte verwenden']],
  ['MORE_QUEUE_ACTION_NOTE', ['Replace queue', 'Replace upcoming tracks', 'Append to queue', 'Play next'], ['Wiedergabeliste ersetzen', 'Folgende Titel ersetzen', 'An Wiedergabeliste anhängen', 'Als Nächstes abspielen']],
  ['ARTIST_REPEAT_MODE_DESC', ['Any shared credited artist', 'Primary artist only', 'Exact Bliss artist credit'], ['Jeder gemeinsame beteiligte Interpret', 'Nur Hauptinterpret', 'Exakte Bliss-Interpretenangabe']],
  ['REPEAT_IDENTITY_EXPLANATION', ['Any shared credited artist', 'Primary artist only', 'Exact Bliss artist credit'], ['Jeder gemeinsame beteiligte Interpret', 'Nur Hauptinterpret', 'Exakte Bliss-Interpretenangabe']],
  ['ROUTE_LENGTH_POLICY_DESC', ['Choose automatically', 'Use an exact count'], ['Automatisch auswählen', 'Genaue Anzahl verwenden']],
  ['ROUTE_DIRECT_CAUTION_DESC', ['Normal', 'Cautious'], ['Normal', 'Vorsichtig']],
  ['ROUTE_SEARCH_EFFORT_DESC', ['Fast', 'Balanced', 'Thorough'], ['Schnell', 'Ausgewogen', 'Gründlich']]
];
for (const [key, en, de] of cases) {
  const block = blocks.get('PLUGIN_BETTERCALLBLISS_' + key);
  assert.ok(block, key + ' has both translations');
  for (const [language, options] of [['EN', en], ['DE', de]]) {
    for (const option of options) assert.ok(block[language].includes('<b>' + option + ':</b>'), key + ' ' + language + ' describes ' + option);
    for (const option of options.slice(1)) assert.ok(block[language].includes('<br/><br/><b>' + option + ':</b>'), key + ' ' + language + ' separates ' + option);
    assert.doesNotMatch(block[language], /previous default|früher|bisherig/i);
  }
}
console.log('Better Call Bliss choice explanations: ok');
