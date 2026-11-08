import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
  id: root
  signal activated()

  color: Commons.Color.accent
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  font.underline: activeFocus
  opacity: enabled ? 1 : 0.45
  activeFocusOnTab: enabled

  Keys.onReturnPressed: function(event) {
    activated()
    event.accepted = true
  }
  Keys.onEnterPressed: function(event) {
    activated()
    event.accepted = true
  }
  Keys.onSpacePressed: function(event) {
    activated()
    event.accepted = true
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.activated()
    }
  }
}
