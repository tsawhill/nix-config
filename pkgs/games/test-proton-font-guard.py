import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("guard", Path(__file__).with_name("proton-font-guard.py"))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

STALE = b'"Old Font"="Z:\\\\nix\\\\store\\\\missing-font-guard-test\\\\font.ttf"\n'
HEADER = b'[Software\\\\Wine\\\\Fonts\\\\External Fonts] 123\n'


class FontGuardTests(unittest.TestCase):
    def test_only_missing_nix_fonts_removed(self):
        windows = b'"Arial"="arial.ttf"\n'
        existing = STALE.replace(b"missing-font-guard-test", b"existing-font-guard-test")
        unrelated = b'[Software\\\\Example]\n' + STALE
        data = HEADER + STALE + existing + windows + unrelated
        with patch.object(Path, "exists", lambda p: "existing-font-guard-test" in str(p)):
            updated, count = guard.prune(data)
        self.assertEqual(count, 1)
        self.assertEqual(updated, HEADER + existing + windows + unrelated)

    def test_backup_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix = root / "prefix"
            registry = prefix / "pfx"
            registry.mkdir(parents=True)
            state = root / "state"
            state.mkdir()
            source = registry / "user.reg"
            source.write_bytes(HEADER + STALE)
            source.chmod(0o640)
            with patch.object(guard, "active_prefix", return_value=False):
                guard.clean(prefix, state)
                guard.clean(prefix, state)
            backups = list(state.glob("backup-*/user.reg"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), HEADER + STALE)
            self.assertEqual(source.read_bytes(), HEADER)
            self.assertEqual(source.stat().st_mode & 0o777, 0o640)

    def test_running_prefix_is_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            source = prefix / "user.reg"
            source.write_bytes(HEADER + STALE)
            child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                     env={**os.environ, "WINEPREFIX": str(prefix / "pfx")})
            try:
                self.assertTrue(guard.active_prefix(guard.prefix_paths(prefix)))
                guard.clean(prefix, prefix)
                self.assertEqual(source.read_bytes(), HEADER + STALE)
                self.assertEqual(list(prefix.glob("backup-*")), [])
            finally:
                child.terminate()
                child.wait()

    def test_syncthing_change_aborts_write(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            source = prefix / "user.reg"
            source.write_bytes(HEADER + STALE)
            calls = 0

            def check(paths):
                nonlocal calls
                calls += 1
                if calls == 2:
                    source.write_bytes(b"new remote registry\n")
                return False

            with patch.object(guard, "active_prefix", side_effect=check):
                guard.clean(prefix, prefix)
            self.assertEqual(source.read_bytes(), b"new remote registry\n")

    def test_launcher_preserves_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, str(Path(guard.__file__)), directory,
                 sys.executable, "-c", "import sys; assert sys.argv[1] == 'with spaces'; sys.exit(7)",
                 "with spaces"], env={**os.environ, "XDG_STATE_HOME": directory})
            self.assertEqual(result.returncode, 7)


if __name__ == "__main__":
    unittest.main()
