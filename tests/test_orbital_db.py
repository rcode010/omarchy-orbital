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
            self.assertEqual(db.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 4)

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

    def test_day_summary_splits_work_and_excludes_pause(self):
        self.call("activities.create", name="Thesis")
        wall_times = ["2026-11-08T20:50:00.000+00:00", "2026-11-08T21:00:00.000+00:00",
                      "2026-11-08T22:00:00.000+00:00", "2026-11-08T22:10:00.000+00:00"]
        mono_times = [0, 600, 4200, 4800]
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db, "utc_now", side_effect=wall_times
        ), patch.object(orbital_db.time, "monotonic_ns",
                        side_effect=[value * 1_000_000_000 for value in mono_times]):
            self.call("timer.start", mode="stopwatch")
            self.call("timer.pause")
            self.call("timer.resume")
            self.call("timer.finish")
        first = self.call("reports.day", day="2026-11-08", zone="Asia/Baghdad")
        second = self.call("reports.day", day="2026-11-09", zone="Asia/Baghdad")
        self.assertEqual(first["total_ms"], 600000)
        self.assertEqual(second["total_ms"], 600000)
        self.assertEqual(first["session_count"], 1)
        self.assertEqual(second["session_count"], 1)
        self.assertEqual(len(self.call("sessions.recent")["sessions"]), 1)

    def test_dst_day_boundaries_and_split(self):
        activity_id = self.call("activities.create", name="Study")["activity_id"]
        with closing(orbital_db.connect(self.path)) as db, db:
            db.execute("INSERT INTO sessions (id, activity_id, mode, source, started_at, ended_at, "
                       "active_seconds, reason) VALUES ('dst', ?, 'focus', 'measured', ?, ?, 3600, 'completed')",
                       (activity_id, "2026-03-08T04:30:00.000+00:00", "2026-03-08T05:30:00.000+00:00"))
            db.execute("INSERT INTO work_segments VALUES ('dst', ?, ?, 3600000)",
                       ("2026-03-08T04:30:00.000+00:00", "2026-03-08T05:30:00.000+00:00"))
        previous = self.call("reports.day", day="2026-03-07", zone="America/New_York")
        next_day = self.call("reports.day", day="2026-03-08", zone="America/New_York")
        self.assertEqual(previous["total_ms"], 1800000)
        self.assertEqual(next_day["total_ms"], 1800000)
        _, start, end = orbital_db.day_bounds({"day": "2026-03-08", "zone": "America/New_York"})
        self.assertEqual((end - start).total_seconds(), 23 * 3600)
        _, start, end = orbital_db.day_bounds({"day": "2026-11-01", "zone": "America/New_York"})
        self.assertEqual((end - start).total_seconds(), 25 * 3600)

    def test_archiving_active_activity_preserves_timer(self):
        activity_id = self.call("activities.create", name="Exercise")["activity_id"]
        with patch.object(orbital_db, "boot_id", return_value="boot"):
            self.call("timer.start", mode="stopwatch")
        with self.assertRaises(orbital_db.RequestError) as error:
            self.call("activities.archive", activity_id=activity_id)
        self.assertEqual(error.exception.code, "timer_active")
        self.assertEqual(self.call("activities.list")["selected_activity_id"], activity_id)
        self.assertEqual(self.call("timer.checkpoint")["phase"], "paused")

    def test_delete_refuses_history_and_allows_unused_activity(self):
        used = self.call("activities.create", name="Study")["activity_id"]
        unused = self.call("activities.create", name="One-off")["activity_id"]
        with closing(orbital_db.connect(self.path)) as db, db:
            db.execute("INSERT INTO sessions (id, activity_id, mode, source, started_at, ended_at, "
                       "active_seconds, reason) VALUES ('saved', ?, 'focus', 'measured', ?, ?, 60, 'completed')",
                       (used, "2026-11-08T12:00:00.000+00:00", "2026-11-08T12:01:00.000+00:00"))
        with self.assertRaises(orbital_db.RequestError) as error:
            self.call("activities.delete", activity_id=used)
        self.assertEqual(error.exception.code, "history_exists")
        self.call("activities.delete", activity_id=unused)
        self.assertEqual([row["id"] for row in self.call("activities.list")["activities"]], [used])

    def test_manual_add_edit_delete_updates_calendar_totals(self):
        first = self.call("activities.create", name="Study")["activity_id"]
        second = self.call("activities.create", name="Reading")["activity_id"]
        started = "2026-11-07T15:00:00+03:00"
        session_id = self.call("sessions.add_manual", activity_id=first, started_at=started,
                               active_seconds=1800, note="Missed half hour")["session_id"]
        initial = self.call("reports.day", day="2026-11-07", zone="Asia/Baghdad")
        self.assertEqual(initial["total_ms"], 1800000)
        self.call("sessions.edit", session_id=session_id, activity_id=second,
                  active_seconds=2700, note="Corrected duration")
        changed = self.call("reports.day", day="2026-11-07", zone="Asia/Baghdad")
        self.assertEqual(changed["total_ms"], 2700000)
        self.assertEqual(changed["activities"][0]["activity_id"], second)
        self.assertEqual(self.call("sessions.recent")["sessions"][0]["source"], "corrected")
        self.call("sessions.delete", session_id=session_id)
        self.assertEqual(self.call("reports.day", day="2026-11-07", zone="Asia/Baghdad")["total_ms"], 0)

    def test_manual_overlap_requires_explicit_allowance(self):
        activity_id = self.call("activities.create", name="Exercise")["activity_id"]
        start = "2026-11-07T12:00:00+00:00"
        self.call("sessions.add_manual", activity_id=activity_id, started_at=start, active_seconds=3600)
        with self.assertRaises(orbital_db.RequestError) as error:
            self.call("sessions.add_manual", activity_id=activity_id,
                      started_at="2026-11-07T12:30:00+00:00", active_seconds=1800)
        self.assertEqual(error.exception.code, "overlap")
        self.call("sessions.add_manual", activity_id=activity_id,
                  started_at="2026-11-07T12:30:00+00:00", active_seconds=1800,
                  allow_overlap=True)
        self.assertEqual(self.call("reports.day", day="2026-11-07", zone="UTC")["total_ms"], 5400000)

    def test_history_pages_are_bounded_and_filterable(self):
        first = self.call("activities.create", name="Study")["activity_id"]
        second = self.call("activities.create", name="Reading")["activity_id"]
        for hour, activity_id in ((9, first), (10, second), (11, first)):
            self.call("sessions.add_manual", activity_id=activity_id,
                      started_at=f"2026-11-07T{hour:02d}:00:00+00:00", active_seconds=600)
        first_page = self.call("sessions.list", limit=2)
        self.assertEqual(len(first_page["sessions"]), 2)
        self.assertIsNotNone(first_page["next_cursor"])
        second_page = self.call("sessions.list", limit=2, before=first_page["next_cursor"])
        self.assertEqual(len(second_page["sessions"]), 1)
        self.assertIsNone(second_page["next_cursor"])
        self.assertEqual(len(self.call("sessions.list", activity_id=first)["sessions"]), 2)

    def test_period_totals_and_trends_reconcile(self):
        activity_id = self.call("activities.create", name="Study")["activity_id"]
        self.call("sessions.add_manual", activity_id=activity_id,
                  started_at="2026-02-28T23:30:00+00:00", active_seconds=3600)
        day = self.call("reports.period", period="day", anchor="2026-03-01", zone="UTC")
        week = self.call("reports.period", period="week", anchor="2026-03-01", zone="UTC")
        month = self.call("reports.period", period="month", anchor="2026-03-01", zone="UTC")
        year = self.call("reports.period", period="year", anchor="2026-03-01", zone="UTC")
        self.assertEqual(day["total_ms"], 1800000)
        self.assertEqual(week["start_day"], "2026-02-23")
        self.assertEqual(week["total_ms"], 3600000)
        self.assertEqual(month["total_ms"], 1800000)
        self.assertEqual(year["total_ms"], 3600000)
        for report in (day, week, month, year):
            self.assertEqual(sum(point["active_ms"] for point in report["trend"]), report["total_ms"])
            self.assertEqual(sum(item["active_ms"] for item in report["activities"]), report["total_ms"])

    def test_leap_day_period_and_dst_hour_count(self):
        _, start, end, _, _ = orbital_db.period_dates(
            {"period": "month", "anchor": "2024-02-29"}, orbital_db.ZoneInfo("UTC")
        )
        self.assertEqual((end - start).days, 29)
        spring = self.call("reports.period", period="day", anchor="2026-03-08", zone="America/New_York")
        autumn = self.call("reports.period", period="day", anchor="2026-11-01", zone="America/New_York")
        self.assertEqual(len(spring["trend"]), 23)
        self.assertEqual(len(autumn["trend"]), 25)

    def test_settings_are_validated_and_persist(self):
        defaults = self.call("settings.get")["settings"]
        self.assertEqual(defaults["focus_minutes"], 25)
        self.assertFalse(defaults["auto_start_break"])
        updated = self.call("settings.update", settings={"focus_minutes": 40,
                                                         "auto_start_break": True})["settings"]
        self.assertEqual(updated["focus_minutes"], 40)
        self.assertTrue(self.call("settings.get")["settings"]["auto_start_break"])
        with self.assertRaises(orbital_db.RequestError):
            self.call("settings.update", settings={"focus_minutes": 0})
        self.assertEqual(self.call("settings.get")["settings"]["focus_minutes"], 40)

    def test_manual_finish_never_starts_break(self):
        self.call("activities.create", name="Study")
        self.call("settings.update", settings={"auto_start_break": True})
        clock = {"ns": 0}
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=lambda: clock["ns"]
        ):
            self.call("timer.start", mode="focus", planned_seconds=1500)
            clock["ns"] = 17 * 60 * 1_000_000_000
            finished = self.call("timer.finish")
        self.assertEqual(finished["timer"]["phase"], "idle")
        self.assertEqual(finished["active_seconds"], 1020)

    def test_break_cycle_excludes_break_time_and_respects_auto_start(self):
        self.call("activities.create", name="Study")
        self.call("settings.update", settings={"auto_start_break": True,
                                               "auto_start_focus": True,
                                               "short_break_minutes": 5})
        clock = {"ns": 0}
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=lambda: clock["ns"]
        ):
            self.call("timer.start", mode="focus", planned_seconds=60)
            clock["ns"] += 60 * 1_000_000_000
            work = self.call("timer.complete")
            self.assertEqual(work["timer"]["phase"], "break_running")
            clock["ns"] += 120 * 1_000_000_000
            self.call("timer.pause")
            clock["ns"] += 3600 * 1_000_000_000
            self.call("timer.resume")
            clock["ns"] += 180 * 1_000_000_000
            next_focus = self.call("timer.complete_break")
            self.assertEqual(next_focus["timer"]["phase"], "running")
            clock["ns"] += 30 * 1_000_000_000
            self.call("timer.finish")
        with closing(orbital_db.connect(self.path)) as db:
            saved = db.execute("SELECT active_seconds FROM sessions ORDER BY created_at").fetchall()
            self.assertEqual(sorted(row[0] for row in saved), [30, 60])

    def test_long_break_after_configured_number_of_focus_sessions(self):
        self.call("activities.create", name="Study")
        self.call("settings.update", settings={"long_break_every": 2})
        clock = {"ns": 0}
        with patch.object(orbital_db, "boot_id", return_value="boot"), patch.object(
            orbital_db.time, "monotonic_ns", side_effect=lambda: clock["ns"]
        ):
            self.call("timer.start", mode="focus", planned_seconds=60)
            clock["ns"] += 60 * 1_000_000_000
            first = self.call("timer.complete")
            self.assertEqual(first["timer"]["break_kind"], "short")
            self.call("timer.skip_break")
            self.call("timer.start", mode="focus", planned_seconds=60)
            clock["ns"] += 60 * 1_000_000_000
            second = self.call("timer.complete")
        self.assertEqual(second["timer"]["break_kind"], "long")
        self.assertEqual(second["timer"]["planned_seconds"], 900)


if __name__ == "__main__":
    unittest.main()
