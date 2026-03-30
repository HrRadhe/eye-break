# 👁 EyeBreak — Menu Bar App

20-20-20 eye break reminder. Lives in your menu bar. Reads iCloud Calendar.

## Build & Run (one time)

```bash
chmod +x build.sh
./build.sh
open EyeBreak.app
```

## Install permanently

```bash
cp -r EyeBreak.app /Applications/
open /Applications/EyeBreak.app
```

Then add to Login Items:
**System Settings → General → Login Items → +  → EyeBreak**

## Menu bar

```
👁  (active) / ⏸ (paused)
─────────────────────────
Next break in 18:42
─────────────────────────
Pause / Resume          ⌘P
Test break now          ⌘T
─────────────────────────
Interval  ▶  10 / 15 / 20 / 30 / 45 min
─────────────────────────
Quit Eye Break          ⌘Q
```

## Tweak colours

The colour palette is inside `EyeBreak.swift` in the `buildHTML()` function.
Look for the `:root { ... }` CSS block — change any hex value, rebuild.

```bash
./build.sh && open EyeBreak.app
```

## Permissions

macOS will ask on first launch:
- **Calendars** — to show today's events (System Settings → Privacy → Calendars)
