import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.rcode010.omarchy-orbital"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground

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

        Text {
          text: "Your activities"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.service && root.service.activities.length
            ? "Choose the activity you want to track."
            : "Create an activity to begin your Orbital history."
          color: root.foreground
          opacity: 0.72
          font.family: Style.font.family
          font.pixelSize: Style.font.body
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

        Repeater {
          model: root.service ? root.service.activities : []

          Rectangle {
            required property var modelData
            width: content.width
            height: Style.space(42)
            radius: Style.space(9)
            color: modelData.id === root.service.selectedActivityId
              ? Commons.Color.accent : "transparent"
            border.color: root.foreground
            border.width: modelData.id === root.service.selectedActivityId ? 0 : 1

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              verticalAlignment: Text.AlignVCenter
              text: modelData.icon ? modelData.icon + "  " + modelData.name : modelData.name
              elide: Text.ElideRight
              color: modelData.id === root.service.selectedActivityId
                ? Commons.Color.background : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.service.submit("activities.select", { activity_id: modelData.id })
            }
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
      }
      }
    }
  }
}
