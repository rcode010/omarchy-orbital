import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var service: null
  property var activity: null
  property string chosenColor: "blue"
  property bool confirmDelete: false
  signal done()

  readonly property var palette: [
    { name: "blue", value: "#5b9cff" },
    { name: "cyan", value: "#45c7d9" },
    { name: "green", value: "#6ac889" },
    { name: "amber", value: "#e6bc5c" },
    { name: "orange", value: "#ed9863" },
    { name: "purple", value: "#ad8df0" },
    { name: "pink", value: "#e68fba" },
    { name: "red", value: "#e77b78" }
  ]

  visible: activity !== null
  width: parent ? parent.width : 0
  spacing: Style.space(9)

  onActivityChanged: {
    if (!activity) return
    nameInput.text = activity.name
    iconInput.text = activity.icon
    chosenColor = activity.color
    confirmDelete = false
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
      }
    }
  }

  Row {
    spacing: Style.space(8)

    Repeater {
      model: root.palette

      Rectangle {
        required property var modelData
        width: Style.space(23)
        height: width
        radius: width / 2
        color: modelData.value
        border.color: Commons.Color.foreground
        border.width: root.chosenColor === modelData.name ? 2 : 0

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.chosenColor = modelData.name
        }
      }
    }
  }

  Row {
    spacing: Style.space(14)

    Repeater {
      model: ["Save", root.activity && root.activity.archived_at ? "Restore" : "Archive",
              root.confirmDelete ? "Confirm delete" : "Delete", "Cancel"]

      Text {
        required property string modelData
        text: modelData
        color: modelData === "Save" ? Commons.Color.accent : Commons.Color.foreground
        opacity: modelData === "Delete" ? 0.65 : 1
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          enabled: root.service && !root.service.busy
          onClicked: {
            if (modelData === "Save") {
              root.service.submit("activities.update", {
                activity_id: root.activity.id,
                name: nameInput.text.trim(), icon: iconInput.text.trim(), color: root.chosenColor
              })
              root.done()
            } else if (modelData === "Archive" || modelData === "Restore") {
              root.service.submit(modelData === "Archive" ? "activities.archive" : "activities.restore",
                                  { activity_id: root.activity.id })
              root.done()
            } else if (modelData === "Delete") {
              root.confirmDelete = true
            } else if (modelData === "Confirm delete") {
              root.service.submit("activities.delete", { activity_id: root.activity.id })
              root.done()
            } else {
              root.done()
            }
          }
        }
      }
    }
  }
}
