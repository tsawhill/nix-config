#!/usr/bin/env python3
"""Watch SearxNG logs and remediate Startpage blocks through the VPN gateway."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable


STARTPAGE_BLOCK = re.compile(
    r"(?is)(startpage.*(?:captcha|access denied|blocked|forbidden|status[_ ]?code.?403)|(?:captcha|access denied|blocked|forbidden).*startpage)"
)


def is_startpage_block(message: str) -> bool:
    return bool(STARTPAGE_BLOCK.search(message))


def load_state(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            "cursor": None,
            "blocked": 0,
            "backoffUntil": 0,
            "lastRemediationSuccess": 1,
            "rotationRequests": 0,
            "restarts": 0,
        }


def save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(state, handle, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


def render_metrics(state: dict[str, Any], now: int) -> str:
    backoff = int(int(state.get("backoffUntil", 0)) > now)
    return "\n".join(
        [
            f"searx_vpn_startpage_blocked {int(state.get('blocked', 0))}",
            f"searx_vpn_backoff_active {backoff}",
            f"searx_vpn_last_remediation_success {int(state.get('lastRemediationSuccess', 0))}",
            f"searx_vpn_rotation_requests_total {int(state.get('rotationRequests', 0))}",
            f"searx_vpn_restarts_total {int(state.get('restarts', 0))}",
        ]
    ) + "\n"


class Watchdog:
    def __init__(
        self,
        config: dict[str, Any],
        state: dict[str, Any],
        *,
        run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        sleep: Callable[[float], None] = time.sleep,
        now: Callable[[], float] = time.time,
        canary: Callable[[], bool] | None = None,
        persist: Callable[[dict[str, Any]], None] | None = None,
    ):
        self.config = config
        self.state = state
        self.run = run
        self.sleep = sleep
        self.now = now
        self.canary = canary or self._canary
        self.persist = persist or (lambda _state: None)

    def _canary(self) -> bool:
        query = urllib.parse.urlencode(
            {"q": "nixos", "engines": "startpage", "language": "en-US"}
        )
        request = urllib.request.Request(f'{self.config["canaryUrl"]}?{query}')
        try:
            with urllib.request.urlopen(request, timeout=self.config["canaryTimeoutSeconds"]) as response:
                body = response.read(1024 * 1024).decode("utf-8", "replace")
            return response.status == 200 and not is_startpage_block(body)
        except (OSError, TimeoutError):
            return False

    def request_rotation(self) -> int:
        self.state["rotationRequests"] = int(self.state.get("rotationRequests", 0)) + 1
        self.persist(self.state)
        try:
            result = self.run(
                [
                    self.config["ssh"],
                    "-i",
                    self.config["identityFile"],
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=10",
                    self.config["gateway"],
                    "rotate searx-startpage-blocked",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.config["rotationTimeoutSeconds"],
            )
            return result.returncode
        except (OSError, subprocess.SubprocessError):
            return 1

    def remediate(self) -> bool:
        now = int(self.now())
        if int(self.state.get("backoffUntil", 0)) > now:
            return False
        self.state["blocked"] = 1
        self.persist(self.state)
        for attempt in range(self.config["incidentAttempts"]):
            if attempt:
                self.sleep(self.config["cooldownSeconds"])
            result = self.request_rotation()
            if result == 75:
                self.sleep(self.config["cooldownSeconds"])
                result = self.request_rotation()
            if result != 0:
                continue
            self.run([self.config["systemctl"], "restart", "searx.service"], check=False)
            self.state["restarts"] = int(self.state.get("restarts", 0)) + 1
            self.sleep(self.config["restartSettleSeconds"])
            if self.canary():
                self.state.update(
                    {
                        "blocked": 0,
                        "backoffUntil": 0,
                        "lastRemediationSuccess": 1,
                    }
                )
                self.persist(self.state)
                return True
        self.state.update(
            {
                "blocked": 1,
                "backoffUntil": int(self.now()) + self.config["incidentBackoffSeconds"],
                "lastRemediationSuccess": 0,
            }
        )
        self.persist(self.state)
        return False


def write_metrics(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(content)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    state_path = Path(config["stateFile"])
    metrics_path = Path(config["metricsFile"])
    state = load_state(state_path)

    def persist(current: dict[str, Any]) -> None:
        save_state(state_path, current)
        write_metrics(metrics_path, render_metrics(current, int(time.time())))

    watchdog = Watchdog(config, state, persist=persist)
    persist(state)

    command = [config["journalctl"], "--follow", "--output=json", "--unit=searx.service"]
    if state.get("cursor"):
        command.append(f'--after-cursor={state["cursor"]}')
    else:
        command.extend(["--since", "now"])

    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE)
    assert process.stdout is not None
    for line in process.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        state["cursor"] = event.get("__CURSOR", state.get("cursor"))
        if is_startpage_block(str(event.get("MESSAGE", ""))):
            watchdog.remediate()
        save_state(state_path, state)
        write_metrics(metrics_path, render_metrics(state, int(time.time())))
    return process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
