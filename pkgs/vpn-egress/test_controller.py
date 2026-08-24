#!/usr/bin/env python3

import fcntl
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from controller import Controller, parse_remote_command, rotation_lock
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
            {"name": "one", "ip": "192.0.2.1", "port": 1637},
            {"name": "two", "ip": "192.0.2.2", "port": 1637},
            {"name": "three", "ip": "192.0.2.3", "port": 1637},
        ],
        "allowedReasons": ["startup", "tunnel-unhealthy", "searx-startpage-blocked"],
        "remoteAllowedReasons": ["searx-startpage-blocked"],
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

    def test_lock_rejects_concurrent_rotation(self):
        path = Path(self.tmp.name) / "lock"
        with rotation_lock(path):
            with self.assertRaises(RuntimeError):
                with rotation_lock(path):
                    pass


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
