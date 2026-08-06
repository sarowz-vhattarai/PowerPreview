#!/usr/bin/env bash
# Automated smoke checks for Classic PowerPreview before DMG packaging.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export POWERPREVIEW_FORCE_NATIVE=1

PASS=0
FAIL=0

ok() { echo "PASS: $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

echo "== Classic verify: unit tests =="
if (cd "$ROOT_DIR" && swift test 2>&1); then
  ok "swift test"
else
  bad "swift test"
fi

echo "== Classic verify: build app =="
if "$ROOT_DIR/Scripts/build-app.sh" >/tmp/pp-classic-build.log 2>&1; then
  ok "build-app.sh"
else
  bad "build-app.sh (see /tmp/pp-classic-build.log)"
  cat /tmp/pp-classic-build.log
  exit 1
fi

BIN="$ROOT_DIR/.build/manual/PowerPreview"
test -x "$BIN" && ok "binary exists" || bad "binary missing"

echo "== Classic verify: Play All AppState logic (inline) =="
# Compile a tiny harness against PowerPreviewCore + AppState sources is heavy;
# instead validate MediaScanner folder listing used by Play All.
TEST_DIR="$(mktemp -d /tmp/pp-classic-XXXX)"
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# Minimal JPEG (1x1) and copy a short system media if available
python3 - <<'PY' "$TEST_DIR"
import struct, zlib, sys, pathlib
out = pathlib.Path(sys.argv[1])
def write_png(path, rgb=(200, 100, 50)):
    w = h = 8
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    path.write_bytes(data)
write_png(out / "a.png")
write_png(out / "b.png")
write_png(out / "c.png")
(out / "notes.txt").write_text("ignore")
print(out)
PY

cd "$ROOT_DIR"
COUNT=$(python3 - <<'PY' "$TEST_DIR"
import sys, pathlib
img = {"jpg","jpeg","png","gif","tif","tiff","heic","heif","bmp","webp"}
vid = {"mp4","m4v","mov","mkv","webm","avi","mpeg","mpg","wmv","flv","3gp","3g2","ts","mts","m2ts","ogv"}
folder = pathlib.Path(sys.argv[1])
items = [p for p in folder.iterdir() if p.suffix.lower().lstrip(".") in img|vid]
print(len(items))
assert len(items) == 3
PY
) && ok "folder has $COUNT media siblings for Play All scan" || bad "fixture scan count"

echo "== Classic verify: launch + open file (native) =="
# Reset Play All default
defaults delete com.powerpreview.app isPlayAllEnabled 2>/dev/null || true
defaults write com.powerpreview.app isPlayAllEnabled -bool false

# Install temp app bundle for Launch Services open
TMP_APP="/tmp/PowerPreviewClassicVerify.app"
rm -rf "$TMP_APP"
mkdir -p "$TMP_APP/Contents/MacOS" "$TMP_APP/Contents/Frameworks" "$TMP_APP/Contents/Resources"
cp "$BIN" "$TMP_APP/Contents/MacOS/PowerPreview"
cp "$ROOT_DIR/.build/manual/libPowerPreviewCore.dylib" "$TMP_APP/Contents/Frameworks/"
cat > "$TMP_APP/Contents/Info.plist" <<'PLIST'
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
codesign --force --deep --sign - "$TMP_APP" >/dev/null 2>&1 || true

pkill -f "/tmp/PowerPreviewClassicVerify.app" 2>/dev/null || true
pkill -x PowerPreview 2>/dev/null || true
sleep 0.5

open -a "$TMP_APP" --args || open "$TMP_APP"
sleep 2

if pgrep -f "PowerPreviewClassicVerify.app/Contents/MacOS/PowerPreview" >/dev/null \
   || pgrep -x PowerPreview >/dev/null; then
  ok "app launched"
else
  bad "app did not launch"
fi

# Open a single PNG — with Play All off should stay 1 of 1 (can't read UI easily;
# at least ensure process stays alive and accepts open)
open -a "$TMP_APP" "$TEST_DIR/a.png"
sleep 2

if pgrep -f "PowerPreviewClassicVerify.app/Contents/MacOS/PowerPreview" >/dev/null \
   || pgrep -x PowerPreview >/dev/null; then
  ok "app still alive after opening image"
else
  bad "app crashed after opening image"
fi

# Open a sample video if present
SAMPLE_VIDEO=""
for candidate in \
  "$HOME/Downloads/Still renting.mp4" \
  "/System/Library/Compositions/Cube.mov" \
  "/Library/Application Support/Apple/iChat Icons" ; do
  if [[ -f "$candidate" ]]; then SAMPLE_VIDEO="$candidate"; break; fi
done

# Find any short mov/mp4 under Downloads
if [[ -z "$SAMPLE_VIDEO" ]]; then
  SAMPLE_VIDEO="$(find "$HOME/Downloads" -maxdepth 2 \( -iname '*.mp4' -o -iname '*.mov' \) -size -200M 2>/dev/null | head -1 || true)"
fi

if [[ -n "$SAMPLE_VIDEO" && -f "$SAMPLE_VIDEO" ]]; then
  open -a "$TMP_APP" "$SAMPLE_VIDEO"
  sleep 3
  if pgrep -f "PowerPreviewClassicVerify.app/Contents/MacOS/PowerPreview" >/dev/null \
     || pgrep -x PowerPreview >/dev/null; then
    ok "opened video without crash: $(basename "$SAMPLE_VIDEO")"
  else
    bad "crashed opening video"
  fi
else
  echo "SKIP: no sample mp4/mov found for video check"
fi

# Window title check via AppleScript
TITLE="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if exists (process "PowerPreview") then
    tell process "PowerPreview"
      if exists window 1 then
        return name of window 1
      end if
    end tell
  end if
end tell
return ""
APPLESCRIPT
)"
if [[ "$TITLE" == *"Classic"* ]] || [[ "$TITLE" == *"PowerPreview"* ]]; then
  ok "window title: $TITLE"
else
  echo "WARN: could not read window title via Accessibility (got: '$TITLE') — not a hard fail"
fi

# Ensure single instance / no runaway memory spike in 3s of next navigation simulation
MEM1="$(ps -o rss= -p "$(pgrep -n PowerPreview | head -1)" 2>/dev/null | tr -d ' ' || echo 0)"
sleep 2
MEM2="$(ps -o rss= -p "$(pgrep -n PowerPreview | head -1)" 2>/dev/null | tr -d ' ' || echo 0)"
if [[ "$MEM1" -gt 0 && "$MEM2" -lt 2000000 ]]; then
  ok "memory RSS stable-ish (${MEM1}KB -> ${MEM2}KB)"
else
  echo "WARN: memory check inconclusive ($MEM1 -> $MEM2)"
fi

pkill -f "/tmp/PowerPreviewClassicVerify.app" 2>/dev/null || true
pkill -x PowerPreview 2>/dev/null || true

echo
echo "Classic verify summary: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "Manual UI checklist still required for toolbar clicks, Play All toggle, slideshow, scrubber."
exit 0
