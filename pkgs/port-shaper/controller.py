#!/usr/bin/env python3
"""Shape router egress toward each switch port slower than the uplink, learned over SNMP.

A 10G uplink feeding a 1G access port overflows the switch's small buffers on bursty
WAN traffic. Queueing that traffic here at the port's speed keeps the switch from dropping it.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

IF_NAME = "1.3.6.1.2.1.31.1.1.1.1"
IF_HIGH_SPEED = "1.3.6.1.2.1.31.1.1.1.15"
IF_OPER_STATUS = "1.3.6.1.2.1.2.2.1.8"
BASE_PORT_IF_INDEX = "1.3.6.1.2.1.17.1.4.1.2"
Q_BRIDGE_FDB_PORT = "1.3.6.1.2.1.17.7.1.2.2.1.2"
BRIDGE_FDB_PORT = "1.3.6.1.2.1.17.4.3.1.2"

OPER_UP = "1"
CLASS_BASE = 0x100
HTB_QUANTUM = 60000


class ShaperError(Exception):
    pass


@dataclass(frozen=True)
class Port:
    index: int
    name: str
    speed: int
    up: bool


@dataclass(frozen=True)
class ShapedPort:
    name: str
    speed: int
    classid: str
    rate_kbit: int
    macs: tuple[str, ...]


def parse_walk(output: str, base: str) -> dict[tuple[int, ...], str]:
    """OID suffix under `base` -> value, from `snmpbulkwalk -On -Oq -Oe` output."""
    prefix = f".{base}."
    rows: dict[tuple[int, ...], str] = {}
    for line in output.splitlines():
        oid, _, value = line.strip().partition(" ")
        if not oid.startswith(prefix):
            continue
        try:
            suffix = tuple(int(part) for part in oid[len(prefix) :].split("."))
        except ValueError:
            continue
        rows[suffix] = value.strip().strip('"')
    return rows


def build_ports(
    names: dict[tuple[int, ...], str],
    speeds: dict[tuple[int, ...], str],
    statuses: dict[tuple[int, ...], str],
) -> dict[int, Port]:
    ports = {}
    for suffix, speed in speeds.items():
        if len(suffix) != 1 or not speed.isdigit():
            continue
        index = suffix[0]
        ports[index] = Port(
            index=index,
            name=names.get(suffix, str(index)),
            speed=int(speed),
            up=statuses.get(suffix) == OPER_UP,
        )
    return ports


def format_mac(octets: tuple[int, ...]) -> str:
    return ":".join(f"{octet:02x}" for octet in octets)


def learned_macs(
    q_bridge: dict[tuple[int, ...], str],
    bridge: dict[tuple[int, ...], str],
    base_ports: dict[tuple[int, ...], str],
) -> dict[str, int]:
    """MAC -> ifIndex from the forwarding table, preferring the VLAN-aware Q-BRIDGE view."""
    rows = [(suffix[1:], value) for suffix, value in q_bridge.items() if len(suffix) == 7]
    if not rows:
        rows = [(suffix, value) for suffix, value in bridge.items() if len(suffix) == 6]
    learned = {}
    for octets, value in rows:
        if not value.isdigit() or int(value) == 0:
            continue
        base_port = int(value)
        if_index = base_ports.get((base_port,), str(base_port))
        learned[format_mac(octets)] = int(if_index)
    return learned


def remember(
    previous: dict[str, dict], learned: dict[str, int], now: float, ttl: float
) -> dict[str, dict]:
    """Keep MACs that aged out of the switch table, so idle clients stay shaped."""
    merged = {
        mac: entry for mac, entry in previous.items() if now - entry.get("seen", 0) < ttl
    }
    for mac, index in learned.items():
        merged[mac] = {"port": index, "seen": now}
    return merged


def plan(
    ports: dict[int, Port],
    mac_ports: dict[str, int],
    router_macs: set[str],
    headroom: float,
) -> list[ShapedPort]:
    uplinks = {mac_ports[mac] for mac in router_macs if mac in mac_ports}
    if not uplinks:
        raise ShaperError("none of the router's MACs are in the switch's forwarding table")
    uplink_speeds = [ports[index].speed for index in uplinks if index in ports]
    if not uplink_speeds:
        raise ShaperError(f"uplink port(s) {sorted(uplinks)} missing from the interface table")
    uplink_speed = max(uplink_speeds)

    shaped = []
    for index, port in sorted(ports.items()):
        if index in uplinks or not port.up or not 0 < port.speed < uplink_speed:
            continue
        macs = tuple(
            sorted(
                mac
                for mac, where in mac_ports.items()
                if where == index and mac not in router_macs
            )
        )
        if not macs:
            continue
        shaped.append(
            ShapedPort(
                name=port.name,
                speed=port.speed,
                classid=f"1:{CLASS_BASE + index:x}",
                rate_kbit=int(port.speed * 1000 * headroom),
                macs=macs,
            )
        )
    return shaped


def tc_commands(shaped: list[ShapedPort], interfaces: list[str], ifb: str) -> list[str]:
    lines = [f"qdisc add dev {ifb} root handle 1: htb"]
    for port in shaped:
        rate = f"{port.rate_kbit}kbit"
        lines.append(
            f"class add dev {ifb} parent 1: classid {port.classid} "
            f"htb rate {rate} ceil {rate} quantum {HTB_QUANTUM}"
        )
        lines.append(f"qdisc add dev {ifb} parent {port.classid} fq_codel")
    for interface in interfaces:
        lines.append(f"qdisc add dev {interface} clsact")
        for port in shaped:
            for mac in port.macs:
                lines.append(
                    f"filter add dev {interface} egress protocol all prio 1 "
                    f"flower dst_mac {mac} "
                    f"action skbedit priority {port.classid} "
                    f"action mirred egress redirect dev {ifb}"
                )
    return lines


def signature(shaped: list[ShapedPort], interfaces: list[str]) -> str:
    return json.dumps(
        {
            "interfaces": interfaces,
            "ports": [[p.name, p.classid, p.rate_kbit, list(p.macs)] for p in shaped],
        },
        sort_keys=True,
    )


class System:
    """Everything that touches the switch or the kernel."""

    def __init__(self, switch: str, snmp_env: dict[str, str]):
        self.switch = switch
        self.snmp_env = snmp_env

    def walk(self, base: str) -> dict[tuple[int, ...], str]:
        result = subprocess.run(
            ["snmpbulkwalk", "-On", "-Oq", "-Oe", "-t", "3", "-r", "2", self.switch, base],
            capture_output=True,
            text=True,
            env=self.snmp_env,
            check=False,
        )
        if result.returncode != 0:
            raise ShaperError(f"snmpbulkwalk {base} failed: {result.stderr.strip()}")
        return parse_walk(result.stdout, base)

    def router_macs(self, interfaces: list[str]) -> set[str]:
        return {
            Path(f"/sys/class/net/{name}/address").read_text().strip().lower()
            for name in interfaces
            if Path(f"/sys/class/net/{name}").exists()
        }

    def run(self, *args: str, check: bool = True, stdin: str | None = None) -> str:
        result = subprocess.run(
            list(args), input=stdin, capture_output=True, text=True, check=False
        )
        if check and result.returncode != 0:
            raise ShaperError(f"{' '.join(args)} failed: {result.stderr.strip()}")
        return result.stdout

    def ensure_ifb(self, ifb: str) -> None:
        if not Path(f"/sys/class/net/{ifb}").exists():
            self.run("ip", "link", "add", ifb, "type", "ifb")
        self.run("ip", "link", "set", ifb, "up")

    def in_place(self, interfaces: list[str], ifb: str) -> bool:
        if "htb 1:" not in self.run("tc", "qdisc", "show", "dev", ifb, check=False):
            return False
        return all(
            "clsact" in self.run("tc", "qdisc", "show", "dev", name, check=False)
            for name in interfaces
        )

    def teardown(self, interfaces: list[str], ifb: str) -> None:
        for name in interfaces:
            self.run("tc", "qdisc", "del", "dev", name, "clsact", check=False)
        self.run("tc", "qdisc", "del", "dev", ifb, "root", check=False)

    def apply(self, commands: list[str]) -> None:
        self.run("tc", "-batch", "-", stdin="\n".join(commands) + "\n")


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def atomic_write(path: Path, text: str) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w") as handle:
        handle.write(text)
    os.replace(temporary, path)


def discover(system: System, config: dict, state_dir: Path, now: float) -> list[ShapedPort]:
    ports = build_ports(
        system.walk(IF_NAME), system.walk(IF_HIGH_SPEED), system.walk(IF_OPER_STATUS)
    )
    q_bridge = system.walk(Q_BRIDGE_FDB_PORT)
    bridge = {} if q_bridge else system.walk(BRIDGE_FDB_PORT)
    learned = learned_macs(q_bridge, bridge, system.walk(BASE_PORT_IF_INDEX))
    if not learned:
        raise ShaperError("the switch returned an empty forwarding table")

    macs_file = state_dir / "macs.json"
    remembered = remember(load_json(macs_file, {}), learned, now, config["macTtlSeconds"])
    atomic_write(macs_file, json.dumps(remembered, sort_keys=True))

    mac_ports = {mac: entry["port"] for mac, entry in remembered.items()}
    return plan(
        ports, mac_ports, system.router_macs(config["interfaces"]), config["headroom"]
    )


def describe(shaped: list[ShapedPort]) -> str:
    if not shaped:
        return "no ports slower than the uplink have clients; nothing shaped"
    return "; ".join(
        f"{p.name} {p.speed}M -> {p.rate_kbit // 1000}mbit ({len(p.macs)} MACs)"
        for p in shaped
    )


def sync(system: System, config: dict, state_dir: Path, now: float, log: Callable) -> None:
    interfaces, ifb = config["interfaces"], config["ifb"]
    shaped = discover(system, config, state_dir, now)

    applied_file = state_dir / "applied"
    wanted = signature(shaped, interfaces)
    current = applied_file.read_text() if applied_file.exists() else ""
    # Rules vanish when the container restarts, so check the kernel and not only the record.
    if wanted == current and (not shaped or system.in_place(interfaces, ifb)):
        return

    system.teardown(interfaces, ifb)
    if shaped:
        try:
            system.ensure_ifb(ifb)
            system.apply(tc_commands(shaped, interfaces, ifb))
        except ShaperError:
            # Fail open: unshaped traffic still flows, half-built redirects might not.
            system.teardown(interfaces, ifb)
            applied_file.unlink(missing_ok=True)
            raise
    atomic_write(applied_file, wanted)
    log(f"applied: {describe(shaped)}")


def snmp_environment(state_dir: Path) -> dict[str, str]:
    credentials = os.environ.get("CREDENTIALS_DIRECTORY")
    if not credentials or not (Path(credentials) / "snmp.conf").exists():
        raise ShaperError("snmp.conf credential missing; set LoadCredential=snmp.conf:...")
    env = dict(os.environ)
    env["SNMPCONFPATH"] = credentials
    env["SNMP_PERSISTENT_DIR"] = str(state_dir / "net-snmp")
    return env


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--state-dir", type=Path, default=Path("/var/lib/port-shaper"))
    parser.add_argument("command", choices=["sync", "plan", "clear"])
    args = parser.parse_args()

    config = json.loads(args.config.read_text())
    args.state_dir.mkdir(parents=True, exist_ok=True)
    try:
        if args.command == "clear":
            system = System(config["switch"], {})
            system.teardown(config["interfaces"], config["ifb"])
            system.run("ip", "link", "del", config["ifb"], check=False)
            (args.state_dir / "applied").unlink(missing_ok=True)
            return 0
        system = System(config["switch"], snmp_environment(args.state_dir))
        if args.command == "plan":
            shaped = discover(system, config, args.state_dir, time.time())
            print(describe(shaped))
            for line in tc_commands(shaped, config["interfaces"], config["ifb"]):
                print(f"  tc {line}")
            return 0
        sync(system, config, args.state_dir, time.time(), print)
    except ShaperError as error:
        print(f"port-shaper: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
