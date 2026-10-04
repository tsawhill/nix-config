#!/usr/bin/env python3
"""Sync the software.games.* library into Steam as non-Steam shortcuts.

For every Steam account this:
  * writes each game into shortcuts.vdf (launch command, art, hidden marker),
  * copies SteamGridDB art (~/Games/art/<id>/) into the account grid/ dir, and
  * adds one Steam Collection per game category (cloud-storage-namespace-1.json),
    so the categories show up in Steam's library sidebar.

The user's own shortcuts and collections are preserved; everything we manage
carries a marker so removed games are cleaned up on the next run.

Steam is only touched when something actually changed. With --stop-steam it is
never stopped mid-game: the sync is handed to a background unit that waits for
the game to end (--wait), then stops, syncs and restarts Steam.

argv: <games.json> <art_base_dir> <bin_dir> [--stop-steam] [--restart-steam] [--wait]
games.json: [ { "id", "name", "command", "category" }, ... ]
"""

import binascii
import filecmp
import json
import os
import shutil
import subprocess
import sys
import time

import vdf

# Hidden marker on every shortcut we manage (so a later sync can find/remove all
# of them, including deleted games, without touching the user's own shortcuts).
MARKER = "nixos-game"
# Prefix for the collections we own, so we can rewrite/clean only ours.
COLLECTION_PREFIX = "user-collections.nixos-"
# Background unit that finishes a sync once no game is running.
DEFERRED_UNIT = "sync-steam-shortcuts-deferred"
# Shortcut fields we set that Steam leaves alone; compared to detect changes.
COMPARED_FIELDS = ("appid", "AppName", "Exe", "StartDir", "tags")
ART_FILES = (
    ("boxFront.png", "{}p.png"),
    ("logo.png", "{}_logo.png"),
    ("background.png", "{}_hero.png"),
)


def app_id(exe: str, name: str) -> int:
    """Unsigned 32-bit non-Steam app id (Steam/SteamGridDB convention)."""
    return binascii.crc32((exe + name).encode("utf-8")) | 0x80000000


def signed32(value: int) -> int:
    return value - 0x100000000 if value >= 0x80000000 else value


def slug(text: str) -> str:
    return text.lower().replace(" ", "-").replace("/", "-")


def steam_running() -> bool:
    return subprocess.run(["pgrep", "-x", "steam"], capture_output=True).returncode == 0


def game_running() -> bool:
    # Steam launches every game, non-Steam shortcuts included, under `reaper SteamLaunch`.
    return subprocess.run(["pgrep", "-f", "SteamLaunch AppId="], capture_output=True).returncode == 0


def wait_for_no_game(poll: int = 30) -> None:
    # Two quiet polls in a row, so switching games doesn't count as finished.
    quiet = 0
    while quiet < 2:
        quiet = 0 if game_running() else quiet + 1
        time.sleep(poll)


def wait_for_steam_exit(timeout: int = 45) -> bool:
    for _ in range(timeout):
        if not steam_running():
            return True
        time.sleep(1)
    return not steam_running()


def user_env() -> dict:
    env = os.environ.copy()
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return env


def systemctl_user(action: str, unit: str) -> int:
    return subprocess.run(
        ["systemctl", "--user", action, unit], check=False, env=user_env(), capture_output=True
    ).returncode


def game_mode_active() -> bool:
    return systemctl_user("is-active", "gamescope-session.service") == 0


def defer_sync() -> None:
    """Re-run this sync in a background user unit that waits for the game to end."""
    systemctl_user("stop", f"{DEFERRED_UNIT}.service")
    argv = [sys.executable, os.path.abspath(__file__), *sys.argv[1:]]
    if "--wait" not in argv:
        argv.append("--wait")
    subprocess.run(
        [
            "systemd-run", "--user", "--collect", f"--unit={DEFERRED_UNIT}",
            "--description=Sync Steam shortcuts once no game is running",
            f"--setenv=PATH={os.environ.get('PATH', '')}",
            *argv,
        ],
        check=False,
        env=user_env(),
    )
    print(f"A game is running; deferred the Steam sync to {DEFERRED_UNIT}.service.")


def stop_steam() -> bool:
    if not steam_running():
        return False

    print("Stopping Steam before syncing shortcuts...")
    systemctl_user("stop", "gamescope-session.service")
    subprocess.run(["pkill", "-TERM", "-x", "steam"], check=False)
    subprocess.run(["pkill", "-TERM", "-x", "steamwebhelper"], check=False)

    if wait_for_steam_exit():
        return True

    print("Steam did not exit after SIGTERM; forcing it down.", file=sys.stderr)
    subprocess.run(["pkill", "-KILL", "-x", "steam"], check=False)
    subprocess.run(["pkill", "-KILL", "-x", "steamwebhelper"], check=False)
    return wait_for_steam_exit(timeout=10)


def restart_steam(game_mode: bool, bin_dir: str) -> None:
    if game_mode:
        print("Starting Steam Game Mode session...")
        systemctl_user("start", "gamescope-session.service")
        return

    print("Starting Steam in the desktop session...")
    steam = os.path.join(bin_dir, "steam")
    uwsm = os.path.join(bin_dir, "uwsm")
    # A transient user service, so Steam outlives the activation that started it.
    if os.path.exists(uwsm):
        cmd = [uwsm, "app", "-t", "service", "--", steam]
    else:
        cmd = ["systemd-run", "--user", "--collect", steam]
    subprocess.run(cmd, check=False, env=user_env())


def find_accounts(home: str) -> list:
    roots = [
        os.path.join(home, ".local/share/Steam/userdata"),
        os.path.join(home, ".steam/steam/userdata"),
    ]
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for entry in os.listdir(root):
            # Account dirs are the numeric Steam3 id; "0" / "ac" aren't accounts.
            if entry.isdigit() and entry != "0":
                found.append(os.path.realpath(os.path.join(root, entry)))
    return sorted(set(found))


def load_shortcuts(path):
    """Parsed shortcuts.vdf, an empty one if missing, or None if unparseable."""
    if not (os.path.exists(path) and os.path.getsize(path) > 0):
        return {"shortcuts": {}}
    try:
        with open(path, "rb") as handle:
            return vdf.binary_load(handle)
    except Exception as exc:  # noqa: BLE001 - never clobber a file we can't parse
        print(f"Skipping {path}: could not parse ({exc}).", file=sys.stderr)
        return None


def desired_shortcuts(games, bin_dir):
    """[(game, unsigned_appid, shortcut_entry), ...] for every managed game."""
    out = []
    for game in games:
        exe = f'"{bin_dir}/{game["command"]}"'
        aid = app_id(exe, game["name"])
        out.append((game, aid, {
            "appid": signed32(aid),
            "AppName": game["name"],
            "Exe": exe,
            "StartDir": f'"{bin_dir}/"',
            "icon": "",
            "ShortcutPath": "",
            "LaunchOptions": "",
            "IsHidden": 0,
            "AllowDesktopConfig": 1,
            "AllowOverlay": 1,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": MARKER,
            "DevkitOverrideAppID": 0,
            "LastPlayTime": 0,
            "FlatpakAppID": "",
            "tags": {"0": game["category"]},
        }))
    return out


def account_in_sync(config_dir, games, art_base, bin_dir) -> bool:
    """True when shortcuts, grid art and collections already match the library."""
    data = load_shortcuts(os.path.join(config_dir, "shortcuts.vdf"))
    if data is None:
        return True  # write_shortcuts would skip it anyway

    def project(entry):
        return json.dumps({k: entry.get(k) for k in COMPARED_FIELDS}, sort_keys=True)

    desired = desired_shortcuts(games, bin_dir)
    current = [s for s in data.get("shortcuts", {}).values() if s.get("DevkitGameID") == MARKER]
    if sorted(map(project, current)) != sorted(project(e) for _, _, e in desired):
        return False

    grid = os.path.join(config_dir, "grid")
    for game, aid, _ in desired:
        for src, dst in ART_FILES:
            src_path = os.path.join(art_base, game["id"], src)
            dst_path = os.path.join(grid, dst.format(aid))
            if os.path.exists(src_path) and not (
                os.path.exists(dst_path) and filecmp.cmp(src_path, dst_path, shallow=False)
            ):
                return False

    ns1 = os.path.join(config_dir, "cloudstorage", "cloud-storage-namespace-1.json")
    if not os.path.exists(ns1):
        return True  # update_collections skips this account too
    by_category = {}
    for game, aid, _ in desired:
        by_category.setdefault(game["category"], set()).add(aid)
    want = {
        COLLECTION_PREFIX + slug(cat): [cat, sorted(ids)] for cat, ids in by_category.items()
    }
    have = {}
    for key, obj in json.load(open(ns1, encoding="utf-8")):
        if key.startswith(COLLECTION_PREFIX):
            value = json.loads(obj.get("value") or "{}")
            have[key] = [value.get("name"), sorted(value.get("added", []))]
    return have == want


def write_shortcuts(config_dir, games, art_base, bin_dir):
    """Rewrite shortcuts.vdf + grid art; return {category: [unsigned_appid,...]}."""
    grid = os.path.join(config_dir, "grid")
    os.makedirs(grid, exist_ok=True)
    path = os.path.join(config_dir, "shortcuts.vdf")

    data = load_shortcuts(path)
    if data is None:
        return None

    existing = data.get("shortcuts", {})
    kept = [s for s in existing.values() if s.get("DevkitGameID") != MARKER]
    stale = [s for s in existing.values() if s.get("DevkitGameID") == MARKER]

    # Drop grid art for previously-managed shortcuts (current ones re-copy below).
    for shortcut in stale:
        old = shortcut.get("appid", 0)
        old_unsigned = old + 0x100000000 if old < 0 else old
        for name in (f"{old_unsigned}p.png", f"{old_unsigned}_logo.png", f"{old_unsigned}_hero.png"):
            art = os.path.join(grid, name)
            if os.path.exists(art):
                os.remove(art)

    by_category = {}
    ours = []
    for game, aid, entry in desired_shortcuts(games, bin_dir):
        by_category.setdefault(game["category"], []).append(aid)
        ours.append(entry)

        art_dir = os.path.join(art_base, game["id"])
        for src, dst in ART_FILES:
            src_path = os.path.join(art_dir, src)
            if os.path.exists(src_path):
                shutil.copyfile(src_path, os.path.join(grid, dst.format(aid)))

    merged = kept + ours
    data["shortcuts"] = {str(i): entry for i, entry in enumerate(merged)}
    with open(path, "wb") as handle:
        vdf.binary_dump(data, handle)
    print(f"  {len(ours)} shortcuts -> {path}")
    return by_category


def update_collections(config_dir, by_category, now):
    """Add a Steam library collection per category to cloud-storage-namespace-1."""
    cs = os.path.join(config_dir, "cloudstorage")
    ns1 = os.path.join(cs, "cloud-storage-namespace-1.json")
    nss = os.path.join(cs, "cloud-storage-namespaces.json")
    modified = os.path.join(cs, "cloud-storage-namespace-1.modified.json")
    if not os.path.exists(ns1):
        print("  (no collections file yet — open Steam's library once)", file=sys.stderr)
        return

    entries = json.load(open(ns1, encoding="utf-8"))
    order = [key for key, _ in entries]
    table = {key: obj for key, obj in entries}

    namespaces = json.load(open(nss, encoding="utf-8")) if os.path.exists(nss) else [[1, "0"]]
    counter = 0
    for pair in namespaces:
        if pair[0] == 1:
            counter = int(pair[1])

    changed = []
    # Remove our previous collections so renamed/removed categories disappear.
    for key in list(table):
        if key.startswith(COLLECTION_PREFIX):
            del table[key]
            order.remove(key)
            changed.append(key)

    for category, appids in by_category.items():
        collection_id = "nixos-" + slug(category)
        key = "user-collections." + collection_id
        counter += 1
        value = json.dumps(
            {"id": collection_id, "name": category, "added": sorted(set(appids)), "removed": []},
            separators=(",", ":"),
        )
        table[key] = {"key": key, "timestamp": now, "value": value, "version": str(counter)}
        if key not in order:
            order.append(key)
        if key not in changed:
            changed.append(key)

    json.dump([[key, table[key]] for key in order], open(ns1, "w", encoding="utf-8"),
              separators=(",", ":"))

    updated_ns = False
    for pair in namespaces:
        if pair[0] == 1:
            pair[1] = str(counter)
            updated_ns = True
    if not updated_ns:
        namespaces.append([1, str(counter)])
    json.dump(namespaces, open(nss, "w", encoding="utf-8"), separators=(",", ":"))
    json.dump(changed, open(modified, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"  {len(by_category)} collections -> {ns1}")


def main() -> int:
    flags = set(sys.argv[4:])
    valid_flags = {"--stop-steam", "--restart-steam", "--wait"}
    if len(sys.argv) < 4 or flags - valid_flags:
        print(
            "usage: sync-steam-shortcuts.py <games.json> <art_base_dir> <bin_dir> "
            "[--stop-steam] [--restart-steam] [--wait]",
            file=sys.stderr,
        )
        return 2

    games = json.load(open(sys.argv[1], encoding="utf-8"))
    art_base = sys.argv[2]
    bin_dir = sys.argv[3]
    home = os.path.expanduser("~")
    stopped_steam = False
    game_mode = False

    accounts = find_accounts(home)
    if not accounts:
        print("No Steam account found; open Steam and log in once first.", file=sys.stderr)
        return 0

    def in_sync():
        return all(
            account_in_sync(os.path.join(a, "config"), games, art_base, bin_dir) for a in accounts
        )

    if in_sync():
        print("Steam shortcuts already up to date.")
        return 0

    if steam_running():
        if "--stop-steam" not in flags:
            print(
                "Steam is running; not touching shortcuts.vdf because Steam will "
                "overwrite it on exit. Fully quit Steam, run `sync-steam-shortcuts`, "
                "then reopen Steam.",
                file=sys.stderr,
            )
            return 0

        if game_running():
            if "--wait" not in flags:
                defer_sync()
                return 0
            print("Waiting for the running game to exit...")
            wait_for_no_game()
            if in_sync():
                return 0

        game_mode = game_mode_active()
        stopped_steam = stop_steam()
        if steam_running():
            print("Steam is still running; cannot safely sync shortcuts.", file=sys.stderr)
            return 1

    now = int(time.time())
    try:
        for account in accounts:
            config = os.path.join(account, "config")
            os.makedirs(config, exist_ok=True)
            print(f"Account {os.path.basename(account)}:")
            by_category = write_shortcuts(config, games, art_base, bin_dir)
            if by_category is not None:
                update_collections(config, by_category, now)

        return 0
    finally:
        if stopped_steam and "--restart-steam" in flags:
            restart_steam(game_mode, bin_dir)


if __name__ == "__main__":
    sys.exit(main())
