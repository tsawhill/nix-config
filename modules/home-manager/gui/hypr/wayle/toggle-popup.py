"""Toggle an app's popup in a special workspace positioned near the click."""

import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path


# name: (command, window classes, max width, max height, close instead of hiding)
APPS = {
    "music": (["feishin"], {"feishin"}, 1100, 900, False),
    "volume": (["pavucontrol"], {"org.pulseaudio.pavucontrol", "pavucontrol"}, 700, 700, False),
    "network": (["nm-connection-editor"], {"nm-connection-editor"}, 700, 700, False),
    "bluetooth": (["blueman-manager"], {".blueman-manager-wrapped", "blueman-manager"}, 700, 700, False),
    "mouse": (["periph-gui", "mchose-m7-ultra"], {"periph-mchose-m7-ultra"}, 760, 1000, True),
}


def query(kind):
    return json.loads(subprocess.check_output(["hyprctl", "-j", kind], text=True))


def lua(value):
    # JSON strings are valid Lua literals for these ASCII names and addresses.
    return json.dumps(value)


def dispatch(expression):
    # The Lua config evaluates dispatch arguments as hl.dispatch(<expression>).
    result = subprocess.run(["hyprctl", "dispatch", expression], capture_output=True, text=True)
    if result.returncode or not result.stdout.startswith("ok"):
        raise RuntimeError(f"{expression}: {result.stdout.strip()}")


def monitor_bounds(monitor):
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    scale = monitor["scale"]
    return monitor["x"], monitor["y"], width / scale, height / scale


def main():
    app = sys.argv[1] if len(sys.argv) > 1 else "music"
    command, classes, max_width, max_height, close = APPS[app]
    workspace = "music" if app == "music" else "wayle-" + app
    # Ignore repeated clicks while waiting for a cold app launch.
    with (Path(os.environ["XDG_RUNTIME_DIR"]) / f"wayle-{app}.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return

        cursor = query("cursorpos")
        monitors = query("monitors")
        monitor = next(m for m in monitors if m["focused"])
        for candidate in monitors:
            x, y, width, height = monitor_bounds(candidate)
            if x <= cursor["x"] < x + width and y <= cursor["y"] < y + height:
                monitor = candidate
                break
        dispatch(f"hl.dsp.focus({{ monitor = {lua(monitor['name'])} }})")

        def app_windows():
            return [w for w in query("clients") if w["class"].lower() in classes]

        if monitor.get("specialWorkspace", {}).get("name") == "special:" + workspace:
            if close:
                for window in app_windows():
                    dispatch(f'hl.dsp.window.close({{ window = {lua("address:" + window["address"])} }})')
            dispatch(f'hl.dsp.workspace.toggle_special({lua(workspace)})')
            return

        windows = app_windows()
        cold_launch = not windows
        if cold_launch:
            subprocess.Popen(["uwsm", "app", "--", *command], start_new_session=True)
            for _ in range(80):
                time.sleep(0.1)
                windows = app_windows()
                if windows:
                    break
        if not windows:
            raise RuntimeError(f"{' '.join(command)} did not open within eight seconds")

        # Also handles an already-running window from before these rules loaded.
        window = max(windows, key=lambda w: w["size"][0] * w["size"][1])
        address = lua("address:" + window["address"])
        dispatch(f'hl.dsp.window.move({{ workspace = {lua("special:" + workspace)}, follow = false, window = {address} }})')
        dispatch(f'hl.dsp.window.float({{ action = "enable", window = {address} }})')

        mx, my, mw, mh = monitor_bounds(monitor)
        left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
        margin = 12
        x0, y0 = mx + left + margin, my + top + margin
        x1, y1 = mx + mw - right - margin, my + mh - bottom - margin
        width = min(max_width, int((x1 - x0) * 0.8))
        height = min(max_height, int((y1 - y0) * 0.85))
        x = min(max(cursor["x"] - 24, x0), x1 - width)
        y = min(max(cursor["y"] + margin, y0), y1 - height)
        # Prepare the hidden window before starting the workspace reveal animation.
        dispatch(f"hl.dsp.window.resize({{ x = {width}, y = {height}, window = {address} }})")
        dispatch(f"hl.dsp.window.move({{ x = {int(x)}, y = {int(y)}, window = {address} }})")
        if cold_launch:
            # Client registration precedes completion of windowsIn (500 ms) and
            # geometry animations (450 ms). Let both settle while hidden so the
            # workspace reveal does not overlap a partially finished entrance.
            time.sleep(0.6)
        dispatch(f'hl.dsp.workspace.toggle_special({lua(workspace)})')


if __name__ == "__main__":
    main()
