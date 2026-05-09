#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
EXEC_SRC="$BIN_DIR/AppLauncher"
OUT_APP="$ROOT/build/App Launcher.app"
rm -rf "$OUT_APP"
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"

cp "$EXEC_SRC" "$OUT_APP/Contents/MacOS/AppLauncher"
chmod +x "$OUT_APP/Contents/MacOS/AppLauncher"

cp "$ROOT/Support/Info.plist" "$OUT_APP/Contents/Info.plist"
cp "$ROOT/Sources/AppLauncher/Resources/AppIcon.icns" "$OUT_APP/Contents/Resources/AppIcon.icns"

# Copy every SwiftPM resource bundle (the old script only copied one bundle and flattened it).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
	cp -R "$bundle" "$OUT_APP/Contents/Resources/"
done
shopt -u nullglob

codesign --force --deep --sign - "$OUT_APP" 2>/dev/null || {
	echo "Note: codesign failed (install Xcode CLTs or run: codesign --force --deep --sign - \"$OUT_APP\")" >&2
}

echo "Built: $OUT_APP"
echo "Install: drag into /Applications or run scripts/install-user-applications.sh"
