import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property string phase: "idle"
  property string activityName: ""
  property int elapsedSeconds: 0
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
    : activityName + " · " + Math.floor(elapsedSeconds / 60) + "m"

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

  Component.onCompleted: refresh()
}
