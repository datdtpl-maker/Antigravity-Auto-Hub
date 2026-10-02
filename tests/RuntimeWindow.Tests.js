const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'RuntimeBridge.ps1'), 'utf8');
const expression = source.match(/\$expression = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
function check(name, focused, activeEditor, text, expected, nested = false) {
  const editor = { value: text, textContent: '', matches: () => activeEditor, closest: () => nested ? {} : null };
  const document = { hasFocus: () => focused, activeElement: editor, querySelectorAll: () => [editor] };
  assert.equal(vm.runInNewContext(expression, { document }), expected, name);
  console.log(`PASS: ${name}`);
}
check('Background empty composer does not block account rotation', false, true, '', true);
check('Focused composer still blocks rotation', true, true, '', false);
check('Background draft is preserved', false, true, 'fixture draft', false);
check('Draft blocks rotation even when another control is focused', false, false, 'fixture draft', false);
check('Focused nested editable element blocks rotation', true, false, '', false, true);
check('Empty page is safe', false, false, '', true);
