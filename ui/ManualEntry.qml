import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property bool expanded: false
  property bool allowOverlap: false
  property string validationError: ""

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  function submit() {
    validationError = ""
    if (!service || !service.selectedActivityId) {
      validationError = "Select an activity first."
      return
    }
    var match = startInput.text.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/)
    var minutes = Number(durationInput.text.trim())
    if (!match || !Number.isInteger(minutes) || minutes < 1 || minutes > 1440) {
      validationError = "Enter a valid date, time, and duration from 1 to 1440 minutes."
      return
    }
    var start = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                         Number(match[4]), Number(match[5]))
    if (start.getFullYear() !== Number(match[1]) || start.getMonth() + 1 !== Number(match[2])
        || start.getDate() !== Number(match[3]) || start.getHours() !== Number(match[4])
        || start.getMinutes() !== Number(match[5]) || start.getTime() + minutes * 60000 > Date.now()) {
      validationError = "This date or time is invalid or extends into the future."
      return
    }
    service.submit("sessions.add_manual", {
      activity_id: service.selectedActivityId,
      started_at: start.toISOString(),
      active_seconds: minutes * 60,
      note: noteInput.text.trim(),
      allow_overlap: allowOverlap
    })
  }

  Connections {
    target: root.service
    function onRequestFinished(command, success, code) {
      if (command !== "sessions.add_manual") return
      if (success) {
        root.expanded = false
        root.allowOverlap = false
        root.validationError = ""
        noteInput.text = ""
      } else if (code === "overlap") {
        root.validationError = "This overlaps saved time. Enable Allow overlap to add it deliberately."
      }
    }
  }

  Text {
    text: root.expanded ? "Cancel missed time" : "+ Add missed time"
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expanded = !root.expanded
    }
  }

  Text {
    visible: root.expanded
    text: "Local start · YYYY-MM-DD HH:MM"
    color: Commons.Color.foreground
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    visible: root.expanded
    width: root.width
    height: Style.space(38)
    radius: Style.space(8)
    color: "transparent"
    border.color: Commons.Color.foreground
    border.width: 1

    TextInput {
      id: startInput
      anchors.fill: parent
      anchors.margins: Style.space(9)
      verticalAlignment: TextInput.AlignVCenter
      text: Qt.formatDateTime(new Date(Date.now() - 3600000), "yyyy-MM-dd HH:mm")
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: 16
    }
  }

  Row {
    visible: root.expanded
    width: root.width
    spacing: Style.space(8)

    Rectangle {
      width: Style.space(86)
      height: Style.space(38)
      radius: Style.space(8)
      color: "transparent"
      border.color: Commons.Color.foreground
      border.width: 1

      TextInput {
        id: durationInput
        anchors.fill: parent
        anchors.margins: Style.space(9)
        verticalAlignment: TextInput.AlignVCenter
        text: "30"
        validator: IntValidator { bottom: 1; top: 1440 }
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "minutes"
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Rectangle {
    visible: root.expanded
    width: root.width
    height: Style.space(38)
    radius: Style.space(8)
    color: "transparent"
    border.color: Commons.Color.foreground
    border.width: 1

    TextInput {
      id: noteInput
      anchors.fill: parent
      anchors.margins: Style.space(9)
      verticalAlignment: TextInput.AlignVCenter
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: 500
    }

    Text {
      anchors.fill: noteInput
      verticalAlignment: Text.AlignVCenter
      visible: noteInput.text === "" && !noteInput.activeFocus
      text: "Optional note"
      color: Commons.Color.foreground
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Text {
    visible: root.expanded
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
    visible: root.expanded && root.validationError !== ""
    width: root.width
    wrapMode: Text.WordWrap
    text: root.validationError
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: root.expanded
    text: "Save missed time"
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold

    MouseArea {
      anchors.fill: parent
      enabled: root.service && !root.service.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: root.submit()
    }
  }
}
