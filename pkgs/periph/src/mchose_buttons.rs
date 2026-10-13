//! MCHOSE button bindings. Each of the six slots in the config block holds
//! `index << 4 | type` and a 24-bit value, big-endian; types and values come from
//! M HUB's binding tables.

/// Slots in config-block order, from M HUB's template code. Only `dpi` has been
/// checked against a mouse.
pub const SLOTS: [&str; 6] = ["left", "middle", "right", "forward", "back", "dpi"];

/// Named actions: (name, type, value). Type 0 keeps the button's own function.
pub const ACTIONS: [(&str, u8, [u8; 3]); 21] = [
    ("default", 0, [0x00, 0x00, 0x00]),
    ("disabled", 9, [0xFF, 0xFF, 0xFF]),
    ("left-click", 1, [0x01, 0x00, 0x00]),
    ("right-click", 1, [0x02, 0x00, 0x00]),
    ("middle-click", 1, [0x04, 0x00, 0x00]),
    ("back", 1, [0x08, 0x00, 0x00]),
    ("forward", 1, [0x10, 0x00, 0x00]),
    ("scroll-up", 1, [0x00, 0x02, 0x00]),
    ("scroll-down", 1, [0x00, 0xFE, 0x00]),
    ("dpi-cycle", 5, [0x01, 0x00, 0x00]),
    ("dpi-up", 5, [0x02, 0x00, 0x00]),
    ("dpi-down", 5, [0x03, 0x00, 0x00]),
    ("volume-up", 3, [0xE9, 0x00, 0x00]),
    ("volume-down", 3, [0xEA, 0x00, 0x00]),
    ("mute", 3, [0xE2, 0x00, 0x00]),
    ("play-pause", 3, [0xCD, 0x00, 0x00]),
    ("next-track", 3, [0xB5, 0x00, 0x00]),
    ("previous-track", 3, [0xB6, 0x00, 0x00]),
    ("stop", 3, [0xB7, 0x00, 0x00]),
    ("brightness-up", 8, [0x0C, 0x6F, 0x00]),
    ("brightness-down", 8, [0x0C, 0x70, 0x00]),
];

/// Keyboard keys (type 2) carry a HID modifier byte and a HID usage.
const MODIFIERS: [(&str, u8); 4] = [("ctrl", 0x01), ("shift", 0x02), ("alt", 0x04), ("super", 0x08)];
const KEY_TYPE: u8 = 2;

const NAMED_KEYS: [(&str, u8); 38] = [
    ("enter", 0x28),
    ("esc", 0x29),
    ("backspace", 0x2A),
    ("tab", 0x2B),
    ("space", 0x2C),
    ("minus", 0x2D),
    ("equal", 0x2E),
    ("leftbracket", 0x2F),
    ("rightbracket", 0x30),
    ("backslash", 0x31),
    ("semicolon", 0x33),
    ("apostrophe", 0x34),
    ("grave", 0x35),
    ("comma", 0x36),
    ("period", 0x37),
    ("slash", 0x38),
    ("capslock", 0x39),
    ("printscreen", 0x46),
    ("scrolllock", 0x47),
    ("pause", 0x48),
    ("insert", 0x49),
    ("home", 0x4A),
    ("pageup", 0x4B),
    ("delete", 0x4C),
    ("end", 0x4D),
    ("pagedown", 0x4E),
    ("right", 0x4F),
    ("left", 0x50),
    ("down", 0x51),
    ("up", 0x52),
    ("menu", 0x65),
    ("leftctrl", 0xE0),
    ("leftshift", 0xE1),
    ("leftalt", 0xE2),
    ("leftsuper", 0xE3),
    ("rightctrl", 0xE4),
    ("rightshift", 0xE5),
    ("rightalt", 0xE6),
];

/// Every key name: a-z, 0-9, f1-f24 and the named keys.
pub fn key_names() -> Vec<(String, u8)> {
    let letters = (b'a'..=b'z').map(|c| ((c as char).to_string(), c - b'a' + 0x04));
    let digits = (1..=10u8).map(|i| ((i % 10).to_string(), 0x1D + i));
    let f1_12 = (1..=12u8).map(|i| (format!("f{i}"), 0x39 + i));
    let f13_24 = (13..=24u8).map(|i| (format!("f{i}"), 0x5B + i));
    let named = NAMED_KEYS.iter().map(|&(n, u)| (n.to_string(), u));
    letters.chain(digits).chain(f1_12).chain(f13_24).chain(named).collect()
}

/// "ctrl+shift+c" -> [modifiers, usage, 0].
fn parse_combo(combo: &str) -> Option<[u8; 3]> {
    let mut parts: Vec<&str> = combo.split('+').collect();
    let key = parts.pop()?;
    let mut modifiers = 0;
    for m in parts {
        modifiers |= MODIFIERS.iter().find(|(n, _)| *n == m)?.1;
    }
    let usage = key_names().into_iter().find(|(n, _)| n == key)?.1;
    Some([modifiers, usage, 0])
}

fn combo_name(value: [u8; 3]) -> Option<String> {
    let [modifiers, usage, rest] = value;
    let key = key_names().into_iter().find(|&(_, u)| u == usage)?.0;
    if rest != 0 || modifiers & !0x0F != 0 {
        return None;
    }
    let mut parts: Vec<&str> = MODIFIERS.iter().filter(|(_, bit)| modifiers & bit != 0).map(|(n, _)| *n).collect();
    parts.push(&key);
    Some(parts.join("+"))
}

/// "raw:8:070106" -> (8, [07, 01, 06]): any type and value, for bindings without a name.
fn parse_raw(raw: &str) -> Option<(u8, [u8; 3])> {
    let (kind, hex) = raw.split_once(':')?;
    let kind: u8 = kind.parse().ok().filter(|k| *k < 16)?;
    if hex.len() != 6 {
        return None;
    }
    let v = u32::from_str_radix(hex, 16).ok()?;
    Some((kind, [(v >> 16) as u8, (v >> 8) as u8, v as u8]))
}

/// The four config-block bytes for `action` in `slot`.
pub fn encode(action: &str, slot: usize) -> Option<[u8; 4]> {
    let (kind, value) = if let Some(&(_, kind, value)) = ACTIONS.iter().find(|(n, ..)| *n == action) {
        (kind, value)
    } else if let Some(combo) = action.strip_prefix("key:") {
        (KEY_TYPE, parse_combo(combo)?)
    } else {
        parse_raw(action.strip_prefix("raw:")?)?
    };
    Some([(slot as u8) << 4 | kind, value[0], value[1], value[2]])
}

/// The action a slot's bytes hold, as `encode` takes it back.
pub fn decode(bytes: [u8; 4]) -> String {
    let kind = bytes[0] & 0x0F;
    let value = [bytes[1], bytes[2], bytes[3]];
    if let Some((name, ..)) = ACTIONS.iter().find(|(_, k, v)| *k == kind && *v == value) {
        return name.to_string();
    }
    if kind == KEY_TYPE {
        if let Some(combo) = combo_name(value) {
            return format!("key:{combo}");
        }
    }
    format!("raw:{kind}:{:02x}{:02x}{:02x}", value[0], value[1], value[2])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip() {
        for (name, ..) in ACTIONS {
            assert_eq!(decode(encode(name, 3).unwrap()), name);
        }
        assert_eq!(encode("disabled", 5), Some([0x59, 0xFF, 0xFF, 0xFF]), "the binding verified on an M7 Ultra");
        assert_eq!(encode("default", 5), Some([0x50, 0x00, 0x00, 0x00]));
    }

    #[test]
    fn key_combos_match_m_hub() {
        // Values M HUB itself sends.
        assert_eq!(encode("key:ctrl+c", 0), Some([0x02, 0x01, 0x06, 0x00]));
        assert_eq!(encode("key:alt+left", 0), Some([0x02, 0x04, 0x50, 0x00]));
        assert_eq!(encode("key:super+tab", 0), Some([0x02, 0x08, 0x2B, 0x00]));
        assert_eq!(encode("key:1", 0), Some([0x02, 0x00, 0x1E, 0x00]));
        assert_eq!(encode("key:0", 0), Some([0x02, 0x00, 0x27, 0x00]));
        assert_eq!(encode("key:f12", 0), Some([0x02, 0x00, 0x45, 0x00]));
        assert_eq!(encode("key:f13", 0), Some([0x02, 0x00, 0x68, 0x00]));
        assert_eq!(decode([0x32, 0x03, 0x04, 0x00]), "key:ctrl+shift+a");
    }

    #[test]
    fn unknown_bindings_survive_as_raw() {
        let copy = [0x48, 0x07, 0x01, 0x06];
        assert_eq!(decode(copy), "raw:8:070106");
        assert_eq!(encode("raw:8:070106", 4), Some(copy));
        assert_eq!(encode("key:hyper+a", 0), None);
        assert_eq!(encode("teleport", 0), None);
    }
}
