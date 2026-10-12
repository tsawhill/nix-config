"""Toggle Feishin's special workspace beneath a Wayle button click."""

import fcntl
import json
import os
import subprocess
import time
from pathlib import Path


def query(kind):
    return json.loads(subprocess.check_output(["hyprctl", "-j", kind], text=True))


def dispatch(name, argument):
    subprocess.run(["hyprctl", "dispatch", name, str(argument)], check=True)


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
        dispatch("focusmonitor", monitor["id"])
        if monitor.get("specialWorkspace", {}).get("name") == "special:music":
            dispatch("togglespecialworkspace", "music")
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
        address = "address:" + window["address"]
        dispatch("movetoworkspacesilent", "special:music," + address)
        dispatch("setfloating", address)

        mx, my, mw, mh = monitor_bounds(monitor)
        left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
        margin = 12
        x0, y0 = mx + left + margin, my + top + margin
        x1, y1 = mx + mw - right - margin, my + mh - bottom - margin
        width = min(1100, int((x1 - x0) * 0.8))
        height = min(900, int((y1 - y0) * 0.85))
        x = min(max(cursor["x"] - 24, x0), x1 - width)
        y = min(max(cursor["y"] + margin, y0), y1 - height)
        dispatch("togglespecialworkspace", "music")
        dispatch("resizewindowpixel", f"exact {width} {height},{address}")
        dispatch("movewindowpixel", f"exact {int(x)} {int(y)},{address}")


if __name__ == "__main__":
    main()
