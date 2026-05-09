#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Support/IconSource.png"
OUT_ICNS="$ROOT/Sources/AppLauncher/Resources/AppIcon.icns"
TMP_ICONSET="${TMPDIR:-/tmp}/AppLauncher$$.iconset"
rm -rf "$TMP_ICONSET"
mkdir -p "$TMP_ICONSET"
trap 'rm -rf "$TMP_ICONSET"' EXIT

[[ -f "$SOURCE" ]] || { echo "Missing $SOURCE"; exit 1; }

sips -z 16 16 "$SOURCE" --out "$TMP_ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE" --out "$TMP_ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE" --out "$TMP_ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE" --out "$TMP_ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE" --out "$TMP_ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE" --out "$TMP_ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE" --out "$TMP_ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE" --out "$TMP_ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE" --out "$TMP_ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE" --out "$TMP_ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$TMP_ICONSET" -o "$OUT_ICNS"
echo "Wrote $OUT_ICNS"
