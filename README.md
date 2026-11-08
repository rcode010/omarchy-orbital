# Orbital

Orbital is a local activity timer for the built-in Omarchy bar. Create recurring activities, select one, and track real active time with a focus countdown or stopwatch.

Repository: https://github.com/rcode010/omarchy-orbital

This repository is under active development. The current build provides activity creation and selection, a shared timer service, pause and resume, natural focus completion, Finish Early or Finish, Discard, and durable SQLite sessions. The panel has no History, Today totals, Insights, settings, or Pomodoro break flow yet. Do not treat this build as a stable 1.0 release.

## Requirements

- Omarchy 4.x with the built-in Quickshell bar. Development currently targets Omarchy 4.0.6 and Quickshell 0.3.2.
- Python 3 with its standard-library `sqlite3` module.

The plugin ID is `io.github.rcode010.omarchy-orbital`. Its service owns the timer and is shared by bar widgets on all monitors. The panel closes without stopping the service. The helper runs only for user actions and a checkpoint every 60 seconds while tracking; the display tick does not write to SQLite.

Activity names are limited to 80 characters, and the current data protocol caps a library at 500 activities so UI responses remain bounded.

## Development checkout

Validate the checkout with `omarchy plugin validate .` and run the backend tests with `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`.

When the Omarchy shell is running, install a local Git checkout with `omarchy plugin add /path/to/omarchy-orbital --enable`. Omarchy copies the committed files into its plugin directory. If using an uncommitted working tree during development, update the installed checkout deliberately and revalidate it. The plugin runs inside the user's shell process with the user's permissions, so review code before enabling it.

No package installation, network service, account, or telemetry is required by Orbital.

## Data and recovery

Orbital stores `orbital.sqlite3` under `$XDG_DATA_HOME/io.github.rcode010.omarchy-orbital/`, or `~/.local/share/io.github.rcode010.omarchy-orbital/` when `XDG_DATA_HOME` is unset. The directory and database are restricted to the user. Normal plugin removal does not delete this directory.

The timer uses Linux monotonic time for measured active intervals. A restart or crash pauses the session at its last verified checkpoint, normally up to a minute earlier while continuously running, and potentially earlier if a checkpoint failed. This conservative recovery avoids counting unverified downtime. The current session can then be resumed, finished, or discarded. Paused time and system suspend do not advance measured active time.

The stored session rows include UTC start/end times and active seconds. Per-day attribution across pauses and midnight needs segment storage and is not implemented in this development build.

## Current keyboard behavior

Press Escape to close the panel. Tab reaches the activity name field, where Enter adds a new activity. Other controls currently use pointer input; complete keyboard support is planned before 1.0.

## Development status

Live shell smoke testing, clean install and removal verification, QML lint with full host type information, multi-monitor behavior, and performance measurements remain to be done on an active Omarchy session. The manifest validator and backend tests are the current automated checks. No screenshots or marketplace submission are available yet.
