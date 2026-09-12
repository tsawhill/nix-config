#!/usr/bin/env python3
"""Tray applet for switching between the host's AirVPN NetworkManager profiles.

Every selected AirVPN server is its own NetworkManager profile sharing one
WireGuard interface, so switching is an unprivileged `nmcli connection up` for
anyone in the networkmanager group. Nothing here needs root.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import threading
import urllib.request
from pathlib import Path
from typing import Any

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")

from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
from gi.repository import GLib, Gtk  # noqa: E402


# Explicit packaged PNGs avoid missing theme names and low-contrast symbolic icons.
ICON_DIR = Path(__file__).resolve().parent.parent / "share/airvpn-tray/icons"
ICONS = {
    state: str(ICON_DIR / f"{state}.png")
    for state in ("connected", "switching", "disconnected", "error")
}

POLL_SECONDS = 5
ACTIVATION_TIMEOUT = 15


class Tray:
    def __init__(self, config: dict[str, Any]):
        self.config = config
        self.nmcli = config["commands"]["nmcli"]
        self.interface = config["interface"]
        self.exit_ip_url = config.get("publicIpUrl")
        self.endpoints = sorted(
            config["endpoints"], key=lambda item: (item["country"], item["city"], item["name"])
        )
        self.by_id = {item["connectionId"]: item for item in self.endpoints}

        self.current: str | None = None
        self.exit_ip: str | None = None
        self.error: str | None = None
        self.pending = ""
        self.busy = False
        # Guards the programmatic set_active() in render() from being taken for
        # a click and starting a switch of its own.
        self.updating = False
        self.items: dict[str, Gtk.CheckMenuItem] = {}

        self.indicator = AppIndicator.Indicator.new(
            "airvpn-tray",
            ICONS["disconnected"],
            AppIndicator.IndicatorCategory.SYSTEM_SERVICES,
        )
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.indicator.set_menu(self.build_menu())

        self.refresh()
        GLib.timeout_add_seconds(POLL_SECONDS, self.on_poll)

    # --- shell out ---

    def run(self, arguments: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            arguments,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def active_connection_id(self) -> str | None:
        try:
            result = self.run(
                [self.nmcli, "--terse", "--fields", "NAME,DEVICE", "connection", "show", "--active"]
            )
        except (OSError, subprocess.SubprocessError):
            return None
        for line in result.stdout.splitlines():
            name, _, device = line.rpartition(":")
            if device == self.interface and name in self.by_id:
                return name
        return None

    # --- menu ---

    def build_menu(self) -> Gtk.Menu:
        menu = Gtk.Menu()

        self.status_item = Gtk.MenuItem(label="AirVPN")
        self.status_item.set_sensitive(False)
        menu.append(self.status_item)

        self.exit_item = Gtk.MenuItem(label="Exit IP: unknown")
        self.exit_item.set_sensitive(False)
        menu.append(self.exit_item)

        menu.append(Gtk.SeparatorMenuItem())

        for endpoint in self.endpoints:
            item = Gtk.CheckMenuItem(label=self.describe(endpoint))
            item.set_draw_as_radio(True)
            item.connect("toggled", self.on_select, endpoint)
            self.items[endpoint["connectionId"]] = item
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        self.disconnect_item = Gtk.MenuItem(label="Disconnect")
        self.disconnect_item.connect("activate", self.on_disconnect)
        menu.append(self.disconnect_item)

        refresh_item = Gtk.MenuItem(label="Refresh")
        refresh_item.connect("activate", lambda _item: self.refresh())
        menu.append(refresh_item)

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda _item: Gtk.main_quit())
        menu.append(quit_item)

        menu.show_all()
        return menu

    def describe(self, endpoint: dict[str, Any]) -> str:
        return f'{endpoint["name"]} — {endpoint["city"]}, {endpoint["country"]}'

    # --- state ---

    def refresh(self, probe: bool = False) -> None:
        current = self.active_connection_id()
        if current != self.current or probe:
            self.current = current
            self.error = None
            self.request_exit_ip()
        self.render()

    def render(self) -> None:
        endpoint = self.by_id.get(self.current) if self.current else None

        if self.busy:
            state = "switching"
        elif self.error is not None:
            state = "error"
        elif endpoint is not None:
            state = "connected"
        else:
            state = "disconnected"

        if self.busy:
            summary = self.pending
        elif self.error is not None:
            summary = self.error
        elif endpoint is not None:
            summary = self.describe(endpoint)
        else:
            summary = "Disconnected"

        self.indicator.set_icon_full(ICONS[state], f"AirVPN: {summary}")
        self.indicator.set_title(f"AirVPN: {summary}")
        self.status_item.set_label(summary)
        self.exit_item.set_label(f"Exit IP: {self.exit_ip or 'unknown'}")
        self.disconnect_item.set_sensitive(endpoint is not None and not self.busy)

        self.updating = True
        for connection_id, item in self.items.items():
            item.set_active(connection_id == self.current)
            item.set_sensitive(not self.busy)
        self.updating = False

    def on_poll(self) -> bool:
        if not self.busy:
            self.refresh()
        return True

    # --- actions ---

    def on_select(self, item: Gtk.CheckMenuItem, endpoint: dict[str, Any]) -> None:
        if self.updating or self.busy or not item.get_active():
            return
        if endpoint["connectionId"] == self.current:
            return
        self.start(
            f'Connecting to {endpoint["name"]}…',
            [self.nmcli, "--wait", str(ACTIVATION_TIMEOUT), "connection", "up", "id", endpoint["connectionId"]],
            f'Could not connect to {endpoint["name"]}',
        )

    def on_disconnect(self, _item: Gtk.MenuItem) -> None:
        if self.busy or self.current is None:
            return
        self.start(
            "Disconnecting…",
            [self.nmcli, "connection", "down", "id", self.current],
            "Could not disconnect",
        )

    def start(self, label: str, command: list[str], failure: str) -> None:
        self.busy = True
        self.error = None
        self.pending = label
        self.render()
        threading.Thread(
            target=self.worker, args=(command, failure), daemon=True
        ).start()

    def worker(self, command: list[str], failure: str) -> None:
        try:
            self.run(command, timeout=ACTIVATION_TIMEOUT + 5)
            message = None
        except (OSError, subprocess.SubprocessError):
            message = failure
        GLib.idle_add(self.finish, message)

    def finish(self, message: str | None) -> bool:
        self.busy = False
        self.error = message
        # On failure the error stays visible until the active profile actually
        # changes, so a failed switch cannot be silently erased by the next poll.
        self.refresh(probe=message is None)
        return False

    # --- exit IP ---

    def request_exit_ip(self) -> None:
        if not self.exit_ip_url:
            return
        self.exit_ip = None
        threading.Thread(target=self.exit_ip_worker, daemon=True).start()

    def exit_ip_worker(self) -> None:
        value = None
        try:
            with urllib.request.urlopen(self.exit_ip_url, timeout=10) as response:
                candidate = response.read(64).decode("utf-8", "replace").strip()
            if candidate:
                value = candidate
        except Exception:
            value = None
        GLib.idle_add(self.exit_ip_done, value)

    def exit_ip_done(self, value: str | None) -> bool:
        self.exit_ip = value
        self.render()
        return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    arguments = parser.parse_args()

    Tray(json.loads(arguments.config.read_text()))
    Gtk.main()


if __name__ == "__main__":
    main()
