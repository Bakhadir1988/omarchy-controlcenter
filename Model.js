// History file helpers for the control-center sidebar.

function popupFileName(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || e.id || 0) + ".json"
}

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || e.id || 0)
}

// Concatenated one-line JSON files → sorted newest-first entries.
// Deduplicates by file name (live popup files and their archived copies
// share the same name; the first occurrence wins so list live dir first).
function parseLines(raw) {
  var lines = String(raw || "").split("\n")
  var seen = {}
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") {
        value.fileName = popupFileName(value)
        if (seen[value.fileName]) continue
        seen[value.fileName] = true
        out.push(value)
      }
    } catch (e) {
    }
  }
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out
}

// Group key for a history entry. "" groups unknown/empty app names together.
function groupKey(entry) {
  return String((entry || {}).app || "")
}

// Flat newest-first list → app-grouped flat list: groups ordered by their
// newest member, members newest-first inside each group. Also returns header
// metadata: key -> { app, appIcon, count }.
function groupByApp(entries) {
  var list = Array.isArray(entries) ? entries : []
  var order = []
  var buckets = {}
  var newest = {}
  var meta = {}

  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var key = groupKey(e)
    if (!buckets[key]) {
      buckets[key] = []
      order.push(key)
      meta[key] = { app: key, appIcon: String(e.appIcon || ""), count: 0 }
    }
    buckets[key].push(e)
    // First non-empty icon wins; input is newest-first so newest row wins.
    if (!meta[key].appIcon && e.appIcon) meta[key].appIcon = String(e.appIcon || "")
    var ts = Number(e.timestamp || 0)
    if (!(key in newest) || ts > newest[key]) newest[key] = ts
  }

  order.sort(function(a, b) { return (newest[b] || 0) - (newest[a] || 0) })

  var flat = []
  var groups = []
  for (var k = 0; k < order.length; k++) {
    var bucket = buckets[order[k]]
    meta[order[k]].count = bucket.length
    groups.push({ key: order[k], items: bucket })
    for (var j = 0; j < bucket.length; j++) flat.push(bucket[j])
  }
  return { rows: flat, meta: meta, groups: groups }
}

function relativeTime(timestampMs, nowMs) {
  var now = typeof nowMs === "number" && isFinite(nowMs) ? nowMs : Date.now()
  var ts = Number(timestampMs || 0)
  if (!isFinite(ts) || ts <= 0) return ""
  var diff = Math.max(0, now - ts)
  var sec = Math.floor(diff / 1000)
  if (sec < 45) return "только что"
  var min = Math.floor(sec / 60)
  if (min < 60) return min + " мин назад"
  var hr = Math.floor(min / 60)
  if (hr < 24) return hr + " ч назад"
  var days = Math.floor(hr / 24)
  if (days === 1) return "вчера"
  if (days < 7) return days + " дн назад"
  var d = new Date(ts)
  var months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
  return d.getDate() + " " + months[d.getMonth()]
}

function iconSource(icon) {
  var value = String(icon || "")
  if (value.length === 0) return ""
  if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
  if (value.charAt(0) === "/") return "file://" + value.split("/").map(encodeURIComponent).join("/")
  try {
    return Quickshell.iconPath(value, true)
  } catch (e) {
    return ""
  }
}
