# Orbital release verification, 2026-11-09

Host: Omarchy 4.0.6, Quickshell 0.3.2, one physical eDP-1 display. The tested source was committed locally and installed through `omarchy plugin update`, followed by `omarchy restart shell` to replace the existing nested panel Loader.

## Passed

- 42 Python storage tests, three JavaScript timer display cases, and `omarchy plugin validate .`.
- A fresh 50,000-session benchmark reconciled chart totals and measured 577.3 ms cold / 560.5 ms warm for the annual report, and 0.6 ms for a filtered 20-row History page on this host.
- The bar entry and Home, Insights, History, and Settings pages rendered. Ctrl+1 through Ctrl+4 navigated between them after a full shell restart.
- A live stopwatch started and paused with Space. Discard returned it to idle without changing the saved session count. Ctrl+2 worked immediately after Discard with the current committed build.
- The privacy-safe [Settings screenshot](orbital-settings.png) was captured from the running plugin and reviewed. It contains no activity names, saved history, or notification content.
- Removing the installed plugin removed it from the live shell. The separate SQLite database remained present, passed `PRAGMA integrity_check`, and retained three activities and six sessions. Reinstalling the committed checkout restored the enabled plugin and the same data.
- A temporary headless output produced a second visible Orbital bar widget; it was removed afterward. Workspace 1 and the sole physical display were restored.
- Ten-second shell samples after fresh restarts measured 4.8% of one CPU core and 480,668 KiB ending RSS with Orbital disabled, versus 5.2% and 486,900 KiB enabled and idle. With Orbital visibly open, the shell measured 3.2% and 554,480 KiB ending RSS; with a disposable stopwatch visibly running, it measured 3.2% and 555,516 KiB. The timer was discarded afterward. These short samples show no obvious CPU spike, but background shell activity and memory warmup limit precision.
- After the final shell restart, the shell log had no Orbital QML runtime warnings. Quickshell's scanner still reports that user plugin paths are outside its config folder.

## Open after the first live run

- Complete a live focus countdown, break cycle, optional notification, and idle pause check. The backend tests cover these paths, but this run did not exercise them in the live shell.
- Exercise backup creation and restore from the live Settings panel with disposable data.
- Check keyboard scrolling, focus order throughout long pages, and accessible names with a working screen reader. The installed AT-SPI tree exposed the `quickshell` application but no child controls during this run.
- Verify open and close behavior on two physical displays. The headless output check proved two bar instances rendered, but did not exercise pointer interaction on both.
- Publish the reviewed source and screenshot only after the remaining checks pass. No release tag or public release was made in this run.

## Continuation on 2026-11-09

The first process check ran inside an isolated workspace and incorrectly reported that the shell was absent. A host check confirmed Hyprland and Quickshell running, Orbital enabled, and two physical displays (`eDP-1` and `HDMI-A-5`). The installed plugin matched the original checkout before testing. The live database passed integrity check with three activities and seven sessions; the timer was idle and settings were at their defaults. A restorable snapshot was created before disposable changes.

Automated gates passed again: 42 Python tests with resource warnings treated as errors, three JavaScript display cases, and `omarchy plugin validate .`. All ten QML files parsed with Qt 6 `qmlformat`. A fresh 50,000-session benchmark reconciled chart totals and measured 278.3 ms cold / 276.5 ms warm for the annual report and 0.3 ms for a filtered History page. These are helper-only timings.

Live checks passed for two natural one-minute Focus completions, exact 60-second saved sessions, an automatically started and naturally completed short break, and both focus and break notifications observed on the session bus. Orbital opened on each physical display through the shell's panel command. Home, Insights, History, and Settings rendered on `eDP-1`; Ctrl+1 through Ctrl+4 switched pages. A Settings keyboard pass revealed that focus could move below the visible panel without scrolling. The `fix: scroll focused controls into view` change was installed, followed by a full shell restart. A later pass found the same issue inside bounded activity, history, and backup lists; `fix: keep list focus visible` now scrolls a focused list row into view. Tabbing through the backup list verified the fix without Orbital QML warnings. A backup was created through the live Settings control and appeared in the list. A two-step restore of an unchanged-data snapshot through Settings also succeeded and created a new `pre-restore` backup; the seven original session IDs and database integrity still matched afterward.

Restart recovery also passed: a disposable stopwatch was checkpointed at 4.052 seconds, and a shell restart left it paused at the same verified duration. It was discarded. Both rounds of disposable data were restored from snapshots. Final checks found the original seven session IDs, no disposable activities, original timer selection and settings, and `PRAGMA integrity_check = ok`. The original Omarchy stay-awake setting was restored.

**Open before stable release:** The live idle-pause check did not produce an idle event. Omarchy's stay-awake setting was temporarily disabled for a two-minute Focus with Orbital's idle threshold at one minute; both Omarchy's idle monitor and Orbital remained active until the Focus completed. This does not establish whether the compositor had another inhibitor or whether idle reporting failed. Quickshell's AT-SPI application exposed zero child controls, and no screen reader was installed, so accessible names and selected states remain unverified. Panel opening was verified on both physical displays by keyboard and shell command, but pointer interaction on both was not exercised. No release tag, push, or public release was made.

## Idle follow-up

The service now checks the monitor's current idle state whenever it applies a timer state, in addition to reacting to idle transitions. This closes the case where a timer starts or automatically resumes while the monitor is already idle and no new `isIdleChanged` signal arrives. The 42 backend tests, three display cases, and plugin validation passed after this change. The earlier live test still needs repeating because neither Omarchy nor Orbital received an idle event then; this code change does not establish why the compositor stayed active.
