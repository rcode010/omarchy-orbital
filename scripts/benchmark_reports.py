import sys
import tempfile
import time
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

import orbital_db


def main():
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "data" / "orbital.sqlite3"
        with closing(orbital_db.connect(path)) as db:
            activities = []
            for name in ("Study", "Project", "Reading"):
                activities.append(orbital_db.create_activity(db, {"name": name})["activity_id"])
            sessions = []
            segments = []
            origin = datetime(2026, 1, 1, tzinfo=timezone.utc)
            for index in range(50000):
                start = origin + timedelta(days=index % 365, hours=(index // 365) % 24)
                duration = 300 + (index % 8) * 300
                end = start + timedelta(seconds=duration)
                session_id = f"benchmark-{index:05d}"
                start_text = start.isoformat(timespec="milliseconds")
                end_text = end.isoformat(timespec="milliseconds")
                sessions.append((session_id, activities[index % len(activities)], "focus", "measured",
                                 start_text, end_text, duration, "completed"))
                segments.append((session_id, start_text, end_text, duration * 1000))
            with db:
                db.executemany(
                    "INSERT INTO sessions (id, activity_id, mode, source, started_at, ended_at, "
                    "active_seconds, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", sessions
                )
                db.executemany("INSERT INTO work_segments VALUES (?, ?, ?, ?)", segments)
            timings = []
            for _ in range(2):
                started = time.perf_counter()
                report = orbital_db.period_summary(db, {
                    "period": "year", "anchor": "2026-06-01", "zone": "UTC"
                })
                timings.append((time.perf_counter() - started) * 1000)
            assert report["total_ms"] == sum(point["active_ms"] for point in report["trend"])
            print(f"sessions=50000 cold_ms={timings[0]:.1f} warm_ms={timings[1]:.1f} "
                  f"total_hours={report['total_ms'] / 3600000:.1f}")


if __name__ == "__main__":
    main()
