#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PowerPreview"
BUNDLE_ID="com.powerpreview.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.2.2)}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ICON_PATH="$ROOT_DIR/.build/icon/PowerPreview.icns"

die() {
  echo "error: $*" >&2
  exit 1
}

require_xcode() {
  [[ -d "$DEVELOPER_DIR" ]] || die "Xcode not found. Install Xcode and/or set DEVELOPER_DIR."
  xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1 || die "macOS SDK platform missing. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
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
        <string>public.tiff</string>
        <string>com.compuserve.gif</string>
        <string>com.microsoft.bmp</string>
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
        <string>mts</string>
        <string>3gp</string>
        <string>3g2</string>
        <string>vob</string>
        <string>ogv</string>
        <string>asf</string>
        <string>m2v</string>
        <string>mxf</string>
      </array>
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
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST
}

require_xcode
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks" "$STAGING_DIR"

"$ROOT_DIR/Scripts/build-app.sh"
"$ROOT_DIR/Scripts/generate-icon.sh"

BIN_PATH="$(cd "$ROOT_DIR" && swift build -c release --show-bin-path)/PowerPreview"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# MPVKit-GPL links libmpv/FFmpeg into the executable (static). Only copy
# truly dynamic deps if the linker emitted any next to the binary.
BIN_DIR="$(dirname "$BIN_PATH")"
shopt -s nullglob
for item in "$BIN_DIR"/*.dylib; do
  cp "$item" "$APP_BUNDLE/Contents/Frameworks/"
done
shopt -u nullglob

if compgen -G "$APP_BUNDLE/Contents/Frameworks/*" >/dev/null; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
else
  rmdir "$APP_BUNDLE/Contents/Frameworks" 2>/dev/null || true
fi

cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/PowerPreview.icns"
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
