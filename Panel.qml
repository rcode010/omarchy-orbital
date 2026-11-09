import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui" as OrbitalUi
import "ui/ActivityColors.js" as ActivityColors

Panel {
  id: root
  moduleName: "io.github.rcode010.omarchy-orbital"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string page: "home"
  property string pendingNewActivityName: ""
  property string pendingNewActivityColor: ""
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground

  function beginEdit(activity) {
    editor.activity = activity
    Qt.callLater(function() {
      scroll.contentY = Math.max(0, Math.min(editor.y, scroll.contentHeight - scroll.height))
    })
  }

  function setPage(nextPage) {
    page = nextPage
    scroll.contentY = 0
    if (!service) return
    if (page === "history") {
      service.loadHistoryActivities()
      service.loadHistory(true)
    }
    if (page === "insights") service.loadInsights()
    if (page === "settings") service.loadBackups()
  }

  function perform(action) {
    if (!service || service.busy) return
    if (action === "Start")
      service.submit("timer.start", { mode: service.mode, planned_seconds: service.plannedSeconds })
    else if (action === "Pause" || action === "Pause Break") service.submit("timer.pause", {})
    else if (action === "Resume" || action === "Resume Break") service.submit("timer.resume", {})
    else if (action === "Discard") service.submit("timer.discard", {})
    else if (action === "Start Break") service.submit("timer.start_break", {})
    else if (action === "Skip Break") service.submit("timer.skip_break", {})
    else service.submit("timer.finish", {})
  }

  function primaryAction() {
    if (!service) return
    if (service.phase === "idle") perform("Start")
    else if (service.phase === "paused") perform("Resume")
    else if (service.phase === "running") perform("Pause")
    else if (service.phase === "break_ready") perform("Start Break")
    else if (service.phase === "break_paused") perform("Resume Break")
    else if (service.phase === "break_running") perform("Pause Break")
  }

  function restorePanelFocus() {
    if (!opened) return
    popup.focusPrimed = false
    popup.beginFocusPrime()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(Math.min(content.implicitHeight, Style.space(480)))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
      Keys.onPressed: function(event) {
        if (event.modifiers === Qt.NoModifier && event.key === Qt.Key_Space) {
          root.primaryAction()
          event.accepted = true
        } else if (event.modifiers === Qt.NoModifier && event.key === Qt.Key_F
                   && root.service && (root.service.phase === "running" || root.service.phase === "paused")) {
          root.perform("Finish")
          event.accepted = true
        }
      }

      Shortcut {
        sequence: "Ctrl+1"
        enabled: root.opened
        context: Qt.WindowShortcut
        onActivated: root.setPage("home")
      }
      Shortcut {
        sequence: "Ctrl+2"
        enabled: root.opened
        context: Qt.WindowShortcut
        onActivated: root.setPage("insights")
      }
      Shortcut {
        sequence: "Ctrl+3"
        enabled: root.opened
        context: Qt.WindowShortcut
        onActivated: root.setPage("history")
      }
      Shortcut {
        sequence: "Ctrl+4"
        enabled: root.opened
        context: Qt.WindowShortcut
        onActivated: root.setPage("settings")
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: "ORBITAL"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
        }

        Row {
          spacing: Style.space(16)

          Repeater {
            model: ["Home", "Insights", "History", "Settings"]

            OrbitalUi.ActionText {
              required property string modelData
              text: modelData
              color: root.foreground
              opacity: root.page === modelData.toLowerCase() ? 1 : 0.55
              font.weight: root.page === modelData.toLowerCase() ? Font.DemiBold : Font.Normal
              onActivated: root.setPage(modelData.toLowerCase())
            }
          }
        }

        Text {
          visible: root.service && root.service.errorMessage !== ""
          width: content.width
          wrapMode: Text.WordWrap
          text: root.service ? root.service.errorMessage : ""
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        OrbitalUi.ActionText {
          visible: root.service && root.service.errorMessage !== ""
          text: "Refresh state"
          enabled: root.service && !root.service.busy
          onActivated: root.service.reloadState()
        }

        Column {
          id: home
          visible: root.page === "home"
          width: content.width
          spacing: Style.space(12)

        Text {
          text: "Today"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }

        Text {
          text: root.service && root.service.today.day
            ? Qt.formatDate(new Date(root.service.today.day + "T12:00:00"), "dddd, MMMM d")
            : ""
          color: root.foreground
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.service && root.service.activities.length
            ? "Select an activity, then begin a focus session or stopwatch."
            : "Create an activity to begin your Orbital history."
          color: root.foreground
          opacity: 0.72
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Row {
          visible: root.service && root.service.activities.length > 0 && root.service.phase === "idle"
          spacing: Style.space(12)

          Repeater {
            model: ["focus", "stopwatch"]

            OrbitalUi.ActionText {
              required property string modelData
              text: modelData === "focus" ? "Focus" : "Stopwatch"
              color: root.foreground
              opacity: root.service && root.service.mode === modelData ? 1 : 0.5
              font.weight: root.service && root.service.mode === modelData ? Font.DemiBold : Font.Normal
              enabled: root.service && root.service.phase === "idle"
              onActivated: root.service.mode = modelData
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: root.service ? root.service.formatDuration(root.service.today.total_ms) : "0s"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }

          Text {
            text: root.service ? root.service.today.session_count + " sessions saved" : ""
            color: root.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Text {
          visible: root.service && root.service.activities.length > 0
          text: root.service ? root.service.formatTime(
            root.service.phase.indexOf("break") === 0
              ? Math.max(0, root.service.plannedSeconds - root.service.elapsedSeconds)
              : root.service.mode === "focus"
            ? Math.max(0, root.service.plannedSeconds - root.service.elapsedSeconds)
            : root.service.elapsedSeconds) : "25:00"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.space(42)
          font.weight: Font.DemiBold
        }

        Text {
          visible: root.service && root.service.phase !== "idle"
          text: root.service
            ? (root.service.phase === "paused" ? "Paused · active time saved"
               : root.service.phase === "break_ready" ? "Ready for a " + root.service.breakKind + " break"
               : root.service.phase === "break_paused" ? root.service.breakKind + " break paused"
               : root.service.phase === "break_running" ? root.service.breakKind + " break · no work time counted"
               : "Tracking active time") : ""
          color: root.foreground
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Row {
          visible: root.service && root.service.activities.length > 0
          spacing: Style.space(8)

          Repeater {
            model: root.service && root.service.phase === "idle"
              ? ["Start"]
              : root.service && root.service.phase === "break_ready"
                ? ["Start Break", "Skip Break"]
              : root.service && root.service.phase === "break_paused"
                ? ["Resume Break", "Skip Break"]
              : root.service && root.service.phase === "break_running"
                ? ["Pause Break", "Skip Break"]
              : root.service && root.service.phase === "paused"
                ? ["Resume", root.service.mode === "focus" ? "Finish Early" : "Finish", "Discard"]
                : ["Pause", root.service && root.service.mode === "focus" ? "Finish Early" : "Finish", "Discard"]

            Button {
              required property string modelData
              required property int index
              text: modelData
              active: index === 0
              focusable: true
              bordered: modelData === "Discard" || modelData === "Skip Break"
              enabled: root.service && !root.service.busy
              foreground: root.foreground
              accent: Commons.Color.accent
              onClicked: root.perform(modelData)
            }
          }
        }

        Text {
          text: "ACTIVITIES"
          color: root.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        ListView {
          width: content.width
          height: Math.min(Style.space(210), count * Style.space(46))
          clip: true
          spacing: Style.space(4)
          model: root.service ? root.service.activities : []

          delegate: Rectangle {
            id: activityRow
            required property var modelData
            width: ListView.view.width
            height: Style.space(42)
            radius: Style.space(9)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name + (modelData.archived_at ? ", archived, manage" : ", select")
            Keys.onReturnPressed: activate()
            Keys.onSpacePressed: activate()

            function activate() {
              if (modelData.archived_at) root.beginEdit(modelData)
              else if (root.service && root.service.phase === "idle")
                root.service.submit("activities.select", { activity_id: modelData.id })
            }

            color: modelData.id === root.service.selectedActivityId
              ? Commons.Color.accent : "transparent"
            border.color: activeFocus ? Commons.Color.accent : root.foreground
            border.width: activeFocus ? 2 : (modelData.id === root.service.selectedActivityId ? 0 : 1)

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(3)
              height: parent.height - Style.space(14)
              radius: width / 2
              color: ActivityColors.value(modelData.color)
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(80)
              verticalAlignment: Text.AlignVCenter
              text: (modelData.icon ? modelData.icon + "  " : "") + modelData.name
                + (modelData.archived_at ? " · Archived" : "")
              elide: Text.ElideRight
              color: modelData.id === root.service.selectedActivityId
                ? Commons.Color.background : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.service.formatDuration(root.service.todayByActivity[modelData.id] || 0)
              color: modelData.id === root.service.selectedActivityId
                ? Commons.Color.background : root.foreground
              opacity: 0.75
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              enabled: root.service && (modelData.archived_at || root.service.phase === "idle")
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                activityRow.forceActiveFocus()
                activityRow.activate()
              }
            }
          }
        }

        Row {
          spacing: Style.space(18)

          OrbitalUi.ActionText {
            text: "Manage selected"
            enabled: root.service && root.service.selectedActivityId !== ""
            onActivated: {
              for (var i = 0; i < root.service.activities.length; i++) {
                var activity = root.service.activities[i]
                if (activity.id === root.service.selectedActivityId) root.beginEdit(activity)
              }
            }
          }

          OrbitalUi.ActionText {
            text: root.service && root.service.showArchived ? "Hide archived" : "Show archived"
            color: root.foreground
            opacity: 0.7
            enabled: root.service !== null
            onActivated: {
              root.service.showArchived = !root.service.showArchived
              root.service.refresh()
            }
          }
        }

        OrbitalUi.ActivityEditor {
          id: editor
          service: root.service
          onDone: editor.activity = null
        }

        Connections {
          target: root.service
          function onRequestFinished(command, success) {
            if (success && ["timer.start", "timer.pause", "timer.resume", "timer.finish",
                            "timer.discard", "timer.start_break", "timer.skip_break"].indexOf(command) !== -1)
              root.restorePanelFocus()
            if (command !== "activities.create" || root.pendingNewActivityName === "") return
            if (success) {
              if (activityInput.text.trim() === root.pendingNewActivityName) activityInput.text = ""
              if (newColorPicker.selectedColor === root.pendingNewActivityColor)
                newColorPicker.selectedColor = "blue"
            }
            root.pendingNewActivityName = ""
            root.pendingNewActivityColor = ""
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            width: parent.width - addButton.width - parent.spacing
            height: Style.space(40)
            radius: Style.space(8)
            color: "transparent"
            border.color: root.foreground
            border.width: 1

            TextInput {
              id: activityInput
              anchors.fill: parent
              anchors.margins: Style.space(10)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              maximumLength: 80
              Accessible.name: "New activity name"
              Keys.onReturnPressed: addButton.createActivity()
            }

            Text {
              anchors.fill: activityInput
              verticalAlignment: Text.AlignVCenter
              visible: activityInput.text === "" && !activityInput.activeFocus
              text: "New activity"
              color: root.foreground
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          Rectangle {
            id: addButton
            width: Style.space(72)
            height: Style.space(40)
            radius: Style.space(8)
            color: Commons.Color.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Add activity"
            enabled: root.service && !root.service.busy
            border.color: activeFocus ? root.foreground : "transparent"
            border.width: activeFocus ? 2 : 0
            Keys.onReturnPressed: function(event) {
              createActivity()
              event.accepted = true
            }
            Keys.onSpacePressed: function(event) {
              createActivity()
              event.accepted = true
            }

            function createActivity() {
              if (!root.service || root.service.busy || activityInput.text.trim() === "") return
              root.pendingNewActivityName = activityInput.text.trim()
              root.pendingNewActivityColor = newColorPicker.selectedColor
              root.service.submit("activities.create", {
                name: root.pendingNewActivityName, color: root.pendingNewActivityColor
              })
            }

            Text {
              anchors.centerIn: parent
              text: "Add"
              color: Commons.Color.background
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                addButton.forceActiveFocus()
                addButton.createActivity()
              }
            }
          }
        }

        Text {
          text: "NEW ACTIVITY COLOR"
          color: root.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        OrbitalUi.ColorPicker {
          id: newColorPicker
        }

        OrbitalUi.ManualEntry {
          service: root.service
        }

        Text {
          visible: root.service && root.service.recentSessions.length > 0
          text: "RECENT SESSIONS"
          color: root.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        Repeater {
          model: root.service ? root.service.recentSessions : []

          Row {
            required property var modelData
            width: content.width
            spacing: Style.space(8)

            Text {
              width: parent.width * 0.48
              text: modelData.activity_name
              elide: Text.ElideRight
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width * 0.24
              text: root.service.formatDuration(modelData.active_seconds * 1000)
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width * 0.24
              text: Qt.formatDateTime(new Date(modelData.started_at), "MMM d")
              color: root.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
        }

        OrbitalUi.HistoryView {
          visible: root.page === "history"
          service: root.service
        }

        OrbitalUi.InsightsView {
          visible: root.page === "insights"
          service: root.service
          onOpenSelectedHistory: {
            root.service.historyFilterId = root.service.selectedActivityId
            root.setPage("history")
          }
        }

        OrbitalUi.SettingsView {
          visible: root.page === "settings"
          service: root.service
        }
      }
      }
    }
  }
}
