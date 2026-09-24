import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model

BorderSurface {
  id: root

  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string glyph: ""
  property int urgency: 1
  property double timestamp: 0
  property double nowMs: Date.now()

  signal closeRequested()
  signal activated()

  readonly property bool hovered: hoverTracker.hovered
  readonly property bool critical: urgency === 2
  readonly property string timeLabel: Model.relativeTime(timestamp, nowMs)
  readonly property int cardPad: Style.space(10)
  // Top-right slot shared by time label (default) and close button (hover).
  readonly property int closeReserve: Style.space(86)

  readonly property string smallIconSource: image.length > 0 ? Model.iconSource(image) : Model.iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool hasIcon: smallIconSource.length > 0
  readonly property color textDim: Qt.darker(Color.notifications.text, 1.35)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.12)
  readonly property color accent: critical ? Color.urgent : Color.notifications.countdown

  // Lift cards off the popup with a faint foreground wash (same recipe as
  // GalleryPanel chips) — popups/notifications bg matches the card backdrop.
  readonly property color cardFill: hovered
    ? Style.hoverFillFor(Color.notifications.text, Color.notifications.countdown)
    : Util.alpha(Color.notifications.text, 0.04)
  readonly property var cardBorderSpec: hovered
    ? Border.controlSpec("hover-cursor", Color.notifications.text, Color.notifications.countdown)
    : Border.flat(Util.alpha(Color.notifications.text, 0.12), Math.max(1, Style.space(1)))

  implicitWidth: ListView.view ? ListView.view.width : Style.space(380)
  // RowLayout carries the padding (stock NotificationCard pattern); the
  // ColumnLayout only adds the border insets.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: Style.cornerRadius
  color: cardFill
  borderSpec: cardBorderSpec
  clip: true

  Behavior on color { ColorAnimation { duration: 100 } }

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  ColumnLayout {
    id: mainColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: root.cardPad
      Layout.rightMargin: root.cardPad + root.closeReserve
      Layout.topMargin: root.cardPad
      Layout.bottomMargin: root.cardPad
      spacing: Style.space(8)

      Item {
        Layout.preferredWidth: visible ? Style.space(26) : 0
        Layout.preferredHeight: visible ? Style.space(26) : 0
        Layout.alignment: Qt.AlignTop
        visible: root.hasGlyph || (root.hasIcon && iconImage.status !== Image.Error)

        Image {
          id: iconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: Style.space(26)
          sourceSize.height: Style.space(26)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: root.hasGlyph && iconImage.status !== Image.Ready
          text: root.glyph
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          color: root.critical ? Color.urgent : Color.notifications.text
          font.family: "Liberation Sans"
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.StyledText
          Layout.fillWidth: true
          visible: String(root.body || "").length > 0
          text: root.body
          color: root.bodyColor
          font.family: "Liberation Sans"
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 5
          elide: Text.ElideRight
          opacity: 0.95
        }
      }
    }

  }

  // Top-right slot: time by default, close button on card hover (smooth crossfade).
  Item {
    id: cornerSlot
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(8)
    anchors.topMargin: Style.space(8)
    width: root.closeReserve
    height: Style.space(22)
    z: 1

    Text {
      id: timeText
      anchors.fill: parent
      textFormat: Text.PlainText
      visible: root.timeLabel.length > 0
      horizontalAlignment: Text.AlignRight
      verticalAlignment: Text.AlignVCenter
      text: root.timeLabel
      color: root.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      opacity: root.hovered ? 0 : 0.85
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }
    }

    Rectangle {
      id: closeButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: Style.space(22)
      radius: width / 2
      readonly property bool closeHovered: closeMouse.containsMouse
      color: closeHovered
        ? Style.hoverFillFor(Color.notifications.text, Color.urgent)
        : Util.alpha(Color.notifications.text, 0.08)
      border.width: Math.max(1, Style.space(1))
      border.color: closeHovered
        ? Util.alpha(Color.urgent, 0.5)
        : Util.alpha(Color.notifications.text, 0.22)
      opacity: root.hovered ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }

      Text {
        anchors.centerIn: parent
        text: "✕"
        color: closeButton.closeHovered ? Color.urgent : Qt.darker(Color.notifications.text, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.hovered
        cursorShape: Qt.PointingHandCursor
        onClicked: root.closeRequested()
      }
    }
  }
}
