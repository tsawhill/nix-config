#!/usr/bin/env python3
"""Sync the software.games.* library into Steam as non-Steam shortcuts.

For every Steam account this:
  * writes each game into shortcuts.vdf (launch command, art, hidden marker),
  * copies SteamGridDB art (~/Games/art/<id>/) into the account grid/ dir, and
  * adds one Steam Collection per game category (cloud-storage-namespace-1.json),
    so the categories show up in Steam's library sidebar.

The user's own shortcuts and collections are preserved; everything we manage
carries a marker so removed games are cleaned up on the next run.

argv: <games.json> <art_base_dir> <bin_dir>
games.json: [ { "id", "name", "command", "category" }, ... ]
"""

import binascii
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


def app_id(exe: str, name: str) -> int:
    """Unsigned 32-bit non-Steam app id (Steam/SteamGridDB convention)."""
    return binascii.crc32((exe + name).encode("utf-8")) | 0x80000000


def signed32(value: int) -> int:
    return value - 0x100000000 if value >= 0x80000000 else value


def slug(text: str) -> str:
    return text.lower().replace(" ", "-").replace("/", "-")


def steam_running() -> bool:
    return subprocess.run(["pgrep", "-x", "steam"], capture_output=True).returncode == 0


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


def write_shortcuts(config_dir, games, art_base, bin_dir):
    """Rewrite shortcuts.vdf + grid art; return {category: [unsigned_appid,...]}."""
    grid = os.path.join(config_dir, "grid")
    os.makedirs(grid, exist_ok=True)
    path = os.path.join(config_dir, "shortcuts.vdf")

    data = {"shortcuts": {}}
    if os.path.exists(path) and os.path.getsize(path) > 0:
        try:
            with open(path, "rb") as handle:
                data = vdf.binary_load(handle)
        except Exception as exc:  # noqa: BLE001 - never clobber a file we can't parse
            print(f"Skipping {path}: could not parse ({exc}).", file=sys.stderr)
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
    for game in games:
        exe = f'"{bin_dir}/{game["command"]}"'
        aid = app_id(exe, game["name"])
        by_category.setdefault(game["category"], []).append(aid)
        ours.append(
            {
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
            }
        )

        art_dir = os.path.join(art_base, game["id"])
        for src, dst in (
            ("boxFront.png", f"{aid}p.png"),
            ("logo.png", f"{aid}_logo.png"),
            ("background.png", f"{aid}_hero.png"),
        ):
            src_path = os.path.join(art_dir, src)
            if os.path.exists(src_path):
                shutil.copyfile(src_path, os.path.join(grid, dst))

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
    games = json.load(open(sys.argv[1], encoding="utf-8"))
    art_base = sys.argv[2]
    bin_dir = sys.argv[3]
    home = os.path.expanduser("~")
    now = int(time.time())

    if steam_running():
        print(
            "Steam is running; not touching shortcuts.vdf because Steam will "
            "overwrite it on exit. Fully quit Steam, run `sync-steam-shortcuts`, "
            "then reopen Steam.",
            file=sys.stderr,
        )
        return 0

    accounts = find_accounts(home)
    if not accounts:
        print("No Steam account found; open Steam and log in once first.", file=sys.stderr)
        return 0

    for account in accounts:
        config = os.path.join(account, "config")
        os.makedirs(config, exist_ok=True)
        print(f"Account {os.path.basename(account)}:")
        by_category = write_shortcuts(config, games, art_base, bin_dir)
        if by_category is not None:
            update_collections(config, by_category, now)

    return 0


if __name__ == "__main__":
    sys.exit(main())
