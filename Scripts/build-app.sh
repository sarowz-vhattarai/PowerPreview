#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift package resolve
swift build -c release --product PowerPreview

BIN_PATH="$(swift build -c release --show-bin-path)/PowerPreview"
echo "$BIN_PATH"
