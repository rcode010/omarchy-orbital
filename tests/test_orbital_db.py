import os
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

import orbital_db


class ActivityStorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "data" / "orbital.sqlite3"

    def tearDown(self):
        self.temp.cleanup()

    def call(self, command, **fields):
        return orbital_db.run({"command": command, **fields}, self.path)

    def test_create_select_rename_and_archive(self):
        first = self.call("activities.create", name="Studying", color="blue")["activity_id"]
        second = self.call("activities.create", name="Reading", icon="📖", color="green")["activity_id"]
        self.assertEqual(self.call("activities.list")["selected_activity_id"], first)
        self.call("activities.select", activity_id=second)
        self.call("activities.update", activity_id=second, name="Books", color="purple")
        self.assertEqual(self.call("activities.list")["activities"][1]["name"], "Books")
        self.call("activities.archive", activity_id=second)
        self.assertEqual(len(self.call("activities.list")["activities"]), 1)
        self.assertIsNone(self.call("activities.list")["selected_activity_id"])
        self.call("activities.restore", activity_id=second)
        self.assertEqual(len(self.call("activities.list")["activities"]), 2)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)

    def test_invalid_inputs_leave_database_unchanged(self):
        self.call("activities.create", name="Exercise")
        for request in (
            {"command": "activities.create", "name": "  "},
            {"command": "activities.create", "name": "A" * 81},
            {"command": "activities.create", "name": "Reading", "color": "#not-a-token"},
            {"command": "activities.update", "activity_id": "missing", "name": "Changed"},
        ):
            with self.assertRaises(orbital_db.RequestError):
                orbital_db.run(request, self.path)
        self.assertEqual(len(self.call("activities.list")["activities"]), 1)

    def test_restart_preserves_selection(self):
        activity_id = self.call("activities.create", name="Project")["activity_id"]
        self.assertEqual(self.call("activities.list")["selected_activity_id"], activity_id)
        with closing(orbital_db.connect(self.path)) as db:
            self.assertEqual(db.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 2)

    def test_finish_early_saves_active_time_once(self):
        self.call("activities.create", name="Study")
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=[0, 17 * 60 * 1_000_000_000, 17 * 60 * 1_000_000_000]
        ):
            self.call("timer.start", mode="focus", planned_seconds=1500)
            finished = self.call("timer.finish")
            repeated = self.call("timer.finish")
        self.assertEqual(finished["active_seconds"], 1020)
        self.assertTrue(finished["saved"])
        self.assertFalse(repeated["saved"])
        with closing(orbital_db.connect(self.path)) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT active_seconds FROM sessions").fetchone()[0], 1020)

    def test_pause_excludes_time_and_discard_saves_nothing(self):
        self.call("activities.create", name="Project")
        seconds = [0, 600, 1800, 2400, 3000]
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=[value * 1_000_000_000 for value in seconds]
        ):
            self.call("timer.start", mode="stopwatch")
            self.call("timer.pause")
            self.call("timer.resume")
            finished = self.call("timer.finish")
            self.call("timer.start", mode="focus")
        self.assertEqual(finished["active_seconds"], 1200)
        with patch.object(orbital_db.time, "monotonic_ns", return_value=3100 * 1_000_000_000):
            self.call("timer.discard")
        with closing(orbital_db.connect(self.path)) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0], 1)

    def test_load_pauses_without_inventing_downtime(self):
        self.call("activities.create", name="Reading")
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", return_value=1000
        ):
            self.call("timer.start", mode="focus")
        recovered = self.call("timer.load")
        self.assertEqual(recovered["phase"], "paused")
        self.assertEqual(recovered["active_ms"], 0)

    def test_checkpoint_survives_reload_without_counting_unknown_time(self):
        self.call("activities.create", name="Writing")
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=[0, 60 * 1_000_000_000]
        ):
            self.call("timer.start", mode="focus")
            checkpoint = self.call("timer.checkpoint")
        self.assertEqual(checkpoint["active_ms"], 60000)
        recovered = self.call("timer.load")
        self.assertEqual(recovered["phase"], "paused")
        self.assertEqual(recovered["active_ms"], 60000)

    def test_natural_completion_waits_for_active_duration_and_is_idempotent(self):
        self.call("activities.create", name="Design")
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=[0, 30 * 1_000_000_000,
                                                            60 * 1_000_000_000,
                                                            60 * 1_000_000_000,
                                                            60 * 1_000_000_000]
        ):
            self.call("timer.start", mode="focus", planned_seconds=60)
            early = self.call("timer.complete")
            completed = self.call("timer.complete")
            repeated = self.call("timer.complete")
        self.assertFalse(early["completed"])
        self.assertTrue(completed["completed"])
        self.assertFalse(repeated["completed"])
        with closing(orbital_db.connect(self.path)) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT reason FROM sessions").fetchone()[0], "completed")

    def test_cli_bounds_and_malformed_json(self):
        env = {**os.environ, "XDG_DATA_HOME": self.temp.name}
        script = ROOT / "backend" / "orbital_db.py"
        for payload, expected in ((b"not json", "invalid_json"), (b"x" * 16385, "request_too_large")):
            result = subprocess.run([sys.executable, str(script)], input=payload, capture_output=True, env=env, check=True)
            self.assertIn(expected.encode(), result.stdout)

    def test_symlink_database_is_refused(self):
        target = Path(self.temp.name) / "other.sqlite3"
        target.touch()
        self.path.parent.mkdir()
        self.path.symlink_to(target)
        with self.assertRaises(orbital_db.RequestError) as error:
            self.call("activities.list")
        self.assertEqual(error.exception.code, "unsafe_path")

    def test_argument_array_protocol_creates_activity(self):
        env = {**os.environ, "XDG_DATA_HOME": self.temp.name}
        script = ROOT / "backend" / "orbital_db.py"
        request = json.dumps({"command": "activities.create", "name": "Reading & writing $(safe)"})
        result = subprocess.run([sys.executable, str(script), request], capture_output=True, env=env, check=True)
        self.assertTrue(json.loads(result.stdout)["ok"])
        listed = subprocess.run([sys.executable, str(script), '{"command":"activities.list"}'],
                                capture_output=True, env=env, check=True)
        self.assertEqual(json.loads(listed.stdout)["result"]["activities"][0]["name"],
                         "Reading & writing $(safe)")


if __name__ == "__main__":
    unittest.main()
