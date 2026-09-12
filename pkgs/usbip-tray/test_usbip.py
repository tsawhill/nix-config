"""Hardware-free tests for privileged validation and lease cleanup."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helper = load('helper')
app = load('app')


class Leases(unittest.TestCase):
    def test_busids_reject_paths_options_and_shell(self):
        for value in ['../1-2', '--help', '1-2;id', '1-2\n', 'usb1', '0-0', '1-0']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                helper.busid(value)
        self.assertEqual(helper.busid('1-2.3'), '1-2.3')

    def test_hubs_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            device = Path(directory)
            (device / 'bDeviceClass').write_text('09\n')
            with self.assertRaisesRegex(ValueError, 'hubs'):
                helper.eligible(device)

    def test_mounted_storage_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            device = Path(directory)
            (device / 'bDeviceClass').write_text('00\n')
            block = device / 'block/sda/sda1'
            block.mkdir(parents=True)
            (block / 'dev').write_text('8:1\n')
            original = Path.read_text
            def read(path, *args, **kwargs):
                if str(path) == '/proc/self/mountinfo':
                    return '21 0 8:1 / /mnt/usb rw - ext4 /dev/sda1 rw\n'
                if str(path) == '/proc/swaps':
                    return 'Filename Type Size Used Priority\n'
                return original(path, *args, **kwargs)
            with patch.object(Path, 'read_text', read), self.assertRaisesRegex(ValueError, 'Unmount'):
                helper.eligible(device)

    def test_export_restores_driver_after_owner_eof(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root / '1-2'
            device.mkdir()
            calls = []
            def run(*args, **kwargs):
                calls.append(args)
                if args[1] == 'bind':
                    (device / 'driver').symlink_to(root / 'usbip-host')
            with patch.object(helper, 'USB', root), patch.object(helper, 'RUNTIME', root), \
                 patch.object(helper, 'eligible'), patch.object(helper, 'run', side_effect=run), \
                 patch.object(helper, 'alive', return_value=False), contextlib.redirect_stdout(io.StringIO()):
                helper.export({'usbip': 'usbip'}, '1-2')
            self.assertEqual([call[1] for call in calls], ['bind', 'unbind'])

    def test_unplug_removes_export_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root / '1-2'
            device.mkdir()
            match = root / 'match_busid'
            match.touch()
            def unplug():
                device.rmdir()
                return True
            with patch.object(helper, 'USB', root), patch.object(helper, 'RUNTIME', root), \
                 patch.object(helper, 'MATCH_BUSID', match), patch.object(helper, 'eligible'), \
                 patch.object(helper, 'run'), patch.object(helper, 'alive', side_effect=unplug), \
                 contextlib.redirect_stdout(io.StringIO()):
                helper.export({'usbip': 'usbip'}, '1-2')
            self.assertEqual(match.read_text(), 'del 1-2')

    def test_receive_detaches_only_allocated_port(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'port3').write_text('127.0.0.1 30000 1-2\n')
            snapshots = [{2: (6, '8-1'), 3: (4, '0-0')}, {2: (6, '8-1'), 3: (6, '8-2')}]
            with patch.object(helper, 'RUNTIME', root), patch.object(helper, 'RECORDS', root), \
                 patch.object(helper, 'ports', side_effect=snapshots), \
                 patch.object(helper, 'alive', return_value=False), patch.object(helper, 'run') as run:
                helper.receive({'usbip': 'usbip'}, '1-2', 30000, False)
            self.assertEqual(run.call_args.args, ('usbip', 'detach', '--port=3'))

    def test_attach_failure_still_detaches_recorded_port(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'port3').write_text('127.0.0.1 30000 1-2\n')
            calls = []
            def run(*args, **kwargs):
                calls.append(args)
                if 'attach' in args:
                    raise RuntimeError('attach failed after allocation')
            with patch.object(helper, 'RUNTIME', root), patch.object(helper, 'RECORDS', root), \
                 patch.object(helper, 'ports', side_effect=[{3: (4, '0-0')}, {3: (6, '8-2')}]), \
                 patch.object(helper, 'run', side_effect=run), self.assertRaises(RuntimeError):
                helper.receive({'usbip': 'usbip'}, '1-2', 30000, False)
            self.assertEqual(calls[-1], ('usbip', 'detach', '--port=3'))

    def test_container_and_tunnel_validation(self):
        with self.assertRaises(ValueError):
            helper.receive({}, '1-2', 30000, True)
        for port in [22, -1, 65536]:
            with self.assertRaises(ValueError):
                helper.receive({}, '1-2', port, False)

    def test_export_uses_resolved_helper_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper_path = root / 'store-helper'
            helper_path.touch()
            alias = root / 'profile-helper'
            alias.symlink_to(helper_path)
            with patch.object(app, 'HELPER', str(alias)):
                self.assertEqual(app.export_command('1-2'),
                                 [app.SUDO, '-n', str(helper_path), 'export', '1-2'])

    def test_receive_resolves_on_remote_host_and_quotes_arguments(self):
        command = app.receive_command('receive', '1-2', 30000)
        self.assertIn('"$(/run/current-system/sw/bin/readlink -e ' + app.HELPER + ')"', command)
        self.assertTrue(command.endswith(' receive 1-2 30000'))
        # Arguments must not become remote shell syntax.
        self.assertTrue(app.receive_command('receive', '1-2;false', 30000)
                        .endswith(" receive '1-2;false' 30000"))

    def test_unit_names_are_validated(self):
        self.assertEqual(app.unit('1-2.3'), 'usbip-port-1-2.3.service')
        with self.assertRaises(ValueError):
            app.unit('../bad')


if __name__ == '__main__':
    unittest.main()
