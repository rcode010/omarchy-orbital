import QtQuick

QtObject {
  id: root

  property string phase: "idle"
  property string activityName: ""
  property int elapsedSeconds: 0

  readonly property string barLabel: phase === "idle"
    ? "Orbital · Ready"
    : activityName + " · " + Math.floor(elapsedSeconds / 60) + "m"
}
