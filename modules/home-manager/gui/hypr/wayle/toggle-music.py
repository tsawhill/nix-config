"""Toggle Feishin's special workspace beneath a Wayle button click."""

import fcntl
import json
import os
import subprocess
import time
from pathlib import Path


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
    # Ignore repeated clicks while waiting for a cold app launch.
    with (Path(os.environ["XDG_RUNTIME_DIR"]) / "wayle-music.lock").open("w") as lock:
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
        if monitor.get("specialWorkspace", {}).get("name") == "special:music":
            dispatch('hl.dsp.workspace.toggle_special("music")')
            return

        def music_windows():
            return [w for w in query("clients") if w["class"].lower() == "feishin"]

        windows = music_windows()
        if not windows:
            subprocess.Popen(["uwsm", "app", "--", "feishin"], start_new_session=True)
            for _ in range(80):
                time.sleep(0.1)
                windows = music_windows()
                if windows:
                    break
        if not windows:
            raise RuntimeError("Feishin did not open within eight seconds")

        # Also handles an already-running window from before these rules loaded.
        window = max(windows, key=lambda w: w["size"][0] * w["size"][1])
        address = lua("address:" + window["address"])
        dispatch(f'hl.dsp.window.move({{ workspace = "special:music", follow = false, window = {address} }})')
        dispatch(f'hl.dsp.window.float({{ action = "enable", window = {address} }})')

        mx, my, mw, mh = monitor_bounds(monitor)
        left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
        margin = 12
        x0, y0 = mx + left + margin, my + top + margin
        x1, y1 = mx + mw - right - margin, my + mh - bottom - margin
        width = min(1100, int((x1 - x0) * 0.8))
        height = min(900, int((y1 - y0) * 0.85))
        x = min(max(cursor["x"] - 24, x0), x1 - width)
        y = min(max(cursor["y"] + margin, y0), y1 - height)
        dispatch('hl.dsp.workspace.toggle_special("music")')
        dispatch(f"hl.dsp.window.resize({{ x = {width}, y = {height}, window = {address} }})")
        dispatch(f"hl.dsp.window.move({{ x = {int(x)}, y = {int(y)}, window = {address} }})")


if __name__ == "__main__":
    main()
