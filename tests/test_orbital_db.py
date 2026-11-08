import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path


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
            self.assertEqual(db.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 1)

    def test_cli_bounds_and_malformed_json(self):
        env = {**os.environ, "XDG_DATA_HOME": self.temp.name}
        script = ROOT / "backend" / "orbital_db.py"
        for payload, expected in ((b"not json", "invalid_json"), (b"x" * 16385, "request_too_large")):
            result = subprocess.run([sys.executable, str(script)], input=payload, capture_output=True, env=env, check=True)
            self.assertIn(expected.encode(), result.stdout)


if __name__ == "__main__":
    unittest.main()
