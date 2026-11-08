import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ActivityColors.js" as ActivityColors

Row {
  id: root
  property string selectedColor: "blue"

  spacing: Style.space(8)

  Repeater {
    model: ActivityColors.palette

    Rectangle {
      id: swatch
      required property var modelData
      width: Style.space(23)
      height: width
      radius: width / 2
      color: modelData.value
      border.color: Commons.Color.foreground
      border.width: activeFocus || root.selectedColor === modelData.name ? 2 : 0
      activeFocusOnTab: true
      Accessible.role: Accessible.RadioButton
      Accessible.name: modelData.name + (root.selectedColor === modelData.name ? ", selected" : "")
      Accessible.checked: root.selectedColor === modelData.name
      Keys.onReturnPressed: function(event) {
        root.selectedColor = swatch.modelData.name
        event.accepted = true
      }
      Keys.onSpacePressed: function(event) {
        root.selectedColor = swatch.modelData.name
        event.accepted = true
      }

      Text {
        anchors.centerIn: parent
        visible: root.selectedColor === parent.modelData.name
        text: "✓"
        color: Commons.Color.background
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          swatch.forceActiveFocus()
          root.selectedColor = swatch.modelData.name
        }
      }
    }
  }

  Text {
    text: root.selectedColor.charAt(0).toUpperCase() + root.selectedColor.slice(1)
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
