import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property var activity: null
  property string pendingCommand: ""
  property bool confirmDelete: false
  signal done()

  visible: activity !== null
  width: parent ? parent.width : 0
  spacing: Style.space(9)

  onActivityChanged: {
    if (!activity) return
    nameInput.text = activity.name
    iconInput.text = activity.icon
    editorColorPicker.selectedColor = activity.color
    confirmDelete = false
    pendingCommand = ""
  }

  Connections {
    target: root.service
    function onRequestFinished(command, success) {
      if (command !== root.pendingCommand) return
      root.pendingCommand = ""
      if (success) root.done()
    }
  }

  Text {
    text: "EDIT ACTIVITY"
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  Row {
    width: root.width
    spacing: Style.space(8)

    Rectangle {
      width: parent.width - iconField.width - parent.spacing
      height: Style.space(40)
      radius: Style.space(8)
      color: "transparent"
      border.color: Commons.Color.foreground
      border.width: 1

      TextInput {
        id: nameInput
        anchors.fill: parent
        anchors.margins: Style.space(10)
        verticalAlignment: TextInput.AlignVCenter
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        maximumLength: 80
        Accessible.name: "Activity name"
      }
    }

    Rectangle {
      id: iconField
      width: Style.space(48)
      height: Style.space(40)
      radius: Style.space(8)
      color: "transparent"
      border.color: Commons.Color.foreground
      border.width: 1

      TextInput {
        id: iconInput
        anchors.fill: parent
        anchors.margins: Style.space(10)
        verticalAlignment: TextInput.AlignVCenter
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        maximumLength: 8
        Accessible.name: "Activity icon"
      }
    }
  }

  ColorPicker {
    id: editorColorPicker
  }

  Row {
    spacing: Style.space(14)

    Repeater {
      model: ["Save", root.activity && root.activity.archived_at ? "Restore" : "Archive",
              root.confirmDelete ? "Confirm delete" : "Delete", "Cancel"]

      ActionText {
        required property string modelData
        text: modelData
        color: modelData === "Save" ? Commons.Color.accent : Commons.Color.foreground
        opacity: modelData === "Delete" ? 0.65 : 1
        font.weight: Font.DemiBold
        enabled: root.service !== null && !root.service.busy
        onActivated: {
          if (modelData === "Save") {
            root.pendingCommand = "activities.update"
            root.service.submit("activities.update", {
              activity_id: root.activity.id,
              name: nameInput.text.trim(), icon: iconInput.text.trim(), color: editorColorPicker.selectedColor
            })
          } else if (modelData === "Archive" || modelData === "Restore") {
            root.pendingCommand = modelData === "Archive" ? "activities.archive" : "activities.restore"
            root.service.submit(root.pendingCommand, { activity_id: root.activity.id })
          } else if (modelData === "Delete") {
            root.confirmDelete = true
          } else if (modelData === "Confirm delete") {
            root.pendingCommand = "activities.delete"
            root.service.submit("activities.delete", { activity_id: root.activity.id })
          } else {
            root.done()
          }
        }
      }
    }
  }
}
