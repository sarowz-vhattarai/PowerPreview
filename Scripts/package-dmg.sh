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

find_mpv_runtime() {
  if [[ -x "$ROOT_DIR/Vendor/mpv/mpv" && -d "$ROOT_DIR/Vendor/mpv/lib" ]]; then
    echo "$ROOT_DIR/Vendor/mpv"
    return 0
  fi
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
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>mp4</string>
        <string>m4v</string>
        <string>mov</string>
        <string>mkv</string>
        <string>webm</string>
        <string>avi</string>
        <string>mpeg</string>
        <string>mpg</string>
        <string>wmv</string>
        <string>flv</string>
        <string>ts</string>
        <string>m2ts</string>
      </array>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.video</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
        <string>org.webmproject.webm</string>
        <string>public.avi</string>
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

MPV_RUNTIME="$(find_mpv_runtime || true)"
if [[ -z "$MPV_RUNTIME" && "${MPV_REQUIRED:-0}" == "1" ]]; then
  die "mpv runtime was not found. Run Scripts/fetch-mpv.sh or place Vendor/mpv/mpv and Vendor/mpv/lib."
fi

if [[ -z "$MPV_RUNTIME" ]]; then
  echo "warning: mpv runtime was not found. Building a native AVKit-only DMG; MKV and many movie formats will not play." >&2
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

if [[ -n "$MPV_RUNTIME" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/mpv-runtime"
  cp "$MPV_RUNTIME/mpv" "$APP_BUNDLE/Contents/Resources/mpv-runtime/mpv"
  chmod +x "$APP_BUNDLE/Contents/Resources/mpv-runtime/mpv"
  cp -R "$MPV_RUNTIME/lib" "$APP_BUNDLE/Contents/Resources/mpv-runtime/lib"
fi

write_info_plist
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

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
