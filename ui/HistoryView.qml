import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property var editingSession: null
  property string editingActivityId: ""
  property string validationError: ""
  property bool confirmDelete: false
  property bool allowOverlap: false

  width: parent ? parent.width : 0
  spacing: Style.space(10)

  function beginEdit(session) {
    editingSession = session
    editingActivityId = session.activity_id
    startInput.text = Qt.formatDateTime(new Date(session.started_at), "yyyy-MM-dd HH:mm:ss")
    secondsInput.text = String(session.active_seconds)
    noteInput.text = session.note
    validationError = ""
    confirmDelete = false
    allowOverlap = false
  }

  function edit() {
    validationError = ""
    var match = startInput.text.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/)
    var seconds = Number(secondsInput.text.trim())
    if (!match || !Number.isInteger(seconds) || seconds < 1 || seconds > 86400) {
      validationError = "Enter a valid local start and 1 to 86400 active seconds."
      return
    }
    var start = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                         Number(match[4]), Number(match[5]), Number(match[6]))
    if (start.getFullYear() !== Number(match[1]) || start.getMonth() + 1 !== Number(match[2])
        || start.getDate() !== Number(match[3]) || start.getHours() !== Number(match[4])
        || start.getMinutes() !== Number(match[5]) || start.getSeconds() !== Number(match[6])
        || start.getTime() + seconds * 1000 > Date.now()) {
      validationError = "This date or duration is invalid or extends into the future."
      return
    }
    service.submit("sessions.edit", {
      session_id: editingSession.id,
      activity_id: editingActivityId,
      started_at: start.toISOString(),
      active_seconds: seconds,
      note: noteInput.text.trim(),
      allow_overlap: allowOverlap
    })
  }

  function nextActivity() {
    if (!service) return
    var available = service.activities.filter(function(activity) { return !activity.archived_at })
    if (available.length === 0) return
    var index = -1
    for (var i = 0; i < available.length; i++) {
      if (available[i].id === editingActivityId) index = i
    }
    editingActivityId = available[(index + 1) % available.length].id
  }

  function activityName() {
    if (editingSession && editingSession.activity_id === editingActivityId)
      return editingSession.activity_name
    if (!service) return ""
    for (var i = 0; i < service.activities.length; i++) {
      if (service.activities[i].id === editingActivityId) return service.activities[i].name
    }
    return "Unknown activity"
  }

  Connections {
    target: root.service
    function onRequestFinished(command, success, code) {
      if (command !== "sessions.edit" && command !== "sessions.delete") return
      if (success) root.editingSession = null
      else if (code === "overlap") root.validationError = "This overlaps saved time. Enable Allow overlap to save it deliberately."
    }
  }

  Text {
    text: "Saved history"
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.weight: Font.DemiBold
  }

  Row {
    spacing: Style.space(14)

    Repeater {
      model: ["All activities", "Selected activity"]

      Text {
        required property string modelData
        text: modelData
        color: Commons.Color.accent
        opacity: root.service && ((modelData === "All activities") === (root.service.historyFilterId === "")) ? 1 : 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.body

        MouseArea {
          anchors.fill: parent
          enabled: root.service && (modelData === "All activities" || root.service.selectedActivityId !== "")
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.service.historyFilterId = modelData === "All activities" ? "" : root.service.selectedActivityId
            root.service.loadHistory(true)
          }
        }
      }
    }
  }

  Text {
    visible: root.service && root.service.historySessions.length === 0
    text: "No saved sessions in this view."
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.service ? root.service.historySessions : []

    Row {
      required property var modelData
      width: root.width
      spacing: Style.space(8)

      Column {
        width: parent.width * 0.48
        spacing: Style.space(3)

        Text {
          text: modelData.activity_name
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          text: Qt.formatDateTime(new Date(modelData.started_at), "MMM d · HH:mm")
            + " · " + modelData.source
          color: Commons.Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width * 0.25
        text: root.service.formatDuration(modelData.active_seconds * 1000)
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        text: "Edit"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.beginEdit(modelData)
        }
      }
    }
  }

  Text {
    visible: root.service && root.service.historyCursor !== null
    text: "Load more"
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body

    MouseArea {
      anchors.fill: parent
      enabled: root.service && !root.service.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: root.service.loadHistory(false)
    }
  }

  Column {
    visible: root.editingSession !== null
    width: root.width
    spacing: Style.space(8)

    Text {
      text: "Correct session"
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
    }

    Text {
      text: "Activity: " + root.activityName() + "  ↻"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.nextActivity()
      }
    }

    Text {
      text: "Local start · YYYY-MM-DD HH:MM:SS"
      color: Commons.Color.foreground
      opacity: 0.65
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    TextInput {
      id: startInput
      width: root.width
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: 19
    }

    Text {
      text: "Active seconds"
      color: Commons.Color.foreground
      opacity: 0.65
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    TextInput {
      id: secondsInput
      width: root.width
      validator: IntValidator { bottom: 1; top: 86400 }
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    TextInput {
      id: noteInput
      width: root.width
      maximumLength: 500
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      text: root.allowOverlap ? "☑ Allow overlap" : "☐ Allow overlap"
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.allowOverlap = !root.allowOverlap
      }
    }

    Text {
      visible: root.validationError !== ""
      width: root.width
      wrapMode: Text.WordWrap
      text: root.validationError
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Row {
      spacing: Style.space(12)

      Repeater {
        model: ["Save correction", root.confirmDelete ? "Confirm delete" : "Delete", "Cancel"]

        Text {
          required property string modelData
          text: modelData
          color: modelData === "Delete" ? Commons.Color.foreground : Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body

          MouseArea {
            anchors.fill: parent
            enabled: root.service && !root.service.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData === "Save correction") root.edit()
              else if (modelData === "Delete") root.confirmDelete = true
              else if (modelData === "Confirm delete")
                root.service.submit("sessions.delete", { session_id: root.editingSession.id })
              else root.editingSession = null
            }
          }
        }
      }
    }
  }
}
