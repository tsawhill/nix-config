//! RongYuan RY5088 Hall-effect keyboards, driven through the monsgeek-akko-linux
//! libraries: https://github.com/echtzeit-solutions/monsgeek-akko-linux
//! Key grids come from that project's device database.

use crate::hidraw::Node;
use monsgeek_keyboard::led::SPEED_MAX;
use monsgeek_keyboard::{
    KeyMode, KeyTriggerSettings, KeyboardError, KeyboardInterface, KeyboardOptions, LedMode, LedParams,
    ModeByte, PollingRate, ProtocolFamily, RgbColor, TravelDepth, TriggerSettings,
};
pub use monsgeek_keyboard::Precision;
use monsgeek_transport::ChecksumType;
use monsgeek_transport::protocol::Profile;
use monsgeek_transport::protocol::cmd::SET_LEDPARAM;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fmt::Display;
use std::io;
use std::thread::sleep;
use std::time::Duration;

const VENDOR: u16 = 0x3151;
// A bulk magnetism write needs this long before reads come back right.
const SETTLE: Duration = Duration::from_millis(300);
// Low nibble of the lighting option byte, as qmk.top writes it and an H60Pro confirmed
// (the library has them swapped).
const LIGHT_NORMAL: u8 = 7;
const LIGHT_RAINBOW: u8 = 8;

pub struct Model {
    pub id: u32,
    pub name: &'static str,
    /// Positions in the firmware's per-key tables, empty slots included.
    grid: u8,
    /// Grid positions that hold a magnetic switch, with the key's name.
    keys: &'static [(u8, &'static str)],
}

impl Model {
    fn positions(&self) -> impl Iterator<Item = u8> + '_ {
        self.keys.iter().map(|&(k, _)| k)
    }
    pub fn key_names(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.keys.iter().map(|&(_, n)| n)
    }
}

const H60PRO_US: &[(u8, &str)] = &[
    (1, "Esc"), (2, "Tab"), (3, "CapsLock"), (4, "LShift"), (5, "LCtrl"), (7, "1"), (8, "Q"), (9, "A"), (11, "LMeta"),
    (13, "2"), (14, "W"), (15, "S"), (16, "Z"), (17, "LAlt"), (19, "3"), (20, "E"), (21, "D"), (22, "X"), (25, "4"),
    (26, "R"), (27, "F"), (28, "C"), (31, "5"), (32, "T"), (33, "G"), (34, "V"), (37, "6"), (38, "Y"), (39, "H"),
    (40, "B"), (41, "Space"), (43, "7"), (44, "U"), (45, "J"), (46, "N"), (49, "8"), (50, "I"), (51, "K"), (52, "M"),
    (55, "9"), (56, "O"), (57, "L"), (58, ","), (61, "0"), (62, "P"), (63, ";"), (64, "."), (65, "RAlt"), (67, "-"),
    (68, "["), (69, "'"), (70, "/"), (73, "="), (74, "]"), (76, "RShift"), (77, "Application"), (79, "Backspace"),
    (80, "\\"), (81, "Enter"), (83, "RCtrl"),
];
const H60PRO_UK: &[(u8, &str)] = &[
    (1, "Esc"), (2, "Tab"), (3, "CapsLock"), (4, "LShift"), (5, "LCtrl"), (7, "1"), (8, "Q"), (9, "A"),
    (10, "IntlBackslash"), (11, "LMeta"), (13, "2"), (14, "W"), (15, "S"), (16, "Z"), (17, "LAlt"), (19, "3"), (20, "E"),
    (21, "D"), (22, "X"), (25, "4"), (26, "R"), (27, "F"), (28, "C"), (31, "5"), (32, "T"), (33, "G"), (34, "V"),
    (37, "6"), (38, "Y"), (39, "H"), (40, "B"), (41, "Space"), (43, "7"), (44, "U"), (45, "J"), (46, "N"), (49, "8"),
    (50, "I"), (51, "K"), (52, "M"), (55, "9"), (56, "O"), (57, "L"), (58, ","), (61, "0"), (62, "P"), (63, ";"),
    (64, "."), (65, "RAlt"), (67, "-"), (68, "["), (69, "'"), (70, "/"), (73, "="), (74, "]"), (75, "IntlHash"),
    (76, "RShift"), (77, "Application"), (79, "Backspace"), (81, "Enter"), (83, "RCtrl"),
];

/// Models keyed by the device ID the firmware reports (`GET_USB_VERSION`).
pub const MODELS: [Model; 2] = [
    Model { id: 2764, name: "BOYI H60Pro", grid: 84, keys: H60PRO_US },
    Model { id: 2875, name: "BOYI H60Pro (UK)", grid: 84, keys: H60PRO_UK },
];

/// Lighting effects as qmk.top names them for the H60Pro, by mode number (its
/// LIGHT_LIST order). The custom-picture, music and screen-sync modes are left out.
pub const EFFECTS: [(&str, u8); 19] = [
    ("off", 0),
    ("always-on", 1),
    ("dynamic-breathing", 2),
    ("spectrum-cycle", 3),
    ("wave", 4),
    ("ripple", 5),
    ("starlight", 6),
    ("stream", 7),
    ("shadow", 8),
    ("mountain-wave", 9),
    ("sine-wave", 10),
    ("color-spring", 11),
    ("flower-wave", 12),
    ("kill-two-birds", 14),
    ("circle-wave", 15),
    ("colorful-cross", 16),
    ("snow-fall", 17),
    ("meteor", 18),
    ("snow-trace", 19),
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

#[derive(Debug, Clone, PartialEq, Deserialize)]
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

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RapidTrigger {
    pub enable: bool,
    pub press: Option<f64>,
    pub release: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KeyOverride {
    pub actuation: Option<f64>,
    pub release: Option<f64>,
}

/// `None` leaves a setting as the keyboard has it.
#[derive(Debug, Clone, PartialEq, Deserialize)]
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
    /// Per-key overrides by key name.
    #[serde(default)]
    pub keys: BTreeMap<String, KeyOverride>,
    pub rapid_trigger: RapidTrigger,
    // No top dead zone: the H60Pro answers that table with values that change between reads.
    pub bottom_deadzone: Option<f64>,
}

pub fn parse_color(s: &str) -> Option<RgbColor> {
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
        let overrides = self.keys.values().flat_map(|o| [o.actuation, o.release]);
        let travels = [Some(self.actuation), self.release].into_iter().chain(overrides);
        if travels.flatten().any(|mm| !(0.1..=3.3).contains(&mm)) {
            return Err("actuation and release must be 0.1-3.3 mm".into());
        }
        let known = |name: &str| MODELS.iter().any(|m| m.keys.iter().any(|&(_, n)| n == name));
        if let Some(name) = self.keys.keys().find(|n| !known(n)) {
            let names: Vec<&str> = MODELS[0].keys.iter().map(|&(_, n)| n).collect();
            return Err(format!("no key named {name:?}; keys are named {}", names.join(" ")));
        }
        let rt = &self.rapid_trigger;
        if [rt.press, rt.release].into_iter().flatten().any(|mm| !(0.01..=2.0).contains(&mm)) {
            return Err("rapid trigger sensitivity must be 0.01-2.0 mm".into());
        }
        if self.bottom_deadzone.is_some_and(|mm| !(0.0..=1.0).contains(&mm)) {
            return Err("bottomDeadzone must be 0-1 mm".into());
        }
        Ok(())
    }
}

struct Target {
    key: u8,
    press: u16,
    lift: u16,
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
            && self.bottom.is_none()
    }
}

fn rate_name(rate: Option<PollingRate>) -> String {
    rate.map(|r| format!("{} Hz", r.to_hz())).unwrap_or_else(|| "unknown".into())
}

pub fn color_name(c: RgbColor) -> String {
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
            // Sent raw: the library's setter rewrites the option byte, dropping the direction.
            let data = [l.mode as u8, SPEED_MAX - l.speed.min(SPEED_MAX), l.brightness, l.direction, l.color.r, l.color.g, l.color.b];
            kb.transport().send_command(SET_LEDPARAM, &data, ChecksumType::Bit8).map_err(other)?;
        }
        for key in &p.keys {
            kb.set_key_trigger(key).map_err(other)?;
        }
        type Bulk = fn(&KeyboardInterface, TravelDepth) -> Result<(), KeyboardError>;
        let bulk: [(Option<u16>, Bulk); 3] = [
            (p.rt_press, KeyboardInterface::set_rt_press_all),
            (p.rt_lift, KeyboardInterface::set_rt_lift_all),
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

    /// Group keys by value: the most common value, then the keys that differ.
    fn groups(&self, value_of: impl Fn(u8) -> u16) -> (u16, Vec<(u16, Vec<&'static str>)>) {
        let mut groups: BTreeMap<u16, Vec<&'static str>> = BTreeMap::new();
        for &(k, name) in self.model.keys {
            groups.entry(value_of(k)).or_default().push(name);
        }
        let base = groups.iter().max_by_key(|(_, names)| names.len()).map_or(0, |(v, _)| *v);
        (base, groups.into_iter().filter(|(v, _)| *v != base).collect())
    }

    /// Per-key values for the log, e.g. "1.000 mm, W A S D 0.500 mm".
    fn describe(&self, value_of: impl Fn(u8) -> u16) -> String {
        let (base, others) = self.groups(value_of);
        let mut out = self.mm(base);
        for (v, names) in others {
            out.push_str(&format!(", {} {}", names.join(" "), self.mm(v)));
        }
        out
    }

    fn spread(&self, values: &[u16]) -> String {
        self.describe(|k| values.get(k as usize).copied().unwrap_or(0))
    }

    fn uniform(&self, values: &[u16], want: u16) -> bool {
        self.model.positions().all(|k| values.get(k as usize) == Some(&want))
    }

    /// Each key's actuation and release: the global value or that key's override.
    fn targets(&self, s: &Settings) -> Vec<Target> {
        self.model
            .keys
            .iter()
            .map(|&(key, name)| {
                let o = s.keys.get(name);
                let press = self.raw(o.and_then(|o| o.actuation).unwrap_or(s.actuation));
                let lift = o.and_then(|o| o.release).or(s.release).map_or(press, |mm| self.raw(mm));
                Target { key, press, lift }
            })
            .collect()
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
            led.direction = (led.direction & 0xF0) | if rainbow { LIGHT_RAINBOW } else { LIGHT_NORMAL };
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
        let targets = self.targets(s);
        let target = |k: u8, pick: fn(&Target) -> u16| targets.iter().find(|x| x.key == k).map_or(0, pick);
        let mode = ModeByte::new(KeyMode::Normal, s.rapid_trigger.enable).to_u8();
        if targets.iter().any(|x| t.press_travel.get(x.key as usize) != Some(&x.press)) {
            let want = self.describe(|k| target(k, |x| x.press));
            p.changes.push(format!("actuation {} -> {want}", self.spread(&t.press_travel)));
        }
        if targets.iter().any(|x| t.lift_travel.get(x.key as usize) != Some(&x.lift)) {
            let want = self.describe(|k| target(k, |x| x.lift));
            p.changes.push(format!("release {} -> {want}", self.spread(&t.lift_travel)));
        }
        if self.model.positions().any(|k| t.key_modes.get(k as usize) != Some(&mode)) {
            let mut have: Vec<String> = self
                .model
                .positions()
                .map(|k| ModeByte::from_u8(t.key_modes.get(k as usize).copied().unwrap_or(0)).to_string())
                .collect();
            have.sort();
            have.dedup();
            p.changes.push(format!("key mode {} -> {}", have.join(", "), ModeByte::from_u8(mode)));
        }
        for x in &targets {
            let i = x.key as usize;
            if t.press_travel.get(i) != Some(&x.press) || t.lift_travel.get(i) != Some(&x.lift) || t.key_modes.get(i) != Some(&mode)
            {
                p.keys.push(KeyTriggerSettings {
                    key_index: x.key,
                    actuation: x.press,
                    deactuation: x.lift,
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
        let bottom = bulk("bottom dead zone", &t.bottom_deadzone, s.bottom_deadzone.map(|mm| self.raw(mm)));
        (p.rt_press, p.rt_lift, p.bottom) = (rt_press, rt_lift, bottom);
        p
    }

    pub fn summary(&self, obs: &Observed) -> Vec<String> {
        let t = &obs.triggers;
        let o = &obs.options;
        let mut modes: Vec<String> = self
            .model
            .positions()
            .map(|k| ModeByte::from_u8(t.key_modes.get(k as usize).copied().unwrap_or(0)).to_string())
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
                if obs.led.direction & 0x0F == LIGHT_RAINBOW { " rainbow" } else { "" },
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
            format!("bottom dead zone  {}", self.spread(&t.bottom_deadzone)),
        ]
    }
}

impl Layout {
    pub fn precision(&self) -> Precision {
        self.precision
    }

    /// The settings the keyboard holds now: the most common per-key value becomes the
    /// global one, and keys that differ become overrides.
    pub fn settings_from(&self, obs: &Observed) -> Settings {
        let t = &obs.triggers;
        let at = |values: &[u16], k: u8| values.get(k as usize).copied().unwrap_or(0);
        let mm = |raw: u16| self.precision.raw_to_mm(raw);
        let common = |values: &[u16]| mm(self.groups(|k| at(values, k)).0);
        let (press, press_others) = self.groups(|k| at(&t.press_travel, k));
        let (lift, lift_others) = self.groups(|k| at(&t.lift_travel, k));
        let release_follows = self.model.positions().all(|k| at(&t.lift_travel, k) == at(&t.press_travel, k));

        let mut keys: BTreeMap<String, KeyOverride> = BTreeMap::new();
        let blank = || KeyOverride { actuation: None, release: None };
        for (v, names) in press_others {
            for name in names {
                keys.entry(name.to_string()).or_insert_with(blank).actuation = Some(mm(v));
            }
        }
        if !release_follows {
            for (v, names) in lift_others {
                for name in names {
                    keys.entry(name.to_string()).or_insert_with(blank).release = Some(mm(v));
                }
            }
        }

        let code = obs.led.mode as u8;
        let o = &obs.options;
        let first = self.model.keys.first().map_or(0, |&(k, _)| k as usize);
        let rt = t.key_modes.get(first).is_some_and(|m| m & ModeByte::RT_FLAG != 0);
        Settings {
            dry_run: false,
            polling_rate: obs.rate.map(|r| r.to_hz()),
            debounce_ms: Some(obs.debounce),
            lighting: Lighting {
                effect: EFFECTS.iter().find(|(_, c)| *c == code).map(|(n, _)| n.to_string()),
                brightness: Some(obs.led.brightness),
                speed: Some(obs.led.speed),
                color: Some(color_name(obs.led.color)),
                rainbow: match obs.led.direction & 0x0F {
                    LIGHT_RAINBOW => Some(true),
                    LIGHT_NORMAL => Some(false),
                    _ => None,
                },
            },
            fn_layer: Some(o.fn_layer),
            anti_mistouch: Some(o.anti_mistouch),
            rt_stability_ms: Some(o.rt_stability_ms()),
            wasd_swap: o.wasd_swap,
            actuation: mm(press),
            release: (!release_follows).then(|| mm(lift)),
            keys,
            rapid_trigger: RapidTrigger { enable: rt, press: Some(common(&t.rt_press)), release: Some(common(&t.rt_lift)) },
            bottom_deadzone: Some(common(&t.bottom_deadzone)),
        }
    }

    /// The keyboard's current state as a Nix snippet.
    pub fn nix(&self, obs: &Observed) -> String {
        to_nix(&self.settings_from(obs), self.precision)
    }
}

/// Settings as a Nix snippet for the home-manager module; unset (None) values are left out.
pub fn to_nix(s: &Settings, precision: Precision) -> String {
    let mm = |v: f64| TravelDepth::from_mm(v as f32, precision).format_mm(precision);
    let quote = |s: &str| format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""));
    let l = &s.lighting;
    let rt = &s.rapid_trigger;
    let lines: Vec<(String, Option<String>)> = vec![
        ("pollingRate".into(), s.polling_rate.map(|v| v.to_string())),
        ("debounceMs".into(), s.debounce_ms.map(|v| v.to_string())),
        ("lighting.effect".into(), l.effect.as_deref().map(quote)),
        ("lighting.brightness".into(), l.brightness.map(|v| v.to_string())),
        ("lighting.speed".into(), l.speed.map(|v| v.to_string())),
        ("lighting.color".into(), l.color.as_deref().map(quote)),
        ("lighting.rainbow".into(), l.rainbow.map(|v| v.to_string())),
        ("fnLayer".into(), s.fn_layer.map(|v| v.to_string())),
        ("antiMistouch".into(), s.anti_mistouch.map(|v| v.to_string())),
        ("rtStabilityMs".into(), s.rt_stability_ms.map(|v| v.to_string())),
        ("wasdSwap".into(), Some(s.wasd_swap.to_string())),
        ("actuation".into(), Some(mm(s.actuation))),
        ("release".into(), s.release.map(mm)),
        ("rapidTrigger.enable".into(), Some(rt.enable.to_string())),
        ("rapidTrigger.press".into(), rt.press.map(mm)),
        ("rapidTrigger.release".into(), rt.release.map(mm)),
        ("bottomDeadzone".into(), s.bottom_deadzone.map(mm)),
    ];
    let overrides = s.keys.iter().flat_map(|(name, o)| {
        [("actuation", o.actuation), ("release", o.release)]
            .into_iter()
            .map(move |(field, v)| (format!("keys.{}.{field}", quote(name)), v.map(mm)))
    });
    let body: String = lines
        .into_iter()
        .chain(overrides)
        .filter_map(|(key, value)| value.map(|v| format!("  {key} = {v};\n")))
        .collect();
    format!("my.peripherals.boyi-h60pro = {{\n{body}}};")
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
            keys: BTreeMap::new(),
            rapid_trigger: RapidTrigger { enable: true, press: Some(0.2), release: Some(0.2) },
            bottom_deadzone: None,
        }
    }

    fn wasd(s: &mut Settings, mm: f64) {
        for name in ["W", "A", "S", "D"] {
            s.keys.insert(name.into(), KeyOverride { actuation: Some(mm), release: None });
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
        assert_eq!(p.bottom, None, "unset dead zone stays");
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
        for k in MODELS[0].positions() {
            let k = k as usize;
            (t.press_travel[k], t.lift_travel[k], t.key_modes[k]) = (100, 100, 0x80);
            (t.rt_press[k], t.rt_lift[k]) = (20, 20);
        }
        let p = l.plan(&s, &obs);
        assert!(p.is_empty(), "{:?}", p.changes);
    }

    #[test]
    fn settings_read_back_plan_nothing() {
        let l = layout();
        let mut obs = observed(84);
        obs.led.direction = 0x38;
        for k in MODELS[0].positions() {
            let v = if [9, 14, 15, 21].contains(&k) { 50 } else { 100 };
            let t = &mut obs.triggers;
            (t.press_travel[k as usize], t.lift_travel[k as usize], t.key_modes[k as usize]) = (v, v, 0x80);
        }
        let s = l.settings_from(&obs);
        assert_eq!(s.keys.len(), 4, "A W S D become overrides");
        assert_eq!((s.actuation, s.release, s.lighting.rainbow), (1.0, None, Some(true)));
        let p = l.plan(&s, &obs);
        assert!(p.is_empty(), "{:?}", p.changes);
    }

    #[test]
    fn rainbow_flag_keeps_the_direction() {
        let l = layout();
        let mut s = settings();
        let mut obs = observed(84);
        obs.led.direction = 0x30;
        s.lighting.rainbow = Some(true);
        assert_eq!(l.plan(&s, &obs).led.map(|led| led.direction), Some(0x38));
        s.lighting.rainbow = Some(false);
        assert_eq!(l.plan(&s, &obs).led.map(|led| led.direction), Some(0x37));
        s.lighting.rainbow = None;
        assert_eq!(l.plan(&s, &obs).led.map(|led| led.direction), Some(0x30), "unset leaves the byte alone");
    }

    #[test]
    fn per_key_actuation_overrides() {
        let l = layout();
        let mut s = settings();
        wasd(&mut s, 0.5);
        let p = l.plan(&s, &observed(84));
        let at = |pos: u8| p.keys.iter().find(|k| k.key_index == pos).map(|k| (k.actuation, k.deactuation));
        assert_eq!(at(14), Some((50, 50)), "W, release follows its own actuation");
        assert_eq!(at(21), Some((50, 50)), "D");
        assert_eq!(at(8), Some((100, 100)), "Q keeps the global value");
        assert!(p.changes.iter().any(|c| c.ends_with("-> 1.00 mm, A W S D 0.50 mm")), "{:?}", p.changes);

        // The Nix snippet gives the same overrides back.
        let mut obs = observed(84);
        for k in MODELS[0].positions() {
            let v = if [9, 14, 15, 21].contains(&k) { 50 } else { 100 };
            (obs.triggers.press_travel[k as usize], obs.triggers.lift_travel[k as usize]) = (v, v);
        }
        let text = l.nix(&obs);
        assert!(text.contains("  actuation = 1.00;\n"), "{text}");
        assert!(text.contains("  keys.\"W\".actuation = 0.50;\n"), "{text}");
        assert!(!text.contains("\n  release ="), "release follows actuation: {text}");
    }

    #[test]
    fn validation() {
        settings().validate().unwrap();
        let mut s = settings();
        assert_eq!(effect_name(LedMode::from_u8(9).unwrap()), "mountain-wave", "read off a board set in qmk.top");
        s.lighting.effect = Some("rainbow".into());
        assert!(s.validate().is_err());
        let mut s = settings();
        s.lighting.color = Some("ff00ff".into());
        assert!(s.validate().is_err());
        let mut s = settings();
        s.rt_stability_ms = Some(30);
        assert!(s.validate().is_err());
        let mut s = settings();
        s.keys.insert("Fn".into(), KeyOverride { actuation: Some(0.5), release: None });
        assert!(s.validate().is_err(), "unknown key name");
        let mut s = settings();
        wasd(&mut s, 0.05);
        assert!(s.validate().is_err(), "override out of range");
        assert_eq!(parse_color("#ff8000"), Some(RgbColor::new(255, 128, 0)));
    }

    #[test]
    fn grids_cover_their_keys() {
        for m in &MODELS {
            assert!(m.positions().all(|k| k < m.grid));
        }
    }
}
