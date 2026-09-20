// Offline interaction checks: no Home Assistant connection or IR transmission.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const registry = {};
class Element {
  attachShadow() {
    const nodes = {};
    const tabs = ['office', 'bedroom', 'living_room'].map(room => ({dataset: {room}, focus() {}}));
    this.shadowRoot = {
      getElementById: id => nodes[id] ||= {},
      querySelectorAll: () => tabs,
      querySelector: selector => tabs.find(t => selector.includes(t.dataset.room)),
    };
  }
}
new Function('HTMLElement', 'customElements', 'window',
  fs.readFileSync(`${__dirname}/hvac-controls.js`, 'utf8'))(
  Element, {define: (name, cls) => registry[name] = cls}, {});
const calls = [];
const states = {};
const state = (id, value) => states[id] = {state: value, attributes: {}};
state('input_boolean.hvac_drafts_initialized', 'on');
state('sensor.hvac_effective_mode', 'cool');
state('sensor.hvac_nap_target', '73');
state('input_number.hvac_override_minutes', '60');
state('input_number.hvac_nap_minutes', '30');
for (const room of ['office', 'bedroom', 'living_room']) {
  state(`input_number.hvac_draft_${room}`, '74');
  state(`input_boolean.hvac_draft_enable_${room}`, 'on');
  state(`input_select.hvac_draft_fan_${room}`, 'schedule');
  state(`input_select.hvac_draft_airflow_${room}`, 'schedule');
  state(`timer.hvac_override_${room}`, 'active');
}
const hass = {states, callService: async (...args) => calls.push(args)};
const card = new registry['hvac-override-card']();
card.hass = hass;
const control = id => card.shadowRoot.getElementById(id);
(async () => {
  assert.equal(calls.length, 0, 'render must never write helpers');
  await control('fan').onchange({target: {value: 'quiet'}});
  assert.deepEqual(calls.pop(), ['input_select', 'select_option', {entity_id:'input_select.hvac_draft_fan_office', option:'quiet'}]);
  card.shadowRoot.querySelector('[data-room="bedroom"]').onclick();
  await control('enabled').onchange({target: {checked: false}});
  assert.deepEqual(calls.pop(), ['input_boolean', 'turn_off', {entity_id:'input_boolean.hvac_draft_enable_bedroom'}]);
  await control('apply').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_apply_override', {room:'bedroom', minutes:60}]);
  await control('resume').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_apply_override', {room:'bedroom', operation:'resume'}]);
  const other = new registry['hvac-override-card'](); other.hass = hass;
  assert.equal(other.room, 'office', 'room tabs must be client-local');
  const nap = new registry['hvac-nap-card'](); nap.hass = hass;
  await nap.shadowRoot.getElementById('apply').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_start_nap', {minutes:30}]);
  card._hass = {...hass, callService: async () => {throw new Error('<failed>');}};
  await control('apply').onclick();
  assert.match(card.shadowRoot.innerHTML, /&lt;failed&gt;/);
  assert.equal(card.busy, false);
  console.log('HVAC card interaction checks passed.');
})().catch(error => {console.error(error); process.exitCode = 1;});
