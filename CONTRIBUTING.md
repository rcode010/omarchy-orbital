# Contributing to Orbital

Orbital runs inside the long-lived Omarchy shell. Keep changes small, reviewable, and focused on reliability and responsiveness. Use the installed Omarchy plugin contract as the source of truth for QML integration.

## Local checks

Run these from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -W error::ResourceWarning -m unittest discover -s tests -v
node tests/timer_display.test.js
omarchy plugin validate .
PYTHONDONTWRITEBYTECODE=1 python3 scripts/benchmark_reports.py
```

The Python tests use temporary databases. The benchmark also uses a temporary database and reports its own machine-specific timing. The CI workflow checks Python, JavaScript, and manifest JSON on a headless runner. It does not establish that the QML panel renders correctly in Omarchy.

For QML changes, inspect the current first-party shell imports and run `qmllint` with the installed Omarchy `qs` modules. Standalone lint may warn about dynamic host properties. Confirm parsing and then perform a live interactive check in the built-in bar on an Omarchy 4 session, including panel close, shell restart, multiple monitors, and theme changes. Record what was actually tested.

Restart the shell before the final live QML check. A plugin update can report success while an existing bar widget still holds an older `Panel.qml` Loader instance; opening and closing that panel does not prove the new nested QML was loaded.

Use local Git commits with concise Conventional Commit subjects. Do not add source-code comments, generated attribution, personal databases, or screenshots that are not from the running plugin. Do not push, publish, tag a release, or change remotes as part of routine development.

## Release work still required

The maintainer selected MIT for Orbital. The privacy-safe screenshot, removal and data-survival checks, short shell performance samples, natural Focus and break cycle, notifications, backup and restore, and keyboard navigation are recorded in the [release report](docs/release-report-2026-11-09.md). A stable release still needs the unresolved idle, screen-reader, and physical multi-monitor pointer checks in that report. Keep the [verification checklist](docs/release-verification.md) authoritative until those checks are complete.
