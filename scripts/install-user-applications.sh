#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh" release

DEST_DIR="${HOME}/Applications"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/App Launcher.app"
cp -R "$ROOT/build/App Launcher.app" "$DEST_DIR/"

echo "Installed: $DEST_DIR/App Launcher.app"
open "$DEST_DIR/App Launcher.app"
