/* Local Lovelace controls. Draft entities are written only by user edits;
 * script.hvac_apply_override commits them together. No external assets. */
const ROOMS = { office: "Office", bedroom: "Bedroom", living_room: "Living Room" };
const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g,
  c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const CSS = `
  :host { display: block; }
  ha-card { padding: 20px; }
  h2 { margin: 0 0 16px; font-size: 20px; font-weight: 500; }
  button, select, input { font: inherit; color: var(--primary-text-color); }
  button { cursor: pointer; border: 0; border-radius: 10px; min-height: 44px;
    background: var(--secondary-background-color); padding: 8px 14px; }
  button:disabled { opacity: .45; cursor: default; }
  button:focus-visible, select:focus-visible, input:focus-visible {
    outline: 2px solid var(--primary-color); outline-offset: 2px; }
  .tabs { display: flex; gap: 4px; background: var(--secondary-background-color);
    border-radius: 12px; padding: 4px; margin-bottom: 16px; }
  .tabs button { flex: 1; padding: 8px; background: transparent; }
  .tabs button[aria-selected=true] { background: var(--card-background-color);
    color: var(--primary-color); box-shadow: 0 1px 4px #0003; }
  .row { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin: 12px 0; }
  .muted { color: var(--secondary-text-color); font-size: 13px; line-height: 1.5; }
  .switch { accent-color: var(--primary-color); width: 22px; height: 22px; cursor: pointer; }
  .temperature { display: flex; align-items: center; justify-content: center; gap: 24px; padding: 10px 0 18px; }
  .temperature button { font-size: 24px; width: 48px; }
  .reading { text-align: center; }
  .reading input { width: 72px; border: 0; background: transparent; text-align: center;
    font-size: 36px; font-weight: 500; appearance: textfield; }
  .reading input::-webkit-inner-spin-button { appearance: none; }
  .reading .unit { color: var(--secondary-text-color); font-size: 20px; }
  .fields { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  label { display: block; font-size: 14px; }
  label select { display: block; margin-top: 6px; width: 100%; }
  select { border: 1px solid var(--divider-color); border-radius: 9px; min-height: 44px;
    padding: 8px; background: var(--card-background-color); }
  .actions { display: flex; gap: 10px; margin-top: 18px; }
  .actions button { flex: 1; }
  .primary { background: var(--primary-color); color: var(--text-primary-color, white); }
  .status { min-height: 20px; margin-top: 12px; }
  .error { color: var(--error-color, #db4437); }
  @media (max-width: 400px) { ha-card { padding: 16px; } .tabs button { font-size: 13px; } }
`;

class HvacControls extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.room = "office"; // Browser-local tab; never switches another client's tab.
    this.minutes = 60;
    this.busy = false;
    this.error = "";
    this._signature = "";
  }
  setConfig(config) { this.config = config; }
  getCardSize() { return this.nap ? 3 : 6; }
  getGridOptions() { return { columns: this.nap ? 12 : 24, rows: "auto", min_columns: 12 }; }
  set hass(hass) {
    this._hass = hass;
    if (!this._durationLoaded) {
      const saved = Number(this.state(this.nap ? "input_number.hvac_nap_minutes" : "input_number.hvac_override_minutes"));
      if (Number.isFinite(saved)) { this.minutes = saved; this._durationLoaded = true; }
    }
    this.render();
  }
  state(id) { return this._hass?.states[id]?.state ?? "unknown"; }
  get active() { return this.state(`timer.hvac_override_${this.nap ? "bedroom" : this.room}`) === "active"; }
  options(values, current) {
    return values.map(([value, label]) => `<option value="${escapeHtml(value)}" ${String(value) === String(current) ? "selected" : ""}>${escapeHtml(label)}</option>`).join("");
  }
  async call(domain, service, data) {
    if (this.busy) return;
    this.busy = true; this.error = ""; this.render(true);
    try { await this._hass.callService(domain, service, data); }
    catch (e) { this.error = e.message || String(e); }
    finally { this.busy = false; this.render(true); }
  }
  setNumber(value) {
    if (!Number.isFinite(value)) return;
    const entity_id = `input_number.hvac_draft_${this.room}`;
    const attrs = this._hass.states[entity_id]?.attributes || {};
    const bounded = Math.min(attrs.max ?? 86, Math.max(attrs.min ?? 60, Math.round(value)));
    this.call("input_number", "set_value", { entity_id, value: bounded });
  }
  render(force = false) {
    if (!this._hass) return;
    const r = this.nap ? "bedroom" : this.room;
    const mode = this.state("sensor.hvac_effective_mode");
    const temp = this.state(`input_number.hvac_draft_${r}`);
    const enabled = this.state(`input_boolean.hvac_draft_enable_${r}`) === "on";
    const fan = this.state(`input_select.hvac_draft_fan_${r}`);
    const airflow = this.state(`input_select.hvac_draft_airflow_${r}`);
    const timer = this._hass.states[`timer.hvac_override_${r}`];
    const ready = this.state("input_boolean.hvac_drafts_initialized") === "on" &&
      (this.nap || [temp, fan, airflow].every(x => !["unknown", "unavailable"].includes(x)));
    const signature = JSON.stringify([r,mode,temp,enabled,fan,airflow,timer?.state,timer?.attributes?.finishes_at,
      ready,this.minutes,this.busy,this.error,this.state("sensor.hvac_nap_target")]);
    if (!force && signature === this._signature) return;
    // Do not replace an input/select while the user is editing it due to a
    // background HA state update. Forced renders follow explicit user actions.
    if (!force && ["INPUT", "SELECT"].includes(this.shadowRoot.activeElement?.tagName)) return;
    this._signature = signature;
    const disabled = this.busy ? "disabled" : "";
    const end = timer?.attributes?.finishes_at;
    const endDate = end ? new Date(end) : null;
    const until = endDate && !Number.isNaN(endDate.getTime()) ? endDate.toLocaleTimeString([], {hour:"numeric",minute:"2-digit"}) : "";
    const status = this.active ? `Override active${until ? ` until ${until}` : ""}` : "Following schedule";
    const durations = this.nap ? [20,30,60,90,120,180,240] : [30,60,90,120,180,240,480];
    if (Number.isFinite(this.minutes) && !durations.includes(this.minutes)) durations.push(this.minutes);
    durations.sort((a,b) => a-b);
    this.shadowRoot.innerHTML = `<style>${CSS}</style><ha-card>
      <h2>${this.nap ? "Bedroom nap" : "Override"}</h2>
      ${this.nap ? `<div class="muted">Bedroom sleep settings · ${escapeHtml(this.state("sensor.hvac_nap_target"))}°F<br>Quiet fan · Comfort airflow</div>` : `
        <div class="tabs" role="tablist" aria-label="Room">${Object.entries(ROOMS).map(([key,name]) =>
          `<button role="tab" id="tab-${key}" aria-controls="controls" aria-selected="${key===r}" tabindex="${key===r ? 0 : -1}" data-room="${key}">${name}</button>`).join("")}</div>
        <div id="controls" role="tabpanel" aria-labelledby="tab-${r}">
          <div class="row"><label for="enabled">Room on</label><input id="enabled" class="switch" type="checkbox" role="switch" ${enabled ? "checked" : ""} ${disabled}></div>
          <div class="temperature"><button id="minus" aria-label="Lower temperature" ${disabled}>−</button>
            <div class="reading"><input id="temperature" type="number" min="60" max="86" step="1" aria-label="Room threshold" value="${escapeHtml(Number.isFinite(Number(temp)) ? temp : "")}" ${disabled}><span class="unit">°F</span>
              <div class="muted">${mode === "heat" ? "Heat below" : mode === "cool" ? "Cool above" : "System is off"}</div></div>
            <button id="plus" aria-label="Raise temperature" ${disabled}>+</button></div>
          <div class="fields"><label>Fan<select id="fan" ${disabled}>${this.options([["schedule","Normal setting"],["auto","Auto"],["quiet","Quiet"],...[1,2,3,4,5].map(n=>[String(n),`Speed ${n}`])],fan)}</select></label>
            <label>Airflow<select id="airflow" ${disabled}>${this.options([["schedule","Normal setting"],["off","Still"],["swing","Swing"],["comfort","Comfort"]],airflow)}</select></label></div>
        </div>`}
      <div class="row"><label for="duration">${this.nap ? "Nap length" : "Duration"}</label><select id="duration" ${disabled}>${this.options(durations.map(m=>[m,m<60 ? `${m} min` : `${m/60} ${m===60 ? "hour" : "hours"}`]),this.minutes)}</select></div>
      ${this.nap ? "" : '<div class="muted">Changes take effect when you press Apply.</div>'}
      <div class="actions"><button id="apply" class="primary" ${this.busy || !ready || (this.nap && !["cool","heat"].includes(mode)) ? "disabled" : ""}>${this.nap ? "Start nap" : "Apply"}</button>
        <button id="resume" ${this.busy || !this.active ? "disabled" : ""}>${this.nap ? "End bedroom override" : "Resume schedule"}</button></div>
      <div class="status muted" role="status">${escapeHtml(this.nap && mode === "off" ? "Turn on heating or cooling to start a nap." : status)}</div>
      ${this.error ? `<div class="error" role="alert">${escapeHtml(this.error)}</div>` : ""}
    </ha-card>`;
    const find = id => this.shadowRoot.getElementById(id);
    this.shadowRoot.querySelectorAll("[data-room]").forEach(button => {
      button.onclick = () => { this.room=button.dataset.room; this.render(true); this.shadowRoot.querySelector(`[data-room="${this.room}"]`).focus(); };
      button.onkeydown = e => {
        if (!["ArrowLeft","ArrowRight","Home","End"].includes(e.key)) return;
        e.preventDefault();
        const keys=Object.keys(ROOMS), i=keys.indexOf(this.room);
        this.room=keys[e.key==="Home" ? 0 : e.key==="End" ? keys.length-1 : (i+(e.key==="ArrowRight" ? 1 : -1)+keys.length)%keys.length];
        this.render(true); this.shadowRoot.querySelector(`[data-room="${this.room}"]`).focus();
      };
    });
    if (!this.nap) {
      find("minus").onclick=()=>this.setNumber(Number(temp)-1);
      find("plus").onclick=()=>this.setNumber(Number(temp)+1);
      find("temperature").onchange=e=>this.setNumber(e.target.valueAsNumber);
      find("enabled").onchange=e=>this.call("input_boolean",e.target.checked ? "turn_on" : "turn_off",{entity_id:`input_boolean.hvac_draft_enable_${r}`});
      for (const key of ["fan","airflow"]) find(key).onchange=e=>this.call("input_select","select_option",{entity_id:`input_select.hvac_draft_${key}_${r}`,option:e.target.value});
    }
    find("duration").onchange=e=>{
      this.minutes=Number(e.target.value);
      this.call("input_number","set_value",{entity_id:this.nap ? "input_number.hvac_nap_minutes" : "input_number.hvac_override_minutes", value:this.minutes});
    };
    find("apply").onclick=()=>this.nap ? this.call("script","hvac_start_nap",{minutes:this.minutes}) : this.call("script","hvac_apply_override",{room:r,minutes:this.minutes});
    find("resume").onclick=()=>this.call("script","hvac_apply_override",{room:r,operation:"resume"});
  }
}
class HvacNap extends HvacControls { constructor() { super(); this.nap=true; } }
customElements.define("hvac-override-card", HvacControls);
customElements.define("hvac-nap-card", HvacNap);
window.customCards = window.customCards || [];
window.customCards.push({type:"hvac-override-card",name:"HVAC override",description:"Room tabs with timed local HVAC controls"},
  {type:"hvac-nap-card",name:"Bedroom nap",description:"Bedroom sleep preset and duration"});
