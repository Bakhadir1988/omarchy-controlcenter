// Notification center popup content for the bar-anchored KeyboardPanel.
// History grouped by app (macOS style). No window/scrim/positioning here —
// the host BarWidget provides the KeyboardPanel scaffolding.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Item {
  id: root

  property bool opened: false
  property var history: []
  property var appMeta: ({})
  property var expandedGroups: ({})
  property int perPage: 2
  property bool dnd: false
  property bool clearConfirmOpen: false
  property double nowMs: Date.now()
  property bool refreshing: false
  property string lastRaw: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/notifications/"
  readonly property string historyDir: stateDir + "history/"
  readonly property string imagesDir: stateDir + "images/"
  readonly property string settingsPath: home + "/.local/state/omarchy/notifications.json"

  property color foreground: Color.notifications.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int listPad: Style.space(6)
  property int listTopPad: Style.space(12)
  property int listBottomPad: Style.space(12)
  property int maxListHeight: Style.space(420)
  property int emptyHeight: Style.space(170)
  readonly property int historyCount: history.length

  signal closeRequested()
  signal tabRequested(int direction)

  property alias keyCatcher: keyCatcher
  property alias listView: resultList

  implicitHeight: mainColumn.implicitHeight

  // Called by the host when the panel opens.
  function activated() {
    root.clearConfirmOpen = false
    root.nowMs = Date.now()
    root.refresh()
  }

  function refresh() {
    if (!readHistoryProc.running) readHistoryProc.running = true
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, resultList.contentHeight - resultList.height)
    resultList.contentY = Math.max(0, Math.min(maxY, resultList.contentY + dy))
  }

  function applyHistory(raw) {
    var text = String(raw || "")
    // Polling refresh must not rebuild the model (and reset the scroll
    // position) when nothing changed on disk.
    if (text === root.lastRaw) {
      root.refreshing = false
      return
    }
    root.lastRaw = text
    root.history = Model.parseLines(text)
    root.nowMs = Date.now()
    root.refreshing = false
  }

  function toggleGroup(key) {
    var next = {}
    for (var k in root.expandedGroups) next[k] = root.expandedGroups[k]
    next[key] = !next[key]
    root.expandedGroups = next
    root.rebuildModel()
  }

  function removeEntry(entry) {
    if (!entry) return
    var name = entry.fileName || Model.popupFileName(entry)
    if (!name) return
    root.lastRaw = ""
    root.history = root.history.filter(function(e) {
      return (e.fileName || Model.popupFileName(e)) !== name
    })
    removeProc.command = ["bash", "-c",
      "live=\"$1\" hist=\"$2\" imgs=\"$3\" name=\"$4\"\n" +
      "stem=\"${name%.json}\"\n" +
      // Live toasts too: the file is gone, so a later expire/dismiss finds
      // nothing to archive and the entry stays removed.
      "rm -f -- \"$live/$name\" \"$hist/$name\" \"$imgs/${stem}\"-* 2>/dev/null\n" +
      "exit 0", "--", root.stateDir, root.historyDir, root.imagesDir, name]
    removeProc.running = true
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
  }

  function confirmClearHistory() {
    root.clearConfirmOpen = false
    root.lastRaw = ""
    root.history = []
    clearProc.running = true
  }

  function setDnd(next) {
    var on = !!next
    root.dnd = on
    dndProc.command = ["omarchy-shell", "notifications", "setDnd", on ? "true" : "false"]
    dndProc.running = true
  }

  function toggleDnd() {
    setDnd(!root.dnd)
  }

  function activateEntry(entry) {
    if (!entry) return
    var argv = entry.execArgv
    if (argv && String(argv).length > 0) {
      root.closeRequested()
      try {
        var parsed = typeof argv === "string" ? JSON.parse(argv) : argv
        if (Array.isArray(parsed) && parsed.length > 0) {
          Quickshell.execDetached(parsed.map(String))
          return
        }
      } catch (e) {
      }
      Quickshell.execDetached(["bash", "-lc", String(argv)])
      return
    }
    // No attached action — focus the sender's window, like macOS does.
    // Ephemeral senders (notify-send, omarchy-action) own no window.
    var app = String(entry.app || "")
    var icon = String(entry.appIcon || "")
    if (app === "" || app === "notify-send" || app === "omarchy-action") return
    var cands = []
    if (app.length > 0) cands.push(app)
    var shortIcon = icon.indexOf(".") >= 0 ? icon.substring(icon.lastIndexOf(".") + 1) : icon
    if (shortIcon.length > 0 && cands.indexOf(shortIcon) === -1) cands.push(shortIcon)
    if (icon.length > 0 && cands.indexOf(icon) === -1) cands.push(icon)
    if (cands.length === 0) return
    // Resolve the sender's window by class (case-insensitive) and focus it
    // by address — deterministic, no regex-flag gamble. Succeeds only when
    // a window actually matched, so the panel closes solely on success.
    focusProc.command = ["bash", "-c",
      "addr=$(hyprctl clients -j 2>/dev/null | python3 -c '\n" +
      "import json, sys\n" +
      "want = set(a.lower() for a in sys.argv[1:])\n" +
      "try:\n" +
      "    clients = json.load(sys.stdin)\n" +
      "except Exception:\n" +
      "    sys.exit(1)\n" +
      "for c in clients:\n" +
      "    if str(c.get(\"class\", \"\")).lower() in want:\n" +
      "        sys.stdout.write(str(c.get(\"address\", \"\")))\n" +
      "        break\n" +
      "' \"$@\") || exit 1\n" +
      "[[ -n $addr ]] || exit 1\n" +
      "hyprctl dispatch focuswindow \"address:$addr\" 2>&1 | grep -qi '^ok'",
      "--"].concat(cands)
    focusProc.running = true
  }

  Component.onCompleted: {
    settingsFile.reload()
  }

  ListModel { id: historyModel }

  function rebuildModel() {
    var savedY = resultList.contentY
    var grouped = Model.groupByApp(root.history)
    root.appMeta = grouped.meta
    historyModel.clear()
    for (var g = 0; g < grouped.groups.length; g++) {
      var key = grouped.groups[g].key
      var items = grouped.groups[g].items
      var expanded = !!root.expandedGroups[key]
      var visCount = expanded ? items.length : Math.min(items.length, root.perPage)
      for (var i = 0; i < visCount; i++) {
        var e = items[i]
        historyModel.append({
          entryType: "notification",
          sectionKey: Model.groupKey(e),
          remaining: 0,
          app: String(e.app || ""),
          appIcon: String(e.appIcon || ""),
          summary: String(e.summary || ""),
          body: String(e.body || ""),
          image: String(e.image || ""),
          glyph: String(e.glyph || ""),
          urgency: Number(e.urgency === undefined ? 1 : e.urgency),
          timestamp: Number(e.timestamp || 0),
          fileName: e.fileName || Model.popupFileName(e),
          execArgv: String(e.execArgv || "")
        })
      }
      // macOS-style collapsed stack: an expander row instead of the rest.
      if (!expanded && items.length > visCount) {
        historyModel.append({
          entryType: "more",
          sectionKey: key,
          remaining: items.length - visCount,
          app: "", appIcon: "", summary: "", body: "",
          image: "", glyph: "", urgency: 1, timestamp: 0,
          fileName: "", execArgv: ""
        })
      } else if (expanded && items.length > root.perPage) {
        historyModel.append({
          entryType: "less",
          sectionKey: key,
          remaining: 0,
          app: "", appIcon: "", summary: "", body: "",
          image: "", glyph: "", urgency: 1, timestamp: 0,
          fileName: "", execArgv: ""
        })
      }
    }
    // Rebuilding resets the view to the top — restore the scroll position
    // (expanding a group, new toasts, deletions must not yank the list).
    Qt.callLater(function() {
      var maxY = Math.max(0, resultList.contentHeight - resultList.height)
      resultList.contentY = Math.max(0, Math.min(maxY, savedY))
    })
  }

  onHistoryChanged: rebuildModel()

  // DND flag on disk — written by the notification service after every toggle.
  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.dnd = !!parsed.dnd
      } catch (e) {
      }
    }
    onLoadFailed: root.dnd = false
    onFileChanged: reload()
  }

  Process {
    id: readHistoryProc
    // Live toasts (*.json directly in stateDir) AND archived history.
    // Live files use the same <timestamp>-<id>.json names; the [0-9] glob
    // skips notifications.json (DND settings). Live dir first so live rows
    // win the fileName dedupe in parseLines. NOTE: unmatched globs must be
    // skipped per-file — a literal (unexpanded) path makes awk abort before
    // reaching the remaining files.
    command: ["bash", "-c",
      "live=\"$1\" hist=\"$2\"\n" +
      "for f in \"$live\"[0-9]*.json \"$hist\"[0-9]*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  cat -- \"$f\"\n" +
      "  printf '\\n'\n" +
      "done\n" +
      "exit 0",
      "--", root.stateDir, root.historyDir]
    onStarted: root.refreshing = true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHistory(text)
    }
    onExited: root.refreshing = false
  }

  Process {
    id: removeProc
    onExited: refreshDebounce.restart()
  }

  Process {
    id: clearProc
    // Service `clear` only forgets archived history; live toasts stay on
    // screen. The panel must still end up empty, so drop the live files as
    // well — their later expire/dismiss finds nothing to archive.
    command: ["bash", "-c",
      "omarchy-shell -q notifications clear\n" +
      "live=\"$1\" imgs=\"$2\"\n" +
      "for f in \"$live\"[0-9]*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  b=\"${f##*/}\"\n" +
      "  rm -f -- \"$f\" \"$imgs/${b%.json}\"-*\n" +
      "done\n" +
      "exit 0", "--", root.stateDir, root.imagesDir]
    onExited: refreshDebounce.restart()
  }

  Process {
    id: dndProc
    onExited: {
      settingsFile.reload()
      refreshDebounce.restart()
    }
  }

  // Window-focus attempt for notification clicks; close the panel only when
  // a window actually matched.
  Process {
    id: focusProc
    onExited: function(exitCode) {
      if (exitCode === 0) root.closeRequested()
    }
  }

  Timer {
    id: refreshDebounce
    interval: 80
    onTriggered: root.refresh()
  }

  // Keep the list fresh while the panel is open (new toasts landing, etc).
  Timer {
    id: refreshTimer
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  // Relative-time labels tick while open.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (root.clearConfirmOpen) {
        if (clearConfirm.handleKey(event)) event.accepted = true
        return
      }
      if (event.key === Qt.Key_Escape) {
        root.closeRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
        root.toggleDnd()
        event.accepted = true
      } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        root.tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Down || event.text === "j") {
        root.scrollBy(Style.space(120))
        event.accepted = true
      } else if (event.key === Qt.Key_Up || event.text === "k") {
        root.scrollBy(-Style.space(120))
        event.accepted = true
      } else if (event.text === "d" || event.text === "D") {
        root.toggleDnd()
        event.accepted = true
      } else if (event.text === "c" || event.text === "C") {
        root.requestClearHistory()
        event.accepted = true
      }
    }

    ConfirmDialog {
      id: clearConfirm
      anchors.fill: parent
      opened: root.clearConfirmOpen
      z: 10
      message: "Очистить историю уведомлений?"
      confirmText: "Очистить"
      cancelText: "Отмена"
      background: Color.popups.background
      foreground: root.foreground
      scrim: Util.alpha(Color.menu.scrim, 0.7)
      selectedBackground: root.selectedBackground
      selectedText: root.selectedText
      fontFamily: root.fontFamily
      cornerRadius: Style.cornerRadius
      onCanceled: root.cancelClearHistory()
      onConfirmed: root.confirmClearHistory()
    }

    Column {
      id: mainColumn
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 0

      // ---- header --------------------------------------------------
      Item {
        id: headerItem
        width: parent.width
        height: root.headerHeight + Style.space(4)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "Уведомления"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Rectangle {
            visible: root.historyCount > 0
            Layout.alignment: Qt.AlignVCenter
            width: countText.implicitWidth + Style.space(12)
            height: countText.implicitHeight + Style.space(6)
            radius: height / 2
            color: Util.alpha(root.selectedText, 0.18)

            Text {
              id: countText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(root.historyCount)
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.historyCount > 0
            text: "Очистить"
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            opacity: clearAllMouse.containsMouse ? 1.0 : 0.85

            MouseArea {
              id: clearAllMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.requestClearHistory()
            }
          }
        }

        Rectangle {
          width: parent.width - Style.space(8)
          height: Math.max(1, Style.space(1))
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          color: Util.alpha(root.foreground, 0.12)
        }
      }

      // ---- DND row -------------------------------------------------
      Item {
        id: dndItem
        width: parent.width
        height: Style.space(52)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          spacing: Style.space(10)

          Text {
            text: root.dnd ? "󰂛" : "󰂚"
            color: root.dnd ? root.selectedText : root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            Layout.alignment: Qt.AlignVCenter
          }

          Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.space(1)

            Text {
              textFormat: Text.PlainText
              text: "Не беспокоить"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              textFormat: Text.PlainText
              text: root.dnd ? "Уведомления отключены" : "Всплывающие уведомления включены"
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          ToggleSwitch {
            Layout.alignment: Qt.AlignVCenter
            checked: root.dnd
            foreground: root.foreground
            accent: root.selectedText
            onToggled: root.toggleDnd()
          }
        }

        Rectangle {
          width: parent.width - Style.space(8)
          height: Math.max(1, Style.space(1))
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          color: Util.alpha(root.foreground, 0.1)
        }
      }

      // ---- grouped list --------------------------------------------
      Item {
        id: listHolder
        width: parent.width
        height: historyModel.count === 0
          ? root.emptyHeight
          : Math.min(resultList.contentHeight + root.listTopPad + root.listBottomPad, root.maxListHeight)
        clip: true

        ListView {
          id: resultList
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          anchors.topMargin: root.listTopPad
          anchors.bottomMargin: root.listBottomPad
          model: historyModel
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
          }

          // Group headers removed — flat list (ordering/expanders still use sectionKey).

          delegate: Item {
            width: resultList.width
            height: model.entryType === "notification"
              ? notifRow.implicitHeight : moreRow.height

            NotificationRow {
              id: notifRow
              visible: model.entryType === "notification"
              width: parent.width
              appIcon: model.appIcon
              summary: model.summary
              body: model.body
              image: model.image
              glyph: model.glyph
              urgency: model.urgency
              timestamp: model.timestamp
              nowMs: root.nowMs
              onActivated: root.activateEntry({ execArgv: model.execArgv, app: model.app, appIcon: model.appIcon })
              onCloseRequested: root.removeEntry({ fileName: model.fileName })
            }

            // Collapsed-stack expander / collapse row (macOS style).
            Item {
              id: moreRow
              visible: model.entryType !== "notification"
              width: parent.width
              height: Style.space(34)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: model.entryType === "more"
                  ? ("Показать ещё · " + model.remaining + "  ∨")
                  : "Свернуть  ∧"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                opacity: moreMouse.containsMouse ? 1.0 : 0.8
              }

              MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleGroup(model.sectionKey)
              }
            }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          visible: historyModel.count === 0

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "󰂚"
            color: root.foreground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.space(40)
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.dnd ? "Тихий режим включён" : "Нет уведомлений"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.dnd
              ? "Новые уведомления не будут показаны"
              : "Новые уведомления появятся здесь"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
