//! RongYuan RY5088 Hall-effect keyboards, driven through the monsgeek-akko-linux
//! libraries: https://github.com/echtzeit-solutions/monsgeek-akko-linux
//! Key grids come from that project's device database.

use crate::hidraw::Node;
use monsgeek_keyboard::led::{DAZZLE_OFF, DAZZLE_ON};
use monsgeek_keyboard::{
    KeyMode, KeyTriggerSettings, KeyboardError, KeyboardInterface, KeyboardOptions, LedMode, LedParams,
    ModeByte, PollingRate, Precision, ProtocolFamily, RgbColor, TravelDepth, TriggerSettings,
};
use monsgeek_transport::protocol::Profile;
use serde::Deserialize;
use std::fmt::Display;
use std::io;
use std::thread::sleep;
use std::time::Duration;

const VENDOR: u16 = 0x3151;
// A bulk magnetism write needs this long before reads come back right.
const SETTLE: Duration = Duration::from_millis(300);

pub struct Model {
    pub id: u32,
    pub name: &'static str,
    /// Positions in the firmware's per-key tables, empty slots included.
    grid: u8,
    /// Grid positions that hold a magnetic switch.
    keys: &'static [u8],
}

const H60PRO_US: &[u8] = &[
    1, 2, 3, 4, 5, 7, 8, 9, 11, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 31, 32, 33, 34, 37, 38, 39, 40, 41,
    43, 44, 45, 46, 49, 50, 51, 52, 55, 56, 57, 58, 61, 62, 63, 64, 65, 67, 68, 69, 70, 73, 74, 76, 77, 79, 80, 81, 83,
];
const H60PRO_UK: &[u8] = &[
    1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 31, 32, 33, 34, 37, 38, 39, 40,
    41, 43, 44, 45, 46, 49, 50, 51, 52, 55, 56, 57, 58, 61, 62, 63, 64, 65, 67, 68, 69, 70, 73, 74, 75, 76, 77, 79, 81,
    83,
];

/// Models keyed by the device ID the firmware reports (`GET_USB_VERSION`).
pub const MODELS: [Model; 2] = [
    Model { id: 2764, name: "BOYI H60Pro", grid: 84, keys: H60PRO_US },
    Model { id: 2875, name: "BOYI H60Pro (UK)", grid: 84, keys: H60PRO_UK },
];

/// Lighting effects by name; the picture, music and screen-sync modes are left out.
const EFFECTS: [(&str, u8); 21] = [
    ("off", 0),
    ("constant", 1),
    ("breathing", 2),
    ("neon", 3),
    ("wave", 4),
    ("ripple", 5),
    ("raindrop", 6),
    ("snake", 7),
    ("reactive", 8),
    ("converge", 9),
    ("sine-wave", 10),
    ("kaleidoscope", 11),
    ("line-wave", 12),
    ("laser", 14),
    ("circle-wave", 15),
    ("starry", 16),
    ("aurora", 17),
    ("flash-away", 18),
    ("layered", 19),
    ("train", 23),
    ("fireworks", 24),
];

fn effect_name(mode: LedMode) -> String {
    let code = mode as u8;
    EFFECTS.iter().find(|(_, c)| *c == code).map(|(n, _)| n.to_string()).unwrap_or_else(|| format!("mode {code}"))
}

fn other(e: impl Display) -> io::Error {
    io::Error::other(e.to_string())
}

/// The RY5088 config interface (usage page 0xFFFF, usage 2). PIDs 0x40xx are YiChip boards,
/// which speak a different dialect.
pub fn is_config_node(n: &Node) -> bool {
    n.vid == VENDOR && n.pid & 0xFF00 != 0x4000 && n.descriptor.windows(5).any(|w| w == [0x06, 0xFF, 0xFF, 0x09, 0x02])
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Lighting {
    pub effect: Option<String>,
    pub brightness: Option<u8>,
    pub speed: Option<u8>,
    /// "#rrggbb"
    pub color: Option<String>,
    /// Cycle through rainbow colours instead of one colour.
    pub rainbow: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RapidTrigger {
    pub enable: bool,
    pub press: Option<f64>,
    pub release: Option<f64>,
}

/// `None` leaves a setting as the keyboard has it.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Settings {
    /// Only log what would change on this keyboard.
    #[serde(default)]
    pub dry_run: bool,
    pub polling_rate: Option<u16>,
    pub debounce_ms: Option<u8>,
    pub lighting: Lighting,
    pub fn_layer: Option<u8>,
    pub anti_mistouch: Option<bool>,
    pub rt_stability_ms: Option<u16>,
    pub wasd_swap: bool,
    pub actuation: f64,
    /// Defaults to the actuation point.
    pub release: Option<f64>,
    pub rapid_trigger: RapidTrigger,
    pub top_deadzone: Option<f64>,
    pub bottom_deadzone: Option<f64>,
}

fn parse_color(s: &str) -> Option<RgbColor> {
    let hex = s.strip_prefix('#')?;
    if hex.len() != 6 {
        return None;
    }
    let v = u32::from_str_radix(hex, 16).ok()?;
    Some(RgbColor::new((v >> 16) as u8, (v >> 8) as u8, v as u8))
}

impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        if let Some(hz) = self.polling_rate.filter(|hz| PollingRate::from_hz(*hz).is_none()) {
            return Err(format!("polling rate {hz} is not 125, 250, 500, 1000, 2000, 4000 or 8000"));
        }
        if let Some(ms) = self.debounce_ms.filter(|ms| *ms > 50) {
            return Err(format!("debounce {ms} ms is above 50"));
        }
        if let Some(ms) = self.rt_stability_ms.filter(|ms| !ms.is_multiple_of(25) || *ms > 125) {
            return Err(format!("rtStabilityMs {ms} is not a multiple of 25 up to 125"));
        }
        let l = &self.lighting;
        if let Some(e) = &l.effect {
            if !EFFECTS.iter().any(|(n, _)| n == e) {
                return Err(format!("unknown lighting effect {e:?}"));
            }
        }
        if l.brightness.is_some_and(|b| b > 4) || l.speed.is_some_and(|s| s > 4) {
            return Err("lighting brightness and speed go from 0 to 4".into());
        }
        if l.color.as_deref().is_some_and(|c| parse_color(c).is_none()) {
            return Err(format!("lighting color {:?} is not #rrggbb", l.color));
        }
        if self.fn_layer.is_some_and(|f| f > 1) {
            return Err("fnLayer is 0 or 1".into());
        }
        let travels = [Some(self.actuation), self.release];
        if travels.into_iter().flatten().any(|mm| !(0.1..=3.3).contains(&mm)) {
            return Err("actuation and release must be 0.1-3.3 mm".into());
        }
        let rt = &self.rapid_trigger;
        if [rt.press, rt.release].into_iter().flatten().any(|mm| !(0.01..=2.0).contains(&mm)) {
            return Err("rapid trigger sensitivity must be 0.01-2.0 mm".into());
        }
        if [self.top_deadzone, self.bottom_deadzone].into_iter().flatten().any(|mm| !(0.0..=1.0).contains(&mm)) {
            return Err("dead zones must be 0-1 mm".into());
        }
        Ok(())
    }
}

/// What planning needs to know about a board, apart from the live connection.
pub struct Layout {
    pub model: &'static Model,
    precision: Precision,
}

pub struct Keyboard {
    layout: Layout,
    kb: KeyboardInterface,
}

impl std::ops::Deref for Keyboard {
    type Target = Layout;
    fn deref(&self) -> &Layout {
        &self.layout
    }
}

pub enum Opened {
    Known(Keyboard),
    /// A RongYuan board whose key grid we don't know yet, by device ID.
    Unknown(u32),
}

/// Open the keyboard behind a hidraw node and identify its model.
pub fn open(node: &Node) -> io::Result<Opened> {
    let path = node.dev.to_string_lossy();
    let devices = monsgeek_keyboard::list_keyboards().map_err(other)?;
    let device = devices
        .iter()
        .find(|d| d.info.device_path == path)
        .ok_or_else(|| other("the keyboard library doesn't list this node"))?;
    let transport = monsgeek_transport::open_device_sync(device).map_err(other)?;
    let probe = KeyboardInterface::new(transport.clone(), 0, true, ProtocolFamily::Ry5088);
    let id = probe.get_device_id().map_err(other)?;
    let Some(model) = MODELS.iter().find(|m| m.id == id) else {
        return Ok(Opened::Unknown(id));
    };
    let kb = KeyboardInterface::new(transport, model.grid, true, ProtocolFamily::Ry5088);
    let precision = kb.get_precision().map_err(other)?;
    Ok(Opened::Known(Keyboard { layout: Layout { model, precision }, kb }))
}

pub struct Observed {
    profile: u8,
    rate: Option<PollingRate>,
    debounce: u8,
    led: LedParams,
    options: KeyboardOptions,
    triggers: TriggerSettings,
}

#[derive(Default)]
pub struct Plan {
    pub changes: Vec<String>,
    profile: bool,
    rate: Option<PollingRate>,
    debounce: Option<u8>,
    options: Option<KeyboardOptions>,
    led: Option<LedParams>,
    keys: Vec<KeyTriggerSettings>,
    rt_press: Option<u16>,
    rt_lift: Option<u16>,
    top: Option<u16>,
    bottom: Option<u16>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        !self.profile
            && self.rate.is_none()
            && self.debounce.is_none()
            && self.options.is_none()
            && self.led.is_none()
            && self.keys.is_empty()
            && self.rt_press.is_none()
            && self.rt_lift.is_none()
            && self.top.is_none()
            && self.bottom.is_none()
    }
}

fn rate_name(rate: Option<PollingRate>) -> String {
    rate.map(|r| format!("{} Hz", r.to_hz())).unwrap_or_else(|| "unknown".into())
}

fn color_name(c: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", c.r, c.g, c.b)
}

impl Keyboard {
    pub fn observe(&self) -> io::Result<Observed> {
        let profile = self.kb.get_profile().map_err(other)?;
        self.kb.set_active_profile(profile);
        Ok(Observed {
            profile: profile.get(),
            rate: self.kb.get_polling_rate().ok(),
            debounce: self.kb.get_debounce().map_err(other)?,
            led: self.kb.get_led_params().map_err(other)?,
            options: self.kb.get_kb_options().map_err(other)?,
            triggers: self.kb.get_all_triggers().map_err(other)?,
        })
    }

    fn execute(&self, p: &Plan) -> io::Result<()> {
        let kb = &self.kb;
        if p.profile {
            // Everything else is per profile, so re-plan after switching.
            let first = Profile::try_from(0u8).map_err(other)?;
            kb.set_profile(first).map_err(other)?;
            kb.set_active_profile(first);
            sleep(SETTLE);
            return Ok(());
        }
        if let Some(r) = p.rate {
            kb.set_polling_rate(r).map_err(other)?;
        }
        if let Some(d) = p.debounce {
            kb.set_debounce(d).map_err(other)?;
        }
        if let Some(o) = &p.options {
            kb.set_kb_options(o).map_err(other)?;
        }
        if let Some(l) = &p.led {
            kb.set_led_params(l).map_err(other)?;
        }
        for key in &p.keys {
            kb.set_key_trigger(key).map_err(other)?;
        }
        type Bulk = fn(&KeyboardInterface, TravelDepth) -> Result<(), KeyboardError>;
        let bulk: [(Option<u16>, Bulk); 4] = [
            (p.rt_press, KeyboardInterface::set_rt_press_all),
            (p.rt_lift, KeyboardInterface::set_rt_lift_all),
            (p.top, KeyboardInterface::set_top_deadzone_all),
            (p.bottom, KeyboardInterface::set_bottom_deadzone_all),
        ];
        for (value, set) in bulk {
            if let Some(v) = value {
                set(kb, TravelDepth::from_raw(v)).map_err(other)?;
            }
        }
        sleep(SETTLE);
        Ok(())
    }

    /// Bring the keyboard to `s`, then read it back until nothing is left to change.
    pub fn apply(&self, s: &Settings) -> io::Result<Vec<String>> {
        let mut changes = Vec::new();
        for round in 0..4 {
            let p = self.plan(s, &self.observe()?);
            if p.is_empty() {
                return Ok(changes);
            }
            if round == 3 {
                return Err(other(format!("the keyboard would not settle: {}", p.changes.join("; "))));
            }
            self.execute(&p)?;
            changes.extend(p.changes);
        }
        unreachable!()
    }
}

impl Layout {
    fn mm(&self, raw: u16) -> String {
        format!("{} mm", TravelDepth::from_raw(raw).format_mm(self.precision))
    }

    fn raw(&self, mm: f64) -> u16 {
        TravelDepth::from_mm(mm as f32, self.precision).raw()
    }

    /// The distinct values a per-key table holds across the real keys, for the log.
    fn spread(&self, values: &[u16]) -> String {
        let mut seen: Vec<u16> = self.model.keys.iter().map(|&k| values.get(k as usize).copied().unwrap_or(0)).collect();
        seen.sort_unstable();
        seen.dedup();
        seen.iter().map(|v| self.mm(*v)).collect::<Vec<_>>().join(", ")
    }

    fn uniform(&self, values: &[u16], want: u16) -> bool {
        self.model.keys.iter().all(|&k| values.get(k as usize) == Some(&want))
    }

    pub fn plan(&self, s: &Settings, obs: &Observed) -> Plan {
        let mut p = Plan::default();
        if obs.profile != 0 {
            p.profile = true;
            p.changes.push(format!("onboard profile {} -> 1", obs.profile + 1));
        }

        if let Some(hz) = s.polling_rate {
            let rate = PollingRate::from_hz(hz);
            if obs.rate != rate {
                p.rate = rate;
                p.changes.push(format!("polling rate {} -> {hz} Hz", rate_name(obs.rate)));
            }
        }
        if let Some(ms) = s.debounce_ms.filter(|ms| *ms != obs.debounce) {
            p.debounce = Some(ms);
            p.changes.push(format!("debounce {} -> {ms} ms", obs.debounce));
        }

        let have = obs.options;
        let want = KeyboardOptions {
            fn_layer: s.fn_layer.unwrap_or(have.fn_layer),
            anti_mistouch: s.anti_mistouch.unwrap_or(have.anti_mistouch),
            rt_stability: s.rt_stability_ms.map_or(have.rt_stability, |ms| (ms / 25) as u8),
            wasd_swap: s.wasd_swap,
            ..have
        };
        if want != have {
            p.options = Some(want);
            p.changes.push(format!("keyboard options {have:?} -> {want:?}"));
        }

        let l = &s.lighting;
        let mut led = obs.led.clone();
        if let Some(code) = l.effect.as_ref().and_then(|e| EFFECTS.iter().find(|(n, _)| n == e)).map(|(_, c)| *c) {
            led.mode = LedMode::from_u8(code).unwrap_or(led.mode);
        }
        led.brightness = l.brightness.unwrap_or(led.brightness);
        led.speed = l.speed.unwrap_or(led.speed);
        if let Some(c) = l.color.as_deref().and_then(parse_color) {
            led.color = c;
        }
        if let Some(rainbow) = l.rainbow {
            led.direction = (led.direction & 0xF0) | if rainbow { DAZZLE_ON } else { DAZZLE_OFF };
        }
        let o = &obs.led;
        if (led.mode, led.brightness, led.speed, led.color, led.direction)
            != (o.mode, o.brightness, o.speed, o.color, o.direction)
        {
            p.changes.push(format!(
                "lighting {} brightness {} speed {} {} -> {} brightness {} speed {} {}",
                effect_name(o.mode),
                o.brightness,
                o.speed,
                color_name(o.color),
                effect_name(led.mode),
                led.brightness,
                led.speed,
                color_name(led.color),
            ));
            p.led = Some(led);
        }

        // Actuation, release and mode go per key: the bulk mode write is cut off at 63 bytes.
        let t = &obs.triggers;
        let press = self.raw(s.actuation);
        let lift = self.raw(s.release.unwrap_or(s.actuation));
        let mode = ModeByte::new(KeyMode::Normal, s.rapid_trigger.enable).to_u8();
        if !self.uniform(&t.press_travel, press) {
            p.changes.push(format!("actuation {} -> {}", self.spread(&t.press_travel), self.mm(press)));
        }
        if !self.uniform(&t.lift_travel, lift) {
            p.changes.push(format!("release {} -> {}", self.spread(&t.lift_travel), self.mm(lift)));
        }
        let modes_differ = self.model.keys.iter().any(|&k| t.key_modes.get(k as usize) != Some(&mode));
        if modes_differ {
            let mut have: Vec<String> = self
                .model
                .keys
                .iter()
                .map(|&k| ModeByte::from_u8(t.key_modes.get(k as usize).copied().unwrap_or(0)).to_string())
                .collect();
            have.sort();
            have.dedup();
            p.changes.push(format!("key mode {} -> {}", have.join(", "), ModeByte::from_u8(mode)));
        }
        for &k in self.model.keys {
            let i = k as usize;
            if t.press_travel.get(i) != Some(&press) || t.lift_travel.get(i) != Some(&lift) || t.key_modes.get(i) != Some(&mode)
            {
                p.keys.push(KeyTriggerSettings {
                    key_index: k,
                    actuation: press,
                    deactuation: lift,
                    mode: KeyMode::Normal,
                    rapid_trigger: s.rapid_trigger.enable,
                });
            }
        }

        let mut bulk = |name: &str, values: &[u16], want: Option<u16>| -> Option<u16> {
            let want = want?;
            if self.uniform(values, want) {
                return None;
            }
            p.changes.push(format!("{name} {} -> {}", self.spread(values), self.mm(want)));
            Some(want)
        };
        let rt_press = bulk("rapid trigger press", &t.rt_press, s.rapid_trigger.press.map(|mm| self.raw(mm)));
        let rt_lift = bulk("rapid trigger release", &t.rt_lift, s.rapid_trigger.release.map(|mm| self.raw(mm)));
        let top = bulk("top dead zone", &t.top_deadzone, s.top_deadzone.map(|mm| self.raw(mm)));
        let bottom = bulk("bottom dead zone", &t.bottom_deadzone, s.bottom_deadzone.map(|mm| self.raw(mm)));
        (p.rt_press, p.rt_lift, p.top, p.bottom) = (rt_press, rt_lift, top, bottom);
        p
    }

    pub fn summary(&self, obs: &Observed) -> Vec<String> {
        let t = &obs.triggers;
        let o = &obs.options;
        let mut modes: Vec<String> = self
            .model
            .keys
            .iter()
            .map(|&k| ModeByte::from_u8(t.key_modes.get(k as usize).copied().unwrap_or(0)).to_string())
            .collect();
        modes.sort();
        modes.dedup();
        vec![
            format!("model             {} (id {}), {} keys, {:?} precision", self.model.name, self.model.id, self.model.keys.len(), self.precision),
            format!("onboard profile   {}", obs.profile + 1),
            format!("polling rate      {}", rate_name(obs.rate)),
            format!("debounce          {} ms", obs.debounce),
            format!(
                "lighting          {} brightness {} speed {} {}{} (option byte {:02x})",
                effect_name(obs.led.mode),
                obs.led.brightness,
                obs.led.speed,
                color_name(obs.led.color),
                if obs.led.direction & 0x0F == DAZZLE_ON { " rainbow" } else { "" },
                obs.led.direction
            ),
            format!(
                "options           fn layer {}, anti-mistouch {}, RT stability {} ms, WASD swap {}, OS mode {}",
                o.fn_layer,
                o.anti_mistouch,
                o.rt_stability_ms(),
                o.wasd_swap,
                o.os_mode
            ),
            format!("key modes         {}", modes.join(", ")),
            format!("actuation         {}", self.spread(&t.press_travel)),
            format!("release           {}", self.spread(&t.lift_travel)),
            format!("RT press/release  {} / {}", self.spread(&t.rt_press), self.spread(&t.rt_lift)),
            format!("dead zones        top {} / bottom {}", self.spread(&t.top_deadzone), self.spread(&t.bottom_deadzone)),
        ]
    }
}

impl Layout {
    /// The keyboard's current state as a Nix snippet for the home-manager module.
    pub fn nix(&self, obs: &Observed) -> String {
        let t = &obs.triggers;
        let mm = |values: &[u16]| -> (String, Option<String>) {
            let v = self.model.keys.first().and_then(|&k| values.get(k as usize)).copied().unwrap_or(0);
            let note = (!self.uniform(values, v)).then(|| format!("varies per key: {}", self.spread(values)));
            (TravelDepth::from_raw(v).format_mm(self.precision), note)
        };
        let code = obs.led.mode as u8;
        let effect = EFFECTS.iter().find(|(_, c)| *c == code);
        let o = &obs.options;
        let rt = obs.triggers.key_modes.get(self.model.keys[0] as usize).is_some_and(|m| m & ModeByte::RT_FLAG != 0);
        let (actuation, actuation_note) = mm(&t.press_travel);
        let (release, release_note) = mm(&t.lift_travel);
        let (rt_press, rt_press_note) = mm(&t.rt_press);
        let (rt_lift, rt_lift_note) = mm(&t.rt_lift);
        let (top, top_note) = mm(&t.top_deadzone);
        let (bottom, bottom_note) = mm(&t.bottom_deadzone);
        let lines: Vec<(&str, String, Option<String>)> = vec![
            (
                "pollingRate",
                obs.rate.map(|r| r.to_hz().to_string()).unwrap_or_else(|| "8000".into()),
                obs.rate.is_none().then(|| "unreadable".to_string()),
            ),
            ("debounceMs", obs.debounce.to_string(), None),
            ("lighting.effect", format!("\"{}\"", effect.map_or("constant", |(n, _)| n)), effect.is_none().then(|| format!("mode {code}"))),
            ("lighting.brightness", obs.led.brightness.to_string(), None),
            ("lighting.speed", obs.led.speed.to_string(), None),
            ("lighting.color", format!("\"{}\"", color_name(obs.led.color)), None),
            ("lighting.rainbow", (obs.led.direction & 0x0F == DAZZLE_ON).to_string(), None),
            ("fnLayer", o.fn_layer.to_string(), None),
            ("antiMistouch", o.anti_mistouch.to_string(), None),
            ("rtStabilityMs", o.rt_stability_ms().to_string(), None),
            ("wasdSwap", o.wasd_swap.to_string(), None),
            ("actuation", actuation, actuation_note),
            ("release", release, release_note),
            ("rapidTrigger.enable", rt.to_string(), None),
            ("rapidTrigger.press", rt_press, rt_press_note),
            ("rapidTrigger.release", rt_lift, rt_lift_note),
            ("topDeadzone", top, top_note),
            ("bottomDeadzone", bottom, bottom_note),
        ];
        let mut body = String::new();
        for (key, value, note) in lines {
            let note = note.map(|n| format!(" # {n}")).unwrap_or_default();
            body.push_str(&format!("  {key} = {value};{note}\n"));
        }
        format!("my.peripherals.boyi-h60pro = {{\n{body}}};")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn layout() -> Layout {
        Layout { model: &MODELS[0], precision: Precision::Medium }
    }

    fn settings() -> Settings {
        Settings {
            dry_run: false,
            polling_rate: Some(8000),
            debounce_ms: Some(1),
            lighting: Lighting { effect: None, brightness: Some(4), speed: Some(1), color: None, rainbow: None },
            fn_layer: None,
            anti_mistouch: None,
            rt_stability_ms: Some(0),
            wasd_swap: false,
            actuation: 1.0,
            release: None,
            rapid_trigger: RapidTrigger { enable: true, press: Some(0.2), release: Some(0.2) },
            top_deadzone: None,
            bottom_deadzone: None,
        }
    }

    // A keyboard with 2.0 mm actuation and rapid trigger off on every slot.
    fn observed(grid: usize) -> Observed {
        let mut triggers = TriggerSettings::new(grid);
        triggers.press_travel = vec![200; grid];
        triggers.lift_travel = vec![200; grid];
        triggers.rt_press = vec![30; grid];
        triggers.rt_lift = vec![30; grid];
        triggers.key_modes = vec![0; grid];
        triggers.top_deadzone = vec![0; grid];
        triggers.bottom_deadzone = vec![30; grid];
        Observed {
            profile: 0,
            rate: PollingRate::from_hz(1000),
            debounce: 5,
            led: LedParams {
                mode: LedMode::Wave,
                brightness: 2,
                speed: 2,
                color: RgbColor::new(255, 255, 255),
                direction: 0,
            },
            options: KeyboardOptions::default(),
            triggers,
        }
    }

    #[test]
    fn plans_every_requested_change() {
        let l = layout();
        let p = l.plan(&settings(), &observed(84));
        assert_eq!(p.rate, PollingRate::from_hz(8000));
        assert_eq!(p.debounce, Some(1));
        let led = p.led.as_ref().unwrap();
        assert_eq!((led.mode, led.brightness, led.speed), (LedMode::Wave, 4, 1), "unset effect stays");
        assert_eq!(p.keys.len(), MODELS[0].keys.len(), "every real key gets the new mode");
        assert!(p.keys.iter().all(|k| k.actuation == 100 && k.deactuation == 100 && k.rapid_trigger));
        assert_eq!((p.rt_press, p.rt_lift), (Some(20), Some(20)));
        assert_eq!((p.top, p.bottom), (None, None), "unset dead zones stay");
        assert!(p.options.is_none());
    }

    #[test]
    fn settled_keyboard_plans_nothing() {
        let l = layout();
        let s = settings();
        let mut obs = observed(84);
        obs.rate = PollingRate::from_hz(8000);
        obs.debounce = 1;
        obs.led.brightness = 4;
        obs.led.speed = 1;
        let t = &mut obs.triggers;
        for &k in MODELS[0].keys {
            let k = k as usize;
            (t.press_travel[k], t.lift_travel[k], t.key_modes[k]) = (100, 100, 0x80);
            (t.rt_press[k], t.rt_lift[k]) = (20, 20);
        }
        let p = l.plan(&s, &obs);
        assert!(p.is_empty(), "{:?}", p.changes);
    }

    #[test]
    fn validation() {
        settings().validate().unwrap();
        let mut s = settings();
        s.lighting.effect = Some("rainbow".into());
        assert!(s.validate().is_err());
        let mut s = settings();
        s.lighting.color = Some("ff00ff".into());
        assert!(s.validate().is_err());
        let mut s = settings();
        s.rt_stability_ms = Some(30);
        assert!(s.validate().is_err());
        assert_eq!(parse_color("#ff8000"), Some(RgbColor::new(255, 128, 0)));
    }

    #[test]
    fn grids_cover_their_keys() {
        for m in &MODELS {
            assert!(m.keys.iter().all(|&k| k < m.grid));
        }
    }
}
