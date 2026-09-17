#!/usr/bin/env python3

import fcntl
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from controller import Controller, SystemRunner, parse_remote_command, rotation_lock
from dns_recovery import recover, query
from searx_watchdog import Watchdog, is_startpage_block, render_metrics


class Runner:
    def __init__(self, outcomes=None):
        self.outcomes = outcomes or {}
        self.current = None
        self.set_calls = []
        self.notifications = []

    def set_endpoint(self, endpoint):
        self.current = endpoint["name"]
        self.set_calls.append(self.current)

    def public_ip(self):
        outcome = self.outcomes.get(self.current, f"203.0.113.{len(self.set_calls)}")
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    def handshake_age(self, _now):
        return 5

    def notify(self, *args):
        self.notifications.append(args)


def config(directory):
    return {
        "stateFile": str(Path(directory) / "state.json"),
        "lockFile": str(Path(directory) / "lock"),
        "endpoints": [
            {
                "name": "one",
                "ip": "192.0.2.1",
                "port": 1637,
                "connectionId": "wg-airvpn-one",
            },
            {
                "name": "two",
                "ip": "192.0.2.2",
                "port": 1637,
                "connectionId": "wg-airvpn-two",
            },
            {
                "name": "three",
                "ip": "192.0.2.3",
                "port": 1637,
                "connectionId": "wg-airvpn-three",
            },
        ],
        "allowedReasons": ["startup", "tunnel-unhealthy", "searx-startpage-blocked"],
        "remoteAllowedReasons": ["searx-startpage-blocked"],
        "blockedExitReasons": ["searx-startpage-blocked"],
        "cooldownSeconds": 600,
        "blockedExitTtlSeconds": 86400,
        "maxCandidateAttempts": 3,
        "maxHandshakeAgeSeconds": 120,
        "healthFailuresBeforeRotation": 2,
    }


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cfg = config(self.tmp.name)

    def make(self, runner, now=1000):
        return Controller(self.cfg, runner, now=lambda: now, shuffle=lambda values: None)

    def test_rotation_does_not_repeat_current_endpoint(self):
        runner = Runner()
        controller = self.make(runner)
        controller.state.update({"currentEndpoint": "one", "currentPublicIp": "198.51.100.1"})
        result = controller.rotate("tunnel-unhealthy")
        self.assertEqual(result["endpoint"], "two")
        self.assertNotIn("one", result["attempted"])

    def test_cooldown_rejects_rotation(self):
        controller = self.make(Runner())
        controller.state["lastRotation"] = 900
        with self.assertRaises(TimeoutError):
            controller.rotate("tunnel-unhealthy")

    def test_expired_block_is_pruned(self):
        controller = self.make(Runner())
        controller.state["blockedExits"] = {"198.51.100.1": 999, "198.51.100.2": 1001}
        controller.prune_blocked(1000)
        self.assertEqual(controller.state["blockedExits"], {"198.51.100.2": 1001})

    def test_startpage_block_marks_current_exit_for_24_hours(self):
        runner = Runner({"two": "198.51.100.2"})
        controller = self.make(runner)
        controller.state.update({"currentEndpoint": "one", "currentPublicIp": "198.51.100.1"})
        controller.rotate("searx-startpage-blocked")
        self.assertEqual(controller.state["blockedExits"]["198.51.100.1"], 87400)

    def test_other_rotation_reasons_do_not_block_current_exit(self):
        runner = Runner({"two": "198.51.100.2"})
        controller = self.make(runner)
        controller.config["allowedReasons"].append("low-download-speed")
        controller.state.update({"currentEndpoint": "one", "currentPublicIp": "198.51.100.1"})
        controller.rotate("low-download-speed")
        self.assertNotIn("198.51.100.1", controller.state["blockedExits"])

    def test_shared_blocked_exit_is_skipped(self):
        runner = Runner({"two": "198.51.100.1", "three": "198.51.100.3"})
        controller = self.make(runner)
        controller.state.update({"currentEndpoint": "one", "currentPublicIp": "198.51.100.1"})
        result = controller.rotate("searx-startpage-blocked")
        self.assertEqual(result["endpoint"], "three")
        self.assertEqual(runner.set_calls[:2], ["two", "three"])

    def test_failed_candidates_restore_previous_endpoint(self):
        runner = Runner({"two": RuntimeError("down"), "three": RuntimeError("down")})
        controller = self.make(runner)
        controller.state["currentEndpoint"] = "one"
        with self.assertRaises(RuntimeError):
            controller.rotate("tunnel-unhealthy")
        self.assertEqual(runner.set_calls[-1], "one")
        self.assertEqual(controller.state["lastRotationStatus"], "failed")

    def test_switch_pins_the_requested_endpoint(self):
        runner = Runner({"three": "198.51.100.3"})
        controller = self.make(runner)
        controller.state.update({"currentEndpoint": "one", "currentPublicIp": "198.51.100.1"})
        result = controller.switch("three")
        self.assertEqual(result, {"endpoint": "three", "publicIp": "198.51.100.3", "blockedExit": False})
        self.assertEqual(controller.state["currentEndpoint"], "three")
        self.assertEqual(controller.state["lastRotation"], 1000)
        self.assertEqual(controller.state["lastRotationStatus"], "success")

    def test_switch_ignores_cooldown_but_reports_blocked_exits(self):
        runner = Runner({"two": "198.51.100.2"})
        controller = self.make(runner)
        controller.state.update(
            {"currentEndpoint": "one", "lastRotation": 900, "blockedExits": {"198.51.100.2": 90000}}
        )
        self.assertTrue(controller.switch("two")["blockedExit"])

    def test_switch_restores_the_previous_endpoint_on_failure(self):
        runner = Runner({"two": RuntimeError("down")})
        controller = self.make(runner)
        controller.state["currentEndpoint"] = "one"
        with self.assertRaises(RuntimeError):
            controller.switch("two")
        self.assertEqual(runner.set_calls, ["two", "one"])
        self.assertEqual(controller.state["currentEndpoint"], "one")
        self.assertEqual(controller.state["lastRotationStatus"], "failed")

    def test_switch_rejects_unknown_endpoints(self):
        controller = self.make(Runner())
        with self.assertRaises(ValueError):
            controller.switch("nowhere")

    def test_health_rotates_after_consecutive_failures(self):
        runner = Runner({None: RuntimeError("down"), "one": RuntimeError("down"), "two": "203.0.113.2"})
        controller = self.make(runner)
        controller.state["currentEndpoint"] = "one"
        self.assertFalse(controller.health())
        self.assertFalse(controller.health())
        self.assertEqual(controller.state["currentEndpoint"], "two")

    def test_remote_command_is_exact_and_enumerated(self):
        allowed = ["searx-startpage-blocked"]
        self.assertEqual(parse_remote_command("rotate searx-startpage-blocked", allowed), allowed[0])
        for command in ["rotate tunnel-unhealthy", "rotate searx-startpage-blocked now", "sh"]:
            with self.assertRaises(ValueError):
                parse_remote_command(command, allowed)

    def test_packet_loss_rotates_even_during_switch_cooldown(self):
        self.cfg.update(packetLossTargets=["1.1.1.1"], packetLossThresholdPercent=40)
        runner = Runner()
        runner.packet_loss = Mock(side_effect=[60, 40, 0])
        controller = self.make(runner)
        controller.state.update(currentEndpoint="one", lastRotation=999)
        controller.health()
        self.assertEqual(runner.set_calls, [])
        controller.health()
        self.assertEqual(controller.state["currentEndpoint"], "two")
        self.assertEqual(controller.state["packetLossPercent"], 0)

    def test_healthy_sample_resets_loss_failure_streak(self):
        self.cfg.update(packetLossTargets=["1.1.1.1"], packetLossThresholdPercent=40)
        runner = Runner()
        runner.packet_loss = Mock(side_effect=[60, 0, 60])
        controller = self.make(runner)
        for _ in range(3):
            controller.health()
        self.assertEqual(runner.set_calls, [])
        self.assertEqual(controller.state["consecutiveHealthFailures"], 1)

    def test_packet_loss_uses_best_target_and_tunnel_source(self):
        runner = SystemRunner({
            "commands": {"ping": "ping"}, "tunnelAddress": "10.1.2.3/32",
            "packetLossProbeCount": 5, "packetLossTargets": ["1.1.1.1", "9.9.9.9"],
        })
        with patch("controller.subprocess.run", side_effect=[
            subprocess.CompletedProcess([], 1, "100% packet loss", ""),
            subprocess.CompletedProcess([], 0, "20% packet loss", ""),
        ]) as run:
            self.assertEqual(runner.packet_loss(), 20)
            self.assertIn("10.1.2.3", run.call_args.args[0])

    def test_literal_ip_probe_parses_trace_and_rejects_garbage(self):
        runner = SystemRunner({
            "commands": {"curl": "curl"}, "tunnelAddress": "10.1.2.3/32",
            "probeTimeoutSeconds": 10, "publicIpUrl": "https://1.1.1.1/cdn-cgi/trace",
        })
        runner._run = Mock(return_value=Mock(stdout="fl=123\nip=198.51.100.2\n"))
        self.assertEqual(runner.public_ip(), "198.51.100.2")
        runner._run.return_value.stdout = "error page"
        with self.assertRaises(RuntimeError):
            runner.public_ip()

    def test_lock_rejects_concurrent_rotation(self):
        path = Path(self.tmp.name) / "lock"
        with rotation_lock(path):
            with self.assertRaises(RuntimeError):
                with rotation_lock(path):
                    pass

    def test_system_runner_activates_the_networkmanager_profile(self):
        runner = SystemRunner(
            {
                "commands": {"nmcli": "/run/current-system/sw/bin/nmcli"},
                "probeTimeoutSeconds": 10,
            }
        )
        runner._run = Mock()
        runner.set_endpoint(
            {
                "name": "two",
                "connectionId": "wg-airvpn-two",
            }
        )
        runner._run.assert_called_once_with(
            [
                "/run/current-system/sw/bin/nmcli",
                "--wait",
                "10",
                "connection",
                "up",
                "id",
                "wg-airvpn-two",
            ],
            timeout=12,
        )


class DnsRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.cfg = {"port": 5335, "service": "unbound", "systemctl": "systemctl",
                    "upstreams": [["@9.9.9.9", "+tls-ca"]]}

    def test_upstream_outage_never_restarts_local_dns(self):
        state = {}
        run = Mock()
        for _ in range(5):
            recover(self.cfg, state, probe=lambda *_: False, run=run, now=lambda: 1000)
        run.assert_not_called()

    def test_recovery_requires_repeated_failure_and_working_upstream(self):
        state = {}
        run = Mock()
        probe = lambda _cfg, args, _name: args[0] != "@127.0.0.1"
        recover(self.cfg, state, probe=probe, run=run, now=lambda: 1000)
        run.assert_not_called()
        recover(self.cfg, state, probe=probe, run=run, now=lambda: 1030)
        run.assert_called_once_with(["systemctl", "restart", "unbound.service"], check=True, timeout=30)
        recover(self.cfg, state, probe=probe, run=run, now=lambda: 1060)
        self.assertEqual(run.call_count, 1)

    def test_healthy_resolver_resets_failure_count(self):
        state = {"failures": 4}
        run = Mock()
        recover(self.cfg, state, probe=lambda *_: True, run=run)
        self.assertEqual(state["failures"], 0)
        run.assert_not_called()

    def test_servfail_is_not_a_successful_dns_probe(self):
        with patch("dns_recovery.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "status: SERVFAIL", "")
            self.assertFalse(query({"kdig": "kdig"}, [], "example.com"))
            run.return_value.stdout = "status: NXDOMAIN"
            self.assertTrue(query({"kdig": "kdig"}, [], "example.com"))


class WatchdogTests(unittest.TestCase):
    def test_parser_only_matches_startpage_blocks(self):
        self.assertTrue(is_startpage_block("startpage CAPTCHA challenge"))
        self.assertTrue(is_startpage_block("access denied while querying Startpage"))
        self.assertFalse(is_startpage_block("brave engine returned status code 429"))

    def test_successful_remediation_restarts_and_clears_block(self):
        calls = []

        def run(arguments, **_kwargs):
            calls.append(arguments)
            return subprocess.CompletedProcess(arguments, 0, "", "")

        state = {}
        watchdog = Watchdog(
            {
                "ssh": "ssh",
                "identityFile": "/key",
                "gateway": "root@gateway",
                "systemctl": "systemctl",
                "rotationTimeoutSeconds": 30,
                "incidentAttempts": 3,
                "cooldownSeconds": 600,
                "restartSettleSeconds": 1,
                "incidentBackoffSeconds": 21600,
            },
            state,
            run=run,
            sleep=lambda _seconds: None,
            now=lambda: 1000,
            canary=lambda: True,
        )
        self.assertTrue(watchdog.remediate())
        self.assertEqual(state["blocked"], 0)
        self.assertEqual(state["restarts"], 1)
        self.assertIn(["systemctl", "restart", "searx.service"], calls)

    def test_exhaustion_sets_six_hour_backoff(self):
        def run(arguments, **_kwargs):
            return subprocess.CompletedProcess(arguments, 1, "", "")

        state = {}
        watchdog = Watchdog(
            {
                "ssh": "ssh",
                "identityFile": "/key",
                "gateway": "root@gateway",
                "systemctl": "systemctl",
                "rotationTimeoutSeconds": 30,
                "incidentAttempts": 3,
                "cooldownSeconds": 600,
                "restartSettleSeconds": 1,
                "incidentBackoffSeconds": 21600,
            },
            state,
            run=run,
            sleep=lambda _seconds: None,
            now=lambda: 1000,
            canary=lambda: False,
        )
        self.assertFalse(watchdog.remediate())
        self.assertEqual(state["rotationRequests"], 3)
        self.assertEqual(state["backoffUntil"], 22600)
        self.assertIn("searx_vpn_backoff_active 1", render_metrics(state, 1001))


if __name__ == "__main__":
    unittest.main()
