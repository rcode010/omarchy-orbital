# Stable release verification

Run these checks against the committed checkout on an Omarchy 4 desktop before publishing a stable release. Use a disposable Orbital data directory or make a restorable snapshot before testing data changes. Record the date, Omarchy and Quickshell versions, monitor count, and results.

## Automated gates

- Run the Python and JavaScript tests in `CONTRIBUTING.md`.
- Run `omarchy plugin validate .`.
- Run the 50,000-session benchmark and record the machine and timings. Check that chart points reconcile with saved totals.
- Parse every QML file with the installed Qt tools and inspect warnings in the context of the installed Omarchy shell.

## Live shell checks

- Open and close Orbital from the bar. Switch all four pages, scroll long content, and check that the shell log contains no Orbital errors.
- With keyboard only, tab through visible controls on each page. Check focus visibility, activation with Enter and Space, Escape to close, page shortcuts, text entry, and scroll reachability. Inspect accessible names and selected states with a screen reader.
- Create, select, edit, archive, and restore a disposable activity. Start, pause, resume, finish, and discard focus and stopwatch sessions. Confirm the bar and Today total update on every monitor.
- Let a short focus complete naturally. Check the break cycle and notifications. Exercise idle pause and resume, and restart the shell during a running session to verify conservative recovery.
- Add, correct, filter, and delete disposable missed time. Check History pages and Insights totals for the current day and an older period.
- Create and restore a disposable backup. Confirm that the pre-restore snapshot is listed and that saved history matches the snapshot.
- Measure idle shell CPU and memory with Orbital disabled and enabled on the same desktop, then measure while a timer runs and while the panel is open. Record the method and results.
- Disable and remove the plugin. Confirm the bar entry disappears and the separate XDG data directory survives. Reinstall the committed checkout and confirm its saved history returns.
- Capture a privacy-safe screenshot from the running plugin with disposable activity names and no personal history or notifications visible. Review the image before publishing.

Publish a stable release only after every live check passes and the screenshot has been reviewed. Keep any unresolved check visible in the release notes.
