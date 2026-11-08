import json
import os
import sqlite3
import sys
import time
import uuid
from contextlib import closing
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


PLUGIN_ID = "io.github.rcode010.omarchy-orbital"
MAX_REQUEST_BYTES = 16384
MAX_ACTIVITIES = 500
COLORS = {"blue", "cyan", "green", "amber", "orange", "purple", "pink", "red"}


class RequestError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def data_path():
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    return base / PLUGIN_ID / "orbital.sqlite3"


def connect(path):
    os.umask(0o077)
    if path.is_symlink() or path.parent.is_symlink():
        raise RequestError("unsafe_path", "Orbital data path cannot be a symlink")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    db = sqlite3.connect(path, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA busy_timeout = 5000")
    db.execute("PRAGMA journal_mode = WAL")
    os.chmod(path, 0o600)
    migrate(db)
    return db


def migrate(db):
    with db:
        db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY)")
        version = db.execute("SELECT COALESCE(MAX(version), 0) FROM schema_migrations").fetchone()[0]
        if version > 3:
            raise RequestError("unsupported_schema", "Orbital data requires a newer version")
        if version == 0:
            db.executescript("""
                CREATE TABLE activities (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '',
                    color TEXT NOT NULL, sort_order INTEGER NOT NULL,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, archived_at TEXT
                );
                CREATE TABLE sessions (
                    id TEXT PRIMARY KEY, activity_id TEXT NOT NULL REFERENCES activities(id),
                    mode TEXT NOT NULL, source TEXT NOT NULL, started_at TEXT NOT NULL,
                    ended_at TEXT NOT NULL, active_seconds INTEGER NOT NULL CHECK (active_seconds >= 0),
                    note TEXT NOT NULL DEFAULT '', reason TEXT NOT NULL,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX sessions_by_start ON sessions(started_at);
                CREATE INDEX sessions_by_activity_start ON sessions(activity_id, started_at);
                CREATE TABLE timer_state (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    selected_activity_id TEXT REFERENCES activities(id),
                    mode TEXT NOT NULL DEFAULT 'focus', phase TEXT NOT NULL DEFAULT 'idle',
                    active_seconds INTEGER NOT NULL DEFAULT 0, segment_started_at TEXT,
                    session_id TEXT, planned_seconds INTEGER NOT NULL DEFAULT 1500,
                    cycle_count INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                INSERT INTO timer_state (singleton) VALUES (1);
                CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT INTO schema_migrations (version) VALUES (1);
            """)
        if version < 2:
            db.execute("ALTER TABLE timer_state ADD COLUMN active_ms INTEGER NOT NULL DEFAULT 0")
            db.execute("ALTER TABLE timer_state ADD COLUMN segment_monotonic_ns INTEGER")
            db.execute("ALTER TABLE timer_state ADD COLUMN boot_id TEXT")
            db.execute("ALTER TABLE timer_state ADD COLUMN work_started_at TEXT")
            db.execute("INSERT INTO schema_migrations (version) VALUES (2)")
        if version < 3:
            db.execute("CREATE TABLE work_segments ("
                       "session_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, "
                       "active_ms INTEGER NOT NULL CHECK (active_ms > 0))")
            db.execute("CREATE INDEX work_segments_by_start ON work_segments(started_at)")
            db.execute("CREATE INDEX work_segments_by_session ON work_segments(session_id)")
            db.execute("INSERT INTO schema_migrations (version) VALUES (3)")


def text_field(request, field, limit, default=None, optional=False):
    value = request.get(field, default)
    if not isinstance(value, str):
        raise RequestError("invalid_field", f"{field} must be text")
    value = value.strip()
    if len(value) > limit or (not optional and not value):
        raise RequestError("invalid_field", f"{field} must contain 1 to {limit} characters")
    return value


def list_activities(db, request):
    archived = request.get("include_archived", False)
    if not isinstance(archived, bool):
        raise RequestError("invalid_field", "include_archived must be a boolean")
    rows = db.execute(
        "SELECT id, name, icon, color, sort_order, archived_at FROM activities "
        "WHERE (? OR archived_at IS NULL) ORDER BY sort_order, created_at", (archived,)
    ).fetchall()
    selected = db.execute("SELECT selected_activity_id FROM timer_state WHERE singleton = 1").fetchone()[0]
    return {"activities": [dict(row) for row in rows], "selected_activity_id": selected}


def create_activity(db, request):
    name = text_field(request, "name", 80)
    icon = text_field(request, "icon", 8, "", True)
    color = text_field(request, "color", 20, "blue")
    if color not in COLORS:
        raise RequestError("invalid_field", "Unknown activity color")
    activity_id = str(uuid.uuid4())
    with db:
        count = db.execute("SELECT COUNT(*) FROM activities").fetchone()[0]
        if count >= MAX_ACTIVITIES:
            raise RequestError("limit_reached", "Orbital supports up to 500 activities")
        position = db.execute("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM activities").fetchone()[0]
        db.execute("INSERT INTO activities (id, name, icon, color, sort_order) VALUES (?, ?, ?, ?, ?)",
                   (activity_id, name, icon, color, position))
        db.execute("UPDATE timer_state SET selected_activity_id = ? "
                   "WHERE singleton = 1 AND selected_activity_id IS NULL", (activity_id,))
    return {"activity_id": activity_id}


def update_activity(db, request):
    activity_id = text_field(request, "activity_id", 36)
    changes = {}
    for field, limit in (("name", 80), ("icon", 8), ("color", 20)):
        if field in request:
            changes[field] = text_field(request, field, limit, optional=field == "icon")
    if not changes:
        raise RequestError("invalid_request", "No changes supplied")
    if "color" in changes and changes["color"] not in COLORS:
        raise RequestError("invalid_field", "Unknown activity color")
    with db:
        if db.execute("SELECT 1 FROM activities WHERE id = ?", (activity_id,)).fetchone() is None:
            raise RequestError("not_found", "Activity not found")
        assignments = ", ".join(f"{field} = ?" for field in changes)
        db.execute(f"UPDATE activities SET {assignments}, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                   (*changes.values(), activity_id))
    return {"activity_id": activity_id}


def archive_activity(db, request, archived):
    activity_id = text_field(request, "activity_id", 36)
    with db:
        if db.execute("SELECT 1 FROM activities WHERE id = ?", (activity_id,)).fetchone() is None:
            raise RequestError("not_found", "Activity not found")
        timer = timer_row(db)
        if archived and timer["selected_activity_id"] == activity_id and timer["phase"] != "idle":
            raise RequestError("timer_active", "Finish or discard this activity's session first")
        db.execute("UPDATE activities SET archived_at = CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END, "
                   "updated_at = CURRENT_TIMESTAMP WHERE id = ?", (archived, activity_id))
        if archived:
            db.execute("UPDATE timer_state SET selected_activity_id = NULL "
                       "WHERE singleton = 1 AND selected_activity_id = ?", (activity_id,))
    return {"activity_id": activity_id}


def select_activity(db, request):
    activity_id = text_field(request, "activity_id", 36)
    with db:
        if db.execute("SELECT 1 FROM activities WHERE id = ? AND archived_at IS NULL",
                      (activity_id,)).fetchone() is None:
            raise RequestError("not_found", "Active activity not found")
        phase = db.execute("SELECT phase FROM timer_state WHERE singleton = 1").fetchone()[0]
        if phase != "idle":
            raise RequestError("timer_active", "Finish or discard the current session first")
        db.execute("UPDATE timer_state SET selected_activity_id = ?, updated_at = CURRENT_TIMESTAMP "
                   "WHERE singleton = 1", (activity_id,))
    return {"selected_activity_id": activity_id}


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def boot_id():
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def timer_row(db):
    return db.execute("SELECT * FROM timer_state WHERE singleton = 1").fetchone()


def elapsed_ms(row, now_ns, current_boot):
    if row["phase"] != "running" or row["boot_id"] != current_boot:
        return row["active_ms"]
    segment_ns = row["segment_monotonic_ns"]
    if segment_ns is None or segment_ns > now_ns:
        return row["active_ms"]
    return row["active_ms"] + (now_ns - segment_ns) // 1_000_000


def record_segment(db, row, now, now_ns, current_boot):
    started_ns = row["segment_monotonic_ns"]
    started_at = row["segment_started_at"]
    if row["phase"] != "running" or row["boot_id"] != current_boot:
        return 0
    if started_ns is None or started_at is None or started_ns > now_ns:
        return 0
    duration_ms = (now_ns - started_ns) // 1_000_000
    if duration_ms <= 0:
        return 0
    start = datetime.fromisoformat(started_at)
    wall_end = datetime.fromisoformat(now)
    expected_end = start + timedelta(milliseconds=duration_ms)
    end = wall_end if abs((wall_end - expected_end).total_seconds()) <= 5 else expected_end
    db.execute("INSERT INTO work_segments (session_id, started_at, ended_at, active_ms) "
               "VALUES (?, ?, ?, ?)",
               (row["session_id"], started_at, end.isoformat(timespec="milliseconds"), duration_ms))
    return duration_ms


def timer_load(db, request):
    with db:
        row = timer_row(db)
        if row["phase"] == "running":
            db.execute("UPDATE timer_state SET phase = 'paused', segment_monotonic_ns = NULL, "
                       "segment_started_at = NULL, updated_at = ? WHERE singleton = 1", (utc_now(),))
            row = timer_row(db)
    return timer_view(row)


def timer_view(row):
    return {key: row[key] for key in (
        "selected_activity_id", "mode", "phase", "active_ms", "planned_seconds", "session_id"
    )}


def timer_start(db, request):
    mode = request.get("mode")
    if mode not in ("focus", "stopwatch"):
        raise RequestError("invalid_field", "Mode must be focus or stopwatch")
    planned = request.get("planned_seconds", 1500)
    if isinstance(planned, bool) or not isinstance(planned, int) or not 60 <= planned <= 14400:
        raise RequestError("invalid_field", "Focus duration must be 1 to 240 minutes")
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    now = utc_now()
    with db:
        row = timer_row(db)
        if row["phase"] != "idle":
            raise RequestError("timer_active", "Finish or discard the current session first")
        if not row["selected_activity_id"]:
            raise RequestError("no_activity", "Select an activity first")
        activity = db.execute("SELECT 1 FROM activities WHERE id = ? AND archived_at IS NULL",
                              (row["selected_activity_id"],)).fetchone()
        if activity is None:
            raise RequestError("no_activity", "Select an active activity first")
        db.execute("UPDATE timer_state SET mode = ?, phase = 'running', active_ms = 0, "
                   "active_seconds = 0, segment_monotonic_ns = ?, boot_id = ?, "
                   "segment_started_at = ?, work_started_at = ?, session_id = ?, "
                   "planned_seconds = ?, updated_at = ? WHERE singleton = 1",
                   (mode, now_ns, current_boot, now, now, str(uuid.uuid4()), planned, now))
        return timer_view(timer_row(db))


def timer_pause(db, request):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    now = utc_now()
    with db:
        row = timer_row(db)
        if row["phase"] != "running":
            raise RequestError("invalid_state", "Timer is not running")
        total = row["active_ms"] + record_segment(db, row, now, now_ns, current_boot)
        db.execute("UPDATE timer_state SET phase = 'paused', active_ms = ?, "
                   "segment_monotonic_ns = NULL, segment_started_at = NULL, updated_at = ? "
                   "WHERE singleton = 1", (total, now))
        return timer_view(timer_row(db))


def timer_resume(db, request):
    now_ns = time.monotonic_ns()
    now = utc_now()
    current_boot = boot_id()
    with db:
        row = timer_row(db)
        if row["phase"] != "paused":
            raise RequestError("invalid_state", "Timer is not paused")
        db.execute("UPDATE timer_state SET phase = 'running', segment_monotonic_ns = ?, "
                   "segment_started_at = ?, boot_id = ?, updated_at = ? WHERE singleton = 1",
                   (now_ns, now, current_boot, now))
        return timer_view(timer_row(db))


def timer_checkpoint(db, request):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    now = utc_now()
    with db:
        row = timer_row(db)
        if row["phase"] != "running":
            return timer_view(row)
        if row["boot_id"] != current_boot:
            db.execute("UPDATE timer_state SET phase = 'paused', segment_monotonic_ns = NULL, "
                       "segment_started_at = NULL, updated_at = ? WHERE singleton = 1", (now,))
        else:
            total = row["active_ms"] + record_segment(db, row, now, now_ns, current_boot)
            db.execute("UPDATE timer_state SET active_ms = ?, segment_monotonic_ns = ?, "
                       "segment_started_at = ?, updated_at = ? WHERE singleton = 1",
                       (total, now_ns, now, now))
        return timer_view(timer_row(db))


def timer_stop(db, request, save, reason=None):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    now = utc_now()
    with db:
        row = timer_row(db)
        if row["phase"] == "idle":
            return {"saved": False, "active_seconds": 0, "timer": timer_view(row)}
        if row["phase"] not in ("running", "paused"):
            raise RequestError("invalid_state", "Timer cannot be stopped")
        total = row["active_ms"] + record_segment(db, row, now, now_ns, current_boot)
        seconds = total // 1000
        if save and seconds > 0:
            db.execute("INSERT INTO sessions (id, activity_id, mode, source, started_at, ended_at, "
                       "active_seconds, reason) VALUES (?, ?, ?, 'measured', ?, ?, ?, ?)",
                       (row["session_id"], row["selected_activity_id"], row["mode"],
                        row["work_started_at"], now, seconds,
                        reason or ("finish_early" if row["mode"] == "focus" else "finish")))
        if not save or seconds == 0:
            db.execute("DELETE FROM work_segments WHERE session_id = ?", (row["session_id"],))
        db.execute("UPDATE timer_state SET phase = 'idle', active_ms = 0, active_seconds = 0, "
                   "segment_monotonic_ns = NULL, segment_started_at = NULL, boot_id = NULL, "
                   "work_started_at = NULL, "
                   "session_id = NULL, updated_at = ? WHERE singleton = 1", (now,))
        return {"saved": bool(save and seconds > 0), "active_seconds": seconds if save else 0,
                "timer": timer_view(timer_row(db))}


def timer_complete(db, request):
    with db:
        row = timer_row(db)
        if row["phase"] == "idle":
            return {"completed": False, "timer": timer_view(row)}
        if row["phase"] != "running" or row["mode"] != "focus":
            raise RequestError("invalid_state", "No running focus session")
        now_ns = time.monotonic_ns()
        current_boot = boot_id()
        if row["boot_id"] != current_boot:
            db.execute("UPDATE timer_state SET phase = 'paused', segment_monotonic_ns = NULL, "
                       "segment_started_at = NULL, updated_at = ? WHERE singleton = 1", (utc_now(),))
            return {"completed": False, "timer": timer_view(timer_row(db))}
        total = elapsed_ms(row, now_ns, current_boot)
        if total < row["planned_seconds"] * 1000:
            now = utc_now()
            total = row["active_ms"] + record_segment(db, row, now, now_ns, current_boot)
            db.execute("UPDATE timer_state SET active_ms = ?, segment_monotonic_ns = ?, "
                       "segment_started_at = ?, updated_at = ? WHERE singleton = 1",
                       (total, now_ns, now, now))
            return {"completed": False, "timer": timer_view(timer_row(db))}
    result = timer_stop(db, request, True, "completed")
    result["completed"] = result["saved"]
    return result


def local_zone(request):
    name = request.get("zone") or os.environ.get("TZ")
    if name is None:
        path = str(Path("/etc/localtime").resolve())
        marker = "/zoneinfo/"
        name = path.split(marker, 1)[1] if marker in path else None
    if name is None:
        return datetime.now().astimezone().tzinfo
    if not isinstance(name, str) or not 1 <= len(name) <= 80:
        raise RequestError("invalid_zone", "Invalid time zone")
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        raise RequestError("invalid_zone", "Unknown time zone") from None


def day_bounds(request):
    zone = local_zone(request)
    raw_day = request.get("day")
    if raw_day is None:
        selected_day = datetime.now(zone).date()
    elif isinstance(raw_day, str) and len(raw_day) == 10:
        try:
            selected_day = date.fromisoformat(raw_day)
        except ValueError:
            raise RequestError("invalid_day", "Day must be a valid ISO date") from None
    else:
        raise RequestError("invalid_day", "Day must be a valid ISO date")
    start = datetime.combine(selected_day, datetime.min.time(), zone).astimezone(timezone.utc)
    end = datetime.combine(selected_day + timedelta(days=1), datetime.min.time(), zone).astimezone(timezone.utc)
    return selected_day.isoformat(), start, end


def allocated_ms(started_at, ended_at, active_ms, start, end):
    segment_start = datetime.fromisoformat(started_at)
    segment_end = datetime.fromisoformat(ended_at)
    if segment_end <= segment_start:
        return active_ms if start <= segment_start < end else 0
    left = max(start, segment_start)
    right = min(end, segment_end)
    if right <= left:
        return 0
    wall_us = (segment_end - segment_start) // timedelta(microseconds=1)
    left_us = (left - segment_start) // timedelta(microseconds=1)
    right_us = (right - segment_start) // timedelta(microseconds=1)
    return active_ms * right_us // wall_us - active_ms * left_us // wall_us


def day_summary(db, request):
    day, start, end = day_bounds(request)
    start_text = start.isoformat(timespec="milliseconds")
    end_text = end.isoformat(timespec="milliseconds")
    rows = db.execute(
        "SELECT s.id, s.activity_id, a.name, a.icon, a.color, w.started_at, w.ended_at, "
        "w.active_ms FROM work_segments w JOIN sessions s ON s.id = w.session_id "
        "JOIN activities a ON a.id = s.activity_id "
        "WHERE w.started_at < ? AND w.ended_at > ?",
        (end_text, start_text),
    ).fetchall()
    legacy = db.execute(
        "SELECT s.id, s.activity_id, a.name, a.icon, a.color, s.started_at, s.ended_at, "
        "s.active_seconds * 1000 AS active_ms FROM sessions s "
        "JOIN activities a ON a.id = s.activity_id "
        "WHERE s.started_at < ? AND s.ended_at > ? "
        "AND NOT EXISTS (SELECT 1 FROM work_segments w WHERE w.session_id = s.id)",
        (end_text, start_text),
    ).fetchall()
    totals = {}
    sessions = set()
    for row in (*rows, *legacy):
        portion = allocated_ms(row["started_at"], row["ended_at"], row["active_ms"], start, end)
        if portion <= 0:
            continue
        sessions.add(row["id"])
        entry = totals.setdefault(row["activity_id"], {
            "activity_id": row["activity_id"], "name": row["name"], "icon": row["icon"],
            "color": row["color"], "active_ms": 0,
        })
        entry["active_ms"] += portion
    activities = sorted(totals.values(), key=lambda item: (-item["active_ms"], item["name"]))
    return {"day": day, "total_ms": sum(item["active_ms"] for item in activities),
            "session_count": len(sessions), "activities": activities}


def recent_sessions(db, request):
    limit = request.get("limit", 20)
    if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 50:
        raise RequestError("invalid_field", "History limit must be 1 to 50")
    rows = db.execute(
        "SELECT s.id, s.activity_id, a.name AS activity_name, a.icon, a.color, "
        "s.mode, s.source, s.started_at, s.ended_at, s.active_seconds, s.note, s.reason "
        "FROM sessions s JOIN activities a ON a.id = s.activity_id "
        "ORDER BY s.started_at DESC, s.id DESC LIMIT ?", (limit,)
    ).fetchall()
    return {"sessions": [dict(row) for row in rows]}


COMMANDS = {
    "activities.list": list_activities,
    "activities.create": create_activity,
    "activities.update": update_activity,
    "activities.archive": lambda db, request: archive_activity(db, request, True),
    "activities.restore": lambda db, request: archive_activity(db, request, False),
    "activities.select": select_activity,
    "timer.load": timer_load,
    "timer.start": timer_start,
    "timer.pause": timer_pause,
    "timer.resume": timer_resume,
    "timer.checkpoint": timer_checkpoint,
    "timer.finish": lambda db, request: timer_stop(db, request, True),
    "timer.discard": lambda db, request: timer_stop(db, request, False),
    "timer.complete": timer_complete,
    "reports.day": day_summary,
    "sessions.recent": recent_sessions,
}


def run(request, path=None):
    if not isinstance(request, dict):
        raise RequestError("invalid_request", "Request must be an object")
    command = request.get("command")
    if not isinstance(command, str) or command not in COMMANDS:
        raise RequestError("unknown_command", "Unknown Orbital command")
    with closing(connect(path or data_path())) as db:
        return COMMANDS[command](db, request)


def main():
    raw = sys.argv[1].encode() if len(sys.argv) == 2 else sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
    try:
        if len(raw) > MAX_REQUEST_BYTES:
            raise RequestError("request_too_large", "Request exceeds size limit")
        try:
            request = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise RequestError("invalid_json", "Request is not valid JSON") from None
        result = {"ok": True, "result": run(request)}
    except RequestError as error:
        result = {"ok": False, "error": {"code": error.code, "message": str(error)}}
    except sqlite3.Error:
        result = {"ok": False, "error": {"code": "storage_error", "message": "Orbital could not access its data"}}
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
