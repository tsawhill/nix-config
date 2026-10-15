//! Native GTK editor for live peripheral settings. Changes are temporary; the
//! service restores the declared Nix configuration when a device reconnects.

use gtk::gdk;
use gtk::glib::{self, ControlFlow};
use gtk::prelude::*;
use gtk::{Align, Orientation};
use periph::config::{self, Config};
use periph::hidraw::{HidRaw, Node};
use periph::{devices, mchose, mchose_buttons, rongyuan};
use std::cell::RefCell;
use std::io;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::mpsc::{self, Receiver};
use std::time::Duration;

const LOCK_WAIT: Duration = Duration::from_secs(3);
const KB_RATES: [u16; 7] = [125, 250, 500, 1000, 2000, 4000, 8000];
const BUTTON_LABELS: [&str; 6] = ["Left", "Middle", "Right", "Forward", "Back", "DPI"];
const DEVICE_NAMES: [&str; 2] = ["mchose-m7-ultra", "boyi-h60pro"];

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
            Self::Mouse { node, .. }
            | Self::Keyboard { node, .. }
            | Self::Unavailable { node, .. } => node,
        }
    }

    fn lift_off(&self) -> Option<mchose::LiftOff> {
        match self {
            Self::Mouse { edit, .. } => Some(edit.lift_off),
            _ => None,
        }
    }

    fn dirty(&self) -> bool {
        match self {
            Self::Mouse { read, edit, .. } => read != edit,
            Self::Keyboard { read, edit, .. } => read != edit,
            Self::Unavailable { .. } => false,
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
        return Err(io::Error::other(format!(
            "MCHOSE device id {} isn't supported yet",
            id.id
        )));
    }
    let wired = node.pid == id.id;
    let read = mchose::settings_from(&mchose::observe(&dev, &id, wired)?, lift_off);
    Ok(Device::Mouse {
        node: node.clone(),
        id,
        wired,
        edit: read.clone(),
        read,
    })
}

fn read_keyboard(node: &Node) -> io::Result<Device> {
    match rongyuan::open(node)? {
        rongyuan::Opened::Unknown(id) => Err(io::Error::other(format!(
            "RongYuan device id {id} isn't supported yet"
        ))),
        rongyuan::Opened::Known(kb) => {
            let read = kb.settings_from(&kb.observe()?);
            Ok(Device::Keyboard {
                node: node.clone(),
                model: kb.model,
                precision: kb.precision(),
                edit: read.clone(),
                read,
            })
        }
    }
}

fn read(node: &Node, lift_off: mchose::LiftOff) -> Device {
    let result = if rongyuan::is_config_node(node) {
        read_keyboard(node)
    } else {
        read_mouse(node, lift_off)
    };
    result.unwrap_or_else(|error| Device::Unavailable {
        node: node.clone(),
        why: error.to_string(),
    })
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
                rongyuan::Opened::Unknown(id) => {
                    Err(io::Error::other(format!("device id {id} isn't supported")))
                }
            }
        }
        Device::Unavailable { .. } => Ok(Vec::new()),
    }
}

enum Msg {
    Scanned(Vec<Device>),
    Applied {
        index: usize,
        device: Box<Device>,
        result: Result<Vec<String>, String>,
    },
}

struct State {
    declared: Option<Config>,
    config_error: Option<String>,
    only: Option<String>,
    devices: Vec<Device>,
    job: Option<Receiver<Msg>>,
    status: String,
    log: Vec<String>,
}

impl State {
    fn declared_lift_off(&self) -> mchose::LiftOff {
        self.declared
            .as_ref()
            .and_then(|c| c.mchose_m7_ultra.as_ref())
            .map_or(mchose::LiftOff::Low, |s| s.lift_off)
    }

    fn reload(&mut self) {
        self.status = "Reading devices…".into();
        let lift_off = self.declared_lift_off();
        let only = self.only.clone();
        self.spawn(move || {
            let nodes = devices()
                .into_iter()
                .filter(|node| wanted(node, only.as_deref()));
            Msg::Scanned(nodes.map(|node| read(&node, lift_off)).collect())
        });
    }

    fn apply(&mut self, index: usize) {
        let Some(device) = self.devices.get(index).cloned() else {
            return;
        };
        self.status = "Applying… (the keyboard can take about 20 seconds)".into();
        let lift_off = device.lift_off().unwrap_or(self.declared_lift_off());
        self.spawn(move || {
            let result = apply(&device).map_err(|error| error.to_string());
            Msg::Applied {
                index,
                device: Box::new(read(device.node(), lift_off)),
                result,
            }
        });
    }

    fn reset_to_nix(&mut self, index: usize) {
        let Some(declared) = &self.declared else {
            return;
        };
        match self.devices.get_mut(index) {
            Some(Device::Mouse { edit, .. }) => {
                if let Some(settings) = &declared.mchose_m7_ultra {
                    *edit = settings.clone();
                }
            }
            Some(Device::Keyboard { edit, .. }) => {
                if let Some(settings) = &declared.boyi_h60pro {
                    *edit = settings.clone();
                }
            }
            _ => return,
        }
        self.apply(index);
    }

    fn spawn(&mut self, job: impl FnOnce() -> Msg + Send + 'static) {
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(job());
        });
        self.job = Some(rx);
    }

    fn poll(&mut self) -> bool {
        let Some(message) = self
            .job
            .as_ref()
            .and_then(|receiver| receiver.try_recv().ok())
        else {
            return false;
        };
        self.job = None;
        match message {
            Msg::Scanned(devices) => {
                self.status = match devices.len() {
                    0 => "No supported devices found".into(),
                    count => format!("{count} device(s)"),
                };
                self.devices = devices;
            }
            Msg::Applied {
                index,
                device,
                result,
            } => {
                match result {
                    Ok(changes) if changes.is_empty() => self.status = "Nothing to change".into(),
                    Ok(changes) => {
                        self.status = format!("Applied {} change(s)", changes.len());
                        self.log.extend(changes);
                    }
                    Err(error) => self.status = format!("Apply failed: {error}"),
                }
                if let Some(slot) = self.devices.get_mut(index) {
                    *slot = *device;
                }
            }
        }
        true
    }
}

type Shared = Rc<RefCell<State>>;
type UiSlot = Rc<RefCell<Option<Ui>>>;

#[derive(Clone)]
struct DeviceActions {
    index: usize,
    apply: gtk::Button,
    revert: gtk::Button,
    reset: gtk::Button,
}

#[derive(Clone)]
struct Ui {
    window: gtk::ApplicationWindow,
    status: gtk::Label,
    spinner: gtk::Spinner,
    reload: gtk::Button,
    devices: gtk::Box,
    actions: Rc<RefCell<Vec<DeviceActions>>>,
}

fn wanted(node: &Node, only: Option<&str>) -> bool {
    match only {
        None => true,
        Some("boyi-h60pro") => rongyuan::is_config_node(node),
        Some(_) => mchose::is_config_node(node),
    }
}

fn clear_box(container: &gtk::Box) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }
}

fn clipboard(text: String) {
    if let Some(display) = gdk::Display::default() {
        display.clipboard().set_text(&text);
    }
}

fn marker(modified: bool) -> gtk::Label {
    let label = gtk::Label::new(modified.then_some("Modified"));
    label.set_halign(Align::Start);
    if modified {
        label.add_css_class("warning");
        label.set_tooltip_text(Some(
            "Differs from Nix; reconnecting restores the declared value",
        ));
    }
    label
}

fn section(grid: &gtk::Grid, row: i32, title: &str) -> i32 {
    let label = gtk::Label::new(Some(title));
    label.add_css_class("heading");
    label.set_halign(Align::Start);
    label.set_margin_top(if row == 0 { 0 } else { 12 });
    grid.attach(&label, 0, row, 3, 1);
    row + 1
}

fn add_row(
    grid: &gtk::Grid,
    row: i32,
    name: &str,
    widget: &impl IsA<gtk::Widget>,
    modified: bool,
) -> i32 {
    let label = gtk::Label::new(Some(name));
    label.set_halign(Align::Start);
    grid.attach(&label, 0, row, 1, 1);
    grid.attach(widget, 1, row, 1, 1);
    grid.attach(&marker(modified), 2, row, 1, 1);
    row + 1
}

fn spin(
    value: f64,
    min: f64,
    max: f64,
    step: f64,
    digits: u32,
    suffix: &str,
) -> (gtk::Box, gtk::SpinButton) {
    let button = gtk::SpinButton::with_range(min, max, step);
    button.set_value(value);
    button.set_digits(digits);
    button.set_width_chars(7);
    let row = gtk::Box::new(Orientation::Horizontal, 6);
    row.append(&button);
    if !suffix.is_empty() {
        row.append(&gtk::Label::new(Some(suffix)));
    }
    (row, button)
}

fn dropdown(labels: &[String], selected: usize) -> gtk::DropDown {
    let names: Vec<&str> = labels.iter().map(String::as_str).collect();
    let dropdown = gtk::DropDown::from_strings(&names);
    dropdown.set_selected(selected as u32);
    dropdown
}

fn refresh(state: &Shared, ui: &Ui) {
    let state = state.borrow();
    let busy = state.job.is_some();
    ui.status.set_label(&state.status);
    ui.reload.set_sensitive(!busy);
    if busy {
        ui.spinner.start();
    } else {
        ui.spinner.stop();
    }
    for actions in ui.actions.borrow().iter() {
        let dirty = state.devices.get(actions.index).is_some_and(Device::dirty);
        let has_nix = match state.devices.get(actions.index) {
            Some(Device::Mouse { .. }) => state
                .declared
                .as_ref()
                .is_some_and(|config| config.mchose_m7_ultra.is_some()),
            Some(Device::Keyboard { .. }) => state
                .declared
                .as_ref()
                .is_some_and(|config| config.boyi_h60pro.is_some()),
            _ => false,
        };
        actions.apply.set_sensitive(dirty && !busy);
        actions.revert.set_sensitive(dirty && !busy);
        actions.reset.set_sensitive(has_nix && !busy);
    }
}

fn changed(state: &Shared, slot: &UiSlot) {
    if let Some(ui) = slot.borrow().as_ref() {
        refresh(state, ui);
    }
}

fn mutate_mouse(state: &Shared, index: usize, change: impl FnOnce(&mut mchose::Settings)) {
    if let Some(Device::Mouse { edit, .. }) = state.borrow_mut().devices.get_mut(index) {
        change(edit);
    }
}

fn mutate_keyboard(state: &Shared, index: usize, change: impl FnOnce(&mut rongyuan::Settings)) {
    if let Some(Device::Keyboard { edit, .. }) = state.borrow_mut().devices.get_mut(index) {
        change(edit);
    }
}

fn mouse_settings(
    index: usize,
    current: &mchose::Settings,
    declared: Option<&mchose::Settings>,
    wired: bool,
    state: &Shared,
    slot: &UiSlot,
) -> gtk::Grid {
    let grid = gtk::Grid::builder()
        .column_spacing(18)
        .row_spacing(10)
        .hexpand(true)
        .build();
    let mut row = section(&grid, 0, "Sensitivity");

    let stages = gtk::Box::new(Orientation::Horizontal, 6);
    for (stage, value) in current.dpi_stages.iter().copied().enumerate() {
        let (widget, input) = spin(value.into(), 50.0, 42000.0, 50.0, 0, "");
        input.set_width_chars(5);
        let state_clone = state.clone();
        let slot_clone = slot.clone();
        input.connect_value_changed(move |input| {
            mutate_mouse(&state_clone, index, |settings| {
                settings.dpi_stages[stage] = input.value() as u16
            });
            changed(&state_clone, &slot_clone);
        });
        stages.append(&widget);
        if current.dpi_stages.len() > 1 {
            let remove = gtk::Button::with_label("−");
            remove.add_css_class("flat");
            let state_clone = state.clone();
            let slot_clone = slot.clone();
            remove.connect_clicked(move |_| {
                mutate_mouse(&state_clone, index, |settings| {
                    settings.dpi_stages.remove(stage);
                    settings.active_stage =
                        settings.active_stage.min(settings.dpi_stages.len() as u8);
                });
                rebuild_devices(&state_clone, &slot_clone);
            });
            stages.append(&remove);
        }
    }
    if current.dpi_stages.len() < 6 {
        let add = gtk::Button::with_label("+");
        let state_clone = state.clone();
        let slot_clone = slot.clone();
        add.connect_clicked(move |_| {
            mutate_mouse(&state_clone, index, |settings| {
                let value = *settings.dpi_stages.last().unwrap_or(&1600);
                settings.dpi_stages.push(value);
            });
            rebuild_devices(&state_clone, &slot_clone);
        });
        stages.append(&add);
    }
    row = add_row(
        &grid,
        row,
        "DPI stages",
        &stages,
        declared.is_some_and(|nix| nix.dpi_stages != current.dpi_stages),
    );

    let stage_labels: Vec<String> = (1..=current.dpi_stages.len())
        .map(|value| value.to_string())
        .collect();
    let stage = dropdown(
        &stage_labels,
        current.active_stage.saturating_sub(1) as usize,
    );
    {
        let state = state.clone();
        let slot = slot.clone();
        stage.connect_selected_notify(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.active_stage = input.selected() as u8 + 1
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Active stage",
        &stage,
        declared.is_some_and(|nix| nix.active_stage != current.active_stage),
    );
    row = section(&grid, row, "Tracking & performance");

    for (name, value, cable) in [
        ("Polling rate (cable)", current.polling_rate.wired, true),
        (
            "Polling rate (dongle)",
            current.polling_rate.wireless,
            false,
        ),
    ] {
        let labels: Vec<String> = mchose::RATES
            .iter()
            .map(|rate| format!("{rate} Hz"))
            .collect();
        let selected = mchose::RATES
            .iter()
            .position(|rate| *rate == value)
            .unwrap_or(0);
        let input = dropdown(&labels, selected);
        let state_clone = state.clone();
        let slot_clone = slot.clone();
        input.connect_selected_notify(move |input| {
            let rate = mchose::RATES[input.selected() as usize];
            mutate_mouse(&state_clone, index, |settings| {
                if cable {
                    settings.polling_rate.wired = rate
                } else {
                    settings.polling_rate.wireless = rate
                }
            });
            changed(&state_clone, &slot_clone);
        });
        let widget = gtk::Box::new(Orientation::Horizontal, 8);
        widget.append(&input);
        if wired != cable {
            let hint = gtk::Label::new(Some(if cable {
                "used over cable"
            } else {
                "used over dongle"
            }));
            hint.add_css_class("dim-label");
            widget.append(&hint);
        }
        let modified = declared.is_some_and(|nix| {
            if cable {
                nix.polling_rate.wired != value
            } else {
                nix.polling_rate.wireless != value
            }
        });
        row = add_row(&grid, row, name, &widget, modified);
    }

    let lift_labels: Vec<String> = mchose::LiftOff::ALL
        .iter()
        .map(|value| value.name().to_string())
        .collect();
    let lift_at = mchose::LiftOff::ALL
        .iter()
        .position(|value| *value == current.lift_off)
        .unwrap_or(0);
    let lift = dropdown(&lift_labels, lift_at);
    {
        let state = state.clone();
        let slot = slot.clone();
        lift.connect_selected_notify(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.lift_off = mchose::LiftOff::ALL[input.selected() as usize]
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Lift-off distance",
        &lift,
        declared.is_some_and(|nix| nix.lift_off != current.lift_off),
    );

    for (name, value, field) in [
        ("Motion sync", current.motion_sync, 0usize),
        ("Ripple control", current.ripple, 1),
        ("Angle snapping", current.angle_snap, 2),
    ] {
        let input = gtk::CheckButton::new();
        input.set_active(value);
        let state_clone = state.clone();
        let slot_clone = slot.clone();
        input.connect_toggled(move |input| {
            mutate_mouse(&state_clone, index, |settings| match field {
                0 => settings.motion_sync = input.is_active(),
                1 => settings.ripple = input.is_active(),
                _ => settings.angle_snap = input.is_active(),
            });
            changed(&state_clone, &slot_clone);
        });
        let modified = declared.is_some_and(|nix| match field {
            0 => nix.motion_sync != value,
            1 => nix.ripple != value,
            _ => nix.angle_snap != value,
        });
        row = add_row(&grid, row, name, &input, modified);
    }

    let (angle_widget, angle) = spin(current.angle_correction.into(), -30.0, 30.0, 1.0, 0, "°");
    {
        let state = state.clone();
        let slot = slot.clone();
        angle.connect_value_changed(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.angle_correction = input.value() as i8
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Angle correction",
        &angle_widget,
        declared.is_some_and(|nix| nix.angle_correction != current.angle_correction),
    );

    let mode_labels: Vec<String> = mchose::Mode::ALL
        .iter()
        .map(|value| value.name().to_string())
        .collect();
    let mode_at = mchose::Mode::ALL
        .iter()
        .position(|value| *value == current.performance_mode)
        .unwrap_or(0);
    let mode = dropdown(&mode_labels, mode_at);
    {
        let state = state.clone();
        let slot = slot.clone();
        mode.connect_selected_notify(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.performance_mode = mchose::Mode::ALL[input.selected() as usize]
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Performance mode",
        &mode,
        declared.is_some_and(|nix| nix.performance_mode != current.performance_mode),
    );

    let (debounce_widget, debounce) = spin(current.debounce_ms.into(), 0.0, 50.0, 1.0, 0, "ms");
    {
        let state = state.clone();
        let slot = slot.clone();
        debounce.connect_value_changed(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.debounce_ms = input.value() as u8
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Debounce",
        &debounce_widget,
        declared.is_some_and(|nix| nix.debounce_ms != current.debounce_ms),
    );
    row = section(&grid, row, "Power & lighting");

    let (sleep_widget, sleep) = spin(current.sleep_minutes.into(), 0.0, 255.0, 1.0, 0, "min");
    sleep.set_tooltip_text(Some("0 never sleeps"));
    {
        let state = state.clone();
        let slot = slot.clone();
        sleep.connect_value_changed(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.sleep_minutes = input.value() as u8
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Sleep after",
        &sleep_widget,
        declared.is_some_and(|nix| nix.sleep_minutes != current.sleep_minutes),
    );
    let lighting = gtk::CheckButton::new();
    lighting.set_active(current.lighting);
    {
        let state = state.clone();
        let slot = slot.clone();
        lighting.connect_toggled(move |input| {
            mutate_mouse(&state, index, |settings| {
                settings.lighting = input.is_active()
            });
            changed(&state, &slot);
        });
    }
    add_row(
        &grid,
        row,
        "Lighting",
        &lighting,
        declared.is_some_and(|nix| nix.lighting != current.lighting),
    );
    grid
}

fn button_assignments(
    index: usize,
    current: &mchose::Buttons,
    declared: Option<&mchose::Buttons>,
    state: &Shared,
    slot: &UiSlot,
) -> gtk::Box {
    let root = gtk::Box::new(Orientation::Vertical, 10);
    root.set_size_request(370, -1);
    let title = gtk::Label::new(Some("Button assignments"));
    title.add_css_class("heading");
    title.set_halign(Align::Start);
    root.append(&title);
    let hint = gtk::Label::new(Some(
        "Choose a named action, or enter a key:ctrl+c style binding.",
    ));
    hint.add_css_class("dim-label");
    hint.set_wrap(true);
    hint.set_halign(Align::Start);
    root.append(&hint);
    let grid = gtk::Grid::builder()
        .column_spacing(10)
        .row_spacing(8)
        .build();
    let names: Vec<String> = mchose_buttons::ACTIONS
        .iter()
        .map(|(name, ..)| (*name).to_string())
        .collect();
    for (button_slot, label) in BUTTON_LABELS.iter().enumerate() {
        let name = gtk::Label::new(Some(label));
        name.set_halign(Align::Start);
        grid.attach(&name, 0, button_slot as i32, 1, 1);
        let entry = gtk::Entry::new();
        entry.set_hexpand(true);
        entry.set_text(current.slots()[button_slot]);
        grid.attach(&entry, 1, button_slot as i32, 1, 1);
        let selected = names
            .iter()
            .position(|name| name == current.slots()[button_slot])
            .unwrap_or(gtk::INVALID_LIST_POSITION as usize);
        let choices = dropdown(&names, selected);
        choices.set_tooltip_text(Some("Named actions"));
        {
            let state = state.clone();
            let slot = slot.clone();
            let entry = entry.clone();
            choices.connect_selected_notify(move |input| {
                let selected = input.selected() as usize;
                if let Some((name, ..)) = mchose_buttons::ACTIONS.get(selected) {
                    entry.set_text(name);
                    mutate_mouse(&state, index, |settings| {
                        *settings.buttons.slots_mut()[button_slot] = (*name).to_string()
                    });
                    changed(&state, &slot);
                }
            });
        }
        grid.attach(&choices, 2, button_slot as i32, 1, 1);
        let set = gtk::Button::with_label("Set");
        {
            let state = state.clone();
            let slot = slot.clone();
            let entry = entry.clone();
            set.connect_clicked(move |_| {
                let value = entry.text().to_string();
                if mchose_buttons::encode(&value, button_slot).is_some() {
                    entry.remove_css_class("error");
                    mutate_mouse(&state, index, |settings| {
                        *settings.buttons.slots_mut()[button_slot] = value
                    });
                    changed(&state, &slot);
                } else {
                    entry.add_css_class("error");
                    entry.set_tooltip_text(Some("Unknown action"));
                }
            });
        }
        grid.attach(&set, 3, button_slot as i32, 1, 1);
        let modified =
            declared.is_some_and(|nix| nix.slots()[button_slot] != current.slots()[button_slot]);
        grid.attach(&marker(modified), 4, button_slot as i32, 1, 1);
    }
    root.append(&grid);
    root
}

fn optional_dropdown<T: Copy + PartialEq + 'static>(
    values: &'static [T],
    labels: Vec<String>,
    current: Option<T>,
    update: impl Fn(T) + 'static,
) -> gtk::Widget {
    let Some(current) = current else {
        return gtk::Label::new(Some("unknown")).upcast();
    };
    let selected = values
        .iter()
        .position(|value| *value == current)
        .unwrap_or(0);
    let input = dropdown(&labels, selected);
    input.connect_selected_notify(move |input| update(values[input.selected() as usize]));
    input.upcast()
}

fn optional_spin(
    value: Option<f64>,
    min: f64,
    max: f64,
    step: f64,
    digits: u32,
    suffix: &str,
    update: impl Fn(f64) + 'static,
) -> gtk::Widget {
    let Some(value) = value else {
        return gtk::Label::new(Some("unknown")).upcast();
    };
    let (widget, input) = spin(value, min, max, step, digits, suffix);
    input.connect_value_changed(move |input| update(input.value()));
    widget.upcast()
}

fn differs<T: PartialEq>(declared: Option<&Option<T>>, current: &Option<T>) -> bool {
    declared.is_some_and(|value| value.is_some() && value != current)
}

fn keyboard_settings(
    index: usize,
    model: &'static rongyuan::Model,
    current: &rongyuan::Settings,
    declared: Option<&rongyuan::Settings>,
    state: &Shared,
    slot: &UiSlot,
) -> gtk::Box {
    let root = gtk::Box::new(Orientation::Vertical, 14);
    let grid = gtk::Grid::builder()
        .column_spacing(18)
        .row_spacing(10)
        .hexpand(true)
        .build();
    let mut row = section(&grid, 0, "Performance");

    let rate = optional_dropdown(
        &KB_RATES,
        KB_RATES.iter().map(|value| format!("{value} Hz")).collect(),
        current.polling_rate,
        {
            let state = state.clone();
            let slot = slot.clone();
            move |value| {
                mutate_keyboard(&state, index, |settings| {
                    settings.polling_rate = Some(value)
                });
                changed(&state, &slot);
            }
        },
    );
    row = add_row(
        &grid,
        row,
        "Polling rate",
        &rate,
        differs(declared.map(|nix| &nix.polling_rate), &current.polling_rate),
    );
    let debounce = optional_spin(
        current.debounce_ms.map(f64::from),
        0.0,
        50.0,
        1.0,
        0,
        "ms",
        {
            let state = state.clone();
            let slot = slot.clone();
            move |value| {
                mutate_keyboard(&state, index, |settings| {
                    settings.debounce_ms = Some(value as u8)
                });
                changed(&state, &slot);
            }
        },
    );
    row = add_row(
        &grid,
        row,
        "Debounce",
        &debounce,
        differs(declared.map(|nix| &nix.debounce_ms), &current.debounce_ms),
    );
    row = section(&grid, row, "Lighting");

    let effects: Vec<String> = rongyuan::EFFECTS
        .iter()
        .map(|(name, _)| (*name).to_string())
        .collect();
    let effect_values: Vec<&str> = rongyuan::EFFECTS.iter().map(|(name, _)| *name).collect();
    let effect: gtk::Widget = if let Some(value) = current.lighting.effect.as_deref() {
        let input = dropdown(
            &effects,
            effect_values
                .iter()
                .position(|name| *name == value)
                .unwrap_or(0),
        );
        let state = state.clone();
        let slot = slot.clone();
        input.connect_selected_notify(move |input| {
            let value = rongyuan::EFFECTS[input.selected() as usize].0.to_string();
            mutate_keyboard(&state, index, |settings| {
                settings.lighting.effect = Some(value)
            });
            changed(&state, &slot);
        });
        input.upcast()
    } else {
        gtk::Label::new(Some("unknown")).upcast()
    };
    row = add_row(
        &grid,
        row,
        "Lighting effect",
        &effect,
        differs(
            declared.map(|nix| &nix.lighting.effect),
            &current.lighting.effect,
        ),
    );

    for (name, value, speed) in [
        ("Brightness", current.lighting.brightness, false),
        ("Effect speed", current.lighting.speed, true),
    ] {
        let widget = optional_spin(value.map(f64::from), 0.0, 4.0, 1.0, 0, "", {
            let state = state.clone();
            let slot = slot.clone();
            move |value| {
                mutate_keyboard(&state, index, |settings| {
                    if speed {
                        settings.lighting.speed = Some(value as u8)
                    } else {
                        settings.lighting.brightness = Some(value as u8)
                    }
                });
                changed(&state, &slot);
            }
        });
        let modified = if speed {
            differs(declared.map(|nix| &nix.lighting.speed), &value)
        } else {
            differs(declared.map(|nix| &nix.lighting.brightness), &value)
        };
        row = add_row(&grid, row, name, &widget, modified);
    }

    let rainbow: gtk::Widget = if let Some(value) = current.lighting.rainbow {
        let input = gtk::CheckButton::new();
        input.set_active(value);
        let state = state.clone();
        let slot = slot.clone();
        input.connect_toggled(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.lighting.rainbow = Some(input.is_active())
            });
            changed(&state, &slot);
        });
        input.upcast()
    } else {
        gtk::Label::new(Some("unknown")).upcast()
    };
    row = add_row(
        &grid,
        row,
        "Rainbow",
        &rainbow,
        differs(
            declared.map(|nix| &nix.lighting.rainbow),
            &current.lighting.rainbow,
        ),
    );

    let color: gtk::Widget = if let Some(value) = current.lighting.color.as_deref() {
        let dialog = gtk::ColorDialog::builder()
            .title("Choose a colour")
            .with_alpha(false)
            .build();
        let input = gtk::ColorDialogButton::new(Some(dialog));
        if let Some(rgb) = rongyuan::parse_color(value) {
            input.set_rgba(&gdk::RGBA::new(
                rgb.r as f32 / 255.0,
                rgb.g as f32 / 255.0,
                rgb.b as f32 / 255.0,
                1.0,
            ));
        }
        let state = state.clone();
        let slot = slot.clone();
        input.connect_rgba_notify(move |input| {
            let color = input.rgba();
            let channel = |value: f32| (value * 255.0).round() as u8;
            let value = format!(
                "#{:02x}{:02x}{:02x}",
                channel(color.red()),
                channel(color.green()),
                channel(color.blue())
            );
            mutate_keyboard(&state, index, |settings| {
                settings.lighting.color = Some(value)
            });
            changed(&state, &slot);
        });
        input.upcast()
    } else {
        gtk::Label::new(Some("unknown")).upcast()
    };
    row = add_row(
        &grid,
        row,
        "Colour",
        &color,
        differs(
            declared.map(|nix| &nix.lighting.color),
            &current.lighting.color,
        ),
    );
    row = section(&grid, row, "Key behaviour");

    const LAYERS: [u8; 2] = [0, 1];
    let layer = optional_dropdown(&LAYERS, vec!["0".into(), "1".into()], current.fn_layer, {
        let state = state.clone();
        let slot = slot.clone();
        move |value| {
            mutate_keyboard(&state, index, |settings| settings.fn_layer = Some(value));
            changed(&state, &slot);
        }
    });
    row = add_row(
        &grid,
        row,
        "Fn layer",
        &layer,
        differs(declared.map(|nix| &nix.fn_layer), &current.fn_layer),
    );
    let anti: gtk::Widget = if let Some(value) = current.anti_mistouch {
        let input = gtk::CheckButton::new();
        input.set_active(value);
        let state = state.clone();
        let slot = slot.clone();
        input.connect_toggled(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.anti_mistouch = Some(input.is_active())
            });
            changed(&state, &slot);
        });
        input.upcast()
    } else {
        gtk::Label::new(Some("unknown")).upcast()
    };
    row = add_row(
        &grid,
        row,
        "Anti-mistouch",
        &anti,
        differs(
            declared.map(|nix| &nix.anti_mistouch),
            &current.anti_mistouch,
        ),
    );

    const STABILITY: [u16; 6] = [0, 25, 50, 75, 100, 125];
    let stability = optional_dropdown(
        &STABILITY,
        STABILITY
            .iter()
            .map(|value| format!("{value} ms"))
            .collect(),
        current.rt_stability_ms,
        {
            let state = state.clone();
            let slot = slot.clone();
            move |value| {
                mutate_keyboard(&state, index, |settings| {
                    settings.rt_stability_ms = Some(value)
                });
                changed(&state, &slot);
            }
        },
    );
    row = add_row(
        &grid,
        row,
        "RT stability",
        &stability,
        differs(
            declared.map(|nix| &nix.rt_stability_ms),
            &current.rt_stability_ms,
        ),
    );
    let swap = gtk::CheckButton::new();
    swap.set_active(current.wasd_swap);
    {
        let state = state.clone();
        let slot = slot.clone();
        swap.connect_toggled(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.wasd_swap = input.is_active()
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "WASD/arrow swap",
        &swap,
        declared.is_some_and(|nix| nix.wasd_swap != current.wasd_swap),
    );
    row = section(&grid, row, "Actuation & rapid trigger");

    let (actuation_widget, actuation) = spin(current.actuation, 0.1, 3.3, 0.01, 2, "mm");
    {
        let state = state.clone();
        let slot = slot.clone();
        actuation.connect_value_changed(move |input| {
            mutate_keyboard(&state, index, |settings| settings.actuation = input.value());
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Actuation",
        &actuation_widget,
        declared.is_some_and(|nix| nix.actuation != current.actuation),
    );

    let release_row = gtk::Box::new(Orientation::Horizontal, 8);
    let follows = gtk::CheckButton::with_label("same as actuation");
    follows.set_active(current.release.is_none());
    release_row.append(&follows);
    if let Some(value) = current.release {
        let (widget, input) = spin(value, 0.1, 3.3, 0.01, 2, "mm");
        let state = state.clone();
        let slot = slot.clone();
        input.connect_value_changed(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.release = Some(input.value())
            });
            changed(&state, &slot);
        });
        release_row.append(&widget);
    }
    {
        let state = state.clone();
        let slot = slot.clone();
        follows.connect_toggled(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.release = (!input.is_active()).then_some(settings.actuation)
            });
            rebuild_devices(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Release",
        &release_row,
        declared.is_some_and(|nix| nix.release != current.release),
    );

    let rt = gtk::CheckButton::new();
    rt.set_active(current.rapid_trigger.enable);
    {
        let state = state.clone();
        let slot = slot.clone();
        rt.connect_toggled(move |input| {
            mutate_keyboard(&state, index, |settings| {
                settings.rapid_trigger.enable = input.is_active()
            });
            changed(&state, &slot);
        });
    }
    row = add_row(
        &grid,
        row,
        "Rapid trigger",
        &rt,
        declared.is_some_and(|nix| nix.rapid_trigger.enable != current.rapid_trigger.enable),
    );
    for (name, value, press) in [
        ("RT press sensitivity", current.rapid_trigger.press, true),
        (
            "RT release sensitivity",
            current.rapid_trigger.release,
            false,
        ),
    ] {
        let widget = optional_spin(value, 0.01, 2.0, 0.01, 2, "mm", {
            let state = state.clone();
            let slot = slot.clone();
            move |value| {
                mutate_keyboard(&state, index, |settings| {
                    if press {
                        settings.rapid_trigger.press = Some(value)
                    } else {
                        settings.rapid_trigger.release = Some(value)
                    }
                });
                changed(&state, &slot);
            }
        });
        let modified = declared.is_some_and(|nix| {
            if press {
                differs(Some(&nix.rapid_trigger.press), &value)
            } else {
                differs(Some(&nix.rapid_trigger.release), &value)
            }
        });
        row = add_row(&grid, row, name, &widget, modified);
    }
    let deadzone = optional_spin(current.bottom_deadzone, 0.0, 1.0, 0.01, 2, "mm", {
        let state = state.clone();
        let slot = slot.clone();
        move |value| {
            mutate_keyboard(&state, index, |settings| {
                settings.bottom_deadzone = Some(value)
            });
            changed(&state, &slot);
        }
    });
    add_row(
        &grid,
        row,
        "Bottom dead zone",
        &deadzone,
        differs(
            declared.map(|nix| &nix.bottom_deadzone),
            &current.bottom_deadzone,
        ),
    );
    root.append(&grid);

    let keys_title = gtk::Label::new(Some("Per-key actuation"));
    keys_title.add_css_class("heading");
    keys_title.set_halign(Align::Start);
    root.append(&keys_title);
    let keys = gtk::Grid::builder()
        .column_spacing(10)
        .row_spacing(8)
        .build();
    for (key_row, (name, override_)) in current.keys.iter().enumerate() {
        keys.attach(&gtk::Label::new(Some(name)), 0, key_row as i32, 1, 1);
        if let Some(value) = override_.actuation {
            let (widget, input) = spin(value, 0.1, 3.3, 0.01, 2, "mm");
            let name = name.clone();
            let state = state.clone();
            let slot = slot.clone();
            input.connect_value_changed(move |input| {
                mutate_keyboard(&state, index, |settings| {
                    if let Some(value) = settings.keys.get_mut(&name) {
                        value.actuation = Some(input.value());
                    }
                });
                changed(&state, &slot);
            });
            keys.attach(&widget, 1, key_row as i32, 1, 1);
        }
        let remove = gtk::Button::with_label("Remove");
        let name = name.clone();
        let state = state.clone();
        let slot = slot.clone();
        remove.connect_clicked(move |_| {
            mutate_keyboard(&state, index, |settings| {
                settings.keys.remove(&name);
            });
            rebuild_devices(&state, &slot);
        });
        keys.attach(&remove, 2, key_row as i32, 1, 1);
    }
    root.append(&keys);
    let available: Vec<String> = model
        .key_names()
        .filter(|name| !current.keys.contains_key(*name))
        .map(str::to_string)
        .collect();
    if !available.is_empty() {
        let add_row = gtk::Box::new(Orientation::Horizontal, 8);
        let choices = dropdown(&available, 0);
        add_row.append(&choices);
        let add = gtk::Button::with_label("Add key");
        let state = state.clone();
        let slot = slot.clone();
        add.connect_clicked(move |_| {
            let name = available[choices.selected() as usize].clone();
            mutate_keyboard(&state, index, |settings| {
                settings.keys.insert(
                    name,
                    rongyuan::KeyOverride {
                        actuation: Some(settings.actuation),
                        release: None,
                    },
                );
            });
            rebuild_devices(&state, &slot);
        });
        add_row.append(&add);
        root.append(&add_row);
    }
    root
}

fn device_card(
    index: usize,
    device: &Device,
    declared: Option<&Config>,
    state: &Shared,
    slot: &UiSlot,
) -> (gtk::Frame, Option<DeviceActions>) {
    let frame = gtk::Frame::new(None);
    frame.set_margin_bottom(14);
    let card = gtk::Box::new(Orientation::Vertical, 14);
    card.set_margin_top(18);
    card.set_margin_bottom(18);
    card.set_margin_start(18);
    card.set_margin_end(18);
    match device {
        Device::Unavailable { node, why } => {
            let title = gtk::Label::new(Some(&format!(
                "{} ({:04x}:{:04x})",
                node.dev.display(),
                node.vid,
                node.pid
            )));
            title.add_css_class("title-2");
            title.set_halign(Align::Start);
            card.append(&title);
            let error = gtk::Label::new(Some(why));
            error.add_css_class("error");
            error.set_halign(Align::Start);
            error.set_wrap(true);
            card.append(&error);
            frame.set_child(Some(&card));
            return (frame, None);
        }
        Device::Mouse {
            id, wired, edit, ..
        } => {
            let title = gtk::Label::new(Some("MCHOSE M7 Ultra"));
            title.add_css_class("title-2");
            title.set_halign(Align::Start);
            card.append(&title);
            let charging = if id.charging { ", charging" } else { "" };
            let details = gtk::Label::new(Some(&format!(
                "Connected via {} · Battery {}%{charging}",
                if *wired { "cable" } else { "dongle" },
                id.battery
            )));
            details.add_css_class("dim-label");
            details.set_halign(Align::Start);
            card.append(&details);
            let flow = gtk::FlowBox::builder()
                .column_spacing(30)
                .row_spacing(18)
                .homogeneous(true)
                .selection_mode(gtk::SelectionMode::None)
                .max_children_per_line(2)
                .min_children_per_line(1)
                .build();
            let nix = declared.and_then(|config| config.mchose_m7_ultra.as_ref());
            let settings = mouse_settings(index, edit, nix, *wired, state, slot);
            settings.set_size_request(470, -1);
            flow.insert(&settings, -1);
            flow.insert(
                &button_assignments(
                    index,
                    &edit.buttons,
                    nix.map(|settings| &settings.buttons),
                    state,
                    slot,
                ),
                -1,
            );
            card.append(&flow);
        }
        Device::Keyboard { model, edit, .. } => {
            let title = gtk::Label::new(Some(model.name));
            title.add_css_class("title-2");
            title.set_halign(Align::Start);
            card.append(&title);
            card.append(&keyboard_settings(
                index,
                model,
                edit,
                declared.and_then(|config| config.boyi_h60pro.as_ref()),
                state,
                slot,
            ));
        }
    }

    let bar = gtk::ActionBar::new();
    let apply = gtk::Button::with_label("Apply changes");
    apply.add_css_class("suggested-action");
    let revert = gtk::Button::with_label("Revert");
    let reset = gtk::Button::with_label("Reset to Nix");
    reset.set_tooltip_text(Some("Apply the declared Nix configuration now"));
    let copy = gtk::Button::with_label("Copy as Nix");
    bar.pack_start(&apply);
    bar.pack_start(&revert);
    bar.pack_start(&reset);
    bar.pack_end(&copy);
    card.append(&bar);
    {
        let state = state.clone();
        let slot = slot.clone();
        apply.connect_clicked(move |_| {
            state.borrow_mut().apply(index);
            if let Some(ui) = slot.borrow().as_ref() {
                refresh(&state, ui);
            }
        });
    }
    {
        let state = state.clone();
        let slot = slot.clone();
        revert.connect_clicked(move |_| {
            match state.borrow_mut().devices.get_mut(index) {
                Some(Device::Mouse { read, edit, .. }) => *edit = read.clone(),
                Some(Device::Keyboard { read, edit, .. }) => *edit = read.clone(),
                _ => return,
            }
            rebuild_devices(&state, &slot);
        });
    }
    {
        let state = state.clone();
        let slot = slot.clone();
        reset.connect_clicked(move |_| {
            state.borrow_mut().reset_to_nix(index);
            if let Some(ui) = slot.borrow().as_ref() {
                refresh(&state, ui);
            }
        });
    }
    {
        let state = state.clone();
        let slot = slot.clone();
        copy.connect_clicked(move |_| {
            let text = match state.borrow().devices.get(index) {
                Some(Device::Mouse { edit, .. }) => mchose::to_nix(edit, true),
                Some(Device::Keyboard {
                    edit, precision, ..
                }) => rongyuan::to_nix(edit, *precision),
                _ => return,
            };
            clipboard(text);
            state.borrow_mut().status = "Copied as Nix".into();
            if let Some(ui) = slot.borrow().as_ref() {
                refresh(&state, ui);
            }
        });
    }
    frame.set_child(Some(&card));
    (
        frame,
        Some(DeviceActions {
            index,
            apply,
            revert,
            reset,
        }),
    )
}

fn rebuild_devices(state: &Shared, slot: &UiSlot) {
    let Some(ui) = slot.borrow().as_ref().cloned() else {
        return;
    };
    clear_box(&ui.devices);
    ui.actions.borrow_mut().clear();
    let snapshot = state.borrow().devices.clone();
    if snapshot.is_empty() && state.borrow().job.is_none() {
        let empty = gtk::Box::new(Orientation::Vertical, 8);
        empty.set_margin_top(36);
        let title = gtk::Label::new(Some("Connect a supported mouse or keyboard"));
        title.add_css_class("title-3");
        empty.append(&title);
        let hint = gtk::Label::new(Some("Wake the device, then select Reload to try again."));
        hint.add_css_class("dim-label");
        empty.append(&hint);
        ui.devices.append(&empty);
    }
    let declared = state.borrow().declared.clone();
    for (index, device) in snapshot.iter().enumerate() {
        let (card, actions) = device_card(index, device, declared.as_ref(), state, slot);
        ui.devices.append(&card);
        if let Some(actions) = actions {
            ui.actions.borrow_mut().push(actions);
        }
    }
    let current = state.borrow();
    if let Some(error) = &current.config_error {
        let label = gtk::Label::new(Some(&format!("Nix config not loaded: {error}")));
        label.add_css_class("error");
        label.set_wrap(true);
        label.set_halign(Align::Start);
        ui.devices.prepend(&label);
    }
    if !current.log.is_empty() {
        let log = gtk::Expander::builder()
            .label("Changes applied")
            .expanded(false)
            .build();
        let lines = gtk::Label::new(Some(&current.log.join("\n")));
        lines.set_halign(Align::Start);
        lines.set_selectable(true);
        log.set_child(Some(&lines));
        ui.devices.append(&log);
    }
    drop(current);
    refresh(state, &ui);
}

fn build_ui(application: &gtk::Application, state: &Shared, slot: &UiSlot) -> Ui {
    let window = gtk::ApplicationWindow::builder()
        .application(application)
        .title("Peripherals")
        .default_width(920)
        .default_height(900)
        .build();
    window.set_size_request(520, 420);
    let header = gtk::HeaderBar::new();
    let title = gtk::Label::new(Some("Peripherals"));
    title.add_css_class("title");
    header.set_title_widget(Some(&title));
    let status = gtk::Label::new(None);
    status.add_css_class("dim-label");
    header.pack_start(&status);
    let spinner = gtk::Spinner::new();
    header.pack_end(&spinner);
    let reload = gtk::Button::with_label("Reload");
    header.pack_end(&reload);
    window.set_titlebar(Some(&header));

    let root = gtk::Box::new(Orientation::Vertical, 0);
    let notice = gtk::Label::new(Some(
        "Temporary settings · Reconnecting restores your Nix configuration.",
    ));
    notice.add_css_class("dim-label");
    notice.set_halign(Align::Start);
    notice.set_margin_top(12);
    notice.set_margin_start(18);
    notice.set_margin_end(18);
    root.append(&notice);
    let devices = gtk::Box::new(Orientation::Vertical, 0);
    devices.set_margin_top(14);
    devices.set_margin_bottom(18);
    devices.set_margin_start(18);
    devices.set_margin_end(18);
    let scroll = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .child(&devices)
        .build();
    root.append(&scroll);
    window.set_child(Some(&root));
    let ui = Ui {
        window,
        status,
        spinner,
        reload,
        devices,
        actions: Rc::new(RefCell::new(Vec::new())),
    };
    {
        let state = state.clone();
        let slot = slot.clone();
        ui.reload.connect_clicked(move |_| {
            state.borrow_mut().reload();
            if let Some(ui) = slot.borrow().as_ref() {
                refresh(&state, ui);
            }
        });
    }
    ui
}

fn parse_args() -> (Option<PathBuf>, Option<String>) {
    let mut args = std::env::args().skip(1);
    let (mut path, mut only) = (None, None);
    while let Some(arg) = args.next() {
        if arg == "--config" {
            path = args.next().map(PathBuf::from);
        } else if DEVICE_NAMES.contains(&arg.as_str()) {
            only = Some(arg);
        } else {
            eprintln!(
                "usage: periph-gui [--config <path>] [{}]",
                DEVICE_NAMES.join("|")
            );
            std::process::exit(2);
        }
    }
    let default = || {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))?;
        Some(base.join("periph/config.json")).filter(|file| file.exists())
    };
    (path.or_else(default), only)
}

fn main() -> glib::ExitCode {
    let (path, only) = parse_args();
    let (declared, config_error) = match path.as_deref().map(config::load) {
        Some(Ok(config)) => (Some(config), None),
        Some(Err(error)) => (None, Some(error)),
        None => (None, None),
    };
    let application_id = only.as_ref().map_or_else(
        || "dev.periph.Settings".to_string(),
        |device| format!("dev.periph.{device}"),
    );
    let application = gtk::Application::builder()
        .application_id(&application_id)
        .build();
    application.connect_activate(move |application| {
        let state = Rc::new(RefCell::new(State {
            declared: declared.clone(),
            config_error: config_error.clone(),
            only: only.clone(),
            devices: Vec::new(),
            job: None,
            status: String::new(),
            log: Vec::new(),
        }));
        let slot = Rc::new(RefCell::new(None));
        let ui = build_ui(application, &state, &slot);
        *slot.borrow_mut() = Some(ui.clone());
        state.borrow_mut().reload();
        refresh(&state, &ui);
        let state_poll = state.clone();
        let slot_poll = slot.clone();
        glib::timeout_add_local(Duration::from_millis(50), move || {
            if state_poll.borrow_mut().poll() {
                rebuild_devices(&state_poll, &slot_poll);
            }
            ControlFlow::Continue
        });
        ui.window.present();
    });
    application.run()
}
