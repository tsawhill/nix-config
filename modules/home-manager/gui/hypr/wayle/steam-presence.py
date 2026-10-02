"""Steam presence policy; never reads Steam account data or starts Steam."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

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


def read_mode(mode_file):
    mode = mode_file.read_text().strip() if mode_file.exists() else "off"
    return mode if mode in MODES else "off"


def choose(mode):
    entries = {("● " if key == mode else "") + label: key for key, label in MODES.items()}
    entries["────────"] = None
    entries.update({label: label for label in STEAM})
    result = subprocess.run(
        ["@menu@", "--dmenu"], input="\n".join(entries) + "\n",
        capture_output=True, text=True,
    )
    return None if result.returncode else entries.get(result.stdout.strip())


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "steam-presence"
    runtime.mkdir(mode=0o700, exist_ok=True)
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "steam-presence"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    mode_file = state / "mode"

    if action == "menu":
        action = choose(read_mode(mode_file))
        if action is None:
            return
    if action in STEAM:
        if running("steam"):
            run("steam", "steam://" + STEAM[action])
        return

    with (runtime / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        mode = read_mode(mode_file)
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

        if action == "status":
            # Empty output hides the button while Steam is closed.
            if not running("steam"):
                return
            paused = idle.exists() or locked()
            label = MODES[mode] + (" (idle)" if mode == "auto" and paused else "")
            print(json.dumps({"alt": mode, "tooltip": "Steam: " + label}))
            return
        if mode == "off" or not running("steam"):
            return
        if mode == "auto":
            if idle.exists() or locked() or not running("hypridle"):
                return
            target = "online"
        else:
            target = mode
        # Use the installed NixOS launcher, not a separate Steam package.
        result = run("steam", "steam://friends/status/" + target)
        if result.returncode:
            raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
