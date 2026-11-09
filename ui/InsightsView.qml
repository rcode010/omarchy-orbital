import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ActivityColors.js" as ActivityColors

Column {
  id: root
  signal openSelectedHistory()
  property var service: null
  property int hoveredIndex: -1
  property bool showValues: false
  readonly property var report: service ? service.insightsReport : null
  readonly property real peakMs: {
    if (!report) return 0
    var peak = 0
    for (var i = 0; i < report.trend.length; i++)
      peak = Math.max(peak, report.trend[i].active_ms)
    return peak
  }

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  function changePeriod(period) {
    if (!service) return
    service.insightsPeriod = period
    service.insightsAnchor = ""
    service.loadInsights()
    hoveredIndex = -1
  }

  function movePeriod(direction) {
    if (!service || !report) return
    if (service.insightsPeriod === "today") service.insightsPeriod = "day"
    service.insightsAnchor = direction < 0 ? report.previous_anchor : report.next_anchor
    service.loadInsights()
    hoveredIndex = -1
  }

  Text {
    text: "Insights"
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.weight: Font.DemiBold
  }

  Row {
    spacing: Style.space(12)

    Repeater {
      model: ["today", "day", "week", "month", "year"]

      ActionText {
        required property string modelData
        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
        opacity: root.service && root.service.insightsPeriod === modelData ? 1 : 0.55
        font.weight: root.service && root.service.insightsPeriod === modelData ? Font.DemiBold : Font.Normal
        onActivated: root.changePeriod(modelData)
      }
    }
  }

  Row {
    width: root.width
    spacing: Style.space(12)

    ActionText {
      text: "‹"
      font.pixelSize: Style.font.title
      onActivated: root.movePeriod(-1)
    }

    Text {
      width: parent.width - Style.space(54)
      horizontalAlignment: Text.AlignHCenter
      text: root.report
        ? (root.report.start_day === root.report.end_day_inclusive
           ? root.report.start_day
           : root.report.start_day + " – " + root.report.end_day_inclusive)
        : "Loading period…"
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    ActionText {
      text: "›"
      font.pixelSize: Style.font.title
      onActivated: root.movePeriod(1)
    }
  }

  Text {
    text: root.report && root.service ? root.service.formatDuration(root.report.total_ms) : "0s"
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.space(38)
    font.weight: Font.DemiBold
  }

  Text {
    text: root.report ? root.report.session_count + " saved sessions" : ""
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Column {
    visible: root.report && root.report.selected_lifetime !== null
    width: root.width
    spacing: Style.space(4)

    Text {
      text: root.report && root.report.selected_lifetime
        ? "SELECTED ACTIVITY · ALL TIME" : ""
      color: Commons.Color.foreground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.5
    }

    Text {
      width: parent.width
      text: root.report && root.report.selected_lifetime
        ? (root.report.selected_lifetime.icon ? root.report.selected_lifetime.icon + "  " : "")
          + root.report.selected_lifetime.name + " · "
          + root.service.formatDuration(root.report.selected_lifetime.total_ms) : ""
      elide: Text.ElideRight
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }

    ActionText {
      text: "View selected history"
      enabled: root.service && !root.service.busy
      onActivated: root.openSelectedHistory()
    }
  }

  Text {
    visible: root.report && root.report.total_ms === 0
    text: "No time recorded in this period."
    color: Commons.Color.foreground
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Item {
    id: chart
    visible: root.report && root.report.total_ms > 0
    width: root.width
    height: Style.space(118)

    Row {
      anchors.fill: parent
      spacing: Style.space(2)

      Repeater {
        model: root.report ? root.report.trend : []

        Item {
          required property var modelData
          required property int index
          width: (chart.width - (root.report.trend.length - 1) * Style.space(2)) / root.report.trend.length
          height: chart.height
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.label + ", " + root.service.formatDuration(modelData.active_ms)
          Keys.onReturnPressed: root.hoveredIndex = index
          Keys.onSpacePressed: root.hoveredIndex = index

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: root.peakMs > 0 ? parent.height * modelData.active_ms / root.peakMs : 0
            radius: Math.min(Style.space(4), width / 2)
            color: Commons.Color.accent
            opacity: root.hoveredIndex === index || parent.activeFocus ? 1 : 0.72
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.hoveredIndex = index
            onExited: if (root.hoveredIndex === index) root.hoveredIndex = -1
            onClicked: {
              parent.forceActiveFocus()
              root.hoveredIndex = index
            }
          }
        }
      }
    }
  }

  Text {
    visible: root.report && root.report.total_ms > 0
    text: root.report && root.report.trend.length
      ? (root.hoveredIndex >= 0
         ? root.report.trend[root.hoveredIndex].label + " · "
           + root.service.formatDuration(root.report.trend[root.hoveredIndex].active_ms)
         : "Hover a bar to inspect its time") : ""
    color: Commons.Color.foreground
    opacity: 0.72
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  ActionText {
    visible: root.report && root.report.total_ms > 0
    text: root.showValues ? "Hide chart values" : "Show chart values"
    onActivated: root.showValues = !root.showValues
  }

  Repeater {
    model: root.showValues && root.report ? root.report.trend : []

    Text {
      required property var modelData
      text: modelData.label + "  " + root.service.formatDuration(modelData.active_ms)
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    visible: root.report && root.report.activities.length > 0
    text: "BY ACTIVITY"
    color: Commons.Color.foreground
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  ListView {
    width: root.width
    height: Math.min(contentHeight, Style.space(250))
    clip: true
    spacing: Style.space(8)
    boundsBehavior: Flickable.StopAtBounds
    model: root.report ? root.report.activities : []

    delegate: Column {
      required property var modelData
      width: root.width
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7)
          height: width
          radius: width / 2
          color: ActivityColors.value(modelData.color)
        }

        Text {
          width: parent.width * 0.7 - Style.space(13)
          text: (modelData.icon ? modelData.icon + "  " : "") + modelData.name
          elide: Text.ElideRight
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          text: root.service.formatDuration(modelData.active_ms)
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Item {
        width: parent.width
        height: Style.space(4)

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Commons.Color.foreground
          opacity: 0.12
        }

        Rectangle {
          width: root.report.total_ms > 0 ? parent.width * modelData.active_ms / root.report.total_ms : 0
          height: parent.height
          radius: height / 2
          color: ActivityColors.value(modelData.color)
        }
      }
    }
  }
}
