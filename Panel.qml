import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui" as OrbitalUi

Panel {
  id: root
  moduleName: "io.github.rcode010.omarchy-orbital"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string page: "home"
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground

  function beginEdit(activity) {
    editor.activity = activity
    Qt.callLater(function() {
      scroll.contentY = Math.max(0, Math.min(editor.y, scroll.contentHeight - scroll.height))
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
            model: ["Home", "Insights", "History"]

            Text {
              required property string modelData
              text: modelData
              color: root.foreground
              opacity: root.page === modelData.toLowerCase() ? 1 : 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: root.page === modelData.toLowerCase() ? Font.DemiBold : Font.Normal

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.page = modelData.toLowerCase()
                  scroll.contentY = 0
                  if (root.page === "history" && root.service) root.service.loadHistory(true)
                  if (root.page === "insights" && root.service) root.service.loadInsights()
                }
              }
            }
          }
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
          visible: root.service && root.service.activities.length > 0
          spacing: Style.space(12)

          Repeater {
            model: ["focus", "stopwatch"]

            Text {
              required property string modelData
              text: modelData === "focus" ? "Focus" : "Stopwatch"
              color: root.foreground
              opacity: root.service && root.service.mode === modelData ? 1 : 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: root.service && root.service.mode === modelData ? Font.DemiBold : Font.Normal

              MouseArea {
                anchors.fill: parent
                enabled: root.service && root.service.phase === "idle"
                cursorShape: Qt.PointingHandCursor
                onClicked: root.service.mode = modelData
              }
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
          text: root.service ? root.service.formatTime(root.service.mode === "focus"
            ? Math.max(0, root.service.plannedSeconds - root.service.elapsedSeconds)
            : root.service.elapsedSeconds) : "25:00"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.space(42)
          font.weight: Font.DemiBold
        }

        Text {
          visible: root.service && root.service.phase !== "idle"
          text: root.service && root.service.phase === "paused" ? "Paused · active time saved" : "Tracking active time"
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
              : root.service && root.service.phase === "paused"
                ? ["Resume", root.service.mode === "focus" ? "Finish Early" : "Finish", "Discard"]
                : ["Pause", root.service && root.service.mode === "focus" ? "Finish Early" : "Finish", "Discard"]

            Rectangle {
              required property string modelData
              width: label.implicitWidth + Style.space(20)
              height: Style.space(38)
              radius: Style.space(8)
              color: modelData === "Discard" ? "transparent" : Commons.Color.accent
              border.color: root.foreground
              border.width: modelData === "Discard" ? 1 : 0

              Text {
                id: label
                anchors.centerIn: parent
                text: modelData
                color: modelData === "Discard" ? root.foreground : Commons.Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.service && !root.service.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData === "Start")
                    root.service.submit("timer.start", { mode: root.service.mode, planned_seconds: root.service.plannedSeconds })
                  else if (modelData === "Pause") root.service.submit("timer.pause", {})
                  else if (modelData === "Resume") root.service.submit("timer.resume", {})
                  else if (modelData === "Discard") root.service.submit("timer.discard", {})
                  else root.service.submit("timer.finish", {})
                }
              }
            }
          }
        }

        Text {
          visible: root.service && root.service.errorMessage !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.service ? root.service.errorMessage : ""
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
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
            required property var modelData
            width: ListView.view.width
            height: Style.space(42)
            radius: Style.space(9)
            color: modelData.id === root.service.selectedActivityId
              ? Commons.Color.accent : "transparent"
            border.color: root.foreground
            border.width: modelData.id === root.service.selectedActivityId ? 0 : 1

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
              enabled: root.service !== null
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.archived_at) root.beginEdit(modelData)
                else root.service.submit("activities.select", { activity_id: modelData.id })
              }
            }
          }
        }

        Row {
          spacing: Style.space(18)

          Text {
            text: "Manage selected"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body

            MouseArea {
              anchors.fill: parent
              enabled: root.service && root.service.selectedActivityId !== ""
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                for (var i = 0; i < root.service.activities.length; i++) {
                  var activity = root.service.activities[i]
                  if (activity.id === root.service.selectedActivityId) root.beginEdit(activity)
                }
              }
            }
          }

          Text {
            text: root.service && root.service.showArchived ? "Hide archived" : "Show archived"
            color: root.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.body

            MouseArea {
              anchors.fill: parent
              enabled: root.service !== null
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.service.showArchived = !root.service.showArchived
                root.service.refresh()
              }
            }
          }
        }

        OrbitalUi.ActivityEditor {
          id: editor
          service: root.service
          onDone: editor.activity = null
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

            function createActivity() {
              if (!root.service || activityInput.text.trim() === "") return
              root.service.submit("activities.create", { name: activityInput.text.trim() })
              activityInput.text = ""
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
              onClicked: addButton.createActivity()
            }
          }
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
        }
      }
      }
    }
  }
}
