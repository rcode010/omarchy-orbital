import json
import os
import sqlite3
import sys
import time
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path


PLUGIN_ID = "io.github.rcode010.omarchy-orbital"
MAX_REQUEST_BYTES = 16384
COLORS = {"blue", "cyan", "green", "amber", "orange", "purple", "pink", "red"}


class RequestError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def data_path():
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    return base / PLUGIN_ID / "orbital.sqlite3"


def connect(path):
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
        if version > 2:
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


def timer_load(db, request):
    with db:
        row = timer_row(db)
        if row["phase"] == "running":
            db.execute("UPDATE timer_state SET phase = 'paused', segment_monotonic_ns = NULL, "
                       "updated_at = ? WHERE singleton = 1", (utc_now(),))
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
                   "work_started_at = ?, session_id = ?, planned_seconds = ?, updated_at = ? "
                   "WHERE singleton = 1", (mode, now_ns, current_boot, now, str(uuid.uuid4()), planned, now))
        return timer_view(timer_row(db))


def timer_pause(db, request):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    with db:
        row = timer_row(db)
        if row["phase"] != "running":
            raise RequestError("invalid_state", "Timer is not running")
        total = elapsed_ms(row, now_ns, current_boot)
        db.execute("UPDATE timer_state SET phase = 'paused', active_ms = ?, "
                   "segment_monotonic_ns = NULL, updated_at = ? WHERE singleton = 1",
                   (total, utc_now()))
        return timer_view(timer_row(db))


def timer_resume(db, request):
    with db:
        row = timer_row(db)
        if row["phase"] != "paused":
            raise RequestError("invalid_state", "Timer is not paused")
        db.execute("UPDATE timer_state SET phase = 'running', segment_monotonic_ns = ?, "
                   "boot_id = ?, updated_at = ? WHERE singleton = 1",
                   (time.monotonic_ns(), boot_id(), utc_now()))
        return timer_view(timer_row(db))


def timer_checkpoint(db, request):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    with db:
        row = timer_row(db)
        if row["phase"] != "running":
            return timer_view(row)
        if row["boot_id"] != current_boot:
            db.execute("UPDATE timer_state SET phase = 'paused', segment_monotonic_ns = NULL, "
                       "updated_at = ? WHERE singleton = 1", (utc_now(),))
        else:
            total = elapsed_ms(row, now_ns, current_boot)
            db.execute("UPDATE timer_state SET active_ms = ?, segment_monotonic_ns = ?, "
                       "updated_at = ? WHERE singleton = 1", (total, now_ns, utc_now()))
        return timer_view(timer_row(db))


def timer_stop(db, request, save):
    now_ns = time.monotonic_ns()
    current_boot = boot_id()
    now = utc_now()
    with db:
        row = timer_row(db)
        if row["phase"] == "idle":
            return {"saved": False, "active_seconds": 0, "timer": timer_view(row)}
        if row["phase"] not in ("running", "paused"):
            raise RequestError("invalid_state", "Timer cannot be stopped")
        total = elapsed_ms(row, now_ns, current_boot)
        seconds = total // 1000
        if save and seconds > 0:
            db.execute("INSERT INTO sessions (id, activity_id, mode, source, started_at, ended_at, "
                       "active_seconds, reason) VALUES (?, ?, ?, 'measured', ?, ?, ?, ?)",
                       (row["session_id"], row["selected_activity_id"], row["mode"],
                        row["work_started_at"], now, seconds,
                        "finish_early" if row["mode"] == "focus" else "finish"))
        db.execute("UPDATE timer_state SET phase = 'idle', active_ms = 0, active_seconds = 0, "
                   "segment_monotonic_ns = NULL, boot_id = NULL, work_started_at = NULL, "
                   "session_id = NULL, updated_at = ? WHERE singleton = 1", (now,))
        return {"saved": bool(save and seconds > 0), "active_seconds": seconds if save else 0,
                "timer": timer_view(timer_row(db))}


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
