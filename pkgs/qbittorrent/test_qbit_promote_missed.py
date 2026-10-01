import io
import json
import os
import tempfile
import unittest

from qbit_promote import PromotionError
from qbit_promote_missed import ArrClient, classify, read_api_key


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def opener_returning(payload, seen=None):
    def opener(request, timeout):
        if seen is not None:
            seen.append(request)
        return FakeResponse(json.dumps(payload).encode())

    return opener


class FakeQbit:
    def __init__(self, torrents):
        self.torrents = torrents

    def get_json(self, path, params):
        return self.torrents


class FakeArr:
    def __init__(self, name, imported=(), error=None):
        self.name = name
        self.hashes = set(imported)
        self.error = error

    def imported(self, torrent_hash):
        if self.error:
            raise PromotionError(self.error)
        return torrent_hash in self.hashes


def torrent(torrent_hash, progress=1.0):
    return {"hash": torrent_hash, "name": torrent_hash, "progress": progress, "category": "radarr"}


class ReadApiKeyTests(unittest.TestCase):
    def read(self, content):
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write(content)
        try:
            return read_api_key(handle.name)
        finally:
            os.unlink(handle.name)

    def test_environment_file(self):
        self.assertEqual(self.read("SONARR__AUTH__APIKEY=abc123\n"), "abc123")

    def test_quoted_value(self):
        self.assertEqual(self.read('KEY="abc123"\n'), "abc123")

    def test_bare_key(self):
        self.assertEqual(self.read("abc123\n"), "abc123")

    def test_empty_file_is_an_error(self):
        with self.assertRaises(PromotionError):
            self.read("\n")


class ArrClientTests(unittest.TestCase):
    def test_import_event_for_this_hash_counts(self):
        seen = []
        payload = {"records": [{"downloadId": "ABCDEF", "eventType": "downloadFolderImported"}]}
        arr = ArrClient("sonarr", "http://x/", "v3", "key", opener=opener_returning(payload, seen))
        self.assertTrue(arr.imported("abcdef"))
        self.assertIn("downloadId=ABCDEF", seen[0].full_url)
        self.assertEqual(seen[0].get_header("X-api-key"), "key")

    def test_lidarr_track_import_counts(self):
        payload = {"records": [{"downloadId": "ABCDEF", "eventType": "trackFileImported"}]}
        arr = ArrClient("lidarr", "http://x", "v1", "key", opener=opener_returning(payload))
        self.assertTrue(arr.imported("abcdef"))

    def test_grab_alone_does_not_count(self):
        payload = {"records": [{"downloadId": "ABCDEF", "eventType": "grabbed"}]}
        arr = ArrClient("radarr", "http://x", "v3", "key", opener=opener_returning(payload))
        self.assertFalse(arr.imported("abcdef"))

    def test_other_hashes_do_not_count(self):
        # An *arr that ignores the downloadId filter returns unrelated history.
        payload = {"records": [{"downloadId": "OTHER", "eventType": "downloadFolderImported"}]}
        arr = ArrClient("radarr", "http://x", "v3", "key", opener=opener_returning(payload))
        self.assertFalse(arr.imported("abcdef"))


class ClassifyTests(unittest.TestCase):
    def test_sorts_torrents_by_state(self):
        intake = FakeQbit([torrent("a"), torrent("b"), torrent("c"), torrent("d", progress=0.5)])
        seeding = FakeQbit([torrent("c")])
        arrs = [FakeArr("sonarr"), FakeArr("radarr", imported={"a", "d"})]

        ready, unimported, duplicated = classify(intake, seeding, arrs, warn=lambda m: None)

        self.assertEqual([(arr, t["hash"]) for arr, t in ready], [("radarr", "a")])
        self.assertEqual([t["hash"] for t in unimported], ["b"])
        self.assertEqual([t["hash"] for t in duplicated], ["c"])

    def test_unreachable_arr_is_never_treated_as_an_import(self):
        warnings = []
        intake = FakeQbit([torrent("a")])
        arrs = [FakeArr("lidarr", error="lidarr: down"), FakeArr("radarr", imported={"a"})]

        ready, unimported, _ = classify(intake, FakeQbit([]), arrs, warn=warnings.append)
        self.assertEqual([arr for arr, _ in ready], ["radarr"])
        self.assertEqual(warnings, ["lidarr: down"])

        ready, unimported, _ = classify(intake, FakeQbit([]), arrs[:1], warn=warnings.append)
        self.assertEqual(ready, [])
        self.assertEqual([t["hash"] for t in unimported], ["a"])


if __name__ == "__main__":
    unittest.main()
