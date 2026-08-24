#!/usr/bin/env python3
"""Health-driven WireGuard endpoint controller for a dedicated VPN gateway."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import random
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Iterable


COOLDOWN_EXIT = 75
BUSY_EXIT = 76


def load_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return dict(default)


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


@contextlib.contextmanager
def rotation_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("rotation already in progress") from error
        yield


def prometheus_escape(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def parse_remote_command(command: str, allowed_reasons: Iterable[str]) -> str:
    try:
        words = shlex.split(command)
    except ValueError as error:
        raise ValueError("malformed command") from error
    if len(words) != 2 or words[0] != "rotate" or words[1] not in set(allowed_reasons):
        raise ValueError("command is not an allowed VPN rotation request")
    return words[1]


class SystemRunner:
    def __init__(self, config: dict[str, Any]):
        self.config = config
        self.commands = config["commands"]

    def _run(self, arguments: list[str], *, timeout: int = 30) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            arguments,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def set_endpoint(self, endpoint: dict[str, Any]) -> None:
        self._run(
            [
                self.commands["wg"],
                "set",
                self.config["interface"],
                "peer",
                self.config["peerPublicKey"],
                "endpoint",
                f'{endpoint["ip"]}:{endpoint["port"]}',
            ]
        )

    def public_ip(self) -> str:
        result = self._run(
            [
                self.commands["curl"],
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                str(self.config["probeTimeoutSeconds"]),
                "--interface",
                self.config["tunnelAddress"].split("/", 1)[0],
                self.config["publicIpUrl"],
            ],
            timeout=self.config["probeTimeoutSeconds"] + 2,
        )
        value = result.stdout.strip()
        if not value or len(value) > 64:
            raise RuntimeError("public-IP probe returned an invalid response")
        return value

    def handshake_age(self, now: int) -> int:
        result = self._run(
            [self.commands["wg"], "show", self.config["interface"], "latest-handshakes"]
        )
        for line in result.stdout.splitlines():
            peer, _, timestamp = line.partition("\t")
            if peer == self.config["peerPublicKey"] and timestamp.isdigit():
                stamp = int(timestamp)
                return max(0, now - stamp) if stamp else 2**31 - 1
        return 2**31 - 1

    def notify(self, title: str, message: str, priority: int) -> None:
        token_file = self.config.get("gotifyTokenFile")
        url = self.config.get("gotifyUrl")
        if not token_file or not url:
            return
        token = Path(token_file).read_text().strip()
        self._run(
            [
                self.commands["curl"],
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                "10",
                "-X",
                "POST",
                url,
                "-H",
                f"X-Gotify-Key: {token}",
                "-F",
                f"title={title}",
                "-F",
                f"message={message}",
                "-F",
                f"priority={priority}",
            ],
            timeout=12,
        )


class Controller:
    def __init__(
        self,
        config: dict[str, Any],
        runner: Any,
        *,
        now: Callable[[], float] = time.time,
        shuffle: Callable[[list[Any]], None] = random.SystemRandom().shuffle,
    ):
        self.config = config
        self.runner = runner
        self.now = now
        self.shuffle = shuffle
        self.state_path = Path(config["stateFile"])
        self.state = load_json(
            self.state_path,
            {
                "currentEndpoint": None,
                "currentPublicIp": None,
                "lastRotation": 0,
                "lastRotationReason": "none",
                "lastRotationStatus": "never",
                "blockedExits": {},
                "rotationCounters": {},
                "consecutiveHealthFailures": 0,
            },
        )

    def save(self) -> None:
        atomic_json(self.state_path, self.state)

    def endpoint(self, name: str | None) -> dict[str, Any] | None:
        return next((item for item in self.config["endpoints"] if item["name"] == name), None)

    def prune_blocked(self, now: int) -> None:
        self.state["blockedExits"] = {
            address: expiry
            for address, expiry in self.state.get("blockedExits", {}).items()
            if int(expiry) > now
        }

    def record(self, reason: str, status: str) -> None:
        key = f"{reason}|{status}"
        counters = self.state.setdefault("rotationCounters", {})
        counters[key] = int(counters.get(key, 0)) + 1
        self.state["lastRotationReason"] = reason
        self.state["lastRotationStatus"] = status

    def candidates(self, now: int) -> list[dict[str, Any]]:
        self.prune_blocked(now)
        current = self.state.get("currentEndpoint")
        values = [item for item in self.config["endpoints"] if item["name"] != current]
        self.shuffle(values)
        return values

    def probe(self, now: int) -> str:
        public_ip = self.runner.public_ip()
        age = self.runner.handshake_age(now)
        if age > self.config["maxHandshakeAgeSeconds"]:
            raise RuntimeError(f"WireGuard handshake is stale ({age}s)")
        return public_ip

    def rotate(self, reason: str, *, force: bool = False) -> dict[str, Any]:
        now = int(self.now())
        self.prune_blocked(now)
        if reason not in self.config["allowedReasons"]:
            raise ValueError(f"rotation reason is not allowed: {reason}")
        if not force and now - int(self.state.get("lastRotation", 0)) < self.config["cooldownSeconds"]:
            raise TimeoutError("VPN rotation is in cooldown")

        previous_endpoint = self.state.get("currentEndpoint")
        previous_public_ip = self.state.get("currentPublicIp")
        if reason == "searx-startpage-blocked" and previous_public_ip:
            self.state.setdefault("blockedExits", {})[previous_public_ip] = (
                now + self.config["blockedExitTtlSeconds"]
            )

        attempted: list[str] = []
        candidates = self.candidates(now)
        blocked = self.state.get("blockedExits", {})
        for candidate in candidates[: self.config["maxCandidateAttempts"]]:
            attempted.append(candidate["name"])
            try:
                self.runner.set_endpoint(candidate)
                public_ip = self.probe(now)
                if public_ip in blocked:
                    continue
            except (OSError, RuntimeError, subprocess.SubprocessError):
                continue

            self.state.update(
                {
                    "currentEndpoint": candidate["name"],
                    "currentPublicIp": public_ip,
                    "lastRotation": now,
                    "consecutiveHealthFailures": 0,
                }
            )
            self.record(reason, "success")
            self.save()
            with contextlib.suppress(Exception):
                self.runner.notify(
                    "VPN egress rotated",
                    f'{reason}: now using {candidate["name"]} ({public_ip})',
                    3,
                )
            return {"endpoint": candidate["name"], "publicIp": public_ip, "attempted": attempted}

        previous = self.endpoint(previous_endpoint)
        if previous is not None:
            with contextlib.suppress(Exception):
                self.runner.set_endpoint(previous)
        self.state["lastRotation"] = now
        self.record(reason, "failed")
        self.save()
        with contextlib.suppress(Exception):
            self.runner.notify(
                "VPN egress rotation failed",
                f'{reason}: no verified endpoint after trying {", ".join(attempted) or "none"}; restored {previous_endpoint or "no endpoint"}',
                8,
            )
        raise RuntimeError("no VPN endpoint passed health checks")

    def ensure(self) -> dict[str, Any]:
        now = int(self.now())
        current = self.endpoint(self.state.get("currentEndpoint")) or self.config["endpoints"][0]
        self.runner.set_endpoint(current)
        try:
            public_ip = self.probe(now)
            if public_ip in self.state.get("blockedExits", {}):
                raise RuntimeError("current public IP is temporarily blocked")
            self.state.update(
                {
                    "currentEndpoint": current["name"],
                    "currentPublicIp": public_ip,
                    "consecutiveHealthFailures": 0,
                }
            )
            self.save()
            return {"endpoint": current["name"], "publicIp": public_ip}
        except (OSError, RuntimeError, subprocess.SubprocessError):
            return self.rotate("tunnel-unhealthy", force=True)

    def health(self) -> bool:
        now = int(self.now())
        try:
            public_ip = self.probe(now)
            if public_ip in self.state.get("blockedExits", {}):
                raise RuntimeError("current public IP is temporarily blocked")
            self.state["currentPublicIp"] = public_ip
            self.state["consecutiveHealthFailures"] = 0
            self.save()
            return True
        except (OSError, RuntimeError, subprocess.SubprocessError):
            failures = int(self.state.get("consecutiveHealthFailures", 0)) + 1
            self.state["consecutiveHealthFailures"] = failures
            self.save()
            if failures >= self.config["healthFailuresBeforeRotation"]:
                try:
                    self.rotate("tunnel-unhealthy")
                except TimeoutError:
                    pass
                except RuntimeError:
                    with contextlib.suppress(Exception):
                        self.runner.notify(
                            "VPN leak prevention active",
                            "The tunnel is unhealthy; client Internet traffic remains blackholed.",
                            8,
                        )
            return False

    def metrics(self) -> str:
        now = int(self.now())
        self.prune_blocked(now)
        try:
            handshake_age = self.runner.handshake_age(now)
        except Exception:
            handshake_age = 2**31 - 1
        tunnel_up = int(
            bool(self.state.get("currentPublicIp"))
            and handshake_age <= self.config["maxHandshakeAgeSeconds"]
            and int(self.state.get("consecutiveHealthFailures", 0)) == 0
        )
        endpoint = prometheus_escape(self.state.get("currentEndpoint") or "none")
        public_ip = prometheus_escape(self.state.get("currentPublicIp") or "unknown")
        cooldown = max(
            0,
            int(self.state.get("lastRotation", 0)) + self.config["cooldownSeconds"] - now,
        )
        lines = [
            "# HELP vpn_egress_tunnel_up Whether the VPN tunnel passed its latest health check.",
            "# TYPE vpn_egress_tunnel_up gauge",
            f"vpn_egress_tunnel_up {tunnel_up}",
            f"vpn_egress_handshake_age_seconds {handshake_age}",
            f'vpn_egress_info{{endpoint="{endpoint}",public_ip="{public_ip}"}} 1',
            f'vpn_egress_last_rotation_timestamp_seconds {int(self.state.get("lastRotation", 0))}',
            f"vpn_egress_blocked_exit_ips {len(self.state.get('blockedExits', {}))}",
            f"vpn_egress_cooldown_remaining_seconds {cooldown}",
            f"vpn_egress_consecutive_health_failures {int(self.state.get('consecutiveHealthFailures', 0))}",
        ]
        for key, value in sorted(self.state.get("rotationCounters", {}).items()):
            reason, _, status = key.partition("|")
            lines.append(
                f'vpn_egress_rotations_total{{reason="{prometheus_escape(reason)}",status="{prometheus_escape(status)}"}} {int(value)}'
            )
        return "\n".join(lines) + "\n"


def write_metrics(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    subparsers = parser.add_subparsers(dest="action", required=True)
    rotate = subparsers.add_parser("rotate")
    rotate.add_argument("--reason", required=True)
    subparsers.add_parser("ensure")
    subparsers.add_parser("health")
    metrics = subparsers.add_parser("metrics")
    metrics.add_argument("--output", required=True, type=Path)
    remote = subparsers.add_parser("remote")
    remote.add_argument("--command", default=os.environ.get("SSH_ORIGINAL_COMMAND", ""))
    remote.add_argument("--allowed-reason", action="append", default=[])
    args = parser.parse_args(argv)

    config = json.loads(args.config.read_text())
    controller = Controller(config, SystemRunner(config))
    lock_path = Path(config["lockFile"])
    try:
        if args.action == "metrics":
            write_metrics(args.output, controller.metrics())
            return 0
        if args.action == "health":
            return 0 if controller.health() else 1
        reason = args.reason if args.action == "rotate" else None
        if args.action == "remote":
            allowed_reasons = args.allowed_reason or config.get("remoteAllowedReasons", [])
            reason = parse_remote_command(args.command, allowed_reasons)
        with rotation_lock(lock_path):
            if args.action == "ensure":
                result = controller.ensure()
            else:
                result = controller.rotate(reason)
        print(json.dumps(result, sort_keys=True))
        return 0
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        return COOLDOWN_EXIT
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return BUSY_EXIT if "already in progress" in str(error) else 1
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 64


if __name__ == "__main__":
    raise SystemExit(main())
