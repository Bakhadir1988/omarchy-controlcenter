# Control Center — notification center bar widget for Omarchy

macOS-style notification center popup for the Omarchy shell (Quickshell):
history list, DND toggle, clear — styled with Omarchy theme tokens.

## Features

- Bell icon in the bar with unread badge (`99+` cap)
- Popup: `Уведомления` header with count + `Очистить` (with confirm dialog)
- `Не беспокоить` toggle (`DND`, shortcuts: `D`, `Ctrl+N`)
- Flat notification list (no app-group headers), newest first
- Card: icon, title, body, time label top-right by default (`только что`, `N мин назад`, …)
- Hover a card: time crossfades into the close button (`✕`, 160ms)
- No visible scrollbar (wheel/touch scroll still works)
- Keyboard: `Esc` close, `Tab`/`Shift+Tab` switch panel, `j`/`k` or arrows scroll, `c` clear
- Mouse: left-click bell toggles, right-click clears history, middle-click toggles DND; click a notification tries to focus the sender app

## Layout / files

- `BarWidget.qml` — bar entry point (`barWidget`), badge, `KeyboardPanel` host
- `ControlCenter.qml` — popup content (header, DND row, flat `ListView`)
- `components/NotificationRow.qml` — card with time/close hover crossfade
- `Model.js` — history parsing (`<timestamp>-<id>.json`), grouping/ordering helpers, relative time, icon resolution

## Install

```bash
omarchy plugin add <git-url> --enable
omarchy restart shell
```

## Validate

```bash
omarchy plugin validate ~/.config/omarchy/plugins/bakhadir.controlcenter
```

## Requirements

- Omarchy shell (Quickshell) with `qs.Commons` / `qs.Ui` theme tokens
- Notification history under `~/.local/state/omarchy/notifications/` (live + `history/`), written by `omarchy-shell notifications`

## License

MIT — see `LICENSE`.
