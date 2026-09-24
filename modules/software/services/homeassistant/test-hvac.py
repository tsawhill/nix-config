"""Offline regression tests for the templates used by the HVAC controller.

Run with Python + jinja2 + tinytuya. No HA connection or credentials required.
"""

import copy
import base64
import importlib.util
import json
from pathlib import Path
import re
import struct
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).parent
SOURCE = (ROOT / "hvac.nix").read_text()
ROOMS = ["office", "bedroom", "living_room"]


def raw_template(name):
    match = re.search(rf"  {name} = (?:room: )?''\n(.*?)'';", SOURCE, re.S)
    assert match, name
    return match[1]


class Templates(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 19, 23, 45, tzinfo=timezone.utc)
        self.values = {}
        for room in ROOMS:
            self.values.update(
                {
                    f"sensor.ac_controller_{room}_temperature": "78",
                    f"sensor.hvac_target_{room}": "76",
                    f"sensor.hvac_heat_target_{room}": "68",
                    f"climate.{room}_ac": "off",
                    f"timer.hvac_override_{room}": "idle",
                    f"timer.hvac_shed_{room}": "idle",
                    f"timer.hvac_min_off_{room}": "idle",
                    f"input_boolean.hvac_enable_{room}": "on",
                    f"input_number.hvac_override_{room}": "73",
                    f"input_number.hvac_draft_{room}": "64",
                }
            )
        self.values["input_select.hvac_system_mode"] = "cool"
        self.values["input_select.hvac_override_mode"] = "heat"
        self.values["input_select.hvac_draft_mode"] = "off"
        self.values["sensor.hvac_effective_mode"] = "cool"
        self.reported = self.now
        self.env = Environment(undefined=StrictUndefined)
        self.env.globals.update(
            states=self.states,
            is_state=lambda entity, value: self.values.get(entity) == value,
            is_number=lambda value: self.numeric(value),
            now=lambda: self.now,
            timedelta=timedelta,
            as_timestamp=lambda value, default=0: (
                value.timestamp() if isinstance(value, datetime) else default
            ),
        )
        self.env.globals["states"] = StateAccessor(self)

    @staticmethod
    def numeric(value):
        try:
            float(value)
            return True
        except (ValueError, TypeError):
            return False

    def states(self, entity):
        return self.values.get(entity, "unknown")

    def expand(self, text):
        refs = {
            "room": "office",
            "effectiveMode": "sensor.hvac_effective_mode",
            "systemMode": "input_select.hvac_system_mode",
            "overrideMode": "input_select.hvac_override_mode",
            "draftMode": "input_select.hvac_draft_mode",
            "followSystem": "follow system",
            "fanFollowsSchedule": "schedule",
            "airflowFollowsSchedule": "schedule",
            "toString tuning.staleMinutes * 60": "900",
            "toString (tuning.staleMinutes * 60)": "900",
            "toString tuning.hysteresis": "2",
            "anyOverrideActive": " or ".join(
                f"is_state('timer.hvac_override_{r}', 'active')" for r in ROOMS
            ),
            "currentBlock": (
                self.expand(raw_template("currentBlock"))
                if "${currentBlock}" in text
                else ""
            ),
            "scheduleJson": json.dumps(self.schedule()),
            "builtins.toJSON (map overrideTimer roomNames)": json.dumps(
                [f"timer.hvac_override_{room}" for room in ROOMS]
            ),
        }
        helpers = {
            "tempSensor": "sensor.ac_controller_office_temperature",
            "climateEntity": "climate.office_ac",
            "overrideTimer": "timer.hvac_override_office",
            "shedTimer": "timer.hvac_shed_office",
            "overrideNumber": "input_number.hvac_override_office",
            "enableToggle": "input_boolean.hvac_enable_office",
            "targetSensor": "sensor.hvac_target_office",
            "heatTargetSensor": "sensor.hvac_heat_target_office",
            "minOffTimer": "timer.hvac_min_off_office",
            "appliedFan": "input_select.hvac_override_fan_office",
            "appliedAirflow": "input_select.hvac_override_airflow_office",
            "fanSelect": "input_select.hvac_fan_office",
            "airflowSelect": "input_select.hvac_airflow_office",
        }
        refs.update({k + " room": v for k, v in helpers.items()})

        def replace(match):
            key = match.group(1).strip()
            if key not in refs:
                raise AssertionError(f"unhandled Nix interpolation: {key}")
            return refs[key]

        return re.sub(r"\$\{([^{}]+)\}", replace, text)

    def schedule(self):
        def block(time, label, threshold):
            hour, minute = map(int, time.split(":"))
            return {
                "from": time,
                "fromMinutes": hour * 60 + minute,
                "label": label,
                "rooms": {
                    "office": {
                        "coolAbove": threshold,
                        "heatBelow": 60,
                        "priority": 1,
                        "fan": "auto",
                        "airflow": "comfort",
                    }
                },
            }

        return {
            "days": {"saturday": "late", "sunday": "early"},
            "patterns": {
                "late": [
                    block("00:00", "Asleep", 82),
                    block("09:30", "Working", 76),
                    block("23:30", "Wind-down", 75),
                ],
                "early": [
                    block("00:00", "Asleep", 82),
                    block("09:30", "Working", 76),
                    block("22:00", "Wind-down", 75),
                ],
            },
        }

    def render(self, name):
        return self.env.from_string(self.expand(raw_template(name))).render().strip()

    def test_drafts_do_not_change_live_mode_or_threshold(self):
        self.assertEqual(self.render("effectiveModeTemplate"), "cool")
        self.assertEqual(self.render("targetTemplate"), "75")
        self.values["timer.hvac_override_office"] = "active"
        self.assertEqual(self.render("effectiveModeTemplate"), "heat")
        self.assertEqual(float(self.render("targetTemplate")), 73)
        self.values["input_number.hvac_draft_office"] = "86"
        self.values["input_select.hvac_draft_mode"] = "cool"
        self.assertEqual(self.render("effectiveModeTemplate"), "heat")
        self.assertEqual(float(self.render("heatTargetTemplate")), 73)

    def test_expiry_restores_schedule_and_enable(self):
        self.values["input_boolean.hvac_enable_office"] = "off"
        self.values["timer.hvac_override_office"] = "active"
        self.assertEqual(self.render("desiredTemplate"), "off")
        self.values["timer.hvac_override_office"] = "idle"
        self.assertEqual(self.render("desiredTemplate"), "cool")
        self.assertEqual(self.render("effectiveModeTemplate"), "cool")
        self.assertEqual(self.render("heatTargetTemplate"), "60")

    def test_room_apply_keeps_shared_mode_and_bulk_apply_copies_draft(self):
        expr = re.search(r'commit_mode = "(.*?)";', SOURCE).group(1)
        template = self.env.from_string(self.expand(expr))
        self.assertEqual(
            template.render(selected_room="office", op="apply"), "follow system"
        )
        self.values["timer.hvac_override_bedroom"] = "active"
        self.assertEqual(template.render(selected_room="office", op="apply"), "heat")
        self.assertEqual(template.render(selected_room="all", op="apply"), "off")

    def test_resume_targets_only_selected_room(self):
        expr = re.search(
            r'target.entity_id = "(\{\{ .*?selected_room == \'all\'.*?)";', SOURCE
        ).group(1)
        template = self.env.from_string(self.expand(expr))
        self.assertEqual(
            template.render(selected_room="office"), "['timer.hvac_override_office']"
        )
        self.assertEqual(
            template.render(selected_room="all"),
            str([f"timer.hvac_override_{r}" for r in ROOMS]),
        )

    def test_timed_fan_and_airflow_restore_normal_preferences(self):
        for name, normal, override, scheduled in [
            ("fan", "2", "quiet", "auto"),
            ("airflow", "off", "swing", "comfort"),
        ]:
            with self.subTest(control=name):
                self.values[f"input_select.hvac_{name}_office"] = normal
                self.values[f"input_select.hvac_override_{name}_office"] = override
                self.values["timer.hvac_override_office"] = "idle"
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    normal,
                )
                self.values["timer.hvac_override_office"] = "active"
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    override,
                )
                self.values[f"input_select.hvac_draft_{name}_office"] = scheduled
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    override,
                )
                self.values[f"input_select.hvac_override_{name}_office"] = "schedule"
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    normal,
                )
                self.values[f"input_select.hvac_{name}_office"] = "schedule"
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    scheduled,
                )
                self.values[f"input_select.hvac_override_{name}_office"] = override
                self.values["timer.hvac_override_office"] = "idle"
                self.assertEqual(
                    self.render(
                        "normalFanTemplate" if name == "fan" else "airflowTemplate"
                    ),
                    scheduled,
                )

    def test_room_power_off_and_nap_power_on(self):
        expr = re.search(
            r'action = "(\{\{ \'input_boolean.turn_on\'.*?)";', SOURCE
        ).group(1)
        template = self.env.from_string(self.expand(expr))
        self.assertEqual(
            template.render(op="apply", enabled_office=False), "input_boolean.turn_off"
        )
        self.assertEqual(
            template.render(op="apply", enabled_office=True), "input_boolean.turn_on"
        )
        self.assertEqual(
            template.render(op="nap", enabled_office=False), "input_boolean.turn_on"
        )

    def test_next_schedule_rolls_over_midnight(self):
        self.assertEqual(self.render("nextBlockTemplate"), "Asleep at 00:00")
        self.now = self.now.replace(hour=12)
        self.assertEqual(self.render("nextBlockTemplate"), "Wind-down at 23:30")
        self.now = self.now.replace(day=20)
        self.assertEqual(self.render("nextBlockTemplate"), "Wind-down at 22:00")

    def test_room_activity_distinguishes_idle_off_and_running(self):
        self.assertEqual(self.render("roomActivity"), "Idle")
        self.values["input_select.hvac_watch_office"] = "off_check"
        self.assertEqual(self.render("roomActivity"), "Idle")
        self.assertEqual(self.render("roomStatus"), "Following schedule")
        self.values["climate.office_ac"] = "cool"
        self.assertEqual(self.render("roomActivity"), "Cooling")
        self.values["climate.office_ac"] = "heat"
        self.assertEqual(self.render("roomActivity"), "Heating")
        self.values["climate.office_ac"] = "off"
        self.values["timer.hvac_override_office"] = "active"
        self.values["input_boolean.hvac_enable_office"] = "off"
        self.assertEqual(self.render("roomActivity"), "Off")
        self.values["input_select.hvac_watch_office"] = "off_failed"
        self.assertEqual(self.render("roomStatus"), "Check unit: shutdown unconfirmed")
        self.values["timer.hvac_override_office"] = "idle"
        self.values["sensor.hvac_effective_mode"] = "off"
        self.assertEqual(self.render("roomActivity"), "Off")

    def test_room_summary_keeps_source_activity_and_warning_separate(self):
        self.values["sensor.hvac_activity_office"] = "Cooling"
        self.values["sensor.hvac_status_office"] = "Following schedule"
        self.assertEqual(
            self.render("roomSummary"),
            "Following schedule · Cool above **76°F** · Cooling",
        )
        self.values["timer.hvac_override_office"] = "active"
        self.values["sensor.hvac_activity_office"] = "Idle"
        self.assertEqual(
            self.render("roomSummary"), "Override · Cool above **76°F** · Idle"
        )
        self.values["sensor.hvac_status_office"] = "Check unit: shutdown unconfirmed"
        self.assertIn("Check unit: shutdown unconfirmed", self.render("roomSummary"))
        self.values["input_boolean.hvac_enable_office"] = "off"
        self.values["sensor.hvac_activity_office"] = "Off"
        self.assertTrue(self.render("roomSummary").startswith("Override · Off"))

    def test_room_status_reports_missing_stale_and_waiting(self):
        self.assertEqual(self.render("roomStatus"), "Following schedule")
        self.values["sensor.ac_controller_office_temperature"] = "unavailable"
        self.assertEqual(self.render("roomStatus"), "Sensor unavailable")
        self.values["sensor.ac_controller_office_temperature"] = "78"
        self.reported = self.now - timedelta(minutes=16)
        self.assertEqual(self.render("roomStatus"), "Sensor stale")
        self.reported = self.now
        self.values["timer.hvac_min_off_office"] = "active"
        self.assertEqual(self.render("roomStatus"), "Waiting to restart")

    def test_restore_settings_and_no_background_draft_overwrite(self):
        selects = SOURCE.split("    input_select =", 1)[1].split(
            "    input_boolean =", 1
        )[0]
        self.assertNotRegex(selects, r"\binitial\s*=")
        sync = SOURCE.split("  sliderSyncAutomation =", 1)[1].split(
            "  patienceTemplate =", 1
        )[0]
        self.assertIn("input_boolean.hvac_drafts_initialized", sync)
        self.assertNotIn("target.entity_id = overrideNumber", sync)

    def test_nap_uses_mode_and_does_not_edit_draft(self):
        expr = re.search(
            r'data.value = "(\{\{ \(\$\{toString sleeping.bedroom.heatBelow\}.*?\}\})"',
            SOURCE,
        ).group(1)
        sleeping = SOURCE.split("  sleeping =", 1)[1].split("  working =", 1)[0]
        bedroom = sleeping.split("bedroom =", 1)[1].split("};", 1)[0]
        targets = {}
        for key in ("heatBelow", "coolAbove"):
            value = re.search(rf"{key}\s*=\s*(\d+)", bedroom).group(1)
            targets[key] = value
            expr = expr.replace("${toString sleeping.bedroom." + key + "}", value)
        expr = expr.replace("${room}", "office")
        t = self.env.from_string(expr)
        self.assertEqual(
            t.render(op="nap", nap_heat=True, value_office=80), targets["heatBelow"]
        )
        self.assertEqual(
            t.render(op="nap", nap_heat=False, value_office=80), targets["coolAbove"]
        )
        self.assertEqual(t.render(op="apply", nap_heat=True, value_office=80), "80")

    def watch(self, **overrides):
        text = raw_template("watchDecision")
        for key, value in {
            "progressDegrees": 0.3,
            "boostMinutes": 10,
            "stallMinutes": 20,
        }.items():
            text = text.replace("${toString tuning." + key + "}", str(value))
        args = dict(
            phase="watching",
            mode="cool",
            desired="cool",
            fresh=True,
            checkpoint=100,
            elapsed=300,
            progress=0,
            patience=1,
            off_drift=0,
            off_overshoot=False,
            stop_boundary=71,
            recovery_elapsed=0,
            unmet=True,
        )
        args.update(overrides)
        return self.env.from_string(text).render(**args).strip()

    def test_watch_retry_is_bounded_and_progress_silent(self):
        self.assertEqual(self.watch(elapsed=299), "wait")
        self.assertEqual(self.watch(), "retry")
        self.assertEqual(self.watch(progress=0.31), "progress")
        for phase in ["retried", "boosted", "stalled", "exhausted", "settled"]:
            self.assertNotEqual(self.watch(phase=phase, elapsed=10000), "retry")
        self.assertEqual(self.watch(phase="idle"), "initialize")
        self.assertEqual(self.watch(phase="exhausted", progress=0.5), "progress")

    def test_shutdown_keeps_monitoring_after_first_retry(self):
        # Replay the incident: HA said off at 71.58F, bedroom kept cooling.
        args = dict(
            mode="off",
            desired="off",
            elapsed=600,
            off_drift=71.58 - 68,
            off_overshoot=True,
        )
        self.assertEqual(self.watch(phase="off_check", **args), "off_correct")
        self.assertEqual(self.watch(phase="off_final", **args), "off_failed")
        self.assertEqual(self.watch(phase="off_failed", **args), "off_recover")
        self.assertEqual(
            self.watch(phase="off_failed", **(args | {"off_drift": 0})), "off_observe"
        )
        self.assertEqual(
            self.watch(phase="off_failed", **(args | {"off_overshoot": False})),
            "off_observe",
        )
        self.assertEqual(
            self.watch(phase="off_check", **(args | {"fresh": False})), "off_correct"
        )
        self.assertEqual(
            self.watch(phase="off_check", **(args | {"off_drift": 0.2})), "off_observe"
        )
        self.assertEqual(
            self.watch(phase="off_check", **(args | {"off_overshoot": False})),
            "off_observe",
        )
        # A heat demand waiting for compressor cooldown must not suppress off retry.
        self.assertEqual(
            self.watch(phase="off_pending", mode="off", desired="heat", elapsed=120),
            "off_retry",
        )
        # A new run must never be stopped by an old off checkpoint.
        self.assertNotIn(
            self.watch(
                phase="off_check",
                mode="heat",
                desired="heat",
                elapsed=600,
                off_drift=3,
                off_overshoot=True,
            ),
            ["off_correct", "off_failed"],
        )

    def test_off_warning_recovers_without_claiming_physical_confirmation(self):
        args = dict(
            mode="off",
            desired="off",
            phase="off_failed",
            elapsed=600,
            off_overshoot=True,
        )
        self.assertEqual(self.watch(**args, off_drift=0), "off_observe")
        self.assertEqual(self.watch(**args, off_drift=-1), "off_observe")
        self.assertEqual(self.watch(**args, off_drift=0.7), "off_recover")
        self.assertEqual(self.watch(**args, fresh=False), "wait")
        self.assertEqual(self.watch(**(args | {"elapsed": 299})), "wait")
        self.assertEqual(self.watch(**args, stop_boundary=-40), "off_rebase")

    def test_off_overshoot_uses_saved_boundary_not_new_schedule(self):
        expr = re.search(r'off_overshoot = "(.*?)";', SOURCE).group(1)
        template = self.env.from_string(expr)
        # A morning heating schedule dropping from 66 to 60 must not turn
        # a stable 67F room into a failed shutdown (old logic did).
        self.assertEqual(
            template.render(last_run="heat", sample=67, stop_boundary=68), "False"
        )
        self.assertEqual(
            template.render(last_run="heat", sample=70, stop_boundary=68), "True"
        )
        self.assertEqual(
            template.render(last_run="cool", sample=68, stop_boundary=71), "True"
        )

    def test_run_recovery_continues_without_replenishing_escalations(self):
        for phase in ["retried", "boosted", "stalled", "exhausted", "settled"]:
            for mode in ["cool", "heat"]:
                args = dict(
                    phase=phase,
                    mode=mode,
                    desired=mode,
                    elapsed=300,
                    recovery_elapsed=300,
                )
                self.assertEqual(self.watch(**args), "recover")
                self.assertEqual(
                    self.watch(**(args | {"recovery_elapsed": 299})), "wait"
                )
                self.assertEqual(self.watch(**args, progress=0.4), "progress")
                self.assertEqual(self.watch(**args, unmet=False), "progress")
                self.assertEqual(self.watch(**args, fresh=False), "wait")
                self.assertEqual(self.watch(**(args | {"desired": "off"})), "wait")
        # Recovery cadence never postpones a due fan/capacity decision.
        self.assertEqual(
            self.watch(phase="retried", elapsed=600, recovery_elapsed=300), "boost"
        )
        self.assertEqual(
            self.watch(phase="boosted", elapsed=1200, recovery_elapsed=300), "stall"
        )

    def test_shutdown_recovery_checks_after_five_minutes(self):
        args = dict(
            mode="off",
            desired="off",
            phase="off_check",
            off_drift=0.6,
            off_overshoot=True,
        )
        self.assertEqual(self.watch(**args, elapsed=299), "wait")
        self.assertEqual(self.watch(**args, elapsed=300), "off_correct")
        self.assertEqual(self.watch(**args, elapsed=299, fresh=False), "wait")
        self.assertEqual(self.watch(**args, elapsed=300, fresh=False), "off_correct")

    def test_dark_sensor_retries_off_blind_then_stops(self):
        # The blaster carries both the sensor and the IR, so a shutdown that
        # loses the sensor must still retry, but must not beep forever.
        args = dict(mode="off", desired="off", fresh=False, elapsed=300)
        self.assertEqual(self.watch(phase="off_pending", **(args | {"elapsed": 120})), "off_retry")
        self.assertEqual(self.watch(phase="off_check", **args), "off_correct")
        self.assertEqual(self.watch(phase="off_final", **args), "off_failed")
        # Ladder exhausted: the warning stands, no further commands.
        self.assertEqual(self.watch(phase="off_failed", **args), "wait")
        self.assertEqual(self.watch(phase="off_failed", **(args | {"elapsed": 86400})), "wait")
        # Blind retries never fire for a unit that was never commanded off.
        for phase in ["watching", "retried", "idle"]:
            self.assertEqual(self.watch(phase=phase, **args), "wait")

    def test_dark_sensor_ladder_resumes_when_sensor_returns(self):
        # Once readings come back, drift evidence takes over from blind retries.
        args = dict(mode="off", desired="off", elapsed=300, off_drift=3.5, off_overshoot=True)
        self.assertEqual(self.watch(phase="off_failed", **args), "off_recover")
        self.assertEqual(
            self.watch(phase="off_failed", **(args | {"off_drift": 0, "off_overshoot": False})),
            "off_observe",
        )

    def test_mode_change_never_retains_opposite_mode_in_deadband(self):
        self.values["sensor.hvac_effective_mode"] = "heat"
        self.values["sensor.ac_controller_office_temperature"] = "69"
        self.values["climate.office_ac"] = "cool"
        self.assertEqual(self.render("desiredTemplate"), "off")
        self.values["climate.office_ac"] = "heat"
        self.assertEqual(self.render("desiredTemplate"), "heat")
        self.values["sensor.hvac_effective_mode"] = "cool"
        self.values["sensor.ac_controller_office_temperature"] = "75"
        self.assertEqual(self.render("desiredTemplate"), "off")
        self.values["climate.office_ac"] = "cool"
        self.assertEqual(self.render("desiredTemplate"), "cool")

    def test_outdoor_gap_only_delays_escalation(self):
        self.assertEqual(self.watch(patience=2), "retry")
        self.assertEqual(self.watch(phase="retried", elapsed=600), "boost")
        self.assertEqual(self.watch(phase="retried", elapsed=600, patience=2), "wait")
        self.assertEqual(self.watch(phase="retried", elapsed=1200, patience=2), "boost")
        self.assertEqual(self.watch(phase="boosted", elapsed=1200), "stall")
        self.assertEqual(self.watch(phase="boosted", elapsed=1200, patience=2), "wait")
        self.assertEqual(self.watch(phase="boosted", elapsed=2400, patience=2), "stall")

    def test_patience_uses_per_room_delta_and_weather_units(self):
        text = raw_template("patienceTemplate").replace(
            "${toString tuning.deltaForDoubleWait}", "35"
        )
        template = self.env.from_string(text)

        def factor(**changes):
            args = dict(
                mode="cool",
                outdoor_fresh=True,
                outdoor_value=110,
                outdoor_unit="°F",
                sample=75,
            )
            args.update(changes)
            return float(template.render(**args))

        self.assertEqual(factor(), 2)
        self.assertEqual(factor(sample=92.5), 1.5)
        self.assertEqual(factor(outdoor_value=75), 1)
        self.assertEqual(factor(outdoor_value=60), 1)
        self.assertEqual(factor(outdoor_value=140), 2)
        self.assertAlmostEqual(
            factor(outdoor_value=43.333333, outdoor_unit="°C"), 2, places=6
        )
        self.assertEqual(factor(outdoor_fresh=False), 1)
        self.assertEqual(factor(outdoor_value=None), 1)
        self.assertEqual(factor(outdoor_unit="K"), 1)
        self.assertEqual(factor(mode="heat"), 1)

    def test_watch_rejects_stale_sensors_and_changed_demand(self):
        self.assertEqual(self.watch(fresh=False), "wait")
        self.assertEqual(self.watch(desired="off"), "wait")
        self.assertEqual(self.watch(mode="unavailable"), "wait")
        self.assertEqual(self.watch(mode="heat", desired="heat"), "retry")
        self.assertEqual(
            self.watch(phase="off_pending", mode="off", elapsed=120), "off_retry"
        )
        self.assertEqual(self.watch(phase="idle", mode="off", elapsed=10000), "wait")

    def test_boost_respects_quiet_and_fixed_fans(self):
        self.values["climate.office_ac"] = "cool"
        self.values["input_select.hvac_watch_office"] = "boosted"
        for normal in ["quiet", "1", "2", "3", "4", "5"]:
            self.values["sensor.hvac_normal_fan_office"] = normal
            self.assertEqual(self.render("fanTemplate"), normal)
        self.values["sensor.hvac_normal_fan_office"] = "auto"
        self.assertEqual(self.render("fanTemplate"), "5")
        self.values["climate.office_ac"] = "off"
        self.assertEqual(self.render("fanTemplate"), "auto")


class StateAccessor:
    def __init__(self, test):
        self.test = test

    def __call__(self, entity):
        return self.test.states(entity)

    @property
    def sensor(self):
        return SimpleNamespace(
            ac_controller_office_temperature=SimpleNamespace(
                last_reported=self.test.reported
            )
        )


spec = importlib.util.spec_from_file_location(
    "codes", ROOT / "generate-daikin-codes.py"
)
codes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codes)


class GeneratedCodes(unittest.TestCase):
    def setUp(self):
        self.table = json.loads((ROOT / "daikin-arc452a21.json").read_text())

    def test_entire_committed_table(self):
        self.assertEqual(codes.validate_generated(self.table), 967)

    def test_generator_produces_all_modes_fans_and_airflows(self):
        # Make a Broadlink input fixture from a verified committed pulse train.
        # This exercises build(), not merely validation of existing output.
        pulses = codes.IR.base64_to_pulses(
            self.table["commands"]["cool"]["auto"]["off"]["72"]
        )
        payload = bytearray()
        for pulse in pulses:
            ticks = round(pulse / codes.TICK_US)
            payload.extend(
                bytes([ticks]) if ticks < 256 else b"\x00" + struct.pack(">H", ticks)
            )
        payload.extend(b"\x0d\x05")
        source = base64.b64encode(
            b"\x26\x00" + struct.pack("<H", len(payload)) + payload
        ).decode()
        for mode in self.table["operationModes"]:
            for fan in self.table["fanModes"]:
                for airflow in self.table["swingModes"]:
                    for temperature in range(64, 87):
                        self.table["commands"][mode][fan][airflow][str(temperature)] = (
                            codes.build(
                                source,
                                mode,
                                fan,
                                codes.celsius_for(temperature),
                                airflow,
                            )
                        )
        self.assertEqual(codes.validate_generated(self.table), 967)

    def mutate(self, frame_index, byte, value, repair_checksum):
        node = self.table["commands"]["cool"]["quiet"]["comfort"]
        pulses = codes.IR.base64_to_pulses(node["72"])
        span = codes.frame_spans(pulses)[frame_index]
        frame = bytearray(codes.read_frame(pulses, span))
        frame[byte] = value
        if repair_checksum:
            frame[-1] = codes.checksum(frame)
        node["72"] = codes.IR.pulses_to_base64(codes.write_frame(pulses, span, frame))

    def test_rejects_bad_checksum_in_each_frame(self):
        original = copy.deepcopy(self.table)
        for index, byte in [(0, 7), (1, 7), (2, 18)]:
            with self.subTest(frame=index):
                self.table = copy.deepcopy(original)
                self.mutate(index, byte, 0, False)
                with self.assertRaisesRegex(ValueError, "checksum"):
                    codes.validate_generated(self.table)

    def test_rejects_wrong_quiet_fan_even_with_valid_checksum(self):
        self.mutate(2, 8, 0xA0, True)
        with self.assertRaisesRegex(ValueError, "fields"):
            codes.validate_generated(self.table)

    def test_rejects_comfort_and_swing_together(self):
        self.mutate(2, 8, 0xBF, True)
        with self.assertRaisesRegex(ValueError, "fields"):
            codes.validate_generated(self.table)

    def test_rejects_missing_comfort_bit(self):
        self.mutate(0, 6, 0, True)
        with self.assertRaisesRegex(ValueError, "fields"):
            codes.validate_generated(self.table)

    def test_rejects_incomplete_table(self):
        del self.table["commands"]["heat"]["quiet"]["swing"]["86"]
        with self.assertRaisesRegex(ValueError, "incomplete"):
            codes.validate_generated(self.table)


if __name__ == "__main__":
    unittest.main()
