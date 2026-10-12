/* Local Lovelace cards for the climate view. Panel edits stay in the browser
 * until one script call applies them. No external assets. */
const ROOMS = { office: "Office", bedroom: "Bedroom", living_room: "Living Room" };
const FAN = [["schedule", "Normal"], ["auto", "Auto"], ["quiet", "Quiet"], ...[1, 2, 3, 4, 5].map(n => [String(n), `Speed ${n}`])];
const AIRFLOW = [["schedule", "Normal"], ["off", "Still"], ["swing", "Swing"], ["comfort", "Comfort"]];
const HOLD_MINUTES = [30, 60, 120, 240, 480];
const NAP_MINUTES = [20, 30, 60, 90, 120, 180, 240];
const SYS = {
  system: "input_select.hvac_system_mode", requested: "sensor.hvac_requested_mode",
  side: "input_select.hvac_auto_side", maxMode: "input_select.hvac_max_mode",
  block: "sensor.hvac_schedule_block", next: "sensor.hvac_next_block",
  wantSince: "input_number.hvac_auto_want_since", switchedAt: "input_number.hvac_auto_switched_at",
};
const ent = r => ({
  temp: `sensor.ac_controller_${r}_temperature`, hum: `sensor.ac_controller_${r}_humidity`,
  cool: `sensor.hvac_target_${r}`, heat: `sensor.hvac_heat_target_${r}`,
  activity: `sensor.hvac_activity_${r}`, status: `sensor.hvac_status_${r}`,
  override: `timer.hvac_override_${r}`, label: `input_text.hvac_override_label_${r}`, enable: `input_boolean.hvac_enable_${r}`,
  max: `timer.hvac_max_${r}`, climate: `climate.${r}_ac`, priority: `sensor.hvac_priority_${r}`,
  fan: `sensor.hvac_fan_${r}`, airflow: `sensor.hvac_airflow_${r}`,
});
// Statuses that need no line of their own, and friendlier words for the rest.
const QUIET = ["Override", "Following schedule", "System off", "Paused by override", "unknown", "unavailable"];
const STATUS = {
  "Sensor unavailable": ["warn", "Sensor unavailable. The room stays off until it reports."],
  "Sensor stale": ["warn", "Sensor has gone quiet. The room stays off until it reports."],
  "Check unit: shutdown unconfirmed": ["bad", "Shutdown not confirmed. Check the unit and its IR blaster."],
  "Paused for capacity": ["warn", "Paused so a more important room can catch up."],
  "Not reaching target": ["warn", "Running, but not reaching its target."],
};
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g,
  c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const duration = m => m < 60 ? `${m} min` : `${m / 60} h`;
const clockTime = ms => new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
const names = rooms => rooms.map(r => ROOMS[r]).join(" and ");
const options = (values, current) => values.map(([v, l]) =>
  `<option value="${escapeHtml(v)}" ${v === current ? "selected" : ""}>${escapeHtml(l)}</option>`).join("");
const CSS = `
  :host { display: block; --cool: var(--state-climate-cool-color, #2b9af9); --heat: var(--state-climate-heat-color, #ff8100);
    --warn: var(--warning-color, #ffa600); --bad: var(--error-color, #db4437); --muted: var(--secondary-text-color);
    --line: var(--divider-color); --chip: var(--secondary-background-color); --accent: var(--primary-color); }
  ha-card { padding: 18px; display: grid; gap: 12px; }
  button, select, input { font: inherit; color: var(--primary-text-color); }
  button { cursor: pointer; }
  button:disabled { opacity: .45; cursor: default; }
  button:focus-visible, select:focus-visible, input:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  ha-icon { --mdc-icon-size: 20px; color: var(--muted); }
  .muted { color: var(--muted); }
  .small { font-size: 13px; line-height: 1.45; }
  p { margin: 0; }
  .head { display: flex; align-items: center; gap: 10px; }
  .head h2 { margin: 0; font-size: 17px; font-weight: 500; flex: 1; min-width: 0; }
  .pill { display: inline-flex; align-items: center; gap: 4px; border-radius: 999px; padding: 3px 10px; font-size: 12px; font-weight: 500;
    background: var(--chip); color: var(--muted); white-space: nowrap; }
  .pill ha-icon { --mdc-icon-size: 14px; color: inherit; }
  .pill.cool, .banner.cool, .maxbtns .cool { background: color-mix(in srgb, var(--cool) 16%, transparent); color: var(--cool); }
  .pill.heat, .banner.heat, .maxbtns .heat { background: color-mix(in srgb, var(--heat) 16%, transparent); color: var(--heat); }
  .pill.warn, .note.warn { background: color-mix(in srgb, var(--warn) 18%, transparent); color: color-mix(in srgb, var(--warn) 60%, var(--primary-text-color)); }
  .note.bad { background: color-mix(in srgb, var(--bad) 15%, transparent); color: var(--bad); }
  .note.info { background: var(--chip); color: var(--muted); }
  .reading { display: flex; align-items: flex-end; justify-content: space-between; gap: 12px; }
  .temp { font-size: 44px; line-height: 1; font-variant-numeric: tabular-nums; }
  .temp span { font-size: 18px; color: var(--muted); margin-left: 2px; }
  .meta { text-align: right; font-size: 13px; color: var(--muted); }
  .meta b { color: var(--primary-text-color); font-weight: 500; }
  .spark { width: 100%; height: auto; display: block; }
  .spark text { fill: var(--muted); font-size: 9px; }
  .spark .band { fill: color-mix(in srgb, var(--accent) 9%, transparent); }
  .spark .edge { stroke: var(--accent); stroke-opacity: .4; stroke-dasharray: 3 3; }
  .spark .area { fill: var(--accent); fill-opacity: .1; }
  .spark .line { fill: none; stroke: var(--accent); stroke-width: 2; stroke-linejoin: round; }
  .spark .dot { fill: var(--accent); }
  .paused .reading, .paused .spark { opacity: .5; }
  .source { display: flex; justify-content: space-between; align-items: center; gap: 8px; flex-wrap: wrap; font-size: 13px; color: var(--muted); }
  .link { background: none; border: 0; padding: 4px 0; color: var(--accent); font-weight: 500; font-size: 13px; }
  .start { justify-self: start; }
  .banner { display: flex; align-items: center; justify-content: space-between; gap: 10px; border-radius: 10px; padding: 8px 8px 8px 12px; font-size: 14px; }
  .banner button { border: 0; border-radius: 8px; padding: 6px 12px; background: var(--card-background-color); font-weight: 500; }
  .note { border-radius: 10px; padding: 8px 12px; font-size: 13px; }
  .actions, .row { display: flex; gap: 8px; }
  .actions button, .row button { flex: 1; min-height: 42px; border-radius: 10px; border: 1px solid var(--line); background: var(--card-background-color); font-weight: 500; }
  .actions button[aria-expanded=true] { border-color: var(--accent); color: var(--accent); background: var(--chip); }
  .row .primary { background: var(--accent); border-color: var(--accent); color: var(--text-primary-color, #fff); }
  .panel { display: grid; gap: 12px; border-top: 1px solid var(--line); padding-top: 14px; }
  .stepper { display: flex; align-items: center; justify-content: center; gap: 22px; }
  .stepper button { width: 46px; height: 46px; border-radius: 50%; border: 1px solid var(--line); background: var(--card-background-color); font-size: 22px; }
  .stepper output { font-size: 40px; font-variant-numeric: tabular-nums; min-width: 3ch; text-align: center; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chips button { border: 1px solid var(--line); background: transparent; border-radius: 999px; padding: 6px 12px; font-size: 13px; }
  .chips button[aria-pressed=true] { background: var(--accent); border-color: var(--accent); color: var(--text-primary-color, #fff); }
  .switchrow { display: flex; justify-content: space-between; align-items: center; }
  .switchrow input { width: 22px; height: 22px; accent-color: var(--accent); }
  .selects { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .selects label { display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  select { border: 1px solid var(--line); border-radius: 9px; min-height: 42px; padding: 6px 8px; background: var(--card-background-color); }
  .maxbtns { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
  .maxbtns button { display: flex; align-items: center; justify-content: center; gap: 6px; min-height: 48px; border: 0; border-radius: 10px; font-weight: 500; }
  .maxbtns ha-icon { color: inherit; }
  .details { display: grid; grid-template-columns: auto 1fr; gap: 2px 12px; margin: 0; font-size: 13px; }
  .details dt { color: var(--muted); }
  .details dd { margin: 0; font-variant-numeric: tabular-nums; }
  .foot { display: flex; justify-content: flex-end; }
  .seg { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; background: var(--chip); border-radius: 12px; padding: 4px; }
  .seg button { border: 0; background: transparent; border-radius: 9px; min-height: 42px; font-weight: 500; color: var(--muted); }
  .seg button[aria-checked=true] { background: var(--card-background-color); color: var(--accent); box-shadow: 0 1px 3px rgba(0,0,0,.18); }
  .block { margin: 0; font-size: 18px; font-weight: 500; }
  .error { color: var(--bad); font-size: 13px; }
`;

class HvacCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.busy = false;
    this.error = "";
    this._signature = "";
  }
  setConfig(config) { this.config = config || {}; }
  connectedCallback() { this._tick = setInterval(() => this.render(), 30000); }
  disconnectedCallback() { clearInterval(this._tick); }
  set hass(hass) { this._hass = hass; this.render(); }
  state(id) { return this._hass?.states[id]?.state ?? "unknown"; }
  attr(id, name) { return this._hass?.states[id]?.attributes?.[name]; }
  num(id) { const n = Number.parseFloat(this.state(id)); return Number.isFinite(n) ? n : null; }
  active(id) { return this.state(id) === "active"; }
  finishes(id) { const t = Date.parse(this.attr(id, "finishes_at") ?? ""); return Number.isFinite(t) ? t : null; }
  maxRooms() { return Object.keys(ROOMS).filter(r => this.active(`timer.hvac_max_${r}`)); }
  async call(domain, service, data) {
    if (this.busy) return false;
    this.busy = true; this.error = ""; this.render(true);
    try { await this._hass.callService(domain, service, data); return true; }
    catch (e) { this.error = e.message || String(e); return false; }
    finally { this.busy = false; this.render(true); }
  }
  // Skip redraws that change nothing, and never replace a control mid-edit.
  changed(watched, local, force) {
    const sig = JSON.stringify([watched.map(id => [this.state(id), this._hass?.states[id]?.last_updated]),
      local, this.busy, this.error, Math.floor(Date.now() / 60000)]);
    if (!force && (sig === this._signature || ["INPUT", "SELECT"].includes(this.shadowRoot.activeElement?.tagName))) return false;
    this._signature = sig;
    return true;
  }
  bind(id, handler, event = "onclick") { const el = this.shadowRoot.getElementById(id); if (el) el[event] = handler; }
  errorHtml() { return this.error ? `<div class="error" role="alert">${escapeHtml(this.error)}</div>` : ""; }
}

class HvacSystemCard extends HvacCard {
  getCardSize() { return 3; }
  getGridOptions() { return { columns: "full", rows: "auto" }; }
  render(force = false) {
    if (!this._hass) return;
    const rooms = Object.keys(ROOMS);
    const watched = [...Object.values(SYS), ...rooms.flatMap(r => [`timer.hvac_max_${r}`, `sensor.hvac_need_${r}`, `sensor.hvac_priority_${r}`])];
    if (!this.changed(watched, [], force)) return;
    const system = this.state(SYS.system), requested = this.state(SYS.requested), side = this.state(SYS.side);
    const maxRooms = this.maxRooms(), maxMode = this.state(SYS.maxMode);
    const persist = this.config.persist_minutes ?? 15, guard = this.config.guard_minutes ?? 90;
    let line;
    if (maxRooms.length) line = `<b>Max ${escapeHtml(maxMode)}</b> in ${names(maxRooms)}. Every other room is paused until it ends.`;
    else if (requested !== system && ["cool", "heat", "off"].includes(requested)) line = `An override is holding the system on <b>${escapeHtml(requested)}</b> until it ends.`;
    else if (requested === "auto") {
      const word = side === "heat" ? "heating" : "cooling", other = side === "heat" ? "cool" : "heat";
      const since = this.num(SYS.wantSince) ?? 0, switched = this.num(SYS.switchedAt) ?? 0, now = Date.now() / 1000;
      const who = rooms.filter(r => this.state(`sensor.hvac_need_${r}`) === other)
        .sort((a, b) => (this.num(`sensor.hvac_priority_${b}`) ?? 0) - (this.num(`sensor.hvac_priority_${a}`) ?? 0))[0];
      if (since > 0 && who) {
        const wait = Math.ceil(Math.max(persist * 60 - (now - since), guard * 60 - (now - switched), 0) / 60);
        line = `Auto is on the <b>${word}</b> side. ${ROOMS[who]} needs ${other}, so it switches ${wait > 0 ? `in ${wait} min` : "within a minute"}.`;
      } else line = `Auto is on the <b>${word}</b> side. It switches only after ${persist} min of need and ${guard} min since the last switch.`;
    }
    else if (requested === "cool") line = "Cooling only. Heat thresholds are ignored.";
    else if (requested === "heat") line = "Heating only. Cool thresholds are ignored.";
    else line = "Nothing runs on the schedule. Max still works for a quick blast.";
    const [label, since] = this.state(SYS.block).split(" since ");
    const disabled = this.busy ? "disabled" : "";
    this.shadowRoot.innerHTML = `<style>${CSS}</style><ha-card>
      <div><p class="block">${escapeHtml(label)}${since ? ` <span class="muted small">since ${escapeHtml(since)}</span>` : ""}</p>
        <p class="muted small">Next: ${escapeHtml(this.state(SYS.next))}</p></div>
      <div class="seg" role="radiogroup" aria-label="System mode">${[["auto", "Auto"], ["cool", "Cool"], ["heat", "Heat"], ["off", "Off"]].map(([k, l]) =>
        `<button id="mode-${k}" role="radio" aria-checked="${system === k}" ${disabled}>${l}</button>`).join("")}</div>
      <p class="small">${line}</p>
      ${this.errorHtml()}
    </ha-card>`;
    for (const k of ["auto", "cool", "heat", "off"]) {
      this.bind(`mode-${k}`, () => system === k ? false : this.call("input_select", "select_option", { entity_id: SYS.system, option: k }));
    }
  }
}

class HvacRoomCard extends HvacCard {
  constructor() {
    super();
    this.panel = null; // Browser-local, so one phone never opens another's panel.
    this.draft = null;
    this.details = false;
    this.points = [];
    this._historyAt = 0;
  }
  setConfig(config) {
    if (!ROOMS[config?.room]) throw new Error("hvac-room-card needs room: office, bedroom or living_room");
    this.config = config;
  }
  getCardSize() { return 7; }
  getGridOptions() { return { columns: 12, rows: "auto", min_columns: 6 }; }
  async loadHistory() {
    const id = ent(this.config.room).temp;
    if (!this._hass?.callWS || Date.now() - this._historyAt < 300000) return;
    this._historyAt = Date.now();
    try {
      const res = await this._hass.callWS({ type: "history/history_during_period", entity_ids: [id],
        start_time: new Date(Date.now() - 6 * 3600000).toISOString(), minimal_response: true, no_attributes: true });
      this.points = (res?.[id] ?? []).map(p => [(p.lu ?? p.lc ?? 0) * 1000, Number.parseFloat(p.s)])
        .filter(([t, v]) => t > 0 && Number.isFinite(v));
    } catch { this.points = []; }
    this.render();
  }
  spark(temp, heat, cool, mode) {
    const now = Date.now(), start = now - 6 * 3600000, W = 300, H = 72, P = 6;
    const pts = this.points.map(([t, v]) => [Math.max(t, start), v]);
    if (temp != null) pts.push([now, temp]);
    if (pts.length < 2) return "";
    const vals = pts.map(p => p[1]), lo = Math.min(...vals) - 1.5, hi = Math.max(...vals) + 1.5;
    const x = t => P + (W - 2 * P) * (t - start) / (now - start), y = v => P + (H - 2 * P) * (hi - v) / (hi - lo);
    const line = pts.map(([t, v], i) => `${i ? "L" : "M"}${x(t).toFixed(1)} ${y(v).toFixed(1)}`).join("");
    const area = `${line}L${x(now).toFixed(1)} ${H - P}L${x(pts[0][0]).toFixed(1)} ${H - P}Z`;
    const edge = (v, label) => v != null && v > lo && v < hi ? `<line class="edge" x1="${P}" x2="${W - P}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}"/>
      <text x="${W - P}" y="${Math.max(y(v) - 3, 10).toFixed(1)}" text-anchor="end">${label}</text>` : "";
    const band = mode === "auto" && heat != null && cool != null ? [y(Math.min(cool, hi)), y(Math.max(heat, lo))] : null;
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" role="img" aria-label="Temperature over the last 6 hours">
      ${band && band[1] > band[0] ? `<rect class="band" x="${P}" y="${band[0].toFixed(1)}" width="${W - 2 * P}" height="${(band[1] - band[0]).toFixed(1)}"/>` : ""}
      ${mode === "auto" || mode === "cool" ? edge(cool, `cool ${cool}°`) : ""}${mode === "auto" || mode === "heat" ? edge(heat, `heat ${heat}°`) : ""}
      <path class="area" d="${area}"/><path class="line" d="${line}"/>
      <circle class="dot" cx="${x(now).toFixed(1)}" cy="${y(pts[pts.length - 1][1]).toFixed(1)}" r="3.5"/></svg>`;
  }
  note(status, maxRooms, maxMode, paused) {
    if (paused) return ["warn", `Paused while ${names(maxRooms)} ${maxRooms.length > 1 ? "run" : "runs"} max ${maxMode}.`];
    if (QUIET.includes(status) || status.startsWith("Max ")) return null;
    return STATUS[status] ?? [status.startsWith("Paused") || status.startsWith("Needs") ? "warn" : "info", status];
  }
  open(kind, start) {
    if (this.panel === kind) { this.panel = null; this.draft = null; }
    else { this.panel = kind; this.draft = start; }
    this.render(true);
  }
  async submit(domain, service, data) {
    if (await this.call(domain, service, data)) { this.panel = null; this.draft = null; this.render(true); }
  }
  adjustPanel(temp, requested, disabled) {
    const d = this.draft, gap = this.config.gap ?? 5;
    let explain;
    if (!d.on) explain = "The room stays off for this time, even if it drifts past its band.";
    else if (requested === "cool") explain = `Cools whenever the room is above ${d.n}°.`;
    else if (requested === "heat") explain = `Heats whenever the room is below ${d.n}°.`;
    else if (requested === "auto" && temp != null) explain = temp > d.n
      ? `Room is ${temp.toFixed(1)}°, so it cools above ${d.n}° and only heats below ${d.n - gap}°.`
      : `Room is ${temp.toFixed(1)}°, so it heats below ${d.n}° and only cools above ${d.n + gap}°.`;
    else explain = "Takes effect when a mode is on.";
    return `<div class="panel">
      <div class="stepper"><button id="down" aria-label="Lower target" ${disabled}>−</button><output aria-live="polite">${d.n}°</output><button id="up" aria-label="Raise target" ${disabled}>+</button></div>
      <p class="muted small">${explain}</p>
      <div class="chips" role="group" aria-label="For how long">${HOLD_MINUTES.map(m => `<button id="dur-${m}" aria-pressed="${d.minutes === m}" ${disabled}>${duration(m)}</button>`).join("")}</div>
      <div class="switchrow"><label for="on">Run this room</label><input id="on" type="checkbox" role="switch" ${d.on ? "checked" : ""} ${disabled}></div>
      <button id="more" class="link start" aria-expanded="${d.more}">Fan and airflow</button>
      ${d.more ? `<div class="selects"><label>Fan<select id="fan" ${disabled}>${options(FAN, d.fan)}</select></label>
        <label>Airflow<select id="airflow" ${disabled}>${options(AIRFLOW, d.airflow)}</select></label></div>` : ""}
      <div class="row"><button id="apply" class="primary" ${disabled}>${d.on ? `Hold ${d.n}° for ${duration(d.minutes)}` : `Turn off for ${duration(d.minutes)}`}</button><button id="cancel">Cancel</button></div>
    </div>`;
  }
  maxPanel(maxRooms, maxMode, disabled) {
    const r = this.config.room, others = maxRooms.filter(k => k !== r), minutes = this.config.max_minutes ?? 20;
    const text = maxRooms.includes(r) ? `Running max ${maxMode}. Pressing either again restarts the ${minutes} min.`
      : others.length ? `Max ${maxMode} is running in ${names(others)}. The same mode adds this room; the other mode replaces it.`
      : `Coldest or hottest setting with the top fan for ${minutes} min. Every other room pauses until it ends.`;
    return `<div class="panel">
      <div class="maxbtns"><button id="max-cool" class="cool" ${disabled}><ha-icon icon="mdi:snowflake"></ha-icon>Max cool</button>
        <button id="max-heat" class="heat" ${disabled}><ha-icon icon="mdi:fire"></ha-icon>Max heat</button></div>
      <p class="muted small">${escapeHtml(text)}</p>
    </div>`;
  }
  napPanel(requested, disabled) {
    const d = this.draft, nap = this.config.nap, off = !["cool", "heat", "auto"].includes(requested);
    return `<div class="panel">
      <p class="muted small">${off ? "Turn on a mode first. A nap needs heating or cooling to run."
        : `Sleep settings: keeps ${nap.heat}–${nap.cool}°, quiet fan, comfort airflow. The schedule takes over when it ends.`}</p>
      <div class="chips" role="group" aria-label="Nap length">${NAP_MINUTES.map(m => `<button id="nap-${m}" aria-pressed="${d.minutes === m}" ${disabled}>${duration(m)}</button>`).join("")}</div>
      <div class="row"><button id="nap-go" class="primary" ${off || this.busy ? "disabled" : ""}>Start ${duration(d.minutes)} nap</button><button id="cancel">Cancel</button></div>
    </div>`;
  }
  render(force = false) {
    if (!this._hass || !this.config) return;
    this.loadHistory();
    const r = this.config.room, E = ent(r);
    const watched = [...Object.values(E), SYS.requested, SYS.maxMode, SYS.block, ...Object.keys(ROOMS).map(k => `timer.hvac_max_${k}`)];
    if (!this.changed(watched, [this.panel, this.draft, this.details, this.points.length], force)) return;
    const temp = this.num(E.temp), hum = this.num(E.hum), cool = this.num(E.cool), heat = this.num(E.heat);
    const requested = this.state(SYS.requested), status = this.state(E.status), activity = this.state(E.activity);
    const maxRooms = this.maxRooms(), maxed = maxRooms.includes(r), maxMode = this.state(SYS.maxMode);
    const holding = this.active(E.override), roomOff = holding && this.state(E.enable) === "off";
    const paused = maxRooms.length > 0 && !maxed;
    const disabled = this.busy ? "disabled" : "";
    const pill = paused || status.startsWith("Paused") ? ["Paused", "warn", ""]
      : { Cooling: ["Cooling", "cool", "mdi:snowflake"], Heating: ["Heating", "heat", "mdi:fire"] }[activity]
      ?? [["unknown", "unavailable"].includes(activity) ? "Unknown" : activity, "", ""];
    const show = v => v ?? "—";
    const band = roomOff ? "Off for now" : requested === "auto" ? `Keeps <b>${show(heat)}–${show(cool)}°</b>`
      : requested === "cool" ? `Cools above <b>${show(cool)}°</b>` : requested === "heat" ? `Heats below <b>${show(heat)}°</b>` : "System off";
    let source;
    if (maxed) {
      const end = this.finishes(E.max), left = end ? Math.max(1, Math.ceil((end - Date.now()) / 60000)) : null;
      source = `<div class="banner ${maxMode === "heat" ? "heat" : "cool"}"><span><b>Max ${escapeHtml(maxMode)}</b>${left ? ` · ${left} min left` : ""}</span><button id="stop" ${disabled}>Stop</button></div>`;
    } else if (holding) {
      const end = this.finishes(E.override), label = this.state(E.label);
      source = `<div class="source"><span>${escapeHtml(["unknown", "unavailable", ""].includes(label) ? "Override" : label)}${end ? ` until ${clockTime(end)}` : ""}</span>
        <button id="resume" class="link" ${disabled}>Back to schedule</button></div>`;
    } else source = `<div class="source"><span>Schedule · ${escapeHtml(this.state(SYS.block).split(" since ")[0])}</span></div>`;
    const note = this.note(status, maxRooms, maxMode, paused);
    const kinds = [["adjust", "Adjust"], ["max", "Max"], ...(this.config.nap ? [["nap", "Nap"]] : [])];
    const panel = this.panel === "adjust" ? this.adjustPanel(temp, requested, disabled)
      : this.panel === "max" ? this.maxPanel(maxRooms, maxMode, disabled)
      : this.panel === "nap" ? this.napPanel(requested, disabled) : "";
    const climate = this.state(E.climate), setpoint = this.attr(E.climate, "temperature");
    const details = this.details ? `<dl class="details">
        <dt>Priority</dt><dd>${escapeHtml(this.state(E.priority))}</dd>
        <dt>Last command</dt><dd>${climate === "off" ? "Off" : `${escapeHtml(climate)} at ${escapeHtml(setpoint ?? "—")}°`}</dd>
        <dt>Fan · airflow</dt><dd>${escapeHtml(this.state(E.fan))} · ${escapeHtml(this.state(E.airflow))}</dd></dl>
      <p class="muted small">IR has no acknowledgement, so this is what was sent, not what the unit confirmed.</p>` : "";
    this.shadowRoot.innerHTML = `<style>${CSS}</style><ha-card class="${paused ? "paused" : ""}">
      <div class="head"><ha-icon icon="${escapeHtml(this.config.icon ?? "mdi:thermometer")}"></ha-icon><h2>${ROOMS[r]}</h2>
        <span class="pill ${pill[1]}">${pill[2] ? `<ha-icon icon="${pill[2]}"></ha-icon>` : ""}${escapeHtml(pill[0])}</span></div>
      <div class="reading"><div class="temp">${temp == null ? "—" : temp.toFixed(1)}<span>°F</span></div>
        <div class="meta"><div>${band}</div>${hum == null ? "" : `<div>${Math.round(hum)}% humidity</div>`}</div></div>
      ${this.spark(temp, heat, cool, requested)}
      ${source}
      ${note ? `<div class="note ${note[0]}">${escapeHtml(note[1])}</div>` : ""}
      <div class="actions">${kinds.map(([k, l]) => `<button id="open-${k}" aria-expanded="${this.panel === k}" ${disabled}>${l}</button>`).join("")}</div>
      ${panel}
      ${details}
      ${this.errorHtml()}
      <div class="foot"><button id="details" class="link" aria-expanded="${this.details}">${this.details ? "Hide details" : "Details"}</button></div>
    </ha-card>`;

    const label = this.state(E.label), held = holding && /(\d+)°/.exec(label);
    const startN = held ? Number(held[1]) : requested === "cool" && cool != null ? cool : requested === "heat" && heat != null ? heat : Math.round(temp ?? 72);
    const savedNap = this.num("input_number.hvac_nap_minutes");
    this.bind("open-adjust", () => this.open("adjust", { n: Math.min(86, Math.max(60, startN)), minutes: 60, on: true, more: false, fan: "schedule", airflow: "schedule" }));
    this.bind("open-max", () => this.open("max", {}));
    this.bind("open-nap", () => this.open("nap", { minutes: NAP_MINUTES.includes(savedNap) ? savedNap : 60 }));
    this.bind("stop", () => this.call("timer", "cancel", { entity_id: E.max }));
    this.bind("resume", () => this.call("script", "hvac_apply_override", { room: r, operation: "resume" }));
    this.bind("details", () => { this.details = !this.details; this.render(true); });
    this.bind("cancel", () => this.open(this.panel));
    const d = this.draft, set = (key, value) => { d[key] = value; this.render(true); };
    if (this.panel === "adjust") {
      this.bind("down", () => set("n", Math.max(60, d.n - 1)));
      this.bind("up", () => set("n", Math.min(86, d.n + 1)));
      for (const m of HOLD_MINUTES) this.bind(`dur-${m}`, () => set("minutes", m));
      this.bind("on", e => set("on", e.target.checked), "onchange");
      this.bind("more", () => set("more", !d.more));
      this.bind("fan", e => set("fan", e.target.value), "onchange");
      this.bind("airflow", e => set("airflow", e.target.value), "onchange");
      this.bind("apply", () => this.submit("script", "hvac_apply_override",
        { room: r, minutes: d.minutes, temperature: d.n, enabled: d.on, fan: d.fan, airflow: d.airflow }));
    } else if (this.panel === "max") {
      for (const mode of ["cool", "heat"]) this.bind(`max-${mode}`, () => this.submit("script", "hvac_start_max", { rooms: [r], hvac_mode: mode }));
    } else if (this.panel === "nap") {
      for (const m of NAP_MINUTES) this.bind(`nap-${m}`, () => set("minutes", m));
      this.bind("nap-go", () => this.submit("script", "hvac_start_nap", { minutes: d.minutes }));
    }
  }
}

customElements.define("hvac-system-card", HvacSystemCard);
customElements.define("hvac-room-card", HvacRoomCard);
window.customCards = window.customCards || [];
window.customCards.push({ type: "hvac-system-card", name: "HVAC system", description: "Shared mode, schedule block and auto status" },
  { type: "hvac-room-card", name: "HVAC room", description: "One room's reading, band, hold, max and nap" });
