import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property string phase: "idle"
  property string mode: "focus"
  property string activityName: ""
  property int elapsedSeconds: 0
  property double activeMs: 0
  property int plannedSeconds: 1500
  property double displayStartedAt: 0
  property var activities: []
  property string selectedActivityId: ""
  property string errorMessage: ""
  property bool busy: false
  property var pending: []
  property var activeRequest: null

  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("backend/orbital_db.py").toString().replace(/^file:\/\//, ""))

  readonly property string barLabel: phase === "idle"
    ? (activityName ? "Orbital · " + activityName : "Orbital · Ready")
    : activityName + " · " + formatTime(mode === "focus" ? Math.max(0, plannedSeconds - elapsedSeconds) : elapsedSeconds)

  function formatTime(seconds) {
    var minutes = Math.floor(seconds / 60)
    var remainder = seconds % 60
    return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
  }

  function applyTimer(timer) {
    phase = timer.phase
    mode = timer.mode
    activeMs = timer.active_ms
    plannedSeconds = timer.planned_seconds
    displayStartedAt = Date.now()
    updateDisplay()
    completionTick.stop()
    if (phase === "running" && mode === "focus") {
      completionTick.interval = Math.max(1000, plannedSeconds * 1000 - activeMs)
      completionTick.start()
    }
  }

  function updateDisplay() {
    var displayMs = activeMs + (phase === "running" ? Math.max(0, Date.now() - displayStartedAt) : 0)
    elapsedSeconds = Math.floor(displayMs / 1000)
  }

  function submit(command, values) {
    var request = values || {}
    request.command = command
    pending = pending.concat([request])
    startNext()
  }

  function startNext() {
    if (busy || pending.length === 0) return
    activeRequest = pending[0]
    pending = pending.slice(1)
    busy = true
    helper.command = ["python3", helperPath, JSON.stringify(activeRequest)]
    helper.running = true
  }

  function refresh() {
    submit("activities.list", {})
  }

  function handleResult(exitCode, output) {
    busy = false
    var parsed = null
    try { parsed = JSON.parse(output) } catch (error) {}
    if (exitCode !== 0 || !parsed || typeof parsed.ok !== "boolean") {
      errorMessage = "Orbital could not read its data. Check Python and plugin installation."
    } else if (!parsed.ok) {
      errorMessage = parsed.error && parsed.error.message ? parsed.error.message : "Orbital data request failed."
    } else {
      errorMessage = ""
      if (activeRequest.command === "activities.list") {
        activities = parsed.result.activities
        selectedActivityId = parsed.result.selected_activity_id || ""
        activityName = ""
        for (var i = 0; i < activities.length; i++) {
          if (activities[i].id === selectedActivityId) activityName = activities[i].name
        }
      } else if (activeRequest.command.indexOf("timer.") === 0) {
        applyTimer(parsed.result.timer || parsed.result)
      } else {
        refresh()
      }
    }
    activeRequest = null
    startNext()
  }

  property Process helper: Process {
    stdout: StdioCollector {
      id: helperOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.handleResult(exitCode, helperOutput.text)
    }
  }

  property Timer displayTick: Timer {
    interval: 1000
    repeat: true
    running: root.phase === "running"
    onTriggered: root.updateDisplay()
  }

  property Timer checkpointTick: Timer {
    interval: 60000
    repeat: true
    running: root.phase === "running"
    onTriggered: root.submit("timer.checkpoint", {})
  }

  property Timer completionTick: Timer {
    repeat: false
    onTriggered: root.submit("timer.complete", {})
  }

  Component.onCompleted: {
    refresh()
    submit("timer.load", {})
  }
}
