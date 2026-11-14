const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'RuntimeBridge.ps1'), 'utf8');
const expression = source.match(/\$expression = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
function check(name, focused, activeEditor, text, expected, nested = false) {
  const editor = control('textarea', text);
  const activeElement = activeEditor ? editor : { matches: () => false, closest: () => nested ? editor : null };
  const document = { hasFocus: () => focused, activeElement, querySelectorAll: () => [editor] };
  assert.equal(vm.runInNewContext(expression, { document }), expected, name);
  console.log(`PASS: ${name}`);
}
check('Background empty composer does not block account rotation', false, true, '', true);
check('Focused composer still blocks rotation', true, true, '', false);
check('Background draft is preserved', false, true, 'fixture draft', false);
check('Draft blocks rotation even when another control is focused', false, false, 'fixture draft', false);
check('Focused nested editable element blocks rotation', true, false, '', false, true);
check('Empty page is safe', false, false, '', true);
function control(type, value = '', editable = false) {
  return {
    type, value, textContent: '', isContentEditable: editable,
    matches: selector => selector === 'textarea,input' ? !editable : selector === 'input' ? type !== 'textarea' && !editable : !editable,
    closest: () => editable ? control('div', '', true) : null
  };
}
function controlsCheck(name, controls, expected, focused = false, activeElement = controls[0]) {
  const document = { hasFocus: () => focused, activeElement, querySelectorAll: () => controls };
  assert.equal(vm.runInNewContext(expression, { document }), expected, name);
  console.log(`PASS: ${name}`);
}
for (const type of ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'range', 'color', 'hidden']) {
  controlsCheck(`Settings ${type} value is not an unsent draft`, [control(type, 'on'), control('textarea')], true);
  controlsCheck(`Focused ${type} is not a focused text editor`, [control(type)], true, true);
}
for (const type of ['text', 'search', 'email', 'url', 'tel', 'password', 'number', 'textarea']) {
  controlsCheck(`${type} draft remains protected`, [control(type, 'fixture')], false);
  controlsCheck(`Focused empty ${type} remains protected`, [control(type)], false, true);
}
controlsCheck('Settings toggle does not conceal a real draft', [control('checkbox', 'on'), control('textarea', 'fixture')], false);
controlsCheck('Pending file attachment remains protected', [control('file', 'C:\\fakepath\\fixture.txt')], false);
controlsCheck('Unused file picker is safe', [control('file')], true);
controlsCheck('Background contenteditable draft remains protected', [{ ...control('div', '', true), textContent: 'fixture' }], false);
controlsCheck('Empty background contenteditable is safe', [control('div', '', true)], true);
controlsCheck('Focused empty contenteditable remains protected', [control('div', '', true)], false, true);
const modelExpression = source.match(/\$modelExpression = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
function modelCheck(name, triggers, expected) {
  assert.equal(vm.runInNewContext(modelExpression, { document: { querySelectorAll: () => triggers } }), expected, name);
  console.log(`PASS: ${name}`);
}
function trigger(text, label = 'Select model, current: ' + text, visible = true) {
  return { innerText: text, getAttribute: () => label, getClientRects: () => visible ? [{}] : [] };
}
modelCheck('Read only the selected model trigger', [trigger('Gemini 3.8 Flash High')], 'Gemini 3.8 Flash High');
modelCheck('Read orchestrator model trigger', [trigger('Orchestrator (Argon)')], 'Orchestrator (Argon)');
modelCheck('Multiple visible selectors are ambiguous', [trigger('Claude Opus Medium'), trigger('Gemini Flash High')], '');
modelCheck('Hidden selectors are ignored', [trigger('Claude Opus Medium'), trigger('Gemini Flash High', '', false)], 'Claude Opus Medium');
modelCheck('Missing selector does not infer from conversation text', [], '');
modelCheck('Inconsistent accessible label fails closed', [trigger('Claude Sonnet Medium', 'different')], '');
modelCheck('Unexpected labels fail closed', [trigger('private conversation text')], '');
