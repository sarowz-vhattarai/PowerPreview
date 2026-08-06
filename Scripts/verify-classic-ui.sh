#!/usr/bin/env bash
set -euo pipefail

ROOT=/Users/sarowzvhattarai/PowerPreview
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export POWERPREVIEW_FORCE_NATIVE=1

"$ROOT/Scripts/build-app.sh" >/tmp/pp-ui-build.log

APP=/tmp/PowerPreviewClassicVerify.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/.build/manual/PowerPreview" "$APP/Contents/MacOS/PowerPreview"
cp "$ROOT/.build/manual/libPowerPreviewCore.dylib" "$APP/Contents/Frameworks/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PowerPreview</string>
  <key>CFBundleIdentifier</key><string>com.powerpreview.app</string>
  <key>CFBundleName</key><string>PowerPreview</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null

FIX=$(mktemp -d /tmp/pp-ui-XXXX)
python3 - "$FIX" <<'PY'
import struct, zlib, pathlib, sys
out = pathlib.Path(sys.argv[1])
def write_png(path, rgb=(10, 20, 30)):
    w = h = 16
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
for n in ["one.png", "two.png", "three.png"]:
    write_png(out / n)
print(out)
PY

pkill -x PowerPreview 2>/dev/null || true
sleep 0.5

defaults delete com.powerpreview.app isPlayAllEnabled 2>/dev/null || true
defaults write com.powerpreview.app isPlayAllEnabled -bool false

open -a "$APP" "$FIX/one.png"
sleep 2.5

TITLE=$(osascript <<'AS' 2>/dev/null || true
tell application "System Events"
  if exists process "PowerPreview" then
    set frontmost of process "PowerPreview" to true
    delay 0.3
    if exists window 1 of process "PowerPreview" then
      return name of window 1 of process "PowerPreview"
    end if
  end if
end tell
return ""
AS
)
echo "Window title: ${TITLE:-<none>}"
if [[ "$TITLE" == *"Classic"* ]] || [[ "$TITLE" == *"PowerPreview"* ]]; then
  echo "PASS: window title"
else
  echo "WARN: title not readable (Accessibility?)"
fi

# Solo mode key navigation must not crash
osascript <<'AS'
tell application "System Events"
  set frontmost of process "PowerPreview" to true
  delay 0.2
  key code 124
  delay 0.2
  key code 123
  delay 0.2
end tell
AS
pgrep -x PowerPreview >/dev/null && echo "PASS: solo arrow keys" || { echo "FAIL: solo arrows"; exit 1; }

# Play All on via persisted default + relaunch (covers loadFile scan path)
pkill -x PowerPreview 2>/dev/null || true
sleep 0.8
defaults write com.powerpreview.app isPlayAllEnabled -bool true
open -a "$APP" "$FIX/one.png"
sleep 2.5

osascript <<'AS'
tell application "System Events"
  set frontmost of process "PowerPreview" to true
  delay 0.3
  key code 124
  delay 0.4
  key code 124
  delay 0.4
  key code 123
  delay 0.3
end tell
AS
pgrep -x PowerPreview >/dev/null && echo "PASS: Play All arrow navigation" || { echo "FAIL: Play All nav"; exit 1; }

# Open folder
open -a "$APP" "$FIX"
sleep 1.5
pgrep -x PowerPreview >/dev/null && echo "PASS: open folder" || { echo "FAIL: open folder"; exit 1; }

# Video + spacebar
VIDEO="$HOME/Downloads/Still renting.mp4"
if [[ -f "$VIDEO" ]]; then
  open -a "$APP" "$VIDEO"
  sleep 3
  osascript <<'AS'
tell application "System Events"
  set frontmost of process "PowerPreview" to true
  delay 0.2
  keystroke " "
  delay 0.6
  keystroke " "
  delay 0.2
end tell
AS
  pgrep -x PowerPreview >/dev/null && echo "PASS: video spacebar" || { echo "FAIL: video"; exit 1; }
fi

WCOUNT=$(osascript -e 'tell application "System Events" to count windows of process "PowerPreview"' 2>/dev/null || echo 0)
echo "Window count (Accessibility): $WCOUNT"
if pgrep -x PowerPreview >/dev/null; then
  echo "PASS: process alive (window AX may be unavailable without Accessibility permission)"
else
  echo "FAIL: process dead after video"
  exit 1
fi

# Stop on navigate: switch back to image while video was playing
open -a "$APP" "$FIX/two.png"
sleep 1.5
pgrep -x PowerPreview >/dev/null && echo "PASS: navigate image after video" || { echo "FAIL: navigate after video"; exit 1; }

pkill -x PowerPreview 2>/dev/null || true
defaults write com.powerpreview.app isPlayAllEnabled -bool false
echo "All UI smoke checks passed"
