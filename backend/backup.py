import json
import os
import re
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote


MAX_BACKUP_BYTES = 512 * 1024 * 1024
BACKUP_NAME = re.compile(r"^orbital-(?:pre-restore-)?\d{8}T\d{6}Z-[0-9a-f]{8}\.sqlite3$")


class BackupError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def database_path(db):
    return Path(db.execute("PRAGMA database_list").fetchone()[2])


def backup_dir(db):
    directory = database_path(db).parent / "backups"
    if directory.is_symlink():
        raise BackupError("unsafe_path", "Backup directory cannot be a symlink")
    directory.mkdir(mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    return directory


def create(db, prefix="orbital"):
    directory = backup_dir(db)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"{prefix}-{timestamp}-{uuid.uuid4().hex[:8]}.sqlite3"
    temporary = directory / f".{name}.tmp"
    target = directory / name
    try:
        with closing(sqlite3.connect(temporary)) as destination:
            db.backup(destination)
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return {"name": name, "size_bytes": target.stat().st_size}


def list_backups(db):
    directory = backup_dir(db)
    entries = []
    for path in directory.iterdir():
        if not BACKUP_NAME.fullmatch(path.name) or path.is_symlink() or not path.is_file():
            continue
        stat = path.stat()
        entries.append({"name": path.name, "size_bytes": stat.st_size,
                        "modified_at": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat()})
    entries.sort(key=lambda item: item["name"], reverse=True)
    return {"backups": entries[:50]}


def export_json(db):
    directory = backup_dir(db)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"orbital-export-{timestamp}-{uuid.uuid4().hex[:8]}.json"
    temporary = directory / f".{name}.tmp"
    target = directory / name
    tables = ("activities", "sessions", "work_segments", "settings")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            stream.write('{"format":"orbital-json","schema_version":4')
            for table in tables:
                stream.write(f',"{table}":[')
                cursor = db.execute(f"SELECT * FROM {table}")
                for index, row in enumerate(cursor):
                    if index:
                        stream.write(",")
                    json.dump(dict(row), stream, ensure_ascii=False, separators=(",", ":"))
                stream.write("]")
            stream.write("}")
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return {"name": name, "size_bytes": target.stat().st_size}


def validate_source(source):
    if source.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise BackupError("invalid_backup", "Backup integrity check failed")
    required = {"activities", "sessions", "work_segments", "timer_state", "settings", "schema_migrations"}
    tables = {row[0] for row in source.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if not required.issubset(tables):
        raise BackupError("invalid_backup", "Backup is missing Orbital tables")
    version = source.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
    if version != 4:
        raise BackupError("unsupported_schema", "Backup schema does not match this Orbital version")
    if source.execute("PRAGMA foreign_key_check").fetchone() is not None:
        raise BackupError("invalid_backup", "Backup contains invalid references")


def restore(db, name):
    if not isinstance(name, str) or not BACKUP_NAME.fullmatch(name):
        raise BackupError("invalid_backup", "Choose a listed Orbital backup")
    path = backup_dir(db) / name
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BACKUP_BYTES:
        raise BackupError("invalid_backup", "Backup file is missing or unsafe")
    uri = "file:" + quote(str(path)) + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=5)) as source:
        source.execute("PRAGMA foreign_keys = ON")
        try:
            validate_source(source)
        except sqlite3.Error:
            raise BackupError("invalid_backup", "Backup cannot be read") from None
        prior = create(db, "orbital-pre-restore")
        source.backup(db)
    return {"restored": name, "previous_backup": prior["name"]}
