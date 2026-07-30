#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/mpv"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  URL="https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-arm64-0.40.0.tar.gz"
else
  URL="https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-0.39.0.tar.gz"
fi

echo "Downloading mpv runtime for $ARCH..."
curl -L --fail -o "$TMP_DIR/mpv.tar.gz" "$URL"
mkdir -p "$TMP_DIR/extract"
tar -xzf "$TMP_DIR/mpv.tar.gz" -C "$TMP_DIR/extract"

MPV_BIN="$(find "$TMP_DIR/extract" -type f -path '*/MacOS/mpv' | head -n 1)"
MPV_LIB="$(find "$TMP_DIR/extract" -type d -path '*/MacOS/lib' | head -n 1)"

[[ -n "$MPV_BIN" && -n "$MPV_LIB" ]] || {
  echo "error: could not find mpv binary/libs in archive" >&2
  exit 1
}

rm -rf "$VENDOR_DIR/mpv" "$VENDOR_DIR/lib"
mkdir -p "$VENDOR_DIR"
cp "$MPV_BIN" "$VENDOR_DIR/mpv"
cp -R "$MPV_LIB" "$VENDOR_DIR/lib"
chmod +x "$VENDOR_DIR/mpv"

echo "Installed mpv runtime to $VENDOR_DIR"
"$VENDOR_DIR/mpv" --version | head -n 3
