"""Offline tests against patched SmartIR/Tuya source, without HA or credentials.

Usage: python test-delivery.py /path/to/custom_components
"""
import ast
import asyncio
import logging
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

ROOT = Path(sys.argv.pop(1))


def extract(path, name):
    tree = ast.parse((ROOT / path).read_text())
    return next(n for n in tree.body if isinstance(n, (ast.ClassDef, ast.FunctionDef)) and n.name == name)


def compile_node(node, namespace):
    exec(compile(ast.Module(body=[node], type_ignores=[]), '<integration>', 'exec'), namespace)


class Delivery(unittest.IsolatedAsyncioTestCase):
    def controller(self, service):
        ns = dict(AbstractController=object, ENC_BASE64='Base64', ENC_HEX='Hex',
                  ENC_PRONTO='Pronto', ATTR_ENTITY_ID='entity_id')
        compile_node(extract('smartir/controller.py', 'BroadlinkController'), ns)
        c = ns['BroadlinkController']()
        c._encoding = 'Base64'
        c._controller_data = 'remote.test'
        c._delay = .5
        c.hass = SimpleNamespace(services=SimpleNamespace(async_call=service))
        return c

    async def test_remote_service_completion_is_awaited(self):
        entered, release = asyncio.Event(), asyncio.Event()
        async def service(*args, blocking=False):
            self.assertTrue(blocking)
            entered.set()
            await release.wait()
        task = asyncio.create_task(self.controller(service).send('test'))
        await entered.wait()
        self.assertFalse(task.done())
        release.set()
        await task

    async def test_transport_error_reaches_caller(self):
        async def service(*args, **kwargs):
            raise ConnectionError('offline')
        with self.assertRaises(ConnectionError):
            await self.controller(service).send('test')

    async def test_failed_mode_change_restores_requested_state(self):
        ns = dict(HVACMode=SimpleNamespace(OFF='off'))
        compile_node(extract('smartir/climate.py', 'restore_on_send_failure'), ns)
        cls = extract('smartir/climate.py', 'SmartIRClimate')
        method = next(n for n in cls.body if isinstance(n, ast.AsyncFunctionDef) and n.name == 'async_set_hvac_mode')
        compile_node(method, ns)
        async def fail():
            raise ConnectionError('offline')
        obj = SimpleNamespace(_hvac_mode='cool', _target_temperature=72,
                              _last_on_operation='cool', _current_fan_mode='auto',
                              _current_swing_mode='off', send_command=fail,
                              async_write_ha_state=lambda: None)
        with self.assertRaises(ConnectionError):
            await ns['async_set_hvac_mode'](obj, 'off')
        self.assertEqual(obj._hvac_mode, 'cool')

    async def test_smartir_does_not_swallow_send_failure(self):
        cls = extract('smartir/climate.py', 'SmartIRClimate')
        method = next(n for n in cls.body if isinstance(n, ast.AsyncFunctionDef) and n.name == 'send_command')
        ns = dict(HVACMode=SimpleNamespace(OFF='off'), _LOGGER=logging.getLogger('test'))
        compile_node(method, ns)
        async def fail(command):
            raise ConnectionError('offline')
        obj = SimpleNamespace(_temp_lock=asyncio.Lock(), _hvac_mode='off',
                              _current_fan_mode='auto', _current_swing_mode='off',
                              _target_temperature=72, _commands={'off':'test'},
                              _controller=SimpleNamespace(send=fail))
        with self.assertLogs('test', level='ERROR'):
            with self.assertRaises(ConnectionError):
                await ns['send_command'](obj)

    async def test_tuya_exhausted_writes_raise_but_polling_does_not(self):
        tree = ast.parse((ROOT / 'tuya_local/device.py').read_text())
        cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and any(getattr(m, 'name', '') == '_retry_on_failed_connection' for m in n.body))
        method = next(n for n in cls.body if getattr(n, 'name', '') == '_retry_on_failed_connection')
        ns = {'_LOGGER': logging.getLogger('test')}
        compile_node(method, ns)
        async def execute(func):
            return func()
        def fail():
            raise ConnectionError('offline')
        obj = SimpleNamespace(_api_protocol_version_index=0, _protocol_configured='3.3',
            _api_protocol_working=True, _SINGLE_PROTO_CONNECTION_ATTEMPTS=2,
            _hass=SimpleNamespace(is_stopping=False, async_add_executor_job=execute),
            _api=SimpleNamespace(set_socketPersistent=lambda value: None, parent=None),
            _reset_cached_state=lambda: None, _api_working_protocol_failures=0,
            _AUTO_FAILURE_RESET_COUNT=10)
        with self.assertLogs('test', level='ERROR'):
            with self.assertRaises(ConnectionError):
                await ns['_retry_on_failed_connection'](obj, fail, 'failed write', raise_on_failure=True)
        self.assertIsNone(await ns['_retry_on_failed_connection'](obj, fail, 'failed poll'))


if __name__ == '__main__':
    unittest.main()
