#!/usr/bin/env python3
"""Sync the software.games.* library into Steam as non-Steam shortcuts.

Writes each game into every Steam account's shortcuts.vdf with its category as a
Steam tag, and copies SteamGridDB art (from ~/Games/art/<id>/) into the account's
grid/ dir keyed by the shortcut's app id. Existing non-managed shortcuts are
preserved; our own entries are matched by AppName and rewritten in place.

argv: <games.json> <art_base_dir> <bin_dir>
games.json: [ { "id", "name", "command", "category" }, ... ]
"""

import binascii
import json
import os
import shutil
import subprocess
import sys

import vdf

# Hidden marker stored on every shortcut we manage, so a later sync can find and
# remove all of them (including games that have since been deleted) without
# touching the user's own non-Steam shortcuts.
MARKER = "nixos-game"


def app_id(exe: str, name: str) -> int:
    """Unsigned 32-bit non-Steam app id (Steam/SteamGridDB convention)."""
    return binascii.crc32((exe + name).encode("utf-8")) | 0x80000000


def signed32(value: int) -> int:
    return value - 0x100000000 if value >= 0x80000000 else value


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
            # Account dirs are the numeric Steam3 id; "0" / "ac" are not accounts.
            if entry.isdigit() and entry != "0":
                found.append(os.path.realpath(os.path.join(root, entry)))
    return sorted(set(found))


def main() -> int:
    games = json.load(open(sys.argv[1], encoding="utf-8"))
    art_base = sys.argv[2]
    bin_dir = sys.argv[3]
    home = os.path.expanduser("~")

    accounts = find_accounts(home)
    if not accounts:
        print("No Steam account found; open Steam and log in once first.", file=sys.stderr)
        return 0

    for account in accounts:
        config = os.path.join(account, "config")
        grid = os.path.join(config, "grid")
        os.makedirs(grid, exist_ok=True)
        path = os.path.join(config, "shortcuts.vdf")

        data = {"shortcuts": {}}
        if os.path.exists(path) and os.path.getsize(path) > 0:
            try:
                with open(path, "rb") as handle:
                    data = vdf.binary_load(handle)
            except Exception as exc:  # noqa: BLE001 - don't clobber a file we can't parse
                print(f"Skipping {path}: could not parse ({exc}).", file=sys.stderr)
                continue

        existing = data.get("shortcuts", {})
        # Keep the user's own shortcuts; drop everything we previously managed so
        # removed games disappear and survivors get rewritten cleanly.
        kept = [s for s in existing.values() if s.get("DevkitGameID") != MARKER]
        stale = [s for s in existing.values() if s.get("DevkitGameID") == MARKER]

        # Remove grid art for previously-managed shortcuts (current ones re-copy below).
        for shortcut in stale:
            old = shortcut.get("appid", 0)
            old_unsigned = old + 0x100000000 if old < 0 else old
            for name in (f"{old_unsigned}p.png", f"{old_unsigned}_logo.png", f"{old_unsigned}_hero.png"):
                art = os.path.join(grid, name)
                if os.path.exists(art):
                    os.remove(art)

        ours = []
        for game in games:
            exe = f'"{bin_dir}/{game["command"]}"'
            aid = app_id(exe, game["name"])
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
        print(f"Wrote {len(ours)} game shortcuts to {path}")

    if steam_running():
        print("Steam is running — fully quit and reopen it to see the shortcuts "
              "(and so it doesn't overwrite them).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
