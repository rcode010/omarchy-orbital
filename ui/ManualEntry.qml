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

  function localDate(value) {
    var match = value.match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/)
    if (!match) return null
    var result = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                          Number(match[4]), Number(match[5]))
    if (result.getFullYear() !== Number(match[1]) || result.getMonth() + 1 !== Number(match[2])
        || result.getDate() !== Number(match[3]) || result.getHours() !== Number(match[4])
        || result.getMinutes() !== Number(match[5])) return null
    return result
  }

  function submit() {
    validationError = ""
    if (!service || !service.selectedActivityId) {
      validationError = "Select an activity first."
      return
    }
    var start = localDate(startInput.text.trim())
    var enteredEnd = endInput.text.trim()
    var minutes = Number(durationInput.text.trim())
    if (!start) {
      validationError = "Enter a valid local start as YYYY-MM-DD HH:MM."
      return
    }
    var durationSeconds = 0
    if (enteredEnd !== "") {
      var end = localDate(enteredEnd)
      durationSeconds = end ? (end.getTime() - start.getTime()) / 1000 : 0
      if (!end || !Number.isInteger(durationSeconds) || durationSeconds < 1
          || durationSeconds > 86400 || end.getTime() > Date.now()) {
        validationError = "Enter an end after the start, within 24 hours and before now."
        return
      }
    } else {
      if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1440) {
        validationError = "Enter a duration from 1 to 1440 minutes."
        return
      }
      durationSeconds = minutes * 60
    }
    if (start.getTime() + durationSeconds * 1000 > Date.now()) {
      validationError = "This time extends into the future."
      return
    }
    service.submit("sessions.add_manual", {
      activity_id: service.selectedActivityId,
      started_at: start.toISOString(),
      active_seconds: durationSeconds,
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
        endInput.text = ""
      } else if (code === "overlap") {
        root.validationError = "This overlaps saved time. Enable Allow overlap to add it deliberately."
      }
    }
  }

  ActionText {
    text: root.expanded ? "Cancel missed time" : "+ Add missed time"
    font.weight: Font.DemiBold
    onActivated: root.expanded = !root.expanded
  }

  Text {
    visible: root.expanded
    text: "Local start · YYYY-MM-DD HH:MM"
    color: Commons.Color.foreground
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: root.expanded
    text: "Use minutes, or enter a local end to calculate duration."
    color: Commons.Color.foreground
    opacity: 0.65
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
      Accessible.name: "Local start date and time"
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
        Accessible.name: "Duration in minutes"
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

  Text {
    visible: root.expanded
    text: "Optional local end · YYYY-MM-DD HH:MM"
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
      id: endInput
      anchors.fill: parent
      anchors.margins: Style.space(9)
      verticalAlignment: TextInput.AlignVCenter
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: 16
      Accessible.name: "Optional local end date and time"
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
      Accessible.name: "Optional note"
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

  ActionText {
    visible: root.expanded
    text: root.allowOverlap ? "☑ Allow overlap" : "☐ Allow overlap"
    color: Commons.Color.foreground
    onActivated: root.allowOverlap = !root.allowOverlap
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

  ActionText {
    visible: root.expanded
    text: "Save missed time"
    font.weight: Font.DemiBold
    enabled: root.service !== null && !root.service.busy
    onActivated: root.submit()
  }
}
