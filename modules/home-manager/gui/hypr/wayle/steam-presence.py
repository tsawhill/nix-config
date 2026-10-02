"""Steam presence policy; never reads Steam account data or starts Steam."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

MODES = {"auto": "Auto", "away": "Away", "invisible": "Invisible", "off": "Off"}


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


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "menu":
        result = subprocess.run(
            ["@menu@", "--dmenu"], input="\n".join(MODES.values()) + "\n",
            capture_output=True, text=True,
        )
        if result.returncode or result.stdout.strip().lower() not in MODES:
            return
        action = result.stdout.strip().lower()

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

        paused = idle.exists() or locked()
        if action == "status":
            label = MODES[mode] + (" (idle)" if mode == "auto" and paused else "")
            print(json.dumps({"text": "Steam: " + label,
                              "tooltip": "Steam mode: " + label + ". Click to choose Auto, Away, Invisible or Off. Change modes here while automation is enabled."}))
            return
        if mode == "off" or not running("steam"):
            return
        if mode == "auto":
            if paused or not running("hypridle"):
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
