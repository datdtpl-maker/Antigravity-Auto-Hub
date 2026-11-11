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
const modelExpression = source.match(/\$modelExpression = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
function modelCheck(name, triggers, expected) {
  assert.equal(vm.runInNewContext(modelExpression, { document: { querySelectorAll: () => triggers } }), expected, name);
  console.log(`PASS: ${name}`);
}
function trigger(text, label = 'Select model, current: ' + text, visible = true) {
  return { innerText: text, getAttribute: () => label, getClientRects: () => visible ? [{}] : [] };
}
modelCheck('Read only the selected model trigger', [trigger('Gemini 3.8 Flash High')], 'Gemini 3.8 Flash High');
modelCheck('Multiple visible selectors are ambiguous', [trigger('Claude Opus Medium'), trigger('Gemini Flash High')], '');
modelCheck('Hidden selectors are ignored', [trigger('Claude Opus Medium'), trigger('Gemini Flash High', '', false)], 'Claude Opus Medium');
modelCheck('Missing selector does not infer from conversation text', [], '');
modelCheck('Inconsistent accessible label fails closed', [trigger('Claude Sonnet Medium', 'different')], '');
modelCheck('Unexpected labels fail closed', [trigger('private conversation text')], '');
