#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PowerPreview"
BUNDLE_ID="com.powerpreview.app"
VERSION="${VERSION:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
ICON_PATH="$ROOT_DIR/.build/icon/PowerPreview.icns"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

die() {
  echo "error: $*" >&2
  exit 1
}

require_macos_sdk() {
  xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || die "macOS SDK is not available. Install or repair Apple Command Line Tools with: xcode-select --install"
}

find_mpv() {
  local candidates=()

  if [[ -n "${POWERPREVIEW_MPV_PATH:-}" ]]; then
    candidates+=("$POWERPREVIEW_MPV_PATH")
  fi

  candidates+=(
    "$ROOT_DIR/Vendor/mpv/mpv"
    "$ROOT_DIR/Sources/PowerPreview/Resources/mpv"
    "/opt/homebrew/bin/mpv"
    "/usr/local/bin/mpv"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

write_info_plist() {
  cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>PowerPreview</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Images</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.image</string>
        <string>public.jpeg</string>
        <string>public.png</string>
        <string>com.apple.quicktime-image</string>
        <string>com.compuserve.gif</string>
        <string>com.microsoft.bmp</string>
        <string>public.tiff</string>
        <string>org.webmproject.webp</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Videos</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.video</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
        <string>org.webmproject.webm</string>
      </array>
    </dict>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST
}

MPV_PATH="$(find_mpv || true)"
if [[ -z "$MPV_PATH" && "${MPV_REQUIRED:-0}" == "1" ]]; then
  die "mpv was not found. Put a self-contained macOS mpv executable at Vendor/mpv/mpv or set POWERPREVIEW_MPV_PATH=/path/to/mpv."
fi

if [[ -z "$MPV_PATH" ]]; then
  echo "warning: mpv was not found. Building a native AVKit-only DMG; video format support will be limited to what macOS can play." >&2
fi

require_macos_sdk

rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks" "$STAGING_DIR"

"$ROOT_DIR/Scripts/build-app.sh"
"$ROOT_DIR/Scripts/generate-icon.sh"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BUILD_DIR/libPowerPreviewCore.dylib" "$APP_BUNDLE/Contents/Frameworks/libPowerPreviewCore.dylib"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/PowerPreview.icns"

if [[ -n "$MPV_PATH" ]]; then
  cp "$MPV_PATH" "$APP_BUNDLE/Contents/Resources/mpv"
  chmod +x "$APP_BUNDLE/Contents/Resources/mpv"
fi

write_info_plist
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

if [[ -n "$MPV_PATH" ]] && command -v otool >/dev/null 2>&1; then
  if otool -L "$APP_BUNDLE/Contents/Resources/mpv" | grep -E '/opt/homebrew|/usr/local' >/dev/null 2>&1; then
    echo "warning: bundled mpv links to Homebrew libraries. Use a self-contained mpv build for a fully independent DMG." >&2
  fi
fi

codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Created app: $APP_BUNDLE"
echo "Created dmg: $DMG_PATH"
