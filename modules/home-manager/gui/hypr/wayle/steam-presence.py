#!/usr/bin/env python3
"""Steam presence policy and tray icon; never reads Steam account data or starts Steam."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time

MODES = {"auto": "Auto", "away": "Away", "invisible": "Invisible", "off": "Off"}
# Stand-ins for Steam's own tray menu, which is hidden from the bar.
STEAM = {
    "Library": "open/games",
    "Store": "store",
    "Community": "url/CommunityHome",
    "Friends": "open/friends",
    "Settings": "open/settings",
    "Big Picture": "open/bigpicture",
    "Exit Steam": "exit",
}
ICON_DIR = Path(__file__).resolve().parent.parent / "share/steam-presence/icons"


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10)


def running(name):
    return run("pgrep", "-u", str(os.getuid()), "-x", name).returncode == 0


def locked():
    if running("hyprlock"):
        return True
    session = os.environ.get("XDG_SESSION_ID")
    if session:
        result = run("loginctl", "show-session", session, "-p", "LockedHint", "--value")
        # Fail closed if the session cannot be queried.
        return result.returncode != 0 or result.stdout.strip() != "no"
    return False


def handle(action):
    """Apply an action; "status" returns (mode, label), or None while Steam is closed."""
    if action in STEAM:
        if running("steam"):
            run("steam", "steam://" + STEAM[action])
        return None

    runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "steam-presence"
    runtime.mkdir(mode=0o700, exist_ok=True)
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "steam-presence"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (runtime / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        mode_file = state / "mode"
        mode = mode_file.read_text().strip() if mode_file.exists() else "off"
        if mode not in MODES:
            mode = "off"
        idle = runtime / ("idle-" + os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "session"))
        if action in MODES:
            mode = action
            mode_file.write_text(mode + "\n")
        elif action == "idle":
            idle.touch()
        elif action == "resume":
            idle.unlink(missing_ok=True)
        elif action not in ("status", "tick"):
            raise SystemExit("Unknown action")

        if not running("steam"):
            return None
        paused = idle.exists() or locked()
        if action == "status":
            return mode, MODES[mode] + (" (idle)" if mode == "auto" and paused else "")
        if mode == "off":
            return None
        if mode == "auto":
            if paused or not running("hypridle"):
                return None
            target = "online"
        else:
            target = mode
        # Use the installed NixOS launcher, not a separate Steam package.
        result = run("steam", "steam://friends/status/" + target)
        if result.returncode:
            raise SystemExit(result.returncode)
        return None


def supervise():
    # Wayle shows passive tray items, so the icon only exists while Steam runs.
    while True:
        if running("steam"):
            subprocess.run([sys.executable, os.path.abspath(__file__), "tray-icon"])
        time.sleep(3)


def tray():
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator, GLib, Gtk

    def safe(action):
        try:
            return handle(action)
        except (OSError, subprocess.SubprocessError, SystemExit) as error:
            print(f"steam-presence {action}: {error}", file=sys.stderr)
            return None

    if safe("status") is None:
        return
    indicator = AppIndicator.Indicator.new(
        "steam-presence", str(ICON_DIR / "off.png"),
        AppIndicator.IndicatorCategory.APPLICATION_STATUS,
    )
    items = {}
    updating = False

    def refresh():
        nonlocal updating
        current = safe("status")
        if current is None:
            Gtk.main_quit()
            return False
        mode, label = current
        indicator.set_icon_full(str(ICON_DIR / (mode + ".png")), "Steam: " + label)
        indicator.set_title("Steam: " + label)
        updating = True
        for key, item in items.items():
            item.set_active(key == mode)
        updating = False
        return True

    def select(_item, action):
        if not updating:
            safe(action)
            refresh()

    menu = Gtk.Menu()
    for key, label in MODES.items():
        item = Gtk.CheckMenuItem(label=label)
        item.set_draw_as_radio(True)
        item.connect("toggled", select, key)
        items[key] = item
        menu.append(item)
    menu.append(Gtk.SeparatorMenuItem())
    for label in STEAM:
        item = Gtk.MenuItem(label=label)
        item.connect("activate", select, label)
        menu.append(item)
    menu.show_all()
    indicator.set_menu(menu)
    indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)

    refresh()
    GLib.timeout_add_seconds(3, refresh)
    Gtk.main()


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "tray":
        supervise()
        return
    if action == "tray-icon":
        tray()
        return
    current = handle(action)
    if action == "status" and current:
        print(current[1])


if __name__ == "__main__":
    main()
