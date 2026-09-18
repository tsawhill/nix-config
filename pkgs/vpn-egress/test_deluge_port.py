import json
import stat
import tempfile
import unittest
from pathlib import Path

from deluge_port import configure


class DelugePortTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "core.conf"

    def read_config(self):
        text = self.path.read_text()
        version, offset = json.JSONDecoder().raw_decode(text)
        return version, json.loads(text[offset:])

    def test_preserves_existing_settings_and_version(self):
        version = {"file": 1, "format": 1}
        self.path.write_text(json.dumps(version) + '\n' + json.dumps({
            "download_location": "/downloads", "random_port": True,
            "listen_ports": [12345, 12346], "upnp": True, "natpmp": True,
        }))
        configure(self.path, "54321")
        actual_version, settings = self.read_config()
        self.assertEqual(actual_version, version)
        self.assertEqual(settings["download_location"], "/downloads")
        self.assertEqual(settings["listen_ports"], [54321, 54321])
        for key in ("random_port", "upnp", "natpmp"):
            self.assertFalse(settings[key])
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_creates_initial_config_and_handles_port_change(self):
        configure(self.path, "54321")
        configure(self.path, "54322")
        self.assertEqual(self.read_config()[1]["listen_ports"], [54322, 54322])

    def test_bad_port_does_not_modify_existing_file(self):
        self.path.write_text('existing configuration')
        for value in ("0", "65536", "-1", "123; flush ruleset", "1\n2", "abc"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                configure(self.path, value)
            self.assertEqual(self.path.read_text(), 'existing configuration')

    def test_malformed_config_is_not_overwritten(self):
        self.path.write_text('{"file": 1}\nnot json')
        with self.assertRaises(ValueError):
            configure(self.path, "54321")
        self.assertEqual(self.path.read_text(), '{"file": 1}\nnot json')


if __name__ == "__main__":
    unittest.main()
