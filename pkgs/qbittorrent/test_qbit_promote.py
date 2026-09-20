import unittest

from qbit_promote import (
    PromotionError,
    add_fields,
    build_multipart,
    promote,
    read_event,
    wait_until_seeding,
)


class FakeClient:
    """Stands in for QbitClient, recording every call made against it."""

    def __init__(self, torrents=None, export=b"torrent-bytes"):
        self.torrents = dict(torrents or {})
        self.export = export
        self.posts = []
        self.multiparts = []

    def torrent(self, torrent_hash):
        return self.torrents.get(torrent_hash)

    def get(self, path, params):
        return self.export

    def post(self, path, fields):
        self.posts.append((path, fields))
        return b""

    def post_multipart(self, path, fields, file_field, filename, content):
        self.multiparts.append((path, fields, filename, content))
        return b""


def seeded(name="Album", save_path="/mnt/downloadSSD/Seeding", category="music-seed"):
    return {
        "name": name,
        "save_path": save_path,
        "category": category,
        "progress": 1.0,
        "state": "uploading",
    }


class ReadEventTests(unittest.TestCase):
    def test_reads_hash_from_any_arr(self):
        for prefix in ("sonarr", "radarr", "lidarr"):
            env = {f"{prefix}_eventtype": "Download", f"{prefix}_download_id": "ABCDEF"}
            self.assertEqual(read_event(env), ("Download", "abcdef"))

    def test_reads_the_capitalised_names_the_arrs_actually_set(self):
        # Sonarr sets Sonarr_EventType / Sonarr_Download_Id, and environment
        # variables are case-sensitive, so a lowercase-only lookup sees nothing.
        for prefix in ("Sonarr", "Radarr", "Lidarr"):
            env = {f"{prefix}_EventType": "Download", f"{prefix}_Download_Id": "ABCDEF"}
            self.assertEqual(read_event(env), ("Download", "abcdef"))

    def test_event_type_matching_is_case_insensitive(self):
        env = {"Sonarr_EventType": "download", "Sonarr_Download_Id": "AbC"}
        self.assertEqual(read_event(env), ("download", "abc"))

    def test_test_event_is_a_no_op(self):
        eventtype, torrent_hash = read_event({"sonarr_eventtype": "Test"})
        self.assertEqual(eventtype, "Test")
        self.assertIsNone(torrent_hash)

    def test_unrelated_event_is_a_no_op(self):
        _, torrent_hash = read_event({"sonarr_eventtype": "Grab"})
        self.assertIsNone(torrent_hash)

    def test_import_without_download_id_is_an_error(self):
        with self.assertRaises(PromotionError):
            read_event({"sonarr_eventtype": "Download"})

    def test_missing_event_type_is_an_error(self):
        with self.assertRaises(PromotionError):
            read_event({})


class AddFieldsTests(unittest.TestCase):
    def test_never_enables_automatic_torrent_management(self):
        # AutoTMM would relocate the data instead of seeding it in place.
        self.assertEqual(add_fields(seeded(), "music-seed")["autoTMM"], "false")

    def test_preserves_the_save_path_verbatim(self):
        torrent = seeded(save_path="/mnt/downloadHDD/downloads/sonarr")
        self.assertEqual(
            add_fields(torrent, "sonarr")["savepath"], "/mnt/downloadHDD/downloads/sonarr"
        )

    def test_keeps_original_content_layout(self):
        self.assertEqual(add_fields(seeded(), "x")["contentLayout"], "Original")


class MultipartTests(unittest.TestCase):
    def test_carries_fields_and_file_content(self):
        content_type, body = build_multipart(
            {"savepath": "/data"}, "torrents", "abc.torrent", b"\x00binary"
        )
        self.assertTrue(content_type.startswith("multipart/form-data; boundary="))
        self.assertIn(b'name="savepath"', body)
        self.assertIn(b"/data", body)
        self.assertIn(b'filename="abc.torrent"', body)
        self.assertIn(b"\x00binary", body)


class WaitUntilSeedingTests(unittest.TestCase):
    def test_returns_once_complete(self):
        client = FakeClient({"abc": seeded()})
        self.assertEqual(wait_until_seeding(client, "abc")["progress"], 1.0)

    def test_raises_on_broken_state(self):
        client = FakeClient({"abc": dict(seeded(), state="missingFiles")})
        with self.assertRaises(PromotionError):
            wait_until_seeding(client, "abc")

    def test_times_out_when_the_torrent_never_appears(self):
        with self.assertRaises(PromotionError):
            wait_until_seeding(FakeClient(), "abc", timeout=0, sleep=lambda _: None)


class PromoteTests(unittest.TestCase):
    def test_adds_to_seeding_then_deletes_from_intake_without_files(self):
        intake = FakeClient({"abc": seeded()})
        seeding = FakeClient()

        def appear(_):
            seeding.torrents["abc"] = seeded()

        promote(intake, seeding, "abc", sleep=appear)

        self.assertEqual(seeding.multiparts[0][0], "torrents/add")
        path, fields = intake.posts[0]
        self.assertEqual(path, "torrents/delete")
        # Deleting files here would destroy the data the seeding instance
        # has just been pointed at.
        self.assertEqual(fields["deleteFiles"], "false")

    def test_leaves_torrent_on_intake_when_seeding_never_completes(self):
        intake = FakeClient({"abc": seeded()})
        seeding = FakeClient()

        with self.assertRaises(PromotionError):
            promote(intake, seeding, "abc", timeout=0, sleep=lambda _: None)

        self.assertEqual(intake.posts, [])

    def test_leaves_torrent_on_intake_when_seeding_reports_an_error(self):
        intake = FakeClient({"abc": seeded()})
        seeding = FakeClient({"abc": dict(seeded(), state="error")})
        seeding.torrents.pop("abc")

        def appear(_):
            seeding.torrents["abc"] = dict(seeded(), state="error")

        with self.assertRaises(PromotionError):
            promote(intake, seeding, "abc", sleep=appear)

        self.assertEqual(intake.posts, [])

    def test_refuses_when_not_on_intake(self):
        with self.assertRaises(PromotionError):
            promote(FakeClient(), FakeClient(), "abc")

    def test_refuses_when_already_on_seeding(self):
        intake = FakeClient({"abc": seeded()})
        seeding = FakeClient({"abc": seeded()})

        with self.assertRaises(PromotionError):
            promote(intake, seeding, "abc")

        self.assertEqual(intake.posts, [])


if __name__ == "__main__":
    unittest.main()
