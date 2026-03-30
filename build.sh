#!/bin/bash
# ============================================================
#  build.sh — compiles EyeBreak.swift into EyeBreak.app
#  Run once: ./build.sh
#  Then: open EyeBreak.app
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="EyeBreak"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
BINARY="$MACOS_DIR/$APP_NAME"

echo "🔨  Building $APP_NAME.app..."

# ── clean old build ──────────────────────────────────────────
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# ── compile ─────────────────────────────────────────────────
swiftc "$SCRIPT_DIR/EyeBreak.swift" \
  -o "$BINARY" \
  -framework Cocoa \
  -framework WebKit \
  -framework EventKit \
  -O

# ── Info.plist ───────────────────────────────────────────────
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.eyebreak.app</string>
  <key>CFBundleName</key>
  <string>EyeBreak</string>
  <key>CFBundleExecutable</key>
  <string>EyeBreak</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSCalendarsUsageDescription</key>
  <string>EyeBreak shows your today's events during eye breaks.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo ""
echo "✅  Built: $APP_BUNDLE"
echo ""
echo "▶   Run now:         open \"$APP_BUNDLE\""
echo "📌  Move to Apps:    cp -r \"$APP_BUNDLE\" /Applications/"
echo ""
echo "First launch: macOS will ask for Calendar access — click Allow."
