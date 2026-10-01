#!/usr/bin/env python3
"""Promote torrents whose *arr import happened but whose promotion did not.

qbit-promote runs once, from the On Import hook. If the seeding instance was
unreachable at that moment, the torrent stays on intake and nothing retries it.
This asks each *arr which downloads it actually imported and runs the same
promotion for those. Anything without a recorded import is left alone, so
in-flight downloads and manual one-offs (qbit-promote-tui's job) are untouched.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from qbit_promote import COMPLETE_PROGRESS, PromotionError, QbitClient, promote

# Sonarr/Radarr record downloadFolderImported; Lidarr records per-track and
# per-download events. Any of them proves the library already has the media.
IMPORT_EVENTS = {"downloadfolderimported", "trackfileimported", "downloadimported"}

# (name, API version, default URL)
ARRS = (
    ("sonarr", "v3", "http://127.0.0.1:8989"),
    ("radarr", "v3", "http://127.0.0.1:7878"),
    ("lidarr", "v1", "http://127.0.0.1:8686"),
)


def read_api_key(path):
    """Read the key from an EnvironmentFile-style secret (NAME=value) or a bare key."""
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                return line.split("=", 1)[-1].strip().strip("\"'")
    raise PromotionError(f"{path} holds no API key")


class ArrClient:
    """Just enough of the *arr history API to tell whether a download was imported."""

    def __init__(self, name, base_url, api_version, api_key, timeout=30, opener=None):
        self.name = name
        self.base_url = base_url.rstrip("/")
        self.api_version = api_version
        self.api_key = api_key
        self.timeout = timeout
        self._opener = opener or urllib.request.urlopen

    def history(self, torrent_hash):
        params = urllib.parse.urlencode(
            {
                # The *arrs store qBittorrent hashes uppercased.
                "downloadId": torrent_hash.upper(),
                "pageSize": 100,
                "sortKey": "date",
                "sortDirection": "descending",
            }
        )
        request = urllib.request.Request(
            f"{self.base_url}/api/{self.api_version}/history?{params}",
            headers={"X-Api-Key": self.api_key},
        )
        try:
            with self._opener(request, timeout=self.timeout) as response:
                data = json.loads(response.read().decode())
        except (urllib.error.URLError, ValueError) as error:
            raise PromotionError(f"{self.name}: {error}") from error
        return data.get("records", []) if isinstance(data, dict) else data

    def imported(self, torrent_hash):
        # Filtered again here: an *arr that ignores downloadId returns its latest
        # history instead, and that must not count as an import of this torrent.
        return any(
            str(record.get("downloadId", "")).lower() == torrent_hash
            and str(record.get("eventType", "")).lower() in IMPORT_EVENTS
            for record in self.history(torrent_hash)
        )


def imported_by(arrs, torrent_hash, warn):
    """Name of the first *arr that imported this hash, or None."""
    for arr in arrs:
        try:
            if arr.imported(torrent_hash):
                return arr.name
        except PromotionError as error:
            warn(str(error))
    return None


def classify(intake, seeding, arrs, warn):
    """Split completed intake torrents into (ready, unimported, duplicated)."""
    # Seeding first, so an instance that is still down fails before anything else.
    on_seeding = {t["hash"] for t in seeding.get_json("torrents/info", {})}
    completed = intake.get_json("torrents/info", {"filter": "completed"})

    ready, unimported, duplicated = [], [], []
    for torrent in sorted(completed, key=lambda t: t.get("name", "")):
        if torrent.get("progress", 0) < COMPLETE_PROGRESS:
            continue
        if torrent["hash"] in on_seeding:
            duplicated.append(torrent)
            continue
        arr = imported_by(arrs, torrent["hash"], warn)
        if arr:
            ready.append((arr, torrent))
        else:
            unimported.append(torrent)
    return ready, unimported, duplicated


def size(torrent):
    return f"{torrent.get('size', 0) / 1073741824:.1f}G"


def build_arrs(env):
    arrs = []
    for name, version, default_url in ARRS:
        key_file = env.get(f"{name.upper()}_API_KEY_FILE")
        if not key_file:
            continue
        url = env.get(f"{name.upper()}_URL", default_url)
        arrs.append(ArrClient(name, url, version, read_api_key(key_file)))
    if not arrs:
        raise PromotionError("no *arr API key files configured")
    return arrs


def main(argv=None, env=None):
    parser = argparse.ArgumentParser(
        prog="qbit-promote-missed",
        description="Promote intake torrents that an *arr imported but qbit-promote never moved.",
    )
    parser.add_argument("-n", "--dry-run", action="store_true", help="list only")
    parser.add_argument("-y", "--yes", action="store_true", help="skip the confirmation")
    args = parser.parse_args(argv)
    env = os.environ if env is None else env

    intake = QbitClient(env.get("QBIT_INTAKE_URL", "http://qbit-gen-nix.lan:8080"))
    seeding = QbitClient(env.get("QBIT_SEEDING_URL", "http://qbit-lts-nix.lan:8080"))

    warnings = set()

    def warn(message):
        if message not in warnings:
            warnings.add(message)
            print(f"warning: {message}", file=sys.stderr)

    try:
        arrs = build_arrs(env)
        ready, unimported, duplicated = classify(intake, seeding, arrs, warn)
    except (PromotionError, OSError) as error:
        print(f"qbit-promote-missed: {error}", file=sys.stderr)
        return 1

    if duplicated:
        print(f"On both instances; remove from intake by hand, keeping files ({len(duplicated)}):")
        for torrent in duplicated:
            print(f"  {torrent.get('category') or '-':<12} {torrent['name']}")
        print()

    if unimported:
        print(f"No *arr import recorded, left on intake ({len(unimported)}):")
        for torrent in unimported:
            print(f"  {torrent.get('category') or '-':<12} {size(torrent):>8}  {torrent['name']}")
        print()

    if not ready:
        print("Nothing missed: every imported torrent is already on seeding.")
        return 0

    print(f"Imported but never promoted ({len(ready)}):")
    for arr, torrent in ready:
        print(f"  {arr:<12} {size(torrent):>8}  {torrent['name']}")
    print()

    if args.dry_run:
        return 0

    if not args.yes:
        try:
            answer = input(f"Promote {len(ready)} torrent(s) to seeding? [y/N] ")
        except EOFError:
            answer = ""
        if answer.strip().lower() not in {"y", "yes"}:
            print("Nothing promoted.")
            return 0

    failed = 0
    for _, torrent in ready:
        try:
            promote(intake, seeding, torrent["hash"])
            print(f"  ok    {torrent['name']}")
        except PromotionError as error:
            print(f"  FAIL  {torrent['name']}: {error}")
            failed += 1

    print(f"\nPromoted {len(ready) - failed}, failed {failed}.")
    if failed:
        print("Failures stayed on intake with their data intact.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
