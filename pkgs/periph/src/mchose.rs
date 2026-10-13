//! MCHOSE mice on the 0x11/0x12 feature-report protocol (L7, M7, A7 families).
//! Frames and firmware quirks: https://github.com/alexfrih/mchose-linux/blob/main/PROTOCOL.md
//! Lift-off list, factory defaults, button codes and the `0x11 0x42` value
//! encoding (0 = unchanged, flags 1 on / 2 off, mode 1-3): MCHOSE's M HUB web driver.

use crate::hidraw::{HidRaw, Node};
use serde::Deserialize;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread::sleep;
use std::time::{Duration, Instant};

pub static TRACE: AtomicBool = AtomicBool::new(false);

const SHORT: u8 = 0x11; // 20-byte payload
const LONG: u8 = 0x12; // 64-byte payload
// Faster than this and the config channel wedges.
const MIN_GAP: Duration = Duration::from_millis(25);
const VENDORS: [u16; 2] = [0x5253, 0x3837];

/// Device ID the M7 Ultra reports in `0x11 0x06`.
pub const M7_ULTRA: u16 = 49;

const RATES: [u32; 6] = [125, 500, 1000, 2000, 4000, 8000];
const FACTORY_DPI: [u16; 6] = [400, 800, 1600, 3200, 6400, 42000];
// The bottom DPI button is the sixth slot; the other five are the clicks and side buttons.
const DPI_SLOT: usize = 5;
// Slot byte is index << 4 | type; type 0 is the slot's own function, 9 is "disabled".
const DPI_DEFAULT: [u8; 4] = [0x50, 0x00, 0x00, 0x00];
const DPI_DISABLED: [u8; 4] = [0x59, 0xFF, 0xFF, 0xFF];

pub fn is_config_node(n: &Node) -> bool {
    VENDORS.contains(&n.vid) && n.descriptor.windows(3).any(|w| w == [0x06, 0x01, 0xFF])
}

fn invalid(msg: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg.into())
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ")
}

fn u16le(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes([b[at], b[at + 1]])
}

fn pace() {
    static LAST: Mutex<Option<Instant>> = Mutex::new(None);
    let mut last = LAST.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(since) = last.map(|t| t.elapsed()).filter(|e| *e < MIN_GAP) {
        sleep(MIN_GAP - since);
    }
    *last = Some(Instant::now());
}

fn payload_len(report: u8) -> usize {
    if report == SHORT {
        20
    } else {
        64
    }
}

/// The whole payload goes out inverted, padding included.
fn frame(report: u8, body: &[u8]) -> Vec<u8> {
    let mut buf = vec![0xFF; payload_len(report) + 1];
    buf[0] = report;
    for (slot, b) in buf[1..].iter_mut().zip(body) {
        *slot = b ^ 0xFF;
    }
    buf
}

fn send(dev: &HidRaw, report: u8, body: &[u8]) -> io::Result<()> {
    if TRACE.load(Ordering::Relaxed) {
        eprintln!("-> {report:02x} {}", hex(body));
    }
    pace();
    dev.set_feature(&frame(report, body))
}

/// Ask again while the echo is wrong or the reply is all zeros (a stalled channel).
fn request(dev: &HidRaw, report: u8, body: &[u8]) -> io::Result<Vec<u8>> {
    for attempt in 1..=6u64 {
        send(dev, report, body)?;
        sleep(Duration::from_millis(20));
        let mut buf = vec![0u8; payload_len(report) + 1];
        buf[0] = report;
        pace();
        let n = dev.get_feature(&mut buf)?;
        buf.truncate(n);
        if buf.len() > 2 && (buf[1] ^ 0xFF) == body[0] && buf[2..].iter().any(|b| *b != 0) {
            let payload: Vec<u8> = buf[2..].iter().map(|b| b ^ 0xFF).collect();
            if TRACE.load(Ordering::Relaxed) {
                eprintln!("<- {report:02x} {:02x} {}", body[0], hex(&payload));
            }
            return Ok(payload);
        }
        sleep(Duration::from_millis(30 * attempt));
    }
    Err(invalid(format!("no reply to {report:02x} {:02x}", body[0])))
}

pub struct Identity {
    pub vid: u16,
    pub id: u16,
    pub firmware: u32,
    pub connected: bool,
    pub battery: u8,
    pub charging: bool,
}

/// `0x11 0x06`, or None while the mouse is idle, asleep or off: the dongle then
/// answers with zeroed fields. The first query after idle can also come back zeroed.
pub fn identity(dev: &HidRaw) -> io::Result<Option<Identity>> {
    for attempt in 1..=4u64 {
        let d = request(dev, SHORT, &[0x06])?;
        if d.len() < 11 {
            return Err(invalid("short identity reply"));
        }
        if u16le(&d, 0) == 0 {
            if attempt < 4 {
                sleep(Duration::from_millis(120 * attempt));
            }
            continue;
        }
        return Ok(Some(Identity {
            vid: u16le(&d, 0),
            id: u16le(&d, 2),
            firmware: u32::from_le_bytes([d[4], d[5], d[6], d[7]]),
            connected: d[8] & 0x08 != 0,
            battery: d[9],
            charging: d[10] != 0,
        }));
    }
    Ok(None)
}

/// The 15 lighting fields from `0x11 0x1b`; byte 0 is on/off.
fn rgb(dev: &HidRaw) -> io::Result<[u8; 15]> {
    let d = request(dev, SHORT, &[0x1b])?;
    d.get(..15).and_then(|s| s.try_into().ok()).ok_or_else(|| invalid("short lighting reply"))
}

/// The 63-byte config block: read with `0x12 0x67`, written with `0x12 0x57`.
#[derive(Clone, PartialEq, Debug)]
pub struct Block(pub [u8; 63]);

impl Block {
    fn read(dev: &HidRaw) -> io::Result<Self> {
        for attempt in 1..=6u64 {
            let d = request(dev, LONG, &[0x67])?;
            let body: [u8; 63] = d.get(..63).and_then(|s| s.try_into().ok()).ok_or_else(|| invalid("short config reply"))?;
            if body.iter().any(|b| *b != 0) {
                return Ok(Self(body));
            }
            // The long-report channel can wedge into answering zeros; re-selecting the profile wakes it.
            if attempt > 1 {
                send(dev, SHORT, &[0x58, 0])?;
            }
            sleep(Duration::from_millis(150 * attempt));
        }
        Err(invalid("the mouse keeps answering an empty config block"))
    }

    fn write(&self, dev: &HidRaw) -> io::Result<()> {
        let mut body = vec![0x57];
        body.extend_from_slice(&self.0);
        send(dev, LONG, &body)
    }

    /// Byte 3 and bit 0 of the sensor byte belong to the mouse.
    fn same(&self, other: &Block) -> bool {
        self.0.iter().zip(other.0.iter()).enumerate().all(|(i, (a, b))| match i {
            3 => true,
            17 => a & !1 == b & !1,
            _ => a == b,
        })
    }

    pub fn profile(&self) -> u8 {
        self.0[0]
    }
    /// (wired, wireless) rate indexes.
    pub fn rates(&self) -> (u8, u8) {
        (self.0[1] >> 4, self.0[2] >> 4)
    }
    /// (wired, wireless) active stage, zero-based.
    pub fn active(&self) -> (u8, u8) {
        (self.0[1] & 0x0F, self.0[2] & 0x0F)
    }
    pub fn dpi(&self, stage: usize) -> u16 {
        u16le(&self.0, 4 + stage * 2)
    }
    pub fn dpi_y(&self, stage: usize) -> u16 {
        u16le(&self.0, 51 + stage * 2)
    }
    pub fn stages(&self) -> u8 {
        self.0[16]
    }
    /// (ripple, angle snap, motion sync)
    pub fn flags(&self) -> (bool, bool, bool) {
        let s = self.0[17];
        (s & 0x04 != 0, s & 0x08 != 0, s & 0x10 != 0)
    }
    /// The top two bits of the sensor byte.
    pub fn mode(&self) -> Option<Mode> {
        Mode::from_bits(self.0[17] >> 6)
    }
    pub fn debounce(&self) -> u8 {
        self.0[18]
    }
    pub fn sleep_minutes(&self) -> u8 {
        self.0[19]
    }
    pub fn button(&self, slot: usize) -> [u8; 4] {
        self.0[20 + slot * 4..24 + slot * 4].try_into().unwrap()
    }
    pub fn angle(&self) -> i8 {
        self.0[49] as i8
    }
}

fn confirm(dev: &HidRaw, want: &Block) -> io::Result<()> {
    let mut last = None;
    for attempt in 1..=5u64 {
        sleep(Duration::from_millis(80 * attempt));
        let got = Block::read(dev)?;
        if got.same(want) {
            return Ok(());
        }
        last = Some(got);
    }
    Err(invalid(format!(
        "the mouse did not take the config block (wanted {}, got {})",
        hex(&want.0),
        last.map(|b| hex(&b.0)).unwrap_or_default()
    )))
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Performance,
    Gaming,
    Extreme,
}

impl Mode {
    /// Sensor byte bits 7-6, as read from an M7 Ultra in each mode.
    fn from_bits(bits: u8) -> Option<Self> {
        match bits {
            0b00 => Some(Self::Performance),
            0b10 => Some(Self::Gaming),
            0b11 => Some(Self::Extreme),
            _ => None,
        }
    }
    /// The `gameMode` value M HUB sends in `0x11 0x42`.
    fn code(self) -> u8 {
        self as u8 + 1
    }
    fn name(self) -> &'static str {
        match self {
            Self::Performance => "performance",
            Self::Gaming => "gaming",
            Self::Extreme => "extreme",
        }
    }
}

fn mode_name(b: &Block) -> String {
    b.mode().map(|m| m.name().to_string()).unwrap_or_else(|| format!("unknown (sensor byte {:02x})", b.0[17]))
}

/// `0x11 0x42` flag value: 0 would mean "leave unchanged".
fn flag(on: bool) -> u8 {
    if on {
        1
    } else {
        2
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
pub enum LiftOff {
    #[serde(rename = "0.7mm")]
    Low,
    #[serde(rename = "1mm")]
    Mid,
    #[serde(rename = "2mm")]
    High,
}

impl LiftOff {
    fn index(self) -> u8 {
        self as u8
    }
    fn name(self) -> &'static str {
        match self {
            Self::Low => "0.7mm",
            Self::Mid => "1mm",
            Self::High => "2mm",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ButtonAction {
    Default,
    Disabled,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Links {
    pub wired: u32,
    pub wireless: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Buttons {
    pub dpi: ButtonAction,
}

/// Every setting the driver manages. The Nix module fills unset ones with factory values.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Settings {
    pub dpi_stages: Vec<u16>,
    pub active_stage: u8,
    pub polling_rate: Links,
    pub lift_off: LiftOff,
    pub ripple: bool,
    pub angle_snap: bool,
    pub motion_sync: bool,
    pub angle_correction: i8,
    pub performance_mode: Mode,
    pub debounce_ms: u8,
    pub sleep_minutes: u8,
    pub lighting: bool,
    pub buttons: Buttons,
}

fn rate_index(hz: u32) -> Option<u8> {
    RATES.iter().position(|r| *r == hz).map(|i| i as u8)
}

fn rate_name(index: u8) -> String {
    RATES.get(index as usize).map(|hz| hz.to_string()).unwrap_or_else(|| format!("index {index}"))
}

fn on_off(b: bool) -> &'static str {
    if b {
        "on"
    } else {
        "off"
    }
}

impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        let n = self.dpi_stages.len();
        if !(1..=6).contains(&n) {
            return Err(format!("dpiStages needs 1 to 6 values, got {n}"));
        }
        if let Some(d) = self.dpi_stages.iter().find(|d| !(50..=42000).contains(*d)) {
            return Err(format!("DPI {d} is outside 50-42000"));
        }
        if !(1..=n as u8).contains(&self.active_stage) {
            return Err(format!("activeStage {} is not one of the {n} stages", self.active_stage));
        }
        for hz in [self.polling_rate.wired, self.polling_rate.wireless] {
            if rate_index(hz).is_none() {
                return Err(format!("polling rate {hz} is not one of {RATES:?}"));
            }
        }
        if !(-30..=30).contains(&self.angle_correction) {
            return Err(format!("angleCorrection {} is outside -30..30", self.angle_correction));
        }
        Ok(())
    }

    /// The config block with this config's fields written into `block`.
    fn edit(&self, block: &Block) -> Block {
        let mut b = block.clone();
        for (stage, factory) in FACTORY_DPI.iter().enumerate() {
            let v = self.dpi_stages.get(stage).unwrap_or(factory).to_le_bytes();
            b.0[4 + stage * 2..6 + stage * 2].copy_from_slice(&v);
            b.0[51 + stage * 2..53 + stage * 2].copy_from_slice(&v);
        }
        b.0[16] = self.dpi_stages.len() as u8;
        let active = self.active_stage - 1;
        b.0[1] = (b.0[1] & 0xF0) | active;
        b.0[2] = (b.0[2] & 0xF0) | active;
        b.0[18] = self.debounce_ms;
        b.0[19] = self.sleep_minutes;
        b
    }

    fn dpi_button(&self) -> [u8; 4] {
        match self.buttons.dpi {
            ButtonAction::Default => DPI_DEFAULT,
            ButtonAction::Disabled => DPI_DISABLED,
        }
    }
}

pub struct Observed {
    pub id: Identity,
    pub block: Block,
    pub rgb: Option<[u8; 15]>,
}

pub fn observe(dev: &HidRaw) -> io::Result<Observed> {
    Ok(Observed {
        id: identity(dev)?.ok_or_else(|| invalid("the mouse stopped answering"))?,
        block: Block::read(dev)?,
        rgb: rgb(dev).ok(),
    })
}

#[derive(Default, Debug)]
pub struct Plan {
    pub changes: Vec<String>,
    pub notes: Vec<String>,
    profile: bool,
    rate: Option<(u8, u8)>,
    block: bool,
    perf: Option<[u8; 10]>,
    button: Option<[u8; 4]>,
    rgb: Option<[u8; 15]>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        !self.profile
            && self.rate.is_none()
            && !self.block
            && self.perf.is_none()
            && self.button.is_none()
            && self.rgb.is_none()
    }
}

/// What it takes to bring the mouse to `s`. Lift-off can't be read back, so
/// `lod_known` says whether this process already wrote it.
pub fn plan(s: &Settings, obs: &Observed, lod_known: bool) -> Plan {
    let mut p = Plan::default();
    let b = &obs.block;

    // Every setting lives per onboard profile; the config always uses the first.
    if b.profile() != 0 {
        p.profile = true;
        p.changes.push(format!("onboard profile {} -> 1", b.profile() + 1));
    }

    let rates = (rate_index(s.polling_rate.wired).unwrap_or(2), rate_index(s.polling_rate.wireless).unwrap_or(2));
    if b.rates() != rates {
        p.rate = Some(rates);
        p.changes.push(format!(
            "polling rate {}/{} -> {}/{} Hz (wired/wireless)",
            rate_name(b.rates().0),
            rate_name(b.rates().1),
            s.polling_rate.wired,
            s.polling_rate.wireless
        ));
    }

    let want = s.edit(b);
    if !want.same(b) {
        p.block = true;
        let stages = |x: &Block| (0..6).map(|i| x.dpi(i).to_string()).collect::<Vec<_>>().join(" ");
        if (0..6).any(|i| b.dpi(i) != want.dpi(i) || b.dpi_y(i) != want.dpi_y(i)) {
            p.changes.push(format!("DPI stages {} -> {}", stages(b), stages(&want)));
        }
        if b.stages() != want.stages() {
            p.changes.push(format!("enabled stages {} -> {}", b.stages(), want.stages()));
        }
        if b.active() != want.active() {
            let (w, g) = b.active();
            p.changes.push(format!("active stage {}/{} -> {} (wired/wireless)", w + 1, g + 1, s.active_stage));
        }
        if b.debounce() != want.debounce() {
            p.changes.push(format!("debounce {} -> {} ms", b.debounce(), want.debounce()));
        }
        if b.sleep_minutes() != want.sleep_minutes() {
            p.changes.push(format!("sleep {} -> {} min", b.sleep_minutes(), want.sleep_minutes()));
        }
    }

    let (ripple, snap, sync) = b.flags();
    let flags_differ = (ripple, snap, sync) != (s.ripple, s.angle_snap, s.motion_sync);
    if flags_differ {
        p.changes.push(format!(
            "ripple/angle snap/motion sync {}/{}/{} -> {}/{}/{}",
            on_off(ripple),
            on_off(snap),
            on_off(sync),
            on_off(s.ripple),
            on_off(s.angle_snap),
            on_off(s.motion_sync)
        ));
    }
    let angle_differs = b.angle() != s.angle_correction;
    if angle_differs {
        p.changes.push(format!("angle correction {} -> {} degrees", b.angle(), s.angle_correction));
    }
    let mode_differs = b.mode() != Some(s.performance_mode);
    if mode_differs {
        p.changes.push(format!("performance mode {} -> {}", mode_name(b), s.performance_mode.name()));
    }
    if !lod_known {
        p.changes.push(format!("lift-off {} (can't be read back, written once per plug)", s.lift_off.name()));
    }
    if flags_differ || angle_differs || mode_differs || !lod_known {
        p.perf = Some([
            0x42,
            s.lift_off.index(),
            flag(s.ripple),
            flag(s.angle_snap),
            flag(s.motion_sync),
            0,
            0,
            s.performance_mode.code(),
            1,
            s.angle_correction as u8,
        ]);
    }

    let have = b.button(DPI_SLOT);
    let want_button = s.dpi_button();
    if have[0] >> 4 != DPI_SLOT as u8 {
        p.notes.push(format!("DPI button slot reads {}, not the expected layout; leaving it alone", hex(&have)));
    } else if have != want_button {
        p.button = Some(want_button);
        p.changes.push(format!("DPI button {} -> {}", hex(&have), hex(&want_button)));
    }

    match obs.rgb {
        Some(rgb) if (rgb[0] != 0) != s.lighting => {
            let mut want = rgb;
            want[0] = s.lighting as u8;
            p.rgb = Some(want);
            p.changes.push(format!("lighting {} -> {}", on_off(rgb[0] != 0), on_off(s.lighting)));
        }
        Some(_) => {}
        None => p.notes.push("no lighting reply; leaving lighting alone".into()),
    }
    p
}

fn execute(dev: &HidRaw, s: &Settings, p: &Plan) -> io::Result<()> {
    if p.profile {
        // Everything else is per profile, so re-plan after switching.
        send(dev, SHORT, &[0x58, 0])?;
        sleep(Duration::from_millis(150));
        return Ok(());
    }
    if let Some((wired, wireless)) = p.rate {
        send(dev, SHORT, &[0x41, wired, wireless])?;
        sleep(Duration::from_millis(120));
    }
    if p.block {
        let have = Block::read(dev)?;
        let want = s.edit(&have);
        want.write(dev)?;
        confirm(dev, &want)?;
    }
    if let Some(perf) = p.perf {
        send(dev, SHORT, &perf)?;
        sleep(Duration::from_millis(120));
    }
    if let Some(button) = p.button {
        let body = [0x52, DPI_SLOT as u8, 0, button[0] & 0x0F, button[1], button[2], button[3]];
        send(dev, LONG, &body)?;
        sleep(Duration::from_millis(120));
    }
    if let Some(rgb) = p.rgb {
        let mut body = vec![0x2B];
        body.extend_from_slice(&rgb);
        send(dev, SHORT, &body)?;
        sleep(Duration::from_millis(120));
    }
    Ok(())
}

/// Bring the mouse to `s`, then read it back until nothing is left to change.
pub fn apply(dev: &HidRaw, s: &Settings, mut lod_known: bool) -> io::Result<Plan> {
    let mut done = Plan::default();
    for round in 0..4 {
        let obs = observe(dev)?;
        let p = plan(s, &obs, lod_known);
        if round == 0 {
            done.notes = p.notes.clone();
        }
        if p.is_empty() {
            return Ok(done);
        }
        if round == 3 {
            return Err(invalid(format!("the mouse would not settle: {}", p.changes.join("; "))));
        }
        execute(dev, s, &p)?;
        lod_known |= p.perf.is_some();
        done.changes.extend(p.changes);
    }
    unreachable!()
}

/// Human-readable dump of what the mouse reports, raw bytes included.
pub fn summary(obs: &Observed) -> Vec<String> {
    let b = &obs.block;
    let (ripple, snap, sync) = b.flags();
    let (aw, ag) = b.active();
    let stages = (0..6).map(|i| b.dpi(i).to_string()).collect::<Vec<_>>().join(" ");
    let buttons = (0..6).map(|i| hex(&b.button(i))).collect::<Vec<_>>().join(" | ");
    vec![
        format!(
            "device id {} (vid {:04x}), firmware {:08x}, battery {}%{}",
            obs.id.id,
            obs.id.vid,
            obs.id.firmware,
            obs.id.battery,
            if obs.id.charging { ", charging" } else { "" }
        ),
        format!("onboard profile   {}", b.profile() + 1),
        format!("DPI stages        {stages} ({} enabled, active {}/{} wired/wireless)", b.stages(), aw + 1, ag + 1),
        format!("polling rate      {} / {} Hz (wired/wireless)", rate_name(b.rates().0), rate_name(b.rates().1)),
        format!("ripple/snap/sync  {}/{}/{}", on_off(ripple), on_off(snap), on_off(sync)),
        format!("angle correction  {} degrees", b.angle()),
        format!("debounce          {} ms", b.debounce()),
        format!("sleep             {} min", b.sleep_minutes()),
        format!("performance mode  {}", mode_name(b)),
        format!("lighting          {}", obs.rgb.map(|r| hex(&r)).unwrap_or_else(|| "no reply".into())),
        format!("buttons           {buttons}"),
        format!("config block      {}", hex(&b.0)),
    ]
}

/// The mouse's current state as a Nix snippet for the home-manager module.
pub fn nix(obs: &Observed) -> String {
    let b = &obs.block;
    let n = (b.stages() as usize).clamp(1, 6);
    let stages = (0..n).map(|i| b.dpi(i).to_string()).collect::<Vec<_>>().join(" ");
    let (ripple, snap, sync) = b.flags();
    let (mode, mode_note) = match b.mode() {
        Some(m) => (m.name(), None),
        None => ("performance", Some(format!("unknown sensor byte {:02x}", b.0[17]))),
    };
    let (lighting, lighting_note) = match obs.rgb {
        Some(r) => (r[0] != 0, None),
        None => (true, Some("no reply".to_string())),
    };
    let (button, button_note) = match b.button(DPI_SLOT) {
        DPI_DEFAULT => ("default", None),
        DPI_DISABLED => ("disabled", None),
        other => ("default", Some(format!("unknown {}", hex(&other)))),
    };
    let lines: [(&str, String, Option<String>); 12] = [
        ("dpiStages", format!("[ {stages} ]"), None),
        ("activeStage", (b.active().0 + 1).to_string(), None),
        (
            "pollingRate",
            format!("{{ wired = {}; wireless = {}; }}", rate_name(b.rates().0), rate_name(b.rates().1)),
            None,
        ),
        ("ripple", ripple.to_string(), None),
        ("angleSnap", snap.to_string(), None),
        ("motionSync", sync.to_string(), None),
        ("angleCorrection", b.angle().to_string(), None),
        ("performanceMode", format!("\"{mode}\""), mode_note),
        ("debounceMs", b.debounce().to_string(), None),
        ("sleepMinutes", b.sleep_minutes().to_string(), None),
        ("lighting", lighting.to_string(), lighting_note),
        ("buttons.dpi", format!("\"{button}\""), button_note),
    ];
    let mut body = String::from("  # liftOff can't be read back from the mouse\n");
    for (key, value, note) in lines {
        let note = note.map(|n| format!(" # {n}")).unwrap_or_default();
        body.push_str(&format!("  {key} = {value};{note}\n"));
    }
    format!("my.peripherals.mchose-m7-ultra = {{\n{body}}};")
}

/// Wayle's custom-module JSON, matching the old Python battery script.
pub fn battery_json(id: &Identity) -> String {
    let charging = if id.charging { " \u{f0e7} " } else { "" };
    serde_json::json!({
        "text": format!("{}%{charging}", id.battery),
        "percentage": id.battery,
        "tooltip": format!("MCHOSE M7: {}%{}", id.battery, if id.charging { " (charging)" } else { "" }),
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> Settings {
        Settings {
            dpi_stages: FACTORY_DPI.to_vec(),
            active_stage: 3,
            polling_rate: Links { wired: 1000, wireless: 1000 },
            lift_off: LiftOff::Low,
            ripple: false,
            angle_snap: false,
            motion_sync: false,
            angle_correction: 0,
            performance_mode: Mode::Performance,
            debounce_ms: 8,
            sleep_minutes: 3,
            lighting: true,
            buttons: Buttons { dpi: ButtonAction::Default },
        }
    }

    // A factory-fresh block: 1000 Hz, stage 3 of 6, the M HUB defaults.
    fn factory_block() -> Block {
        let mut b = Block([0; 63]);
        b.0[1] = 0x22;
        b.0[2] = 0x22;
        for (i, d) in FACTORY_DPI.iter().enumerate() {
            b.0[4 + i * 2..6 + i * 2].copy_from_slice(&d.to_le_bytes());
            b.0[51 + i * 2..53 + i * 2].copy_from_slice(&d.to_le_bytes());
        }
        b.0[16] = 6;
        b.0[17] = 0x02;
        b.0[18] = 8;
        b.0[19] = 3;
        for slot in 0..6 {
            b.0[20 + slot * 4] = (slot as u8) << 4;
        }
        b
    }

    fn observed(block: Block) -> Observed {
        Observed {
            id: Identity { vid: 0x5253, id: M7_ULTRA, firmware: 0, connected: true, battery: 80, charging: false },
            block,
            rgb: Some([1; 15]),
        }
    }

    #[test]
    fn frames_are_inverted_and_padded() {
        let f = frame(SHORT, &[0x41, 5, 5]);
        assert_eq!(f.len(), 21);
        assert_eq!(&f[..4], &[0x11, 0xBE, 0xFA, 0xFA]);
        assert!(f[4..].iter().all(|b| *b == 0xFF));
        assert_eq!(frame(LONG, &[0x67]).len(), 65);
    }

    #[test]
    fn factory_mouse_needs_only_lift_off() {
        let p = plan(&settings(), &observed(factory_block()), true);
        assert!(p.is_empty(), "{:?}", p.changes);
        let p = plan(&settings(), &observed(factory_block()), false);
        assert_eq!(p.perf, Some([0x42, 0, 2, 2, 2, 0, 0, 1, 1, 0]));
    }

    #[test]
    fn modes_read_from_the_sensor_byte() {
        let mut b = factory_block();
        for (sensor, mode) in [(0x02, Mode::Performance), (0x82, Mode::Gaming), (0xc2, Mode::Extreme)] {
            b.0[17] = sensor;
            assert_eq!(b.mode(), Some(mode));
        }
        b.0[17] = 0x42;
        assert_eq!(b.mode(), None);
    }

    #[test]
    fn custom_config_plans_every_field() {
        let mut s = settings();
        s.dpi_stages = vec![1600];
        s.active_stage = 1;
        s.polling_rate = Links { wired: 8000, wireless: 8000 };
        s.lift_off = LiftOff::Mid;
        s.motion_sync = true;
        s.angle_correction = -3;
        s.performance_mode = Mode::Gaming;
        s.sleep_minutes = 10;
        s.lighting = false;
        s.buttons.dpi = ButtonAction::Disabled;
        s.validate().unwrap();

        let p = plan(&s, &observed(factory_block()), true);
        assert_eq!(p.rate, Some((5, 5)));
        assert!(p.block);
        assert_eq!(p.perf, Some([0x42, 1, 2, 2, 1, 0, 0, 2, 1, 253]));
        assert_eq!(p.button, Some(DPI_DISABLED));
        assert_eq!(p.rgb.map(|r| r[0]), Some(0));

        let want = s.edit(&factory_block());
        assert_eq!(want.dpi(0), 1600);
        assert_eq!(want.dpi_y(0), 1600);
        assert_eq!(want.dpi(5), 42000);
        assert_eq!(want.stages(), 1);
        assert_eq!(want.active(), (0, 0));
        assert_eq!(want.rates(), (2, 2), "rate nibbles belong to 0x11 0x41");
        assert_eq!(want.sleep_minutes(), 10);
    }

    #[test]
    fn settled_mouse_plans_nothing() {
        let mut s = settings();
        s.motion_sync = true;
        s.angle_correction = -3;
        s.performance_mode = Mode::Gaming;
        let mut b = factory_block();
        b.0[17] = 0x92;
        b.0[49] = (-3i8) as u8;
        b.0[3] = 0x02; // mouse-owned byte
        let p = plan(&s, &observed(b), true);
        assert!(p.is_empty(), "{:?}", p.changes);
    }

    #[test]
    fn unexpected_button_layout_is_left_alone() {
        let mut s = settings();
        s.buttons.dpi = ButtonAction::Disabled;
        let mut b = factory_block();
        b.0[20 + DPI_SLOT * 4] = 0x05;
        let p = plan(&s, &observed(b), true);
        assert!(p.button.is_none());
        assert_eq!(p.notes.len(), 1);
    }

    #[test]
    fn validation_rejects_bad_values() {
        let mut s = settings();
        s.active_stage = 7;
        assert!(s.validate().is_err());
        let mut s = settings();
        s.polling_rate.wired = 300;
        assert!(s.validate().is_err());
        let mut s = settings();
        s.angle_correction = 31;
        assert!(s.validate().is_err());
    }

    #[test]
    fn nix_snippet_round_trips_the_readable_fields() {
        let mut b = factory_block();
        b.0[49] = (-3i8) as u8;
        b.0[17] = 0x82;
        let text = nix(&observed(b));
        assert!(text.contains("angleCorrection = -3;"));
        assert!(text.contains("performanceMode = \"gaming\";"));
        assert!(text.contains("dpiStages = [ 400 800 1600 3200 6400 42000 ];"));
        assert!(text.contains("buttons.dpi = \"default\";"));
    }

    #[test]
    fn battery_matches_the_python_widget() {
        let id = Identity { vid: 0x5253, id: M7_ULTRA, firmware: 0, connected: true, battery: 57, charging: true };
        let v: serde_json::Value = serde_json::from_str(&battery_json(&id)).unwrap();
        assert_eq!(v["text"], "57% \u{f0e7} ");
        assert_eq!(v["tooltip"], "MCHOSE M7: 57% (charging)");
    }
}
