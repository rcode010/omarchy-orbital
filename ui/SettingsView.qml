import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property var draft: ({})
  property string validationError: ""

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  function fill() {
    if (!service) return
    draft = Object.assign({}, service.settings)
    validationError = ""
  }

  function save() {
    var limits = {
      focus_minutes: [1, 240], short_break_minutes: [1, 120],
      long_break_minutes: [1, 120], long_break_every: [2, 12]
    }
    var changes = {}
    for (var key in limits) {
      var value = Number(draft[key])
      if (!Number.isInteger(value) || value < limits[key][0] || value > limits[key][1]) {
        validationError = "Check the duration and cycle ranges."
        return
      }
      changes[key] = value
    }
    changes.auto_start_break = draft.auto_start_break === true
    changes.auto_start_focus = draft.auto_start_focus === true
    service.submit("settings.update", { settings: changes })
  }

  onServiceChanged: fill()

  Connections {
    target: root.service
    function onSettingsChanged() { root.fill() }
  }

  Text {
    text: "Timer settings"
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.weight: Font.DemiBold
  }

  Text {
    width: root.width
    wrapMode: Text.WordWrap
    text: "Changes apply to the next focus or break, not the current countdown."
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: [
      { key: "focus_minutes", label: "Focus minutes", min: 1, max: 240 },
      { key: "short_break_minutes", label: "Short break minutes", min: 1, max: 120 },
      { key: "long_break_minutes", label: "Long break minutes", min: 1, max: 120 },
      { key: "long_break_every", label: "Long break every", min: 2, max: 12 }
    ]

    Row {
      required property var modelData
      width: root.width
      spacing: Style.space(8)

      Text {
        width: parent.width - Style.space(70)
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        width: Style.space(62)
        height: Style.space(36)
        radius: Style.space(7)
        color: "transparent"
        border.color: Commons.Color.foreground
        border.width: 1

        TextInput {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          verticalAlignment: TextInput.AlignVCenter
          text: root.draft[modelData.key] === undefined ? "" : String(root.draft[modelData.key])
          validator: IntValidator { bottom: modelData.min; top: modelData.max }
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          onTextChanged: root.draft[modelData.key] = text
        }
      }
    }
  }

  Repeater {
    model: [
      { key: "auto_start_break", label: "Start breaks automatically" },
      { key: "auto_start_focus", label: "Start next focus automatically" }
    ]

    Text {
      required property var modelData
      text: (root.draft[modelData.key] ? "☑  " : "☐  ") + modelData.label
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var values = Object.assign({}, root.draft)
          values[modelData.key] = !values[modelData.key]
          root.draft = values
        }
      }
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

  Text {
    text: "Save settings"
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold

    MouseArea {
      anchors.fill: parent
      enabled: root.service && !root.service.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: root.save()
    }
  }
}
