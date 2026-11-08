import QtQuick
import Quickshell.Io

QtObject {
  id: root
  signal requestFinished(string command, bool success, string code)

  property string phase: "idle"
  property string breakKind: ""
  property string mode: "focus"
  property string activityName: ""
  property int elapsedSeconds: 0
  property double activeMs: 0
  property int plannedSeconds: 1500
  property double displayStartedAt: 0
  property var activities: []
  property var today: ({ day: "", total_ms: 0, session_count: 0, activities: [] })
  property var todayByActivity: ({})
  property var recentSessions: []
  property var historySessions: []
  property var historyCursor: null
  property string historyFilterId: ""
  property var insightsReport: null
  property string insightsPeriod: "today"
  property string insightsAnchor: ""
  property var settings: ({ focus_minutes: 25, short_break_minutes: 5,
                            long_break_minutes: 15, long_break_every: 4,
                            auto_start_break: false, auto_start_focus: false,
                            notifications: false })
  property bool showArchived: false
  property string selectedActivityId: ""
  property string errorMessage: ""
  property string errorCode: ""
  property bool busy: false
  property var pending: []
  property var activeRequest: null

  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("backend/orbital_db.py").toString().replace(/^file:\/\//, ""))

  readonly property string barLabel: phase === "idle"
    ? (activityName ? "Orbital · " + activityName : "Orbital · Ready")
    : phase.indexOf("break") === 0
      ? (phase === "break_ready" ? "Orbital · Break ready"
         : "Orbital · Break " + formatTime(Math.max(0, plannedSeconds - elapsedSeconds))
           + (phase === "break_paused" ? " · Paused" : ""))
      : activityName + " · " + formatTime(mode === "focus"
          ? Math.max(0, plannedSeconds - elapsedSeconds) : elapsedSeconds)
          + (phase === "paused" ? " · Paused" : "")

  function formatTime(seconds) {
    var minutes = Math.floor(seconds / 60)
    var remainder = seconds % 60
    return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
  }

  function formatDuration(milliseconds) {
    var seconds = Math.floor(milliseconds / 1000)
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    if (hours > 0) return hours + "h " + minutes + "m"
    if (minutes > 0) return minutes + "m"
    return seconds + "s"
  }

  function applyTimer(timer) {
    phase = timer.phase
    breakKind = timer.break_kind || ""
    mode = timer.mode
    activeMs = timer.active_ms
    plannedSeconds = timer.planned_seconds
    displayStartedAt = Date.now()
    updateDisplay()
    completionTick.stop()
    if ((phase === "running" && mode === "focus") || phase === "break_running") {
      completionTick.interval = Math.max(1000, plannedSeconds * 1000 - activeMs)
      completionTick.start()
    }
  }

  function updateDisplay() {
    var active = phase === "running" || phase === "break_running"
    var displayMs = activeMs + (active ? Math.max(0, Date.now() - displayStartedAt) : 0)
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
    submit("activities.list", { include_archived: showArchived })
  }

  function refreshReports() {
    submit("reports.day", {})
    submit("sessions.recent", { limit: 8 })
  }

  function loadHistory(reset) {
    if (reset) {
      historySessions = []
      historyCursor = null
    }
    var request = { limit: 20 }
    if (historyFilterId) request.activity_id = historyFilterId
    if (!reset && historyCursor) request.before = historyCursor
    submit("sessions.list", request)
  }

  function loadInsights() {
    var request = { period: insightsPeriod }
    if (insightsPeriod !== "today" && insightsAnchor) request.anchor = insightsAnchor
    submit("reports.period", request)
  }

  function showNotification(title, message) {
    if (!settings.notifications || notification.running) return
    notification.command = ["notify-send", "--app-name=Orbital", title, message]
    notification.running = true
  }

  function handleResult(exitCode, output) {
    busy = false
    var parsed = null
    try { parsed = JSON.parse(output) } catch (error) {}
    if (exitCode !== 0 || !parsed || typeof parsed.ok !== "boolean") {
      errorMessage = "Orbital could not read its data. Check Python and plugin installation."
      errorCode = "helper_failure"
    } else if (!parsed.ok) {
      errorMessage = parsed.error && parsed.error.message ? parsed.error.message : "Orbital data request failed."
      errorCode = parsed.error && parsed.error.code ? parsed.error.code : "request_failed"
    } else {
      errorMessage = ""
      errorCode = ""
      if (activeRequest.command === "activities.list") {
        activities = parsed.result.activities
        selectedActivityId = parsed.result.selected_activity_id || ""
        activityName = ""
        for (var i = 0; i < activities.length; i++) {
          if (activities[i].id === selectedActivityId) activityName = activities[i].name
        }
      } else if (activeRequest.command.indexOf("timer.") === 0) {
        applyTimer(parsed.result.timer || parsed.result)
        if (activeRequest.command === "timer.complete" && parsed.result.completed)
          showNotification("Focus complete", "Time for a " + breakKind + " break")
        if (activeRequest.command === "timer.complete_break" && parsed.result.completed)
          showNotification("Break complete", phase === "running" ? "Next focus started" : "Ready for focus")
        if (parsed.result.saved) {
          refreshReports()
          loadHistory(true)
          if (insightsReport) loadInsights()
        }
      } else if (activeRequest.command === "reports.day") {
        today = parsed.result
        var totals = {}
        for (var j = 0; j < today.activities.length; j++)
          totals[today.activities[j].activity_id] = today.activities[j].active_ms
        todayByActivity = totals
      } else if (activeRequest.command === "sessions.recent") {
        recentSessions = parsed.result.sessions
      } else if (activeRequest.command === "sessions.list") {
        historySessions = activeRequest.before
          ? historySessions.concat(parsed.result.sessions) : parsed.result.sessions
        historyCursor = parsed.result.next_cursor
      } else if (activeRequest.command === "reports.period") {
        insightsReport = parsed.result
      } else if (activeRequest.command === "settings.get" || activeRequest.command === "settings.update") {
        settings = parsed.result.settings
        if (phase === "idle") plannedSeconds = settings.focus_minutes * 60
      } else if (activeRequest.command.indexOf("sessions.") === 0) {
        refreshReports()
        loadHistory(true)
        if (insightsReport) loadInsights()
      } else {
        refresh()
        refreshReports()
      }
    }
    requestFinished(activeRequest.command, errorCode === "", errorCode)
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

  property Process notification: Process {}

  property Timer displayTick: Timer {
    interval: 1000
    repeat: true
    running: root.phase === "running" || root.phase === "break_running"
    onTriggered: root.updateDisplay()
  }

  property Timer checkpointTick: Timer {
    interval: 60000
    repeat: true
    running: root.phase === "running" || root.phase === "break_running"
    onTriggered: root.submit("timer.checkpoint", {})
  }

  property Timer completionTick: Timer {
    repeat: false
    onTriggered: root.submit(root.phase === "break_running"
      ? "timer.complete_break" : "timer.complete", {})
  }

  property Timer calendarTick: Timer {
    interval: 60000
    repeat: true
    running: true
    property string visibleDay: new Date().toDateString()
    onTriggered: {
      var currentDay = new Date().toDateString()
      if (currentDay !== visibleDay) {
        visibleDay = currentDay
        root.refreshReports()
      }
    }
  }

  Component.onCompleted: {
    refresh()
    submit("timer.load", {})
    refreshReports()
    submit("settings.get", {})
  }
}
