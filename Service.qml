import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import "model/TimerDisplay.js" as TimerDisplay

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
  property double displayEstimateMs: 0
  property double lastDisplayWall: 0
  property var activities: []
  property var today: ({ day: "", total_ms: 0, session_count: 0, activities: [] })
  property var todayByActivity: ({})
  property var recentSessions: []
  property var historySessions: []
  property var historyActivities: []
  property var historyCursor: null
  property var historyPageBefore: null
  property var historyBackStack: []
  property string historyFilterId: ""
  property string historyStartDay: ""
  property string historyEndDay: ""
  property var insightsReport: null
  property string insightsPeriod: "today"
  property string insightsAnchor: ""
  property var settings: ({ focus_minutes: 25, short_break_minutes: 5,
                            long_break_minutes: 15, long_break_every: 4,
                            auto_start_break: false, auto_start_focus: false,
                            notifications: false, pause_on_idle: true, idle_minutes: 5 })
  property var backups: []
  property string backupMessage: ""
  property string exportName: ""
  property bool showArchived: false
  property string selectedActivityId: ""
  property string errorMessage: ""
  property string errorCode: ""
  property bool busy: false
  property bool helperTimedOut: false
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

  function formatSessionDuration(seconds) {
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    var remainder = seconds % 60
    var padded = remainder < 10 ? "0" + remainder : String(remainder)
    if (hours > 0)
      return hours + ":" + (minutes < 10 ? "0" + minutes : minutes) + ":" + padded
    return minutes + ":" + padded
  }

  function applyTimer(timer) {
    phase = timer.phase
    breakKind = timer.break_kind || ""
    mode = timer.mode
    activeMs = timer.active_ms
    plannedSeconds = timer.planned_seconds
    displayEstimateMs = activeMs
    lastDisplayWall = Date.now()
    updateDisplay()
    completionTick.stop()
    if ((phase === "running" && mode === "focus") || phase === "break_running") {
      completionTick.interval = Math.max(1000, plannedSeconds * 1000 - activeMs)
      completionTick.start()
    }
  }

  function updateDisplay() {
    elapsedSeconds = Math.floor(displayEstimateMs / 1000)
  }

  function advanceDisplay() {
    var next = TimerDisplay.advance(displayEstimateMs, lastDisplayWall, Date.now())
    displayEstimateMs = next.milliseconds
    lastDisplayWall = next.lastWall
    updateDisplay()
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
    helperTimedOut = false
    helper.command = ["python3", helperPath, JSON.stringify(activeRequest)]
    helper.running = true
    helperTimeout.restart()
  }

  function refresh() {
    submit("activities.list", { include_archived: showArchived })
  }

  function refreshReports() {
    submit("reports.day", {})
    submit("sessions.recent", { limit: 8 })
  }

  function reloadState() {
    submit("timer.load", {})
    refresh()
    submit("settings.get", {})
    refreshReports()
  }

  function loadHistory(reset) {
    if (reset) {
      historySessions = []
      historyCursor = null
      historyPageBefore = null
      historyBackStack = []
    }
    var request = { limit: 20 }
    if (historyFilterId) request.activity_id = historyFilterId
    if (historyStartDay && historyEndDay) {
      request.start_day = historyStartDay
      request.end_day = historyEndDay
    }
    if (historyPageBefore) request.before = historyPageBefore
    submit("sessions.list", request)
  }

  function olderHistory() {
    if (busy || !historyCursor) return
    historyBackStack = historyBackStack.concat([historyPageBefore])
    historyPageBefore = historyCursor
    loadHistory(false)
  }

  function newerHistory() {
    if (busy || historyBackStack.length === 0) return
    historyPageBefore = historyBackStack[historyBackStack.length - 1]
    historyBackStack = historyBackStack.slice(0, -1)
    loadHistory(false)
  }

  function loadHistoryActivities() {
    submit("activities.list", { include_archived: true, for_history: true })
  }

  function loadInsights() {
    var request = { period: insightsPeriod }
    if (insightsPeriod !== "today" && insightsAnchor) request.anchor = insightsAnchor
    if (selectedActivityId) request.activity_id = selectedActivityId
    submit("reports.period", request)
  }

  function loadBackups() {
    submit("backup.list", {})
  }

  function showNotification(title, message) {
    if (!settings.notifications || notification.running) return
    notification.command = ["notify-send", "--app-name=Orbital", title, message]
    notification.running = true
  }

  function handleResult(exitCode, output) {
    helperTimeout.stop()
    var parsed = null
    try { parsed = JSON.parse(output) } catch (error) {}
    if (helperTimedOut) {
      errorMessage = "Orbital data request timed out. Refresh state before retrying."
      errorCode = "helper_timeout"
      pending = []
    } else if (exitCode !== 0 || !parsed || typeof parsed.ok !== "boolean") {
      errorMessage = "Orbital could not read its data. Check Python and plugin installation."
      errorCode = "helper_failure"
    } else if (!parsed.ok) {
      errorMessage = parsed.error && parsed.error.message ? parsed.error.message : "Orbital data request failed."
      errorCode = parsed.error && parsed.error.code ? parsed.error.code : "request_failed"
    } else {
      errorMessage = ""
      errorCode = ""
      if (activeRequest.command === "activities.list") {
        if (activeRequest.for_history) {
          historyActivities = parsed.result.activities
        } else {
          activities = parsed.result.activities
          selectedActivityId = parsed.result.selected_activity_id || ""
          activityName = ""
          for (var i = 0; i < activities.length; i++) {
            if (activities[i].id === selectedActivityId) activityName = activities[i].name
          }
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
        historySessions = parsed.result.sessions
        historyCursor = parsed.result.next_cursor
      } else if (activeRequest.command === "reports.period") {
        insightsReport = parsed.result
      } else if (activeRequest.command === "settings.get" || activeRequest.command === "settings.update") {
        settings = parsed.result.settings
        if (phase === "idle") plannedSeconds = settings.focus_minutes * 60
      } else if (activeRequest.command === "backup.list") {
        backups = parsed.result.backups
      } else if (activeRequest.command === "backup.create") {
        backupMessage = "Backup created: " + parsed.result.name
        loadBackups()
      } else if (activeRequest.command === "backup.export_json") {
        exportName = parsed.result.name
        backupMessage = "JSON exported: " + parsed.result.name
      } else if (activeRequest.command === "backup.restore") {
        backupMessage = "Restored " + parsed.result.restored
          + ". Previous data saved as " + parsed.result.previous_backup
        refresh()
        submit("timer.load", {})
        submit("settings.get", {})
        refreshReports()
        loadHistory(true)
        if (insightsReport) loadInsights()
        loadBackups()
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
    busy = false
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

  property Timer helperTimeout: Timer {
    interval: 30000
    onTriggered: {
      root.helperTimedOut = true
      root.helper.running = false
    }
  }

  property Process notification: Process {}

  property IdleMonitor idleMonitor: IdleMonitor {
    enabled: root.settings.pause_on_idle
    timeout: root.settings.idle_minutes * 60
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle && (root.phase === "running" || root.phase === "break_running"))
        root.submit("timer.pause", { cause: "idle" })
    }
  }

  property Timer displayTick: Timer {
    interval: 1000
    repeat: true
    running: root.phase === "running" || root.phase === "break_running"
    onTriggered: root.advanceDisplay()
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
