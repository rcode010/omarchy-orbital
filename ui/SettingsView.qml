import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property var draft: ({})
  property string validationError: ""
  property string confirmingRestoreName: ""

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
      long_break_minutes: [1, 120], long_break_every: [2, 12],
      idle_minutes: [1, 30]
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
    changes.notifications = draft.notifications === true
    changes.pause_on_idle = draft.pause_on_idle === true
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
      { key: "long_break_every", label: "Long break every", min: 2, max: 12 },
      { key: "idle_minutes", label: "Pause after idle minutes", min: 1, max: 30 }
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
          Accessible.name: modelData.label
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
      { key: "auto_start_focus", label: "Start next focus automatically" },
      { key: "notifications", label: "Completion notifications" },
      { key: "pause_on_idle", label: "Pause when idle" }
    ]

    ActionText {
      required property var modelData
      text: (root.draft[modelData.key] ? "☑  " : "☐  ") + modelData.label
      color: Commons.Color.foreground
      onActivated: {
        var values = Object.assign({}, root.draft)
        values[modelData.key] = !values[modelData.key]
        root.draft = values
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

  ActionText {
    text: "Save settings"
    font.weight: Font.DemiBold
    enabled: root.service && !root.service.busy
    onActivated: root.save()
  }

  Text {
    text: "YOUR DATA"
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  Text {
    width: root.width
    wrapMode: Text.WordWrap
    text: "Backups stay on this computer. Restoring replaces current data and first saves a copy of it. Finish the timer before restoring."
    color: Commons.Color.foreground
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Row {
    spacing: Style.space(16)

    Repeater {
      model: ["Create backup", "Export JSON"]

      ActionText {
        required property string modelData
        text: modelData
        font.weight: Font.DemiBold
        enabled: root.service && !root.service.busy
        onActivated: root.service.submit(modelData === "Create backup"
          ? "backup.create" : "backup.export_json", {})
      }
    }
  }

  Text {
    visible: root.service && root.service.backupMessage !== ""
    width: root.width
    wrapMode: Text.WordWrap
    text: root.service ? root.service.backupMessage : ""
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    text: "RESTORABLE BACKUPS"
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  Text {
    visible: root.service && root.service.backups.length === 0
    text: "No backups created yet."
    color: Commons.Color.foreground
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  ListView {
    width: root.width
    height: Math.min(Style.space(176), count * Style.space(44))
    clip: true
    spacing: Style.space(4)
    model: root.service ? root.service.backups : []

    delegate: Row {
      required property var modelData
      width: ListView.view.width
      height: Style.space(40)
      spacing: Style.space(10)

      Text {
        width: parent.width - restoreText.width - parent.spacing
        text: modelData.name
        elide: Text.ElideMiddle
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      ActionText {
        id: restoreText
        text: root.confirmingRestoreName === modelData.name ? "Confirm restore" : "Restore"
        enabled: root.service && !root.service.busy && root.service.phase === "idle"
        onActivated: {
          if (root.confirmingRestoreName === modelData.name) {
            root.service.submit("backup.restore", { name: modelData.name })
            root.confirmingRestoreName = ""
          } else {
            root.confirmingRestoreName = modelData.name
          }
        }
      }
    }
  }
}
