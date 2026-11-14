# Marketplace privacy fix — 0.1.1

Addresses the [review on submission #14797](https://github.com/omacom/omarchy-plugin-marketplace/issues/14797#issuecomment-6863783858).

The service previously serialized database requests into Python process arguments. Manual entries and history corrections therefore exposed notes and timestamps to local accounts able to read process command lines.

All database requests now use the helper's standard-input pipe. The service enables stdin for every queued process, writes the JSON request after startup, and closes the pipe so the helper can finish its bounded read. Its command line contains only `python3` and the helper path. The helper rejects positional arguments and retains the 16 KiB request limit. No schema or stored-data changes are required.

Verification on 2026-11-14:

- 44 Python tests passed, including stdin manual-entry/history-correction round trips with private Unicode notes, rejection of positional request arguments without database creation, malformed/oversized requests, and concurrent stdin helpers.
- Three JavaScript timer display cases passed.
- `omarchy plugin validate .`, QML parsing, and `qmllint Service.qml` passed.
- A separate Quickshell instance loaded this checkout's actual `Service.qml` against temporary XDG data and cache directories. Initial state reads, activity creation, a manual entry, and a duration correction preserving its note all completed through the queued stdin transport. The resulting history contained the corrected 180-second session and the exact Unicode/multiline note. The installed plugin and personal database were not modified.
- The 50,000-session benchmark passed: annual report 278.8 ms cold / 277.4 ms warm, filtered history page 0.3 ms.

The remaining accessibility, idle-pause, and physical-display interaction checks in the earlier release report remain open. This is an early development patch, not a stable 1.0 release.
