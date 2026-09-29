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
    def tuya_io_methods(self):
        cls = extract('tuya_local/device.py', 'TuyaLocalDevice')
        ns = dict(_LOGGER=logging.getLogger('test'), log_json=lambda value: value,
                  CancelledError=asyncio.CancelledError)
        for name in ('_send_pending_updates', 'async_refresh', 'async_receive'):
            compile_node(next(n for n in cls.body if getattr(n, 'name', '') == name), ns)
        return ns

    async def test_write_waits_for_receive_and_snapshots_after_acquiring_lock(self):
        ns = self.tuya_io_methods()
        lock = asyncio.Lock()
        calls = []
        pending = {'1': 'old'}
        async def retry(func, message, **kwargs):
            self.assertTrue(lock.locked())
            self.assertTrue(kwargs['raise_on_failure'])
            func()
        def snapshot():
            calls.append('snapshot')
            return dict(pending)
        obj = SimpleNamespace(_api_lock=lock, _get_unsent_properties=snapshot,
                              _set_values=lambda values: calls.append(values),
                              _retry_on_failed_connection=retry, name='test')
        # A receive/status operation owns the same lock until it completes.
        async with lock:
            task = asyncio.create_task(ns['_send_pending_updates'](obj))
            await asyncio.sleep(0)
            self.assertFalse(task.done())
            self.assertEqual(calls, [])
            pending['1'] = 'new'
        await asyncio.wait_for(task, 1)
        self.assertEqual(calls, ['snapshot', {'1': 'new'}])
        self.assertFalse(lock.locked())

    async def test_failed_write_holds_lock_through_retry_then_releases_it(self):
        ns = self.tuya_io_methods()
        lock = asyncio.Lock()
        entered, release = asyncio.Event(), asyncio.Event()
        async def retry(*args, **kwargs):
            entered.set()
            await release.wait()
            self.assertTrue(lock.locked())
            raise ConnectionError('retries exhausted')
        obj = SimpleNamespace(_api_lock=lock, name='test',
                              _get_unsent_properties=lambda: {'1': 'command'},
                              _retry_on_failed_connection=retry)
        task = asyncio.create_task(ns['_send_pending_updates'](obj))
        await asyncio.wait_for(entered.wait(), 1)
        receiver = asyncio.create_task(lock.acquire())
        await asyncio.sleep(0)
        receiver_was_blocked = not receiver.done()
        release.set()
        with self.assertRaises(ConnectionError):
            await task
        await asyncio.wait_for(receiver, 1)
        lock.release()
        self.assertTrue(receiver_was_blocked)

    async def test_cancelled_receive_waiter_cannot_close_or_unlock_writer(self):
        ns = self.tuya_io_methods()
        persistence = []
        obj = SimpleNamespace(should_poll=False, _running=True,
                              _api_working_protocol_failures=0,
                              _api_lock=asyncio.Lock(), _cached_state={},
                              _api=SimpleNamespace(parent=None,
                                  set_socketPersistent=persistence.append))
        generator = ns['async_receive'](obj)
        async with obj._api_lock:
            task = asyncio.create_task(anext(generator))
            await asyncio.sleep(0)
            self.assertFalse(task.done())
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            self.assertTrue(obj._api_lock.locked())
            self.assertNotIn(False, persistence)
        await generator.aclose()

    async def test_already_drained_write_batch_does_not_resend(self):
        ns = self.tuya_io_methods()
        async def retry(*args, **kwargs):
            self.fail('empty batch must not touch transport')
        obj = SimpleNamespace(_api_lock=asyncio.Lock(), name='test',
                              _get_unsent_properties=lambda: {},
                              _retry_on_failed_connection=retry)
        await ns['_send_pending_updates'](obj)

    async def test_startup_refresh_waits_for_io_and_rechecks_monitor(self):
        ns = self.tuya_io_methods()
        calls = []
        async def retry(func, message):
            self.assertTrue(obj._api_lock.locked())
            calls.append('refresh')
        obj = SimpleNamespace(_api_lock=asyncio.Lock(), name='test',
                              _running=False, _retry_on_failed_connection=retry)
        async with obj._api_lock:
            task = asyncio.create_task(ns['async_refresh'](obj))
            await asyncio.sleep(0)
            self.assertFalse(task.done())
            obj._running = True
        await asyncio.wait_for(task, 1)
        self.assertEqual(calls, [])
        obj._running = False
        await ns['async_refresh'](obj)
        self.assertEqual(calls, ['refresh'])

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
            _api=SimpleNamespace(close=lambda: None, parent=None),
            _reset_cached_state=lambda: None, _api_working_protocol_failures=0,
            _AUTO_FAILURE_RESET_COUNT=10)
        with self.assertLogs('test', level='ERROR'):
            with self.assertRaises(ConnectionError):
                await ns['_retry_on_failed_connection'](obj, fail, 'failed write', raise_on_failure=True)
        self.assertIsNone(await ns['_retry_on_failed_connection'](obj, fail, 'failed poll'))

    async def test_retry_preserves_persistence_and_closes_parent(self):
        tree = ast.parse((ROOT / 'tuya_local/device.py').read_text())
        method = next(n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef) and n.name == '_retry_on_failed_connection')
        ns = {'_LOGGER': logging.getLogger('test')}
        compile_node(method, ns)
        for persistent in [True, False]:
            closes = []
            parent = SimpleNamespace(socketPersistent=persistent, close=lambda: closes.append('parent'))
            api = SimpleNamespace(socketPersistent=persistent, parent=parent, close=lambda: closes.append('device'))
            calls = 0
            async def execute(func):
                return func()
            def operation():
                nonlocal calls
                calls += 1
                if calls == 1:
                    raise ConnectionError('transient')
                return {'ok': True}
            obj = SimpleNamespace(_api_protocol_version_index=0, _protocol_configured='3.4',
                _api_protocol_working=True, _SINGLE_PROTO_CONNECTION_ATTEMPTS=2,
                _hass=SimpleNamespace(is_stopping=False, async_add_executor_job=execute),
                _api=api, _api_working_protocol_failures=0)
            self.assertEqual(await ns['_retry_on_failed_connection'](obj, operation, 'failed'), {'ok': True})
            self.assertEqual(closes, ['device', 'parent'])
            self.assertEqual(api.socketPersistent, persistent)
            self.assertEqual(parent.socketPersistent, persistent)

    async def test_heartbeat_does_not_open_a_second_session(self):
        tree = ast.parse((ROOT / 'tuya_local/device.py').read_text())
        method = next(n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef) and n.name == 'async_receive')
        branch = next(n for n in ast.walk(method) if isinstance(n, ast.If) and isinstance(n.test, ast.Name) and n.test.id == 'persist')
        wrapper = ast.parse('async def run(self):\n    now = 100\n    last_heartbeat = 0\n').body[0]
        wrapper.body.extend(branch.body)
        ns = {}
        compile_node(ast.fix_missing_locations(wrapper), ns)
        for connected in [False, True]:
            calls = []
            api = SimpleNamespace(parent=None, socket=object() if connected else None, socketPersistent=False)
            api.set_socketPersistent = lambda value: setattr(api, 'socketPersistent', value)
            api.heartbeat = lambda nowait: calls.append('heartbeat')
            api.receive = lambda: calls.append('receive')
            async def execute(func, *args):
                return func(*args)
            obj = SimpleNamespace(_api=api, _HEARTBEAT_INTERVAL=5,
                                  _hass=SimpleNamespace(async_add_executor_job=execute))
            await ns['run'](obj)
            self.assertTrue(api.socketPersistent)
            self.assertEqual(calls, ['heartbeat', 'receive'] if connected else ['receive'])


if __name__ == '__main__':
    unittest.main()
