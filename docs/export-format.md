# Orbital data exports

Orbital keeps its working database in SQLite. Settings can create two local files in the data directory's `backups/` folder:

- `orbital-YYYYMMDDTHHMMSSZ-XXXXXXXX.sqlite3` is a restorable SQLite snapshot. Restore replaces the current database after checking its schema, integrity, settings, timer state, and references. Orbital creates a `pre-restore` snapshot of the current database first.
- `orbital-export-YYYYMMDDTHHMMSSZ-XXXXXXXX.json` is a readable export for inspection or external processing. The app does not import JSON; use a SQLite snapshot for restore.

The JSON document has `format: "orbital-json"`, `schema_version: 4`, and arrays named `activities`, `sessions`, `work_segments`, and `settings`. Each array contains the corresponding SQLite rows as objects, with their column names as keys. IDs link sessions to activities and work segments to sessions. Times in measured and manual session rows are ISO 8601 UTC timestamps with an offset. `active_seconds` is the saved whole-second session duration; `work_segments.active_ms` stores recorded work intervals used for calendar attribution. Settings rows have a `key` and a JSON-encoded `value` string.

Exports contain activity names, notes, timestamps, and other personal history. Keep copies in a location you trust. Orbital writes the backup folder with owner-only permissions and each generated file with owner-only permissions.
