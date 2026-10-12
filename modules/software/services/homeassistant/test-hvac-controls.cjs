// Offline interaction checks: no Home Assistant connection or IR transmission.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const registry = {};
class Element {
  attachShadow() {
    const nodes = {};
    this.shadowRoot = {getElementById: id => nodes[id] ||= {}, innerHTML: ''};
  }
}
new Function('HTMLElement', 'customElements', 'window',
  fs.readFileSync(`${__dirname}/hvac-controls.js`, 'utf8'))(
  Element, {define: (name, cls) => registry[name] = cls}, {});
const calls = [];
const states = {};
let stamp = 0;
const state = (id, value, attributes = {}) => states[id] = {state: value, attributes, last_updated: String(++stamp)};
state('input_select.hvac_system_mode', 'cool');
state('sensor.hvac_requested_mode', 'cool');
state('input_select.hvac_auto_side', 'cool');
state('input_select.hvac_max_mode', 'cool');
state('sensor.hvac_schedule_block', 'Working since 06:00');
state('sensor.hvac_next_block', 'Wind-down at 22:00');
state('input_number.hvac_nap_minutes', '30');
for (const room of ['office', 'bedroom', 'living_room']) {
  state(`sensor.ac_controller_${room}_temperature`, '74.2');
  state(`sensor.ac_controller_${room}_humidity`, '45');
  state(`sensor.hvac_target_${room}`, '76');
  state(`sensor.hvac_heat_target_${room}`, '68');
  state(`sensor.hvac_activity_${room}`, 'Idle');
  state(`sensor.hvac_status_${room}`, 'Following schedule');
  state(`timer.hvac_override_${room}`, 'idle');
  state(`timer.hvac_max_${room}`, 'idle');
  state(`input_boolean.hvac_enable_${room}`, 'on');
}
const hass = {states, callService: async (...args) => calls.push(args)};
const el = (card, id) => card.shadowRoot.getElementById(id);
const office = new registry['hvac-room-card']();
office.setConfig({room: 'office', gap: 5, max_minutes: 20});
office.hass = hass;
(async () => {
  assert.equal(calls.length, 0, 'render must never write helpers');
  assert.match(office.shadowRoot.innerHTML, /Cools above <b>76°<\/b>/);

  el(office, 'open-adjust').onclick();
  el(office, 'up').onclick();
  el(office, 'dur-120').onclick();
  await el(office, 'apply').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_apply_override',
    {room: 'office', minutes: 120, temperature: 77, enabled: true, fan: 'schedule', airflow: 'schedule'}]);
  assert.equal(office.panel, null, 'a successful apply closes the panel');

  el(office, 'open-max').onclick();
  await el(office, 'max-cool').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_start_max', {rooms: ['office'], hvac_mode: 'cool'}]);
  state('timer.hvac_max_bedroom', 'active');
  office.hass = hass;
  assert.match(office.shadowRoot.innerHTML, /Paused while Bedroom runs max cool\./);
  state('timer.hvac_max_office', 'active');
  office.hass = hass;
  await el(office, 'stop').onclick();
  assert.deepEqual(calls.pop(), ['timer', 'cancel', {entity_id: 'timer.hvac_max_office'}]);
  state('timer.hvac_max_office', 'idle');
  state('timer.hvac_max_bedroom', 'idle');

  state('timer.hvac_override_office', 'active');
  state('input_text.hvac_override_label_office', 'Hold 67°');
  office.hass = hass;
  assert.match(office.shadowRoot.innerHTML, /Hold 67°/);
  await el(office, 'resume').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_apply_override', {room: 'office', operation: 'resume'}]);

  const bedroom = new registry['hvac-room-card']();
  bedroom.setConfig({room: 'bedroom', nap: {heat: 65, cool: 73}});
  bedroom.hass = hass;
  assert.equal(bedroom.panel, null, 'panels are local to each card');
  el(bedroom, 'open-nap').onclick();
  el(bedroom, 'nap-90').onclick();
  await el(bedroom, 'nap-go').onclick();
  assert.deepEqual(calls.pop(), ['script', 'hvac_start_nap', {minutes: 90}]);

  const system = new registry['hvac-system-card']();
  system.setConfig({persist_minutes: 15, guard_minutes: 90});
  system.hass = hass;
  assert.match(system.shadowRoot.innerHTML, /Cooling only/);
  await el(system, 'mode-auto').onclick();
  assert.deepEqual(calls.pop(), ['input_select', 'select_option', {entity_id: 'input_select.hvac_system_mode', option: 'auto'}]);

  assert.throws(() => new registry['hvac-room-card']().setConfig({room: 'garage'}));

  office._hass = {...hass, callService: async () => { throw new Error('<failed>'); }};
  el(office, 'open-adjust').onclick();
  await el(office, 'apply').onclick();
  assert.match(office.shadowRoot.innerHTML, /&lt;failed&gt;/);
  assert.equal(office.busy, false);
  assert.equal(office.panel, 'adjust', 'a failed apply keeps the panel open');
  console.log('HVAC card interaction checks passed.');
})().catch(error => {console.error(error); process.exitCode = 1;});
