#!/bin/bash
# =============================================================
#  eye_break.sh — 20-20-20 Eye Break Reminder
#  Reads iCloud Calendar events, shows full-screen overlay
#
#  Usage:
#    ./eye_break.sh              # default: every 20 minutes
#    ./eye_break.sh 30           # custom interval in minutes
#
#  Stop: pkill -f eye_break.sh
# =============================================================

INTERVAL_MINS=${1:-20}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_FILE="$SCRIPT_DIR/eye_break.html"
EVENTS_FILE="$SCRIPT_DIR/events.json"

# ── sanity checks ────────────────────────────────────────────
if [ ! -f "$HTML_FILE" ]; then
  echo "❌  eye_break.html not found in $SCRIPT_DIR"
  exit 1
fi

if ! command -v swift &>/dev/null; then
  echo "❌  swift not found. Install Xcode Command Line Tools:"
  echo "    xcode-select --install"
  exit 1
fi

echo "👁  Eye Break started  |  interval: ${INTERVAL_MINS} min  |  Ctrl+C to stop"
echo "📁  Working dir: $SCRIPT_DIR"
echo ""

# ── fetch iCloud Calendar events for today ───────────────────
fetch_events() {
  local today
  today=$(date '+%A, %B %-d, %Y')

  # AppleScript: get all events from ALL iCloud calendars for today
  local raw
  raw=$(osascript <<'APPLESCRIPT' 2>/dev/null
set todayStart to (current date)
set time of todayStart to 0
set todayEnd to todayStart + (24 * 60 * 60) - 1
set eventLines to {}
tell application "Calendar"
  repeat with cal in calendars
    try
      set evs to (events of cal whose start date >= todayStart and start date <= todayEnd)
      repeat with ev in evs
        set evStart to start date of ev
        set evHour to hours of evStart
        set evMin to minutes of evStart
        set ampm to "AM"
        set dispHour to evHour
        if evHour >= 12 then
          set ampm to "PM"
          if evHour > 12 then set dispHour to evHour - 12
        end if
        if dispHour is 0 then set dispHour to 12
        set minStr to text -2 thru -1 of ("00" & evMin)
        set timeStr to (dispHour as string) & ":" & minStr & " " & ampm
        set evName to summary of ev
        set end of eventLines to timeStr & "|||" & evName
      end repeat
    end try
  end repeat
end tell
set tid to text item delimiters
set text item delimiters to "~~~"
set result to eventLines as string
set text item delimiters to tid
return result
APPLESCRIPT
)

  # Build JSON from the raw output
  if [ -z "$raw" ] || [ "$raw" = "missing value" ]; then
    echo "[]" > "$EVENTS_FILE"
    return
  fi

  local json="["
  local first=true
  IFS='~~~' read -ra lines <<< "$raw"
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    local time_part name_part
    time_part=$(echo "$line" | cut -d'|' -f1)
    name_part=$(echo "$line" | cut -d'|' -f4-)
    # escape double quotes in name
    name_part="${name_part//\"/\\\"}"
    [ "$first" = true ] && first=false || json+=","
    json+="{\"time\":\"$time_part\",\"name\":\"$name_part\"}"
  done
  json+="]"

  echo "$json" > "$EVENTS_FILE"
  echo "[$(date '+%H:%M:%S')] 📅  Fetched $(echo "$json" | grep -o '"time"' | wc -l | tr -d ' ') event(s)"
}

# ── inject events into HTML and show overlay ─────────────────
show_break() {
  # Read events JSON
  local events="[]"
  [ -f "$EVENTS_FILE" ] && events=$(cat "$EVENTS_FILE")

  # Create a temp HTML with events injected as a JS variable
  local tmp_html
  tmp_html=$(mktemp /tmp/eye_break_XXXX.html)

  # Inject EVENTS_DATA right before </head>
  sed "s|</head>|<script>window.EVENTS_DATA = ${events};</script>\n</head>|" \
    "$HTML_FILE" > "$tmp_html"

  echo "[$(date '+%H:%M:%S')] 👁  Showing eye break..."

  # Run the Swift window (blocks until window closes, max ~25s)
  swift "$SCRIPT_DIR/eye_break.swift" "$tmp_html"

  rm -f "$tmp_html"
  echo "[$(date '+%H:%M:%S')] ✅  Break done. Next in ${INTERVAL_MINS} min."
}

# ── main loop ────────────────────────────────────────────────
# Show immediately on first run so you can verify it works
echo "[$(date '+%H:%M:%S')] 🚀  Showing first break now..."
fetch_events
show_break

while true; do
  echo "[$(date '+%H:%M:%S')] ⏳  Waiting ${INTERVAL_MINS} min..."
  sleep $((INTERVAL_MINS * 60))
  fetch_events
  show_break
done