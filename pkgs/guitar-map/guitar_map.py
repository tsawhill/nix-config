#!/usr/bin/env python3
"""Interactive raw SDL2 joystick to GameController mapping, without root access."""
import argparse
from collections import namedtuple
import ctypes as C
import ctypes.util
import curses
import json
import os
from pathlib import Path
import re
import sys

# Guitar convention: frets A/B/Y/X/LB, strum D-pad, whammy RX, tilt RY.
CONTROLS = [
    ("a", "Green fret / A"), ("b", "Red fret / B"),
    ("y", "Yellow fret / Y"), ("x", "Blue fret / X"),
    ("leftshoulder", "Orange fret / LB"),
    ("dpup", "Strum up / D-pad up"), ("dpdown", "Strum down / D-pad down"),
    ("back", "Select / Back"), ("start", "Start"),
    ("rightx", "Whammy: move fully from rest"),
    ("righty", "Tilt: raise neck from playing position"),
    ("dpleft", "D-pad left"), ("dpright", "D-pad right"),
    ("rightshoulder", "RB / extra shoulder"), ("guide", "Guide / Home"),
    ("leftstick", "Left stick click"), ("rightstick", "Right stick click"),
    ("lefttrigger", "Left trigger"), ("righttrigger", "Right trigger"),
    ("leftx", "Left stick: fully RIGHT"), ("lefty", "Left stick: fully DOWN"),
    ("misc1", "Misc / Share"), ("paddle1", "Paddle 1"),
    ("paddle2", "Paddle 2"), ("paddle3", "Paddle 3"),
    ("paddle4", "Paddle 4"), ("touchpad", "Touchpad click"),
]
AXES = ["leftx", "lefty", "rightx", "righty", "lefttrigger", "righttrigger"]
BUTTONS = ["a", "b", "x", "y", "back", "guide", "start", "leftstick",
           "rightstick", "leftshoulder", "rightshoulder", "dpup", "dpdown",
           "dpleft", "dpright", "misc1", "paddle1", "paddle2", "paddle3",
           "paddle4", "touchpad"]


# Wine's hidraw backend passes the device's own report descriptor through to
# dinput, which assigns fixed DIJOYSTATE2 members per HID usage and fills
# rgbButtons in declaration order. SDL instead numbers buttons by evdev BTN_*
# code, so the two never have to agree -- hence measuring both.
HID_DESKTOP_PAGE = 0x01
HID_BUTTON_PAGE = 0x09
HID_HAT_USAGE = 0x39
HID_AXIS_MEMBERS = {0x30: "lX", 0x31: "lY", 0x32: "lZ", 0x33: "lRx", 0x34: "lRy",
                    0x35: "lRz", 0x36: "rglSlider[0]", 0x37: "rglSlider[1]"}

HidField = namedtuple("HidField", "report_id offset size page usage logical_min logical_max")
DiMember = namedtuple("DiMember", "kind name index")


class HidUnavailable(Exception):
    """Raw HID is unreadable; SDL capture still works, DirectInput cannot be measured."""


class GUID(C.Structure):
    _fields_ = [("data", C.c_uint8 * 16)]


class SDL:
    def __init__(self):
        library = os.environ.get("GUITAR_MAP_SDL_LIBRARY") or ctypes.util.find_library("SDL2")
        if not library:
            raise RuntimeError("SDL2 not found. Run the Nix-packaged guitar-map command.")
        self.lib = C.CDLL(library)
        specs = {
            "Init": (C.c_int, [C.c_uint32]), "Quit": (None, []),
            "GetError": (C.c_char_p, []),
            "PumpEvents": (None, []), "NumJoysticks": (C.c_int, []),
            "FlushEvents": (None, [C.c_uint32, C.c_uint32]),
            "JoystickNameForIndex": (C.c_char_p, [C.c_int]),
            "JoystickPathForIndex": (C.c_char_p, [C.c_int]),
            "JoystickOpen": (C.c_void_p, [C.c_int]),
            "JoystickClose": (None, [C.c_void_p]),
            "JoystickGetAttached": (C.c_int, [C.c_void_p]),
            "JoystickGetGUID": (GUID, [C.c_void_p]),
            "JoystickInstanceID": (C.c_int32, [C.c_void_p]),
            "JoystickGetDeviceInstanceID": (C.c_int32, [C.c_int]),
            "JoystickGetSerial": (C.c_char_p, [C.c_void_p]),
            "JoystickGetVendor": (C.c_uint16, [C.c_void_p]),
            "JoystickGetProduct": (C.c_uint16, [C.c_void_p]),
            "JoystickNumAxes": (C.c_int, [C.c_void_p]),
            "JoystickNumButtons": (C.c_int, [C.c_void_p]),
            "JoystickNumHats": (C.c_int, [C.c_void_p]),
            "JoystickGetAxis": (C.c_int16, [C.c_void_p, C.c_int]),
            "JoystickGetButton": (C.c_uint8, [C.c_void_p, C.c_int]),
            "JoystickGetHat": (C.c_uint8, [C.c_void_p, C.c_int]),
            "GameControllerAddMapping": (C.c_int, [C.c_char_p]),
            "GameControllerOpen": (C.c_void_p, [C.c_int]),
            "GameControllerClose": (None, [C.c_void_p]),
            "GameControllerGetJoystick": (C.c_void_p, [C.c_void_p]),
            "GameControllerGetAxis": (C.c_int16, [C.c_void_p, C.c_int]),
            "GameControllerGetButton": (C.c_uint8, [C.c_void_p, C.c_int]),
        }
        for name, (result, args) in specs.items():
            fn = getattr(self.lib, "SDL_" + name)
            fn.restype, fn.argtypes = result, args
            setattr(self, name, fn)
        if self.Init(0x2000 | 0x200):
            raise RuntimeError(self.error())

    def error(self):
        return self.GetError().decode(errors="replace")

    def snapshot(self, joy):
        self.PumpEvents()
        self.FlushEvents(0, 0xFFFF)
        if not self.JoystickGetAttached(joy):
            raise RuntimeError("Controller disconnected. Reconnect it and restart guitar-map.")
        return tuple(tuple(getter(joy, i) for i in range(count(joy))) for getter, count in [
            (self.JoystickGetButton, self.JoystickNumButtons),
            (self.JoystickGetHat, self.JoystickNumHats),
            (self.JoystickGetAxis, self.JoystickNumAxes),
        ])

    def device_index(self, instance_id):
        """Resolve a live connection, never reuse a possibly renumbered index."""
        self.PumpEvents()
        for index in range(self.NumJoysticks()):
            if self.JoystickGetDeviceInstanceID(index) == instance_id:
                return index
        raise RuntimeError("Selected controller disconnected. Reconnect it and restart guitar-map.")


def parse_report_descriptor(blob):
    """Input-report fields in HID declaration order, with their bit positions."""
    fields, offsets, stack = [], {}, []
    state = {"page": 0, "size": 0, "count": 0, "id": 0, "min": 0, "max": 0}
    usages, usage_min = [], None
    position = 0
    while position < len(blob):
        prefix = blob[position]
        position += 1
        if prefix == 0xFE:  # long item: payload size, tag, then payload
            if position >= len(blob):
                break
            position += 2 + blob[position]
            continue
        width = (0, 1, 2, 4)[prefix & 0x03]
        if position + width > len(blob):
            break
        value = int.from_bytes(blob[position:position + width], "little")
        position += width
        tag, kind = prefix >> 4, (prefix >> 2) & 0x03
        if kind == 1:
            for item, field in [(0x0, "page"), (0x1, "min"), (0x2, "max"),
                                (0x7, "size"), (0x8, "id"), (0x9, "count")]:
                if tag == item:
                    state[field] = value
            if tag == 0xA:
                stack.append(dict(state))
            elif tag == 0xB and stack:
                state = stack.pop()
        elif kind == 2:
            if tag == 0x0:
                usages.append((value >> 16, value & 0xFFFF) if width == 4 else (state["page"], value))
            elif tag == 0x1:
                usage_min = value
        elif kind == 0:
            if tag == 0x8:  # input
                offset = offsets.get(state["id"], 0)
                variable = bool(value & 0x02)
                for index in range(state["count"]):
                    if not value & 0x01:  # data, not constant padding
                        if usages and variable:
                            page, usage = usages[min(index, len(usages) - 1)]
                        elif usages:
                            page, usage = usages[0]
                        elif usage_min is not None and variable:
                            page, usage = state["page"], usage_min + index
                        else:
                            page, usage = state["page"], usage_min or 0
                        fields.append(HidField(state["id"], offset, state["size"], page,
                                               usage, state["min"], state["max"]))
                    offset += state["size"]
                offsets[state["id"]] = offset
            if tag in (0x8, 0x9, 0xA, 0xB, 0xC):
                usages, usage_min = [], None
    return fields


def dinput_members(fields):
    """DIJOYSTATE2 member each field feeds, in Wine's assignment order."""
    members, buttons, hats = {}, 0, 0
    for field in fields:
        if field.page == HID_BUTTON_PAGE:
            members[field] = DiMember("button", f"rgbButtons[{buttons}]", buttons)
            buttons += 1
        elif field.page != HID_DESKTOP_PAGE:
            continue
        elif field.usage == HID_HAT_USAGE:
            members[field] = DiMember("pov", f"rgdwPOV[{hats}]", hats)
            hats += 1
        elif field.usage in HID_AXIS_MEMBERS:
            members[field] = DiMember("axis", HID_AXIS_MEMBERS[field.usage], None)
    return members


def field_value(payload, field):
    """HID packs report fields little-endian from the start of the report."""
    first, last = field.offset // 8, (field.offset + field.size + 7) // 8
    if len(payload) < last:
        return None
    return (int.from_bytes(payload[first:last], "little") >> (field.offset - first * 8)) \
        & ((1 << field.size) - 1)


def locate_hidraw(evdev_path):
    """Walk from SDL's evdev node up to the owning HID device's hidraw node."""
    name = os.path.basename(evdev_path or "")
    if not re.fullmatch(r"event\d+", name):
        raise HidUnavailable(f"SDL reports no evdev node for this device ({evdev_path or 'none'}).")
    try:
        node = (Path("/sys/class/input") / name).resolve(strict=True)
    except OSError as error:
        raise HidUnavailable(f"Cannot resolve /sys/class/input/{name}: {error}")
    for parent in node.parents:
        nodes = sorted(entry.name for entry in (parent / "hidraw").iterdir()) \
            if (parent / "hidraw").is_dir() else []
        if nodes:
            return Path("/dev") / nodes[0], parent
    raise HidUnavailable("This device exposes no hidraw node, so Wine cannot use its "
                         "hidraw backend and DirectInput sees a synthesised layout.")


class HidRaw:
    """The guitar as Wine's hidraw backend sees it, for the DirectInput table."""

    def __init__(self, evdev_path):
        self.node, sysfs = locate_hidraw(evdev_path)
        try:
            descriptor = (sysfs / "report_descriptor").read_bytes()
        except OSError as error:
            raise HidUnavailable(f"Cannot read {sysfs / 'report_descriptor'}: {error}")
        self.fields = parse_report_descriptor(descriptor)
        self.members = dinput_members(self.fields)
        if not self.members:
            raise HidUnavailable(f"{self.node} declares no buttons or axes DirectInput would expose.")
        self.uses_ids = any(field.report_id for field in self.fields)
        self.latest = {}
        try:
            self.fd = os.open(str(self.node), os.O_RDONLY | os.O_NONBLOCK)
        except PermissionError:
            raise HidUnavailable(
                f"No read access to {self.node}. Give this guitar a udev rule tagging its "
                "hidraw node uaccess (see minihost.nix), then replug it.")
        except OSError as error:
            raise HidUnavailable(f"Cannot open {self.node}: {error}")

    def close(self):
        os.close(self.fd)

    def snapshot(self):
        """Drain pending reports; devices that only report on change keep the last."""
        while True:
            try:
                data = os.read(self.fd, 512)
            except BlockingIOError:
                break
            except OSError as error:
                raise RuntimeError(f"hidraw read failed on {self.node}: {error}")
            if not data:
                break
            self.latest[data[0] if self.uses_ids else 0] = data[1:] if self.uses_ids else data
        values = {}
        for field in self.fields:
            payload = self.latest.get(field.report_id)
            value = None if payload is None else field_value(payload, field)
            if value is not None:
                values[field] = value
        return values


def hid_observe(observed, rest, current, members):
    """Fold a gesture into one record per member, keeping the extremes reached.

    An axis sweep produces a report per intermediate value, so the extremes are
    accumulated rather than each step being offered as its own candidate.
    """
    for field, after in current.items():
        before, member = rest.get(field), members.get(field)
        if member is None or before is None or before == after:
            continue
        if member.kind == "button" and not after:
            continue
        seen = observed.setdefault(member.name, {"member": member, "field": field,
                                                 "rest": before, "low": after, "high": after})
        seen["low"], seen["high"] = min(seen["low"], after), max(seen["high"], after)
    return observed


def describe_observation(seen):
    """Buttons and hats are presence; axes show the travel and declared range."""
    member, field = seen["member"], seen["field"]
    if member.kind != "axis":
        return member.name
    return (f"{member.name} {seen['rest']}->{seen['low']}..{seen['high']} "
            f"of {field.logical_min}..{field.logical_max}")


def profile_entry(seen):
    """The Nix-ready form of one measured control."""
    member, field = seen["member"], seen["field"]
    if member.kind == "axis":
        return {"kind": "axis", "member": member.name,
                "min": field.logical_min, "max": field.logical_max}
    return {"kind": member.kind, "index": member.index}


def entry_label(entry):
    if entry["kind"] == "axis":
        return f"{entry['member']} ({entry['min']}..{entry['max']})"
    return ("rgbButtons" if entry["kind"] == "button" else "rgdwPOV") + f"[{entry['index']}]"


def candidates(rest, current, target, threshold):
    """Require explicit selection when a gesture changes multiple inputs."""
    result = []
    for i, (before, after) in enumerate(zip(rest[0], current[0])):
        if after and not before:
            result.append(f"b{i}")
    for i, (before, after) in enumerate(zip(rest[1], current[1])):
        for mask in (1, 2, 4, 8):
            if after & mask and not before & mask:
                result.append(f"h{i}.{mask}")
    for i, (before, after) in enumerate(zip(rest[2], current[2])):
        if abs(after - before) < threshold:
            continue
        positive = after > before
        if target in AXES and (abs(before) > 24000 or target in ("leftx", "lefty")):
            binding = f"a{i}" + ("" if positive else "~")
        else:
            binding = ("+" if positive else "-") + f"a{i}"
        result.append(binding)
    return result


def mapping_string(guid, name, bindings):
    # Mapping delimiters and terminal control characters cannot occur in names.
    name = re.sub(r"[,\r\n\x00-\x1f\x7f]", " ", name).strip() or "Guitar"
    return f"{guid},{name}," + ",".join(f"{k}:{v}" for k, v in bindings.items()) + ",platform:Linux,"


def nix_quote(value):
    return json.dumps(value, ensure_ascii=False).replace("${", r"\${")


def profile_slug(name):
    """Profile attribute and file name; one per SDL GUID, not per unit."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "guitar"


def nix_attrs(name, entries, indent):
    """Empty sets stay inline, populated ones expand: what nixfmt would produce."""
    pad = " " * indent
    if not entries:
        return f"{pad}{name} = {{ }};\n"
    body = "".join(f"{pad}  {key} = {value};\n" for key, value in entries)
    return f"{pad}{name} = {{\n{body}{pad}}};\n"


def nix_dinput(dinput):
    """Group measured members the way the profile module's submodule expects."""
    ordered = [(target, dinput[target]) for target, _ in CONTROLS if target in dinput]
    indexed = {
        kind: [(target, entry["index"]) for target, entry in ordered if entry["kind"] == kind]
        for kind in ("button", "pov")
    }
    axes = "".join(
        nix_attrs(target, [("member", f'"{entry["member"]}"'), ("min", entry["min"]),
                           ("max", entry["max"])], 10)
        for target, entry in ordered if entry["kind"] == "axis")
    return ('      dinput = {\n'
            + nix_attrs("buttons", indexed["button"], 8)
            + nix_attrs("povs", indexed["pov"], 8)
            + ('        axes = {\n' + axes + '        };\n' if axes else '        axes = { };\n')
            + '      };\n')


def nix_profile(slug, mapping, usb, dinput=None, hid_error=None):
    usb_block = ('      usb = null;\n' if not usb else
                 f'      usb = {{\n        vendor = "{usb[0]}";\n'
                 f'        product = "{usb[1]}";\n      }};\n')
    note = ("      # DirectInput NOT measured: " + re.sub(r"\s+", " ", hid_error) + "\n"
            if hid_error else "")
    return ('{ config, lib, ... }:\n{\n'
            '  config = lib.mkIf config.software.apps.gaming.enable {\n'
            f'    software.apps.gaming.guitarProfiles.{nix_quote(slug)} = {{\n'
            + usb_block
            + f'      sdl = {nix_quote(mapping)};\n'
            + note
            + nix_dinput(dinput or {})
            + '    };\n  };\n}\n')


def draw(screen, lines):
    screen.erase()
    height, width = screen.getmaxyx()
    for row, line in enumerate(lines[:height - 1]):
        try:
            screen.addnstr(row, 0, str(line), max(0, width - 1))
        except curses.error:
            pass
    screen.refresh()


def key(screen):
    k = screen.getch()
    if k in (ord("q"), 27):
        raise KeyboardInterrupt
    return k


def choose(screen, title, choices):
    selected = 0
    while True:
        height = screen.getmaxyx()[0]
        page = max(1, height - 5)
        start = (selected // page) * page
        draw(screen, [title, "Up/down: select   Enter: continue   q: quit", ""] + [
            ("> " if i == selected else "  ") + choices[i]
            for i in range(start, min(len(choices), start + page))])
        k = key(screen)
        if k == curses.KEY_UP:
            selected = (selected - 1) % len(choices)
        elif k == curses.KEY_DOWN:
            selected = (selected + 1) % len(choices)
        elif k in (10, 13):
            return selected


def capture(screen, sdl, hid, joy, target, label, threshold):
    """Record one control as both an SDL binding and a DirectInput member."""
    while True:
        draw(screen, [label, "Release all buttons; leave whammy/sticks at rest.",
                      "Hold the guitar in normal playing position.",
                      "Enter: ready   s: skip/remove mapping   q: quit",
                      "DirectInput: measuring via " + str(hid.node) if hid
                      else "DirectInput: not measured (SDL mapping only)"])
        k = key(screen)
        sdl.snapshot(joy)
        # Keep the raw HID baseline fresh: devices that report only on change
        # would otherwise have no resting report to diff the gesture against.
        if hid:
            hid.snapshot()
        if k == ord("s"):
            return None
        if k not in (10, 13):
            continue
        rest = sdl.snapshot(joy)
        hid_rest = hid.snapshot() if hid else {}
        found, observed = set(), {}
        while True:
            found.update(candidates(rest, sdl.snapshot(joy), target, threshold))
            if hid:
                hid_observe(observed, hid_rest, hid.snapshot(), hid.members)
            draw(screen, [label, "Perform ONLY this input, through its full travel, then release.",
                          "Enter: review detected inputs   r: retry   s: skip   q: quit",
                          "Detected: " + (", ".join(sorted(found)) or "waiting..."),
                          "DirectInput: " + (", ".join(describe_observation(observed[name])
                                                       for name in sorted(observed)) or "waiting...")])
            k = key(screen)
            if k == ord("s"):
                return None
            if k == ord("r"):
                break
            if k in (10, 13) and found:
                options = sorted(found)
                choice = choose(screen, f"{label}: select the raw input", options + ["Retry"])
                if choice == len(options):
                    break
                binding = options[choice]
                if target in AXES and "a" in binding:
                    choice = choose(screen, "Axis range/direction (adjust in preview if needed)", [
                        f"Use detected: {binding}",
                        f"Invert: {binding.rstrip('~') if binding.endswith('~') else binding + '~'}",
                        "Retry",
                    ])
                    if choice == 2:
                        break
                    if choice == 1:
                        binding = binding.rstrip("~") if binding.endswith("~") else binding + "~"
                entry = None
                if len(observed) == 1:
                    entry = profile_entry(next(iter(observed.values())))
                elif observed:
                    picks = sorted(observed)
                    selected = choose(screen, f"{label}: select the DirectInput member",
                                      [describe_observation(observed[name]) for name in picks]
                                      + ["None of these"])
                    if selected < len(picks):
                        entry = profile_entry(observed[picks[selected]])
                return binding, entry


def select_device(screen, sdl, threshold):
    while True:
        sdl.PumpEvents()
        devices = []
        for i in range(sdl.NumJoysticks()):
            name = (sdl.JoystickNameForIndex(i) or b"Unknown").decode(errors="replace")
            path = (sdl.JoystickPathForIndex(i) or b"no device path").decode(errors="replace")
            devices.append((sdl.JoystickGetDeviceInstanceID(i), name, path))
        choice = choose(screen, "Select guitar/receiver; confirm by pressing a control next", [
            f"{name} ({path}, connection {instance})" for instance, name, path in devices
        ] + ["Refresh device list"])
        if choice == len(devices):
            continue
        instance, name, path = devices[choice]
        joy = sdl.JoystickOpen(sdl.device_index(instance))
        if not joy:
            raise RuntimeError(sdl.error())
        accepted = False
        try:
            # Check identity again in case hotplug occurred while opening.
            if sdl.JoystickInstanceID(joy) != instance:
                raise RuntimeError("Device list changed. Restart guitar-map to select again.")
            serial = (sdl.JoystickGetSerial(joy) or b"not provided").decode(errors="replace")
            guid = bytes(sdl.JoystickGetGUID(joy).data).hex()
            rest = sdl.snapshot(joy)
            seen = False
            while True:
                current = sdl.snapshot(joy)
                seen = seen or bool(candidates(rest, current, "a", threshold))
                draw(screen, ["CONFIRM PHYSICAL GUITAR", name, f"Serial: {serial}",
                              f"GUID: {guid}",
                              "Press/release a fret or strum on the guitar you want to map.",
                              "Input detected on this device." if seen else "Waiting for this device...",
                              "Enter: accept after input   r: choose another   q: quit",
                              "This profile will apply to ALL guitars with this GUID."])
                k = key(screen)
                if k == ord("r"):
                    break
                if k in (10, 13) and seen:
                    accepted = True
                    return joy, name, path
        finally:
            if not accepted:
                sdl.JoystickClose(joy)


def preview(screen, sdl, hid, joy, guid, name, bindings, dinput):
    mapping = mapping_string(guid, name, bindings)
    if sdl.GameControllerAddMapping(mapping.encode()) < 0:
        raise RuntimeError("SDL rejected mapping: " + sdl.error())
    controller = sdl.GameControllerOpen(sdl.device_index(sdl.JoystickInstanceID(joy)))
    if not controller:
        raise RuntimeError("Cannot preview SDL mapping: " + sdl.error())
    offset = 0
    try:
        if sdl.JoystickInstanceID(sdl.GameControllerGetJoystick(controller)) != sdl.JoystickInstanceID(joy):
            raise RuntimeError("Device list changed while opening preview. Restart guitar-map.")
        while True:
            buttons, hats, axes = sdl.snapshot(joy)
            lines = ["LIVE SDL CONTROLLER PREVIEW",
                     "Enter: finish   e: edit an input   up/down: scroll   q: quit",
                     "Check every fret, strum, extra button, whammy and tilt."]
            details = []
            for target, label in CONTROLS:
                if target not in bindings:
                    continue
                value = (sdl.GameControllerGetAxis(controller, AXES.index(target)) if target in AXES
                         else sdl.GameControllerGetButton(controller, BUTTONS.index(target)))
                details.append(f"{target:14} {bindings[target]:8} {value:7}  {label}")
            details += ["", "RAW INPUTS (including unmapped controls)",
                        "Buttons down: " + ", ".join(f"b{i}" for i, v in enumerate(buttons) if v),
                        "Hats: " + "  ".join(f"h{i}={v}" for i, v in enumerate(hats))]
            details += [f"a{i}: {v:7}  " + "#" * int((v + 32768) * 24 / 65535)
                        for i, v in enumerate(axes)]
            details += ["", "DIRECTINPUT VIEW (raw HID; what the Wine shim reads)"]
            if hid:
                values = hid.snapshot()
                details += [f"{target:14} {entry_label(dinput[target])}" for target, _ in CONTROLS
                            if target in dinput]
                details += ["", "Live DIJOYSTATE2 members:"] + [
                    f"  {hid.members[field].name:16} {values.get(field, '-')}"
                    for field in hid.fields if field in hid.members]
            else:
                details.append("not measured; the shim table cannot be derived from SDL")
            draw(screen, lines + details[offset:])
            k = key(screen)
            if k in (10, 13):
                return False
            if k == ord("e"):
                return True
            if k == curses.KEY_DOWN:
                offset = min(offset + 1, max(0, len(details) - 1))
            elif k == curses.KEY_UP:
                offset = max(0, offset - 1)
    finally:
        sdl.GameControllerClose(controller)


def wizard(screen, sdl, threshold):
    screen.timeout(30)
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    joy, name, path = select_device(screen, sdl, threshold)
    hid, hid_error = None, None
    try:
        hid = HidRaw(path)
    except HidUnavailable as error:
        hid_error = str(error)
    try:
        guid = bytes(sdl.JoystickGetGUID(joy).data).hex()
        vendor, product = sdl.JoystickGetVendor(joy), sdl.JoystickGetProduct(joy)
        usb = (f"{vendor:04x}", f"{product:04x}") if vendor and product else None
        bindings, dinput = {}, {}
        for target, label in CONTROLS:
            recorded = capture(screen, sdl, hid, joy, target, label, threshold)
            if recorded and recorded[0]:
                bindings[target], entry = recorded[0], recorded[1]
                if entry:
                    dinput[target] = entry
        while True:
            if not bindings:
                raise RuntimeError("No inputs mapped; no configuration generated.")
            if not preview(screen, sdl, hid, joy, guid, name, bindings, dinput):
                break
            selected = choose(screen, "Select input to re-record (s removes its mapping)", [
                f"{label}: {bindings.get(target, 'unmapped')}" for target, label in CONTROLS])
            target, label = CONTROLS[selected]
            recorded = capture(screen, sdl, hid, joy, target, label, threshold)
            bindings.pop(target, None)
            dinput.pop(target, None)
            if recorded and recorded[0]:
                bindings[target], entry = recorded[0], recorded[1]
                if entry:
                    dinput[target] = entry
        return (profile_slug(name), mapping_string(guid, name, bindings), usb,
                dinput, hid_error)
    finally:
        sdl.JoystickClose(joy)
        if hid:
            hid.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="save Nix snippet to a NEW file")
    parser.add_argument("--threshold", type=int, default=12000, help="minimum raw axis movement (default: 12000)")
    args = parser.parse_args()
    if not 1000 <= args.threshold <= 65535:
        parser.error("--threshold must be between 1000 and 65535")
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error("run in an interactive terminal")
    # Steam's filters can hide the very guitar we need to configure.
    os.environ.pop("SDL_GAMECONTROLLER_IGNORE_DEVICES", None)
    os.environ.pop("SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT", None)
    os.environ["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"] = "1"
    sdl = None
    try:
        sdl = SDL()
        slug, mapping, usb, dinput, hid_error = curses.wrapper(wizard, sdl, args.threshold)
        snippet = nix_profile(slug, mapping, usb, dinput, hid_error)
        print(f"\nSave this as modules/software/guitars/{slug}.nix (auto-imported),")
        print("or import it as a host module:\n")
        print(snippet)
        if hid_error:
            print(f"DirectInput not measured: {hid_error}")
        print("Log out/in after applying the Nix config so games inherit the mapping.")
        print("The profile also supplies the hidraw rule and the Steam exclusion.")
        print("Its dinput block is for xinput-guitar-dll.c, which still hardcodes the")
        print("MiniHost layout; the DLL does not read profiles yet.")
        if args.output:
            with args.output.open("x") as output:
                output.write(snippet)
            print(f"Saved {args.output}")
    except KeyboardInterrupt:
        print("\nCancelled; no configuration written.", file=sys.stderr)
        return 130
    except (RuntimeError, OSError, curses.error) as error:
        print(f"guitar-map: {error}", file=sys.stderr)
        return 1
    finally:
        if sdl:
            sdl.Quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
