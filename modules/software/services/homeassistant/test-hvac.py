"""Offline regression tests for the templates used by the HVAC controller.

Run with Python + jinja2 + tinytuya. No HA connection or credentials required.
"""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).parent
SOURCE = (ROOT / 'hvac.nix').read_text()
ROOMS = ['office', 'bedroom', 'living_room']


def raw_template(name):
    match = re.search(rf"  {name} = (?:room: )?''\n(.*?)'';", SOURCE, re.S)
    assert match, name
    return match[1]


class Templates(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 19, 23, 45, tzinfo=timezone.utc)
        self.values = {}
        for room in ROOMS:
            self.values.update({
                f'sensor.ac_controller_{room}_temperature': '78',
                f'sensor.hvac_target_{room}': '76',
                f'sensor.hvac_heat_target_{room}': '68',
                f'climate.{room}_ac': 'off',
                f'timer.hvac_override_{room}': 'idle',
                f'timer.hvac_shed_{room}': 'idle',
                f'timer.hvac_min_off_{room}': 'idle',
                f'input_boolean.hvac_enable_{room}': 'on',
                f'input_number.hvac_override_{room}': '73',
                f'input_number.hvac_draft_{room}': '64',
            })
        self.values['input_select.hvac_system_mode'] = 'cool'
        self.values['input_select.hvac_override_mode'] = 'heat'
        self.values['input_select.hvac_draft_mode'] = 'off'
        self.values['sensor.hvac_effective_mode'] = 'cool'
        self.reported = self.now
        self.env = Environment(undefined=StrictUndefined)
        self.env.globals.update(
            states=self.states,
            is_state=lambda entity, value: self.values.get(entity) == value,
            is_number=lambda value: self.numeric(value),
            now=lambda: self.now,
            timedelta=timedelta,
            as_timestamp=lambda value, default=0: value.timestamp() if isinstance(value, datetime) else default,
        )
        self.env.globals['states'] = StateAccessor(self)

    @staticmethod
    def numeric(value):
        try:
            float(value)
            return True
        except (ValueError, TypeError):
            return False

    def states(self, entity):
        return self.values.get(entity, 'unknown')

    def expand(self, text):
        refs = {
            'room': 'office',
            'effectiveMode': 'sensor.hvac_effective_mode',
            'systemMode': 'input_select.hvac_system_mode',
            'overrideMode': 'input_select.hvac_override_mode',
            'followSystem': 'follow system',
            'toString tuning.staleMinutes * 60': '900',
            'toString (tuning.staleMinutes * 60)': '900',
            'toString tuning.hysteresis': '2',
            'anyOverrideActive': ' or '.join(f"is_state('timer.hvac_override_{r}', 'active')" for r in ROOMS),
            'currentBlock': self.expand(raw_template('currentBlock')) if '${currentBlock}' in text else '',
            'scheduleJson': json.dumps(self.schedule()),
        }
        helpers = {'tempSensor':'sensor.ac_controller_office_temperature', 'climateEntity':'climate.office_ac',
                   'overrideTimer':'timer.hvac_override_office', 'shedTimer':'timer.hvac_shed_office',
                   'overrideNumber':'input_number.hvac_override_office', 'enableToggle':'input_boolean.hvac_enable_office',
                   'targetSensor':'sensor.hvac_target_office', 'heatTargetSensor':'sensor.hvac_heat_target_office',
                   'minOffTimer':'timer.hvac_min_off_office'}
        refs.update({k+' room':v for k,v in helpers.items()})
        def replace(match):
            key=match.group(1)
            if key not in refs:
                raise AssertionError(f'unhandled Nix interpolation: {key}')
            return refs[key]
        return re.sub(r'\$\{([^{}]+)\}', replace, text)

    def schedule(self):
        def block(time, label, threshold):
            hour, minute = map(int,time.split(':'))
            return {'from':time, 'fromMinutes':hour*60+minute, 'label':label,
                    'rooms':{'office':{'coolAbove':threshold, 'heatBelow':60, 'priority':1}}}
        return {'days':{'saturday':'late', 'sunday':'early'}, 'patterns':{
            'late':[block('00:00','Asleep',82),block('09:30','Working',76),block('23:30','Wind-down',75)],
            'early':[block('00:00','Asleep',82),block('09:30','Working',76),block('22:00','Wind-down',75)]}}

    def render(self,name):
        return self.env.from_string(self.expand(raw_template(name))).render().strip()

    def test_drafts_do_not_change_live_mode_or_threshold(self):
        self.assertEqual(self.render('effectiveModeTemplate'),'cool')
        self.assertEqual(self.render('targetTemplate'),'75')
        self.values['timer.hvac_override_office']='active'
        self.assertEqual(self.render('effectiveModeTemplate'),'heat')
        self.assertEqual(self.render('targetTemplate'),'73')
        self.values['input_number.hvac_draft_office']='86'
        self.values['input_select.hvac_draft_mode']='cool'
        self.assertEqual(self.render('effectiveModeTemplate'),'heat')
        self.assertEqual(self.render('heatTargetTemplate'),'73')

    def test_expiry_restores_schedule_and_enable(self):
        self.values['input_boolean.hvac_enable_office']='off'
        self.values['timer.hvac_override_office']='active'
        self.assertEqual(self.render('desiredTemplate'),'off')
        self.values['timer.hvac_override_office']='idle'
        self.assertEqual(self.render('desiredTemplate'),'cool')
        self.assertEqual(self.render('effectiveModeTemplate'),'cool')
        self.assertEqual(self.render('heatTargetTemplate'),'60')

    def test_next_schedule_rolls_over_midnight(self):
        self.assertEqual(self.render('nextBlockTemplate'),'Asleep at 00:00')
        self.now=self.now.replace(hour=12)
        self.assertEqual(self.render('nextBlockTemplate'),'Wind-down at 23:30')
        self.now=self.now.replace(day=20)
        self.assertEqual(self.render('nextBlockTemplate'),'Wind-down at 22:00')

    def test_room_status_reports_missing_stale_and_waiting(self):
        self.assertEqual(self.render('roomStatus'),'Following schedule')
        self.values['sensor.ac_controller_office_temperature']='unavailable'
        self.assertEqual(self.render('roomStatus'),'Sensor unavailable')
        self.values['sensor.ac_controller_office_temperature']='78'
        self.reported=self.now-timedelta(minutes=16)
        self.assertEqual(self.render('roomStatus'),'Sensor stale')
        self.reported=self.now
        self.values['timer.hvac_min_off_office']='active'
        self.assertEqual(self.render('roomStatus'),'Waiting to restart')

    def test_restore_settings_and_no_background_draft_overwrite(self):
        selects=SOURCE.split('    input_select =',1)[1].split('    input_boolean =',1)[0]
        self.assertNotRegex(selects,r'\binitial\s*=')
        sync=SOURCE.split('  sliderSyncAutomation =',1)[1].split('  reconcileAutomation =',1)[0]
        self.assertIn('input_boolean.hvac_drafts_initialized',sync)
        self.assertNotIn('target.entity_id = overrideNumber',sync)

    def test_nap_uses_mode_and_does_not_edit_draft(self):
        expr=re.search(r'data.value = "(\{\{ \(\$\{toString sleeping.bedroom.heatBelow\}.*?\}\})"',SOURCE).group(1)
        sleeping=SOURCE.split('  sleeping =',1)[1].split('  working =',1)[0]
        bedroom=sleeping.split('bedroom =',1)[1].split('};',1)[0]
        for key in ('heatBelow','coolAbove'):
            value=re.search(rf'{key}\s*=\s*(\d+)',bedroom).group(1)
            expr=expr.replace('${toString sleeping.bedroom.'+key+'}',value)
        expr=expr.replace('${room}','office')
        t=self.env.from_string(expr)
        self.assertEqual(t.render(op='nap',nap_heat=True,value_office=80),'66')
        self.assertEqual(t.render(op='nap',nap_heat=False,value_office=80),'71')
        self.assertEqual(t.render(op='apply',nap_heat=True,value_office=80),'80')


class StateAccessor:
    def __init__(self,test):
        self.test=test
    def __call__(self,entity):
        return self.test.states(entity)
    @property
    def sensor(self):
        return SimpleNamespace(ac_controller_office_temperature=SimpleNamespace(last_reported=self.test.reported))


spec=importlib.util.spec_from_file_location('codes',ROOT/'generate-daikin-codes.py')
codes=importlib.util.module_from_spec(spec)
spec.loader.exec_module(codes)


class GeneratedCodes(unittest.TestCase):
    def setUp(self):
        self.table=json.loads((ROOT/'daikin-arc452a21.json').read_text())

    def test_entire_committed_table(self):
        self.assertEqual(codes.validate_generated(self.table),967)

    def mutate(self,frame_index,byte,value,repair_checksum):
        node=self.table['commands']['cool']['quiet']['comfort']
        pulses=codes.IR.base64_to_pulses(node['72'])
        span=codes.frame_spans(pulses)[frame_index]
        frame=bytearray(codes.read_frame(pulses,span))
        frame[byte]=value
        if repair_checksum:
            frame[-1]=codes.checksum(frame)
        node['72']=codes.IR.pulses_to_base64(codes.write_frame(pulses,span,frame))

    def test_rejects_bad_checksum_in_each_frame(self):
        original=copy.deepcopy(self.table)
        for index,byte in [(0,7),(1,7),(2,18)]:
            with self.subTest(frame=index):
                self.table=copy.deepcopy(original)
                self.mutate(index,byte,0,False)
                with self.assertRaisesRegex(ValueError,'checksum'):
                    codes.validate_generated(self.table)

    def test_rejects_wrong_quiet_fan_even_with_valid_checksum(self):
        self.mutate(2,8,0xA0,True)
        with self.assertRaisesRegex(ValueError,'fields'):
            codes.validate_generated(self.table)

    def test_rejects_comfort_and_swing_together(self):
        self.mutate(2,8,0xBF,True)
        with self.assertRaisesRegex(ValueError,'fields'):
            codes.validate_generated(self.table)

    def test_rejects_missing_comfort_bit(self):
        self.mutate(0,6,0,True)
        with self.assertRaisesRegex(ValueError,'fields'):
            codes.validate_generated(self.table)

    def test_rejects_incomplete_table(self):
        del self.table['commands']['heat']['quiet']['swing']['86']
        with self.assertRaisesRegex(ValueError,'incomplete'):
            codes.validate_generated(self.table)


if __name__=='__main__':
    unittest.main()
