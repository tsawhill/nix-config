#!/usr/bin/env python3
"""Promote an imported torrent from the intake qBittorrent to the seeding one.

Invoked by Sonarr/Radarr/Lidarr as an On Import custom script. The torrent is
added to the seeding instance at its existing save path and only then removed
from intake, without its data. Any failure leaves the torrent on intake, which
is what makes the intake instance the place to look for stuck downloads.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

# The *arrs set these capitalised (Sonarr_EventType, Sonarr_Download_Id) and
# environment variables are case-sensitive, so every lookup is normalised.
EVENT_VARS = ("sonarr_eventtype", "radarr_eventtype", "lidarr_eventtype")
HASH_VARS = ("sonarr_download_id", "radarr_download_id", "lidarr_download_id")

IMPORT_EVENTS = {"download", "albumdownload", "trackfileimported"}
TEST_EVENTS = {"test"}

# Anything below 1.0 means the seeding instance cannot serve the data yet.
COMPLETE_PROGRESS = 1.0
BROKEN_STATES = {"error", "missingFiles", "unknown"}


class PromotionError(Exception):
    """Raised when the torrent must be left on the intake instance."""


def lookup(env, names):
    """Case-insensitive environment lookup, first non-empty match wins."""
    folded = {key.lower(): value for key, value in env.items()}
    return next((folded[name] for name in names if folded.get(name)), None)


def read_event(env):
    """Return (eventtype, infohash) from whichever *arr invoked us."""
    eventtype = lookup(env, EVENT_VARS)
    if eventtype is None:
        raise PromotionError("no *arr event type in the environment")

    if eventtype.lower() in TEST_EVENTS:
        return eventtype, None

    if eventtype.lower() not in IMPORT_EVENTS:
        return eventtype, None

    torrent_hash = lookup(env, HASH_VARS)
    if not torrent_hash:
        raise PromotionError(f"{eventtype} event carried no download id")

    return eventtype, torrent_hash.lower()


def build_multipart(fields, file_field, filename, content):
    """Encode fields plus one file as multipart/form-data."""
    boundary = uuid.uuid4().hex
    marker = f"--{boundary}".encode()
    parts = []

    for name, value in fields.items():
        parts.append(marker)
        parts.append(f'Content-Disposition: form-data; name="{name}"'.encode())
        parts.append(b"")
        parts.append(str(value).encode())

    parts.append(marker)
    parts.append(
        f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"'.encode()
    )
    parts.append(b"Content-Type: application/x-bittorrent")
    parts.append(b"")
    parts.append(content)
    parts.append(f"--{boundary}--".encode())
    parts.append(b"")

    return f"multipart/form-data; boundary={boundary}", b"\r\n".join(parts)


class QbitClient:
    """Minimal qBittorrent WebAPI client.

    No credentials: the web UIs whitelist this host's address, so the login
    endpoint is never needed.
    """

    def __init__(self, base_url, timeout=30, opener=None):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._opener = opener or urllib.request.urlopen

    def _request(self, path, data=None, headers=None):
        request = urllib.request.Request(
            f"{self.base_url}/api/v2/{path}", data=data, headers=headers or {}
        )
        try:
            with self._opener(request, timeout=self.timeout) as response:
                return response.read()
        except urllib.error.URLError as error:
            raise PromotionError(f"{self.base_url}/{path}: {error}") from error

    def get(self, path, params):
        return self._request(f"{path}?{urllib.parse.urlencode(params)}")

    def get_json(self, path, params):
        return json.loads(self.get(path, params).decode())

    def post(self, path, fields):
        body = urllib.parse.urlencode(fields).encode()
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        return self._request(path, data=body, headers=headers)

    def post_multipart(self, path, fields, file_field, filename, content):
        content_type, body = build_multipart(fields, file_field, filename, content)
        return self._request(path, data=body, headers={"Content-Type": content_type})

    def torrent(self, torrent_hash):
        found = self.get_json("torrents/info", {"hashes": torrent_hash})
        return found[0] if found else None


def add_fields(torrent, category):
    """Fields for the add call on the seeding instance.

    autoTMM must be false: with Automatic Torrent Management on, qBittorrent
    relocates the data to the category save path instead of seeding in place.
    """
    return {
        "savepath": torrent["save_path"],
        "category": category,
        "autoTMM": "false",
        "contentLayout": "Original",
        # Intake verified this data when the download completed.
        "skip_checking": "true",
        "stopped": "false",
    }


def wait_until_seeding(client, torrent_hash, timeout=300, interval=5, sleep=time.sleep):
    """Block until the seeding instance reports the torrent complete."""
    deadline = time.monotonic() + timeout

    while True:
        torrent = client.torrent(torrent_hash)
        if torrent is not None:
            state = torrent.get("state", "unknown")
            if state in BROKEN_STATES:
                raise PromotionError(f"seeding instance reports state {state}")
            if torrent.get("progress", 0) >= COMPLETE_PROGRESS:
                return torrent

        if time.monotonic() >= deadline:
            raise PromotionError(f"torrent did not reach a seeding state within {timeout}s")

        sleep(interval)


def promote(intake, seeding, torrent_hash, timeout=300, sleep=time.sleep):
    """Move one torrent's registration from intake to seeding, never its data."""
    torrent = intake.torrent(torrent_hash)
    if torrent is None:
        raise PromotionError(f"{torrent_hash} is not on the intake instance")

    if seeding.torrent(torrent_hash) is not None:
        raise PromotionError(f"{torrent_hash} is already on the seeding instance")

    metainfo = intake.get("torrents/export", {"hash": torrent_hash})
    category = torrent.get("category", "")

    seeding.post_multipart(
        "torrents/add",
        add_fields(torrent, category),
        "torrents",
        f"{torrent_hash}.torrent",
        metainfo,
    )

    wait_until_seeding(seeding, torrent_hash, timeout=timeout, sleep=sleep)

    # deleteFiles must be false. The seeding instance now points at these exact
    # files, so removing them here would destroy the data both rely on.
    intake.post("torrents/delete", {"hashes": torrent_hash, "deleteFiles": "false"})

    return torrent


def main(argv=None, env=None):
    argv = sys.argv[1:] if argv is None else argv
    env = os.environ if env is None else env

    intake_url = env.get("QBIT_INTAKE_URL", "http://qbit-gen-nix.lan:8080")
    seeding_url = env.get("QBIT_SEEDING_URL", "http://qbit-lts-nix.lan:8080")

    try:
        eventtype, torrent_hash = read_event(env)
    except PromotionError as error:
        print(f"qbit-promote: {error}", file=sys.stderr)
        return 1

    if torrent_hash is None:
        print(f"qbit-promote: nothing to do for {eventtype} event")
        return 0

    try:
        torrent = promote(
            QbitClient(intake_url), QbitClient(seeding_url), torrent_hash
        )
    except PromotionError as error:
        print(f"qbit-promote: {error}; left on intake", file=sys.stderr)
        return 1

    print(f"qbit-promote: promoted {torrent.get('name', torrent_hash)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
