#!/usr/bin/env python3

import tempfile
import unittest
from pathlib import Path

from controller import (
    BASE_PORT_IF_INDEX,
    BRIDGE_FDB_PORT,
    IF_HIGH_SPEED,
    IF_NAME,
    IF_OPER_STATUS,
    Q_BRIDGE_FDB_PORT,
    Port,
    ShaperError,
    learned_macs,
    parse_walk,
    plan,
    remember,
    sync,
    tc_commands,
)

ROUTER = "02:c9:07:cb:e2:47"
CUBE = "90:82:c3:6b:8e:69"
PHONE = "aa:bb:cc:00:00:01"
MODEM = "aa:bb:cc:00:00:99"

PORTS = {
    1: Port(1, "g1", 1000, True),
    2: Port(2, "g2", 1000, True),
    3: Port(3, "g3", 1000, False),
    6: Port(6, "mg6", 2500, True),
    10: Port(10, "xg10", 10000, True),
}


def mac_oid(mac):
    return ".".join(str(int(part, 16)) for part in mac.split(":"))


def walks(fdb):
    """snmpbulkwalk output per subtree for the PORTS layout and a MAC -> port table."""
    return {
        IF_NAME: "\n".join(f".{IF_NAME}.{i} \"{p.name}\"" for i, p in PORTS.items()),
        IF_HIGH_SPEED: "\n".join(f".{IF_HIGH_SPEED}.{i} {p.speed}" for i, p in PORTS.items()),
        IF_OPER_STATUS: "\n".join(
            f".{IF_OPER_STATUS}.{i} {1 if p.up else 2}" for i, p in PORTS.items()
        ),
        BASE_PORT_IF_INDEX: "\n".join(f".{BASE_PORT_IF_INDEX}.{i} {i}" for i in PORTS),
        Q_BRIDGE_FDB_PORT: "\n".join(
            f".{Q_BRIDGE_FDB_PORT}.1.{mac_oid(mac)} {port}" for mac, port in fdb.items()
        ),
        BRIDGE_FDB_PORT: "",
    }


class FakeSystem:
    def __init__(self, fdb):
        self.outputs = walks(fdb)
        self.applied = []
        self.teardowns = 0
        self.rules_present = False
        self.fail_apply = False

    def walk(self, base):
        return parse_walk(self.outputs[base], base)

    def router_macs(self, interfaces):
        return {ROUTER}

    def ensure_ifb(self, ifb):
        pass

    def in_place(self, interfaces, ifb):
        return self.rules_present

    def teardown(self, interfaces, ifb):
        self.teardowns += 1
        self.rules_present = False

    def apply(self, commands):
        if self.fail_apply:
            raise ShaperError("tc failed")
        self.applied.append(commands)
        self.rules_present = True


CONFIG = {"interfaces": ["eth0", "trusted"], "ifb": "lanshape", "headroom": 0.95, "macTtlSeconds": 86400}


class ParseTests(unittest.TestCase):
    def test_parse_walk_strips_quotes_and_skips_missing_objects(self):
        output = (
            f'.{IF_NAME}.1 "g1"\n'
            f".{IF_NAME}.10 xg10\n"
            f".{Q_BRIDGE_FDB_PORT} No Such Object available on this agent at this OID\n"
        )
        self.assertEqual(parse_walk(output, IF_NAME), {(1,): "g1", (10,): "xg10"})

    def test_learned_macs_maps_base_ports_to_if_index(self):
        q_bridge = {(1, 144, 130, 195, 107, 142, 105): "5", (1, 0, 0, 0, 0, 0, 1): "0"}
        self.assertEqual(learned_macs(q_bridge, {}, {(5,): "1"}), {CUBE: 1})

    def test_learned_macs_falls_back_to_bridge_mib(self):
        bridge = {(144, 130, 195, 107, 142, 105): "2"}
        self.assertEqual(learned_macs({}, bridge, {}), {CUBE: 2})


class PlanTests(unittest.TestCase):
    def test_shapes_only_ports_slower_than_the_uplink(self):
        macs = {ROUTER: 10, CUBE: 1, PHONE: 2, MODEM: 6, "aa:bb:cc:00:00:03": 3}
        shaped = plan(PORTS, macs, {ROUTER}, 0.95)
        self.assertEqual(
            [(p.name, p.rate_kbit, p.macs) for p in shaped],
            [("g1", 950000, (CUBE,)), ("g2", 950000, (PHONE,)), ("mg6", 2375000, (MODEM,))],
        )
        self.assertEqual(shaped[0].classid, "1:101")

    def test_skips_ports_without_clients(self):
        self.assertEqual(plan(PORTS, {ROUTER: 10}, {ROUTER}, 0.95), [])

    def test_missing_uplink_is_an_error(self):
        with self.assertRaises(ShaperError):
            plan(PORTS, {CUBE: 1}, {ROUTER}, 0.95)

    def test_remember_keeps_idle_macs_until_ttl(self):
        previous = {CUBE: {"port": 1, "seen": 0}, PHONE: {"port": 2, "seen": 950}}
        merged = remember(previous, {ROUTER: 10}, now=1000, ttl=100)
        self.assertEqual(sorted(merged), sorted([PHONE, ROUTER]))

    def test_tc_commands_redirect_every_shaped_mac_on_every_interface(self):
        shaped = plan(PORTS, {ROUTER: 10, CUBE: 1}, {ROUTER}, 0.95)
        lines = tc_commands(shaped, ["eth0", "trusted"], "lanshape")
        self.assertIn(
            "class add dev lanshape parent 1: classid 1:101 htb rate 950000kbit ceil 950000kbit quantum 60000",
            lines,
        )
        redirects = [line for line in lines if "mirred" in line]
        self.assertEqual(len(redirects), 2)
        self.assertTrue(all(f"dst_mac {CUBE}" in line for line in redirects))


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.state = Path(self.directory.name)
        self.logs = []

    def tearDown(self):
        self.directory.cleanup()

    def run_sync(self, system, now=1000):
        sync(system, CONFIG, self.state, now, self.logs.append)

    def test_applies_once_then_leaves_matching_rules_alone(self):
        system = FakeSystem({ROUTER: 10, CUBE: 1})
        self.run_sync(system)
        self.run_sync(system, now=1060)
        self.assertEqual(len(system.applied), 1)
        self.assertEqual(self.logs, ["applied: g1 1000M -> 950mbit (1 MACs)"])

    def test_reapplies_when_rules_disappear(self):
        system = FakeSystem({ROUTER: 10, CUBE: 1})
        self.run_sync(system)
        system.rules_present = False
        self.run_sync(system, now=1060)
        self.assertEqual(len(system.applied), 2)

    def test_idle_client_stays_shaped_after_aging_out_of_the_switch(self):
        system = FakeSystem({ROUTER: 10, CUBE: 1})
        self.run_sync(system)
        system.outputs = walks({ROUTER: 10})
        self.run_sync(system, now=1060)
        self.assertEqual(len(system.applied), 1)

    def test_failed_apply_fails_open(self):
        system = FakeSystem({ROUTER: 10, CUBE: 1})
        system.fail_apply = True
        with self.assertRaises(ShaperError):
            self.run_sync(system)
        self.assertEqual(system.teardowns, 2)
        self.assertFalse((self.state / "applied").exists())

    def test_nothing_to_shape_tears_down_once(self):
        system = FakeSystem({ROUTER: 10})
        self.run_sync(system)
        self.run_sync(system, now=1060)
        self.assertEqual(system.teardowns, 1)
        self.assertEqual(system.applied, [])


if __name__ == "__main__":
    unittest.main()
