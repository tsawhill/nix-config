//! periph-gui: change device settings live. Changes are runtime only; the service
//! puts the Nix config back the next time a device is plugged in.

use eframe::egui::{self, Button, Color32, ComboBox, DragValue, RichText, Slider};
use periph::config::{self, Config};
use periph::hidraw::{HidRaw, Node};
use periph::{devices, mchose, mchose_buttons, rongyuan};
use std::io;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::Duration;

const LOCK_WAIT: Duration = Duration::from_secs(3);
const CHANGED: Color32 = Color32::from_rgb(230, 160, 60);
const KB_RATES: [u16; 7] = [125, 250, 500, 1000, 2000, 4000, 8000];

// A short list of these, so the size difference between variants doesn't matter.
#[allow(clippy::large_enum_variant)]
#[derive(Clone)]
enum Device {
    Mouse {
        node: Node,
        id: mchose::Identity,
        wired: bool,
        read: mchose::Settings,
        edit: mchose::Settings,
    },
    Keyboard {
        node: Node,
        model: &'static rongyuan::Model,
        precision: rongyuan::Precision,
        read: rongyuan::Settings,
        edit: rongyuan::Settings,
    },
    Unavailable {
        node: Node,
        why: String,
    },
}

impl Device {
    fn node(&self) -> &Node {
        match self {
            Self::Mouse { node, .. } | Self::Keyboard { node, .. } | Self::Unavailable { node, .. } => node,
        }
    }

    fn lift_off(&self) -> Option<mchose::LiftOff> {
        match self {
            Self::Mouse { edit, .. } => Some(edit.lift_off),
            _ => None,
        }
    }
}

fn online(dev: &HidRaw) -> io::Result<mchose::Identity> {
    mchose::identity(dev)?
        .filter(|id| id.connected)
        .ok_or_else(|| io::Error::other("asleep or off: move it, then Reload"))
}

fn read_mouse(node: &Node, lift_off: mchose::LiftOff) -> io::Result<Device> {
    let dev = HidRaw::open_locked(&node.dev, LOCK_WAIT)?;
    let id = online(&dev)?;
    if id.id != mchose::M7_ULTRA {
        return Err(io::Error::other(format!("MCHOSE device id {} isn't supported yet", id.id)));
    }
    let wired = node.pid == id.id;
    let read = mchose::settings_from(&mchose::observe(&dev, &id, wired)?, lift_off);
    Ok(Device::Mouse { node: node.clone(), id, wired, edit: read.clone(), read })
}

fn read_keyboard(node: &Node) -> io::Result<Device> {
    match rongyuan::open(node)? {
        rongyuan::Opened::Unknown(id) => Err(io::Error::other(format!("RongYuan device id {id} isn't supported yet"))),
        rongyuan::Opened::Known(kb) => {
            let read = kb.settings_from(&kb.observe()?);
            Ok(Device::Keyboard { node: node.clone(), model: kb.model, precision: kb.precision(), edit: read.clone(), read })
        }
    }
}

fn read(node: &Node, lift_off: mchose::LiftOff) -> Device {
    let result = if rongyuan::is_config_node(node) { read_keyboard(node) } else { read_mouse(node, lift_off) };
    result.unwrap_or_else(|e| Device::Unavailable { node: node.clone(), why: e.to_string() })
}

fn apply(device: &Device) -> io::Result<Vec<String>> {
    match device {
        Device::Mouse { node, edit, .. } => {
            edit.validate().map_err(io::Error::other)?;
            let dev = HidRaw::open_locked(&node.dev, LOCK_WAIT)?;
            let id = online(&dev)?;
            Ok(mchose::apply(&dev, edit, &id, node.pid == id.id, false)?.changes)
        }
        Device::Keyboard { node, edit, .. } => {
            edit.validate().map_err(io::Error::other)?;
            match rongyuan::open(node)? {
                rongyuan::Opened::Known(kb) => kb.apply(edit),
                rongyuan::Opened::Unknown(id) => Err(io::Error::other(format!("device id {id} isn't supported"))),
            }
        }
        Device::Unavailable { .. } => Ok(Vec::new()),
    }
}

/// Copy through wl-copy (this is a Wayland desktop), falling back to egui's clipboard.
fn copy(ctx: &egui::Context, text: String) {
    let piped = Command::new("wl-copy").stdin(Stdio::piped()).spawn().and_then(|mut child| {
        child.stdin.take().expect("piped stdin").write_all(text.as_bytes())?;
        child.wait()
    });
    if !piped.is_ok_and(|status| status.success()) {
        ctx.copy_text(text);
    }
}

enum Msg {
    Scanned(Vec<Device>),
    Applied { index: usize, device: Box<Device>, result: Result<Vec<String>, String> },
}

enum Action {
    Reload,
    Apply(usize),
    ResetToNix(usize),
    Copy(String),
}

/// Device names `periph-gui <device>` accepts, as the Nix options call them.
const DEVICE_NAMES: [&str; 2] = ["mchose-m7-ultra", "boyi-h60pro"];

fn wanted(node: &Node, only: Option<&str>) -> bool {
    match only {
        None => true,
        Some("boyi-h60pro") => rongyuan::is_config_node(node),
        Some(_) => mchose::is_config_node(node),
    }
}

struct App {
    declared: Option<Config>,
    config_error: Option<String>,
    only: Option<String>,
    devices: Vec<Device>,
    job: Option<Receiver<Msg>>,
    status: String,
    log: Vec<String>,
}

impl App {
    fn new(ctx: &egui::Context, declared: Option<Config>, config_error: Option<String>, only: Option<String>) -> Self {
        let mut app = Self {
            declared,
            config_error,
            only,
            devices: Vec::new(),
            job: None,
            status: String::new(),
            log: Vec::new(),
        };
        app.run(Action::Reload, ctx);
        app
    }

    fn declared_lift_off(&self) -> mchose::LiftOff {
        self.declared.as_ref().and_then(|c| c.mchose_m7_ultra.as_ref()).map_or(mchose::LiftOff::Low, |s| s.lift_off)
    }

    fn spawn(&mut self, ctx: &egui::Context, job: impl FnOnce() -> Msg + Send + 'static) {
        let (tx, rx) = mpsc::channel();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            let _ = tx.send(job());
            ctx.request_repaint();
        });
        self.job = Some(rx);
    }

    fn run(&mut self, action: Action, ctx: &egui::Context) {
        match action {
            Action::Reload => {
                self.status = "Reading devices…".into();
                let lift_off = self.declared_lift_off();
                let only = self.only.clone();
                self.spawn(ctx, move || {
                    let nodes = devices().into_iter().filter(|n| wanted(n, only.as_deref()));
                    Msg::Scanned(nodes.map(|n| read(&n, lift_off)).collect())
                });
            }
            Action::ResetToNix(index) => {
                let Some(declared) = &self.declared else { return };
                match self.devices.get_mut(index) {
                    Some(Device::Mouse { edit, .. }) => {
                        if let Some(s) = &declared.mchose_m7_ultra {
                            *edit = s.clone();
                        }
                    }
                    Some(Device::Keyboard { edit, .. }) => {
                        if let Some(s) = &declared.boyi_h60pro {
                            *edit = s.clone();
                        }
                    }
                    _ => return,
                }
                self.run(Action::Apply(index), ctx);
            }
            Action::Apply(index) => {
                let Some(device) = self.devices.get(index).cloned() else { return };
                self.status = "Applying… (the keyboard can take ~20 s)".into();
                let lift_off = device.lift_off().unwrap_or(self.declared_lift_off());
                self.spawn(ctx, move || {
                    let result = apply(&device).map_err(|e| e.to_string());
                    Msg::Applied { index, device: Box::new(read(device.node(), lift_off)), result }
                });
            }
            Action::Copy(text) => {
                copy(ctx, text);
                self.status = "Copied as Nix".into();
            }
        }
    }

    fn poll(&mut self) {
        let Some(msg) = self.job.as_ref().and_then(|rx| rx.try_recv().ok()) else { return };
        self.job = None;
        match msg {
            Msg::Scanned(devices) => {
                self.status = match devices.len() {
                    0 => "No supported devices found".into(),
                    n => format!("{n} device(s)"),
                };
                self.devices = devices;
            }
            Msg::Applied { index, device, result } => {
                match result {
                    Ok(changes) if changes.is_empty() => self.status = "Nothing to change".into(),
                    Ok(changes) => {
                        self.status = format!("Applied {} change(s)", changes.len());
                        self.log.extend(changes);
                    }
                    Err(e) => self.status = format!("Apply failed: {e}"),
                }
                if let Some(slot) = self.devices.get_mut(index) {
                    *slot = *device;
                }
            }
        }
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.poll();
        let ctx = ui.ctx().clone();
        let busy = self.job.is_some();
        let mut action = None;
        egui::CentralPanel::default().show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.heading("Peripherals");
                if ui.add_enabled(!busy, Button::new("Reload")).clicked() {
                    action = Some(Action::Reload);
                }
                if busy {
                    ui.spinner();
                }
                ui.label(RichText::new(&self.status).weak());
            });
            ui.label(
                RichText::new("Changes here last until the device is plugged in again; then the service restores your Nix config.")
                    .small()
                    .weak(),
            );
            if let Some(e) = &self.config_error {
                ui.colored_label(Color32::LIGHT_RED, format!("Nix config not loaded: {e}"));
            }
            egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
                for (index, device) in self.devices.iter_mut().enumerate() {
                    ui.separator();
                    if let Some(a) = device_ui(ui, index, device, self.declared.as_ref(), busy) {
                        action = Some(a);
                    }
                }
                if !self.log.is_empty() {
                    ui.separator();
                    egui::CollapsingHeader::new("Changes applied").show(ui, |ui| {
                        for line in &self.log {
                            ui.label(RichText::new(line).small());
                        }
                    });
                }
            });
        });
        if let Some(a) = action {
            self.run(a, &ctx);
        }
    }
}

/// One device's panel. Returns what the buttons asked for.
fn device_ui(ui: &mut egui::Ui, index: usize, device: &mut Device, declared: Option<&Config>, busy: bool) -> Option<Action> {
    let (dirty, has_nix, nix_text) = match device {
        Device::Unavailable { node, why } => {
            ui.strong(format!("{} ({:04x}:{:04x})", node.dev.display(), node.vid, node.pid));
            ui.colored_label(CHANGED, why.as_str());
            return None;
        }
        Device::Mouse { id, wired, read, edit, .. } => {
            let link = if *wired { "cable" } else { "dongle" };
            let charging = if id.charging { ", charging" } else { "" };
            ui.strong(format!("MCHOSE M7 Ultra — {link}, battery {}%{charging}", id.battery));
            let nix = declared.and_then(|c| c.mchose_m7_ultra.as_ref());
            mouse_ui(ui, edit, nix, *wired);
            (read != edit, nix.is_some(), mchose::to_nix(edit, true))
        }
        Device::Keyboard { model, precision, read, edit, .. } => {
            ui.strong(model.name);
            let nix = declared.and_then(|c| c.boyi_h60pro.as_ref());
            keyboard_ui(ui, model, edit, nix);
            (read != edit, nix.is_some(), rongyuan::to_nix(edit, *precision))
        }
    };
    let mut action = None;
    ui.horizontal(|ui| {
        if ui.add_enabled(dirty && !busy, Button::new("Apply")).clicked() {
            action = Some(Action::Apply(index));
        }
        if ui.add_enabled(dirty, Button::new("Revert")).clicked() {
            match device {
                Device::Mouse { read, edit, .. } => *edit = read.clone(),
                Device::Keyboard { read, edit, .. } => *edit = read.clone(),
                Device::Unavailable { .. } => {}
            }
        }
        let reset = ui.add_enabled(has_nix && !busy, Button::new("Reset to Nix"));
        if reset.on_hover_text("Apply your declared Nix config now").clicked() {
            action = Some(Action::ResetToNix(index));
        }
        if ui.button("Copy as Nix").on_hover_text("Copy these settings as a Nix snippet").clicked() {
            action = Some(Action::Copy(nix_text));
        }
    });
    action
}

/// Finish a grid row: flag values that differ from the Nix config.
fn mark(ui: &mut egui::Ui, differs: bool) {
    if differs {
        ui.label(RichText::new("≠ nix").color(CHANGED))
            .on_hover_text("Differs from your Nix config; the next plug-in restores the Nix value");
    } else {
        ui.label("");
    }
    ui.end_row();
}

fn combo<T: PartialEq + Copy>(ui: &mut egui::Ui, id: &str, value: &mut T, options: &[(T, String)]) {
    let selected = options.iter().find(|(v, _)| v == value).map_or("?", |(_, l)| l.as_str()).to_string();
    ComboBox::from_id_salt(id).selected_text(selected).show_ui(ui, |ui| {
        for (v, label) in options {
            ui.selectable_value(value, *v, label.as_str());
        }
    });
}

fn mouse_ui(ui: &mut egui::Ui, s: &mut mchose::Settings, nix: Option<&mchose::Settings>, wired: bool) {
    let rates: Vec<(u32, String)> = mchose::RATES.iter().map(|&hz| (hz, format!("{hz} Hz"))).collect();
    egui::Grid::new("mouse").num_columns(3).spacing([14.0, 6.0]).show(ui, |ui| {
        ui.label("DPI stages");
        ui.horizontal(|ui| {
            let count = s.dpi_stages.len();
            let mut remove = None;
            for (i, dpi) in s.dpi_stages.iter_mut().enumerate() {
                ui.add(DragValue::new(dpi).range(50..=42000).speed(10));
                if count > 1 && ui.small_button("✕").clicked() {
                    remove = Some(i);
                }
            }
            if let Some(i) = remove {
                s.dpi_stages.remove(i);
            }
            if s.dpi_stages.len() < 6 && ui.small_button("+").clicked() {
                let last = *s.dpi_stages.last().unwrap_or(&1600);
                s.dpi_stages.push(last);
            }
            s.active_stage = s.active_stage.clamp(1, s.dpi_stages.len() as u8);
        });
        mark(ui, nix.is_some_and(|n| n.dpi_stages != s.dpi_stages));

        ui.label("Active stage");
        let stages: Vec<(u8, String)> = (1..=s.dpi_stages.len() as u8).map(|i| (i, i.to_string())).collect();
        combo(ui, "stage", &mut s.active_stage, &stages);
        mark(ui, nix.is_some_and(|n| n.active_stage != s.active_stage));

        ui.label("Polling rate (cable)");
        ui.horizontal(|ui| {
            combo(ui, "wired", &mut s.polling_rate.wired, &rates);
            if !wired {
                ui.label(RichText::new("applies over the cable").small().weak());
            }
        });
        mark(ui, nix.is_some_and(|n| n.polling_rate.wired != s.polling_rate.wired));

        ui.label("Polling rate (dongle)");
        ui.horizontal(|ui| {
            combo(ui, "wireless", &mut s.polling_rate.wireless, &rates);
            if wired {
                ui.label(RichText::new("applies over the dongle").small().weak());
            }
        });
        mark(ui, nix.is_some_and(|n| n.polling_rate.wireless != s.polling_rate.wireless));

        ui.label("Lift-off distance");
        let lifts: Vec<_> = mchose::LiftOff::ALL.iter().map(|&l| (l, l.name().to_string())).collect();
        combo(ui, "lift", &mut s.lift_off, &lifts);
        mark(ui, nix.is_some_and(|n| n.lift_off != s.lift_off));

        ui.label("Motion sync");
        ui.checkbox(&mut s.motion_sync, "");
        mark(ui, nix.is_some_and(|n| n.motion_sync != s.motion_sync));

        ui.label("Ripple control");
        ui.checkbox(&mut s.ripple, "");
        mark(ui, nix.is_some_and(|n| n.ripple != s.ripple));

        ui.label("Angle snapping");
        ui.checkbox(&mut s.angle_snap, "");
        mark(ui, nix.is_some_and(|n| n.angle_snap != s.angle_snap));

        ui.label("Angle correction");
        ui.add(Slider::new(&mut s.angle_correction, -30..=30).suffix("°"));
        mark(ui, nix.is_some_and(|n| n.angle_correction != s.angle_correction));

        ui.label("Performance mode");
        let modes: Vec<_> = mchose::Mode::ALL.iter().map(|&m| (m, m.name().to_string())).collect();
        combo(ui, "mode", &mut s.performance_mode, &modes);
        mark(ui, nix.is_some_and(|n| n.performance_mode != s.performance_mode));

        ui.label("Debounce");
        ui.add(DragValue::new(&mut s.debounce_ms).range(0..=50).suffix(" ms"));
        mark(ui, nix.is_some_and(|n| n.debounce_ms != s.debounce_ms));

        ui.label("Sleep after");
        ui.add(DragValue::new(&mut s.sleep_minutes).range(0..=255).suffix(" min"))
            .on_hover_text("0 never sleeps");
        mark(ui, nix.is_some_and(|n| n.sleep_minutes != s.sleep_minutes));

        ui.label("Lighting");
        ui.checkbox(&mut s.lighting, "");
        mark(ui, nix.is_some_and(|n| n.lighting != s.lighting));

    });
    ui.add_space(8.0);
    mouse_diagram(ui, &mut s.buttons, nix.map(|n| &n.buttons));
}

const BUTTON_LABELS: [&str; 6] = ["Left", "Middle", "Right", "Forward", "Back", "DPI"];

/// One button's action: free text (for key combos) plus the named actions.
fn button_editor(ui: &mut egui::Ui, slot: usize, action: &mut String) {
    ui.add(egui::TextEdit::singleline(action).desired_width(170.0).hint_text("default"));
    ComboBox::from_id_salt(("button", slot)).selected_text("").width(24.0).show_ui(ui, |ui| {
        for (name, ..) in mchose_buttons::ACTIONS {
            if ui.selectable_label(action == name, name).clicked() {
                *action = name.to_string();
            }
        }
    });
    if mchose_buttons::encode(action, slot).is_none() {
        ui.colored_label(Color32::LIGHT_RED, "unknown")
            .on_hover_text("Pick from the list, or type key:ctrl+c style combos");
    }
}

/// A top-down mouse with a label per button; click a button or label to edit it below.
fn mouse_diagram(ui: &mut egui::Ui, buttons: &mut mchose::Buttons, declared: Option<&mchose::Buttons>) {
    use egui::{pos2, vec2, Align2, CornerRadius, FontId, Pos2, Rect, Sense, Shape, Stroke, StrokeKind};

    let size = vec2(ui.available_width().max(420.0), 330.0);
    let (rect, response) = ui.allocate_exact_size(size, Sense::click());
    let painter = ui.painter_at(rect);
    let v = ui.visuals().clone();
    let id = ui.id().with("selected-button");
    let mut selected = ui.data(|d| d.get_temp::<usize>(id)).unwrap_or(5);

    // Body: a rounded superellipse, a touch wider toward the palm.
    let (cx, top, bw, bh) = (rect.center().x, rect.top() + 18.0, 120.0, 290.0);
    let half = |y: f32| {
        let t = ((y - top) / bh).clamp(0.0, 1.0);
        let p = 2.4;
        bw / 2.0 * (1.0 - (2.0 * t - 1.0).abs().powf(p)).max(0.0).powf(1.0 / p) * (0.9 + 0.1 * t)
    };
    let steps = 48;
    let ys = (0..=steps).map(|i| top + bh * i as f32 / steps as f32);
    let outline: Vec<Pos2> = ys.clone().map(|y| pos2(cx - half(y), y)).chain(ys.rev().map(|y| pos2(cx + half(y), y))).collect();
    let split = top + bh * 0.42;
    let wheel = Rect::from_center_size(pos2(cx, top + bh * 0.17), vec2(16.0, 46.0));
    let side = |frac: f32| {
        let y = top + bh * frac;
        let x = cx - half(y);
        Rect::from_min_max(pos2(x - 6.0, y - 16.0), pos2(x + 6.0, y + 16.0))
    };
    let (forward, back) = (side(0.40), side(0.56));
    let dpi = pos2(cx, top + bh * 0.76);

    // Per slot: the point on the mouse, where its label goes, and which side.
    let (lx, rx) = (cx - bw / 2.0 - 28.0, cx + bw / 2.0 + 28.0);
    let spots: [(Pos2, Pos2, bool); 6] = [
        (pos2(cx - bw * 0.22, top + bh * 0.22), pos2(lx, top + bh * 0.12), false),
        (wheel.center_top() + vec2(0.0, 8.0), pos2(rx, top + bh * 0.06), true),
        (pos2(cx + bw * 0.22, top + bh * 0.24), pos2(rx, top + bh * 0.24), true),
        (forward.left_center(), pos2(lx, top + bh * 0.40), false),
        (back.left_center(), pos2(lx, top + bh * 0.58), false),
        (dpi + vec2(9.0, 0.0), pos2(rx, top + bh * 0.76), true),
    ];
    let label_rect = |pos: Pos2, right: bool| {
        let min = if right { pos - vec2(0.0, 20.0) } else { pos - vec2(120.0, 20.0) };
        Rect::from_min_size(min, vec2(120.0, 40.0))
    };
    let hit = |p: Pos2| -> Option<usize> {
        if wheel.expand(3.0).contains(p) {
            return Some(1);
        }
        if forward.expand(3.0).contains(p) {
            return Some(3);
        }
        if back.expand(3.0).contains(p) {
            return Some(4);
        }
        if p.distance(dpi) <= 13.0 {
            return Some(5);
        }
        if p.y >= top && p.y <= split && (p.x - cx).abs() <= half(p.y) {
            return Some(if p.x < cx { 0 } else { 2 });
        }
        (0..6).find(|&slot| label_rect(spots[slot].1, spots[slot].2).contains(p))
    };

    let hovered = response.hover_pos().and_then(hit);
    if hovered.is_some() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }
    if let Some(slot) = response.clicked().then(|| response.interact_pointer_pos()).flatten().and_then(hit) {
        selected = slot;
        ui.data_mut(|d| d.insert_temp(id, slot));
    }

    let differs = |slot: usize| declared.is_some_and(|d| d.slots()[slot] != buttons.slots()[slot]);
    let fill = |slot: usize| {
        if slot == selected {
            v.selection.bg_fill
        } else if hovered == Some(slot) {
            v.widgets.hovered.bg_fill
        } else {
            v.widgets.inactive.bg_fill
        }
    };
    let line = v.widgets.noninteractive.fg_stroke;
    let stroke = |slot: usize| if differs(slot) { Stroke::new(2.0, CHANGED) } else { line };

    painter.add(Shape::convex_polygon(outline.clone(), v.faint_bg_color, Stroke::new(1.5, line.color)));
    for (slot, clip) in [
        (0, Rect::from_min_max(pos2(rect.left(), top), pos2(cx - 1.0, split))),
        (2, Rect::from_min_max(pos2(cx + 1.0, top), pos2(rect.right(), split))),
    ] {
        painter.with_clip_rect(clip).add(Shape::convex_polygon(outline.clone(), fill(slot), stroke(slot)));
    }
    painter.line_segment([pos2(cx - half(split), split), pos2(cx + half(split), split)], line);
    painter.line_segment([pos2(cx, top), pos2(cx, split)], line);
    painter.rect(wheel, CornerRadius::same(7), fill(1), stroke(1), StrokeKind::Middle);
    for i in 1..5 {
        let y = wheel.top() + wheel.height() * i as f32 / 5.0;
        painter.line_segment([pos2(wheel.left() + 4.0, y), pos2(wheel.right() - 4.0, y)], Stroke::new(1.0, line.color));
    }
    for (slot, r) in [(3, forward), (4, back)] {
        painter.rect(r, CornerRadius::same(4), fill(slot), stroke(slot), StrokeKind::Middle);
    }
    painter.circle(dpi, 9.0, fill(5), stroke(5));
    painter.text(dpi + vec2(0.0, 14.0), Align2::CENTER_TOP, "underside", FontId::proportional(10.0), v.weak_text_color());

    let actions = buttons.slots();
    for (slot, &(anchor, pos, right)) in spots.iter().enumerate() {
        let edge = if right { pos - vec2(6.0, 0.0) } else { pos + vec2(6.0, 0.0) };
        let color = if differs(slot) { CHANGED } else { v.weak_text_color() };
        painter.line_segment([anchor, edge], Stroke::new(1.0, color));
        painter.circle_filled(anchor, 2.5, color);
        let (name_align, action_align) =
            if right { (Align2::LEFT_BOTTOM, Align2::LEFT_TOP) } else { (Align2::RIGHT_BOTTOM, Align2::RIGHT_TOP) };
        let name_color = if slot == selected { v.selection.stroke.color } else { v.strong_text_color() };
        painter.text(pos, name_align, BUTTON_LABELS[slot], FontId::proportional(14.0), name_color);
        painter.text(pos + vec2(0.0, 2.0), action_align, actions[slot].as_str(), FontId::proportional(12.0), color);
    }

    let changed = differs(selected);
    ui.horizontal(|ui| {
        ui.label(RichText::new(format!("{} button", BUTTON_LABELS[selected])).strong());
        button_editor(ui, selected, buttons.slots_mut()[selected]);
        if changed {
            ui.label(RichText::new("≠ nix").color(CHANGED));
        }
    });
}

/// Show an optional value's editor, or "unknown" when the keyboard didn't report it.
fn opt<T>(ui: &mut egui::Ui, value: &mut Option<T>, add: impl FnOnce(&mut egui::Ui, &mut T)) {
    match value {
        Some(v) => add(ui, v),
        None => {
            ui.label(RichText::new("unknown").weak());
        }
    }
}

/// A Nix value of None means "leave it", so only a set value can differ.
fn differs<T: PartialEq>(nix: Option<&Option<T>>, value: &Option<T>) -> bool {
    nix.is_some_and(|n| n.is_some() && n != value)
}

fn mm(ui: &mut egui::Ui, value: &mut f64, max: f64) {
    ui.add(DragValue::new(value).range(0.0..=max).speed(0.01).fixed_decimals(2).suffix(" mm"));
}

fn keyboard_ui(ui: &mut egui::Ui, model: &rongyuan::Model, s: &mut rongyuan::Settings, nix: Option<&rongyuan::Settings>) {
    egui::Grid::new("keyboard").num_columns(3).spacing([14.0, 6.0]).show(ui, |ui| {
        ui.label("Polling rate");
        let rates: Vec<(u16, String)> = KB_RATES.iter().map(|&hz| (hz, format!("{hz} Hz"))).collect();
        opt(ui, &mut s.polling_rate, |ui, v| combo(ui, "kb-rate", v, &rates));
        mark(ui, differs(nix.map(|n| &n.polling_rate), &s.polling_rate));

        ui.label("Debounce");
        opt(ui, &mut s.debounce_ms, |ui, v| {
            ui.add(DragValue::new(v).range(0..=50).suffix(" ms"));
        });
        mark(ui, differs(nix.map(|n| &n.debounce_ms), &s.debounce_ms));

        let l = &mut s.lighting;
        let nl = nix.map(|n| &n.lighting);
        ui.label("Lighting effect");
        opt(ui, &mut l.effect, |ui, v| {
            ComboBox::from_id_salt("effect").selected_text(v.as_str()).show_ui(ui, |ui| {
                for (name, _) in rongyuan::EFFECTS {
                    ui.selectable_value(v, name.to_string(), name);
                }
            });
        });
        mark(ui, differs(nl.map(|n| &n.effect), &l.effect));

        ui.label("Brightness");
        opt(ui, &mut l.brightness, |ui, v| {
            ui.add(Slider::new(v, 0..=4));
        });
        mark(ui, differs(nl.map(|n| &n.brightness), &l.brightness));

        ui.label("Effect speed");
        opt(ui, &mut l.speed, |ui, v| {
            ui.add(Slider::new(v, 0..=4));
        });
        mark(ui, differs(nl.map(|n| &n.speed), &l.speed));

        ui.label("Rainbow");
        opt(ui, &mut l.rainbow, |ui, v| {
            ui.checkbox(v, "").on_hover_text("qmk.top's \"Dazzling\": cycle colours instead of one");
        });
        mark(ui, differs(nl.map(|n| &n.rainbow), &l.rainbow));

        ui.label("Colour");
        opt(ui, &mut l.color, |ui, v| {
            let mut rgb = rongyuan::parse_color(v).map_or([255, 255, 255], |c| [c.r, c.g, c.b]);
            if ui.color_edit_button_srgb(&mut rgb).changed() {
                *v = format!("#{:02x}{:02x}{:02x}", rgb[0], rgb[1], rgb[2]);
            }
        });
        mark(ui, differs(nl.map(|n| &n.color), &l.color));

        ui.label("Fn layer");
        let layers = [(0u8, "0".to_string()), (1, "1".to_string())];
        opt(ui, &mut s.fn_layer, |ui, v| combo(ui, "fn-layer", v, &layers));
        mark(ui, differs(nix.map(|n| &n.fn_layer), &s.fn_layer));

        ui.label("Anti-mistouch");
        opt(ui, &mut s.anti_mistouch, |ui, v| {
            ui.checkbox(v, "");
        });
        mark(ui, differs(nix.map(|n| &n.anti_mistouch), &s.anti_mistouch));

        ui.label("RT stability");
        let steps: Vec<(u16, String)> = (0..=5).map(|i| (i * 25, format!("{} ms", i * 25))).collect();
        opt(ui, &mut s.rt_stability_ms, |ui, v| combo(ui, "rt-stability", v, &steps));
        mark(ui, differs(nix.map(|n| &n.rt_stability_ms), &s.rt_stability_ms));

        ui.label("WASD/arrow swap");
        ui.checkbox(&mut s.wasd_swap, "");
        mark(ui, nix.is_some_and(|n| n.wasd_swap != s.wasd_swap));

        ui.label("Actuation");
        mm(ui, &mut s.actuation, 3.3);
        mark(ui, nix.is_some_and(|n| n.actuation != s.actuation));

        ui.label("Release");
        ui.horizontal(|ui| {
            let mut follows = s.release.is_none();
            if ui.checkbox(&mut follows, "same as actuation").changed() {
                s.release = (!follows).then_some(s.actuation);
            }
            if let Some(v) = &mut s.release {
                mm(ui, v, 3.3);
            }
        });
        mark(ui, nix.is_some_and(|n| n.release != s.release));

        let rt = &mut s.rapid_trigger;
        let nrt = nix.map(|n| &n.rapid_trigger);
        ui.label("Rapid trigger");
        ui.checkbox(&mut rt.enable, "");
        mark(ui, nrt.is_some_and(|n| n.enable != rt.enable));

        ui.label("RT press sensitivity");
        opt(ui, &mut rt.press, |ui, v| mm(ui, v, 2.0));
        mark(ui, differs(nrt.map(|n| &n.press), &rt.press));

        ui.label("RT release sensitivity");
        opt(ui, &mut rt.release, |ui, v| mm(ui, v, 2.0));
        mark(ui, differs(nrt.map(|n| &n.release), &rt.release));

        ui.label("Bottom dead zone");
        opt(ui, &mut s.bottom_deadzone, |ui, v| mm(ui, v, 1.0));
        mark(ui, differs(nix.map(|n| &n.bottom_deadzone), &s.bottom_deadzone));
    });

    ui.add_space(6.0);
    ui.horizontal(|ui| {
        ui.label("Per-key actuation");
        if nix.is_some_and(|n| n.keys != s.keys) {
            ui.label(RichText::new("≠ nix").color(CHANGED));
        }
    });
    let mut remove = None;
    for (name, o) in s.keys.iter_mut() {
        ui.horizontal(|ui| {
            ui.label(format!("{name:>12}"));
            match &mut o.actuation {
                Some(v) => mm(ui, v, 3.3),
                None => {
                    ui.label(RichText::new("—").weak());
                }
            }
            if ui.small_button("✕").clicked() {
                remove = Some(name.clone());
            }
        });
    }
    if let Some(name) = remove {
        s.keys.remove(&name);
    }
    let mut add = None;
    ComboBox::from_id_salt("add-key").selected_text("Add a key…").show_ui(ui, |ui| {
        for name in model.key_names().filter(|n| !s.keys.contains_key(*n)) {
            if ui.selectable_label(false, name).clicked() {
                add = Some(name);
            }
        }
    });
    if let Some(name) = add {
        s.keys.insert(name.to_string(), rongyuan::KeyOverride { actuation: Some(s.actuation), release: None });
    }
}

/// `periph-gui [--config <path>] [device]`; without --config, the copy home-manager
/// puts in ~/.config/periph.
fn parse_args() -> (Option<PathBuf>, Option<String>) {
    let mut args = std::env::args().skip(1);
    let (mut path, mut only) = (None, None);
    while let Some(arg) = args.next() {
        if arg == "--config" {
            path = args.next().map(PathBuf::from);
        } else if DEVICE_NAMES.contains(&arg.as_str()) {
            only = Some(arg);
        } else {
            eprintln!("usage: periph-gui [--config <path>] [{}]", DEVICE_NAMES.join("|"));
            std::process::exit(2);
        }
    }
    let default = || {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))?;
        Some(base.join("periph/config.json")).filter(|p| p.exists())
    };
    (path.or_else(default), only)
}

fn main() -> eframe::Result {
    let (path, only) = parse_args();
    let (declared, config_error) = match path.as_deref().map(config::load) {
        Some(Ok(c)) => (Some(c), None),
        Some(Err(e)) => (None, Some(e)),
        None => (None, None),
    };
    // A per-device class lets window rules and popup toggles tell the windows apart.
    let app_id = only.as_ref().map_or("periph".to_string(), |d| format!("periph-{d}"));
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([720.0, 1000.0])
            .with_title("Peripherals")
            .with_app_id(app_id),
        ..Default::default()
    };
    eframe::run_native(
        "periph",
        options,
        Box::new(move |cc| {
            cc.egui_ctx.set_zoom_factor(1.25);
            Ok(Box::new(App::new(&cc.egui_ctx, declared, config_error, only)))
        }),
    )
}
