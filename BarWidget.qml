import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget + notification center popup (single entry point).
// The bell anchors a KeyboardPanel below the bar; popup content lives in
// ControlCenter.qml. Pattern mirrors omarchy.power / bakhadir.agents.
Panel {
  id: root
  moduleName: "system.controlcenter"
  ipcTarget: "controlcenter"
  manageIpc: false

  readonly property string stateDir: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/notifications/"
  readonly property string historyDir: stateDir + "history/"
  property int count: 0
  readonly property bool hasUnread: count > 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!countProc.running) countProc.running = true
  }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) content.activated()
    else content.clearConfirmOpen = false
    refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(); content.refresh() }
    function count(): string { return String(root.count) }
  }

  Process {
    id: countProc
    // Live toasts + archived history, deduped by file name (same
    // <timestamp>-<id>.json naming in both dirs; [0-9] skips settings).
    command: ["bash", "-c",
      "live=\"$1\" hist=\"$2\" n=0 seen=\"\"\n" +
      "for f in \"$live\"[0-9]*.json \"$hist\"[0-9]*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  b=\"${f##*/}\"\n" +
      "  [[ $seen == *\"|$b|\"* ]] && continue\n" +
      "  seen+=\"|$b|\"\n" +
      "  n=$((n+1))\n" +
      "done\n" +
      "printf '%s\\n' \"$n\"", "--", root.stateDir, root.historyDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text).trim(), 10)
        root.count = isFinite(n) && n > 0 ? n : 0
      }
    }
  }

  // Badge stays fresh: new toasts archive on their own while the bar is up.
  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font bell — same family the stock indicators use.
    text: "󰂚"
    active: root.hasUnread
    activeColor: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: root.hasUnread
      ? (root.count + " уведомлени" + (root.count === 1 ? "е" : (root.count < 5 ? "я" : "й")))
      : "Центр уведомлений"

    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        if (!root.bar) return
        root.bar.run("omarchy-shell -q notifications clear")
        clearDebounce.restart()
      } else if (btn === Qt.MiddleButton) {
        content.toggleDnd()
      } else {
        root.toggle()
      }
    }
  }

  Timer {
    id: clearDebounce
    interval: 200
    onTriggered: {
      root.refresh()
      content.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: content.keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    ControlCenter {
      id: content
      anchors.fill: parent
      opened: root.opened
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }
  }

  // Badge pill in the top-right corner of the slot.
  Rectangle {
    visible: root.hasUnread
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Math.max(0, (Style.bar.iconSlot - Style.bar.iconCanvas) / 2 - Style.space(4))
    anchors.topMargin: Math.max(0, (Style.bar.iconSlot - Style.bar.iconCanvas) / 2 - Style.space(5))
    width: Math.max(Style.space(14), badgeText.implicitWidth + Style.space(8))
    height: Style.space(14)
    radius: height / 2
    color: root.bar && root.bar.urgent ? root.bar.urgent : Color.urgent
    border.width: Math.max(1, Style.space(1))
    border.color: root.bar ? root.bar.background : Color.background

    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.count > 99 ? "99+" : String(root.count)
      color: "#ffffff"
      font.family: Style.font.family
      font.pixelSize: Math.max(8, Style.font.caption - 1)
      font.bold: true
    }
  }
}
