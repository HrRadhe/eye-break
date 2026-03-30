# 👁 Eye Break — 20-20-20 Reminder for macOS

Full-screen overlay every X minutes. Reads your iCloud Calendar. No app install needed.

## Setup (one time)

```bash
# 1. Give execute permission
chmod +x eye_break.sh

# 2. Install Xcode Command Line Tools (if not already)
xcode-select --install

# 3. Allow Calendar access when macOS prompts you (first run only)
```

## Run

```bash
# Default: every 20 minutes
./eye_break.sh

# Custom interval
./eye_break.sh 30    # every 30 min
./eye_break.sh 45    # every 45 min
```

## Run in background (survives terminal close)

```bash
nohup ./eye_break.sh 20 >> ~/eye_break.log 2>&1 &
echo "PID: $!"
```

## Stop

```bash
pkill -f eye_break.sh
```

## Tweak colours

Open `eye_break.html` and edit the `:root` block at the very top:

```css
:root {
  --c-hour-tens:  #F03A8A;   /* H tens  */
  --c-hour-units: #C844CC;   /* H units */
  --c-colon:      #8855BB;   /* colon   */
  --c-min-tens:   #6655E8;   /* M tens  */
  --c-min-units:  #4477F5;   /* M units */
}
```

## Files

| File | Purpose |
|------|---------|
| `eye_break.sh` | Main loop + calendar fetch |
| `eye_break.html` | Overlay UI |
| `eye_break.swift` | Full-screen macOS window |
| `events.json` | Auto-generated before each break |

## Permissions macOS will ask for

- **Calendar** — to read iCloud events (System Settings → Privacy → Calendars)
- **Accessibility** — if using AppleScript automation (System Settings → Privacy → Automation)
