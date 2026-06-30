#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
APP_NAME="PowerPreview"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
TRIPLE="$(swift -print-target-info | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"])')"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swiftc \
  -sdk "$SDKROOT" \
  -target "$TRIPLE" \
  -emit-module \
  -emit-library \
  -module-name PowerPreviewCore \
  -parse-as-library \
  "$ROOT_DIR"/Sources/PowerPreviewCore/*.swift \
  -emit-module-path "$BUILD_DIR/PowerPreviewCore.swiftmodule" \
  -o "$BUILD_DIR/libPowerPreviewCore.dylib"

swiftc \
  -sdk "$SDKROOT" \
  -target "$TRIPLE" \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lPowerPreviewCore \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVKit \
  -framework UniformTypeIdentifiers \
  "$ROOT_DIR"/Sources/PowerPreview/*.swift \
  -o "$BUILD_DIR/$APP_NAME"

echo "$BUILD_DIR/$APP_NAME"
