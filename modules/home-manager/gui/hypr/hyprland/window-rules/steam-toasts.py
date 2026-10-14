"""Position Steam's override-redirect desktop toasts through X11 itself."""

import json
import re
import select
import subprocess
import time


def command(*args):
    return subprocess.check_output(args, text=True, timeout=2)


def adjusted_y(y, height, output, monitor, fullscreen):
    """Convert Hyprland's logical reserved space into XWayland coordinates."""
    if fullscreen:
        return y
    _, top, _, output_height = output
    physical_height = monitor["height"]
    if monitor.get("transform", 0) % 2:
        physical_height = monitor["width"]
    ratio = output_height / (physical_height / monitor["scale"])
    reserved_top = monitor["reserved"][1]
    reserved_bottom = monitor["reserved"][3]
    if not reserved_top and not reserved_bottom:
        return y
    low = top + round((reserved_top + 8) * ratio)
    high = top + output_height - round((reserved_bottom + 8) * ratio) - height
    return max(low, min(y, high))


def main():
    from Xlib import X, display, error

    connection = display.Display()
    # A toast can disappear between a query and a configure request.
    connection.set_error_handler(lambda *_: None)
    root = connection.screen().root
    root.change_attributes(event_mask=X.SubstructureNotifyMask)
    title_atom = connection.intern_atom("_NET_WM_NAME")
    windows = {}
    positions = {}
    next_scan = 0
    next_outputs = 0
    outputs = {}
    while True:
        now = time.monotonic()
        rescan = now >= next_scan
        while connection.pending_events():
            event = connection.next_event()
            if event.type in (X.MapNotify, X.UnmapNotify, X.DestroyNotify):
                rescan = True
        if rescan:
            found = {}
            for window in root.query_tree().children:
                try:
                    if window.get_wm_class() != ("steamwebhelper", "steam"):
                        continue
                    prop = window.get_full_property(title_atom, X.AnyPropertyType)
                    title = prop.value.decode("utf-8", "replace") if prop else window.get_wm_name()
                    attrs = window.get_attributes()
                    if (title or "").startswith("notificationtoasts") and attrs.override_redirect and attrs.map_state == X.IsViewable:
                        found[window.id] = window
                except error.XError:
                    continue
            windows = found
            positions = {key: value for key, value in positions.items() if key in windows}
            next_scan = now + 2
        if windows:
            try:
                monitors = json.loads(command("hyprctl", "-j", "monitors"))
                clients = json.loads(command("hyprctl", "-j", "clients"))
                if now >= next_outputs:
                    outputs = {
                        name: tuple(map(int, (x, y, width, height)))
                        for name, width, height, x, y in re.findall(
                            r"^(\S+) connected (?:primary )?(\d+)x(\d+)([+-]\d+)([+-]\d+)",
                            command("xrandr", "--query"), re.M,
                        )
                    }
                    next_outputs = now + 2
                for key, window in list(windows.items()):
                    try:
                        geometry = window.get_geometry()
                        # Match using the horizontal center and distance to the output;
                        # Steam can initially map a toast just below its bottom edge.
                        cx, cy = geometry.x + geometry.width / 2, geometry.y + geometry.height / 2
                        candidates = [m for m in monitors if m["name"] in outputs]
                        if not candidates:
                            continue
                        def distance(m):
                            x, y, w, h = outputs[m["name"]]
                            return max(x - cx, 0, cx - x - w) ** 2 + max(y - cy, 0, cy - y - h) ** 2
                        monitor = min(candidates, key=distance)
                        visible_workspaces = {monitor["activeWorkspace"]["id"], monitor["specialWorkspace"]["id"]}
                        fullscreen = any(
                            c["monitor"] == monitor["id"]
                            and c["workspace"]["id"] in visible_workspaces
                            and c["fullscreen"] in (2, 3)
                            for c in clients
                        )
                        # Preserve Steam's last requested Y, so fullscreen restores it.
                        original, applied = positions.get(key, (geometry.y, None))
                        if geometry.y != applied:
                            original = geometry.y
                        target = adjusted_y(original, geometry.height, outputs[monitor["name"]], monitor, fullscreen)
                        if target != geometry.y:
                            window.configure(y=target)
                        positions[key] = (original, target)
                    except error.XError:
                        windows.pop(key, None)
                        positions.pop(key, None)
                connection.flush()
            except (subprocess.SubprocessError, OSError, ValueError) as exc:
                print(f"Steam toast positioning deferred: {exc}", flush=True)
        # No hyprctl polling while idle; X11 map events wake us immediately.
        select.select([connection.fileno()], [], [], 0.2 if windows else 2)


if __name__ == "__main__":
    main()
