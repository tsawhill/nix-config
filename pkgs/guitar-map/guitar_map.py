#!/usr/bin/env python3
"""Interactive raw SDL2 joystick to GameController mapping, without root access."""
import argparse
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


def nix_snippet(mapping):
    return ('{ config, lib, ... }:\n{\n'
            '  config = lib.mkIf config.software.apps.gaming.enable {\n'
            '    software.apps.gaming.sdlGameControllerMappings = lib.mkAfter [\n'
            f'      {nix_quote(mapping)}\n'
            '    ];\n  };\n}\n')


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


def capture(screen, sdl, joy, target, label, threshold):
    while True:
        draw(screen, [label, "Release all buttons; leave whammy/sticks at rest.",
                      "Hold the guitar in normal playing position.",
                      "Enter: ready   s: skip/remove mapping   q: quit"])
        k = key(screen)
        sdl.snapshot(joy)
        if k == ord("s"):
            return None
        if k not in (10, 13):
            continue
        rest = sdl.snapshot(joy)
        found = set()
        while True:
            found.update(candidates(rest, sdl.snapshot(joy), target, threshold))
            draw(screen, [label, "Perform ONLY this input, through its full travel, then release.",
                          "Enter: review detected inputs   r: retry   s: skip   q: quit",
                          "Detected: " + (", ".join(sorted(found)) or "waiting...")])
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
                return binding


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
                    return joy, name
        finally:
            if not accepted:
                sdl.JoystickClose(joy)


def preview(screen, sdl, joy, guid, name, bindings):
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
    joy, name = select_device(screen, sdl, threshold)
    try:
        guid = bytes(sdl.JoystickGetGUID(joy).data).hex()
        bindings = {}
        for target, label in CONTROLS:
            binding = capture(screen, sdl, joy, target, label, threshold)
            if binding:
                bindings[target] = binding
        while True:
            if not bindings:
                raise RuntimeError("No inputs mapped; no configuration generated.")
            if not preview(screen, sdl, joy, guid, name, bindings):
                break
            selected = choose(screen, "Select input to re-record (s removes its mapping)", [
                f"{label}: {bindings.get(target, 'unmapped')}" for target, label in CONTROLS])
            target, label = CONTROLS[selected]
            binding = capture(screen, sdl, joy, target, label, threshold)
            bindings.pop(target, None)
            if binding:
                bindings[target] = binding
        return mapping_string(guid, name, bindings)
    finally:
        sdl.JoystickClose(joy)


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
        mapping = curses.wrapper(wizard, sdl, args.threshold)
        snippet = nix_snippet(mapping)
        print("\nSave this as modules/software/guitars/<device-mode>.nix (auto-imported),")
        print("or import it as a host module:\n")
        print(snippet)
        print("Log out/in after applying the Nix config so games inherit the mapping.")
        print("This maps SDL inputs; it does not install a Windows DLL or change firmware.")
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
