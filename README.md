# Orbital

Orbital is a local activity timer for the built-in Omarchy bar. Create recurring activities, select one, and track real active time with a focus countdown or stopwatch.

Repository: https://github.com/rcode010/omarchy-orbital

This repository is under active development. The current build provides activity creation, selection, renaming, color/icon edits, archiving, restoring, and safe deletion of unused activities. It also provides a shared timer service, pause and resume, natural focus completion, Finish Early or Finish, Discard, durable SQLite sessions, saved Today totals by activity, an Add Missed Time form, paged History with correction and deletion, and Today/Day/Week/Month/Year Insights. Settings and Pomodoro break flow are still in progress. Do not treat this build as a stable 1.0 release.

## Requirements

- Omarchy 4.x with the built-in Quickshell bar. Development currently targets Omarchy 4.0.6 and Quickshell 0.3.2.
- Python 3 with its standard-library `sqlite3` module.

The plugin ID is `io.github.rcode010.omarchy-orbital`. Its service owns the timer and is shared by bar widgets on all monitors. The panel closes without stopping the service. The helper runs only for user actions and a checkpoint every 60 seconds while tracking; the display tick does not write to SQLite.

Activity names are limited to 80 characters, and the current data protocol caps a library at 500 activities so UI responses remain bounded.

Select an activity, then choose **Manage selected** to edit its name, icon, and color or archive it. Enable **Show archived** to restore an archived activity. Deletion requires a second click and is refused when the activity has saved history; archiving keeps that history intact.

Add Missed Time accepts a local start date/time, a duration in whole minutes, and an optional note. Future spans are refused. Overlaps with previously saved time require the explicit **Allow overlap** choice. Manual entries do not change a running timer. History loads 20 entries at a time, can filter to the selected activity, and supports corrections and confirmed deletion. Correcting a measured session's start or duration replaces its original active segments with one corrected interval; the source is labeled `corrected`.

Insights uses the current system time zone at query time. Weeks start on Monday. Day charts have 23 or 25 hourly bars when daylight saving changes the length of that day; Week and Month use daily bars, and Year uses monthly bars. Every chart value comes from saved session segments, and **Show chart values** provides a text list.

## Development checkout

Validate the checkout with `omarchy plugin validate .` and run the backend tests with `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`.

When the Omarchy shell is running, install a local Git checkout with `omarchy plugin add /path/to/omarchy-orbital --enable`. Omarchy copies the committed files into its plugin directory. If using an uncommitted working tree during development, update the installed checkout deliberately and revalidate it. The plugin runs inside the user's shell process with the user's permissions, so review code before enabling it.

No package installation, network service, account, or telemetry is required by Orbital.

## Data and recovery

Orbital stores `orbital.sqlite3` under `$XDG_DATA_HOME/io.github.rcode010.omarchy-orbital/`, or `~/.local/share/io.github.rcode010.omarchy-orbital/` when `XDG_DATA_HOME` is unset. The directory and database are restricted to the user. Normal plugin removal does not delete this directory.

The timer uses Linux monotonic time for measured active intervals. A restart or crash pauses the session at its last verified checkpoint, normally up to a minute earlier while continuously running, and potentially earlier if a checkpoint failed. This conservative recovery avoids counting unverified downtime. The current session can then be resumed, finished, or discarded. Paused time and system suspend do not advance measured active time.

The stored session rows include UTC start/end times and active seconds. New measured sessions also store their active work segments. Today totals split those segments at local midnight using the system time zone, including daylight-saving changes, and exclude pauses. Sessions saved by older development builds have no segments; their daily attribution is estimated proportionally across the recorded start/end interval. If the system clock changes substantially during a segment, Orbital anchors that segment to its start time and measured monotonic duration to avoid allocating phantom hours.

## Current keyboard behavior

Press Escape to close the panel. Tab reaches the activity name field, where Enter adds a new activity. Other controls currently use pointer input; complete keyboard support is planned before 1.0.

## Development status

Live shell smoke testing, clean install and removal verification, QML lint with full host type information, multi-monitor behavior, and performance measurements remain to be done on an active Omarchy session. The manifest validator and backend tests are the current automated checks. No screenshots or marketplace submission are available yet.
