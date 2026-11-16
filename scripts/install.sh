#!/usr/bin/env bash
# Builds Clippy.app, installs it to ~/Applications and starts it.
# On first launch it adds itself to Login Items (toggle from the menu bar icon).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x clippy 2>/dev/null || true
rm -rf "$DEST/Clippy.app"
cp -R build/Clippy.app "$DEST/"
open "$DEST/Clippy.app"

echo
echo "Installed to $DEST/Clippy.app and started."
echo "If prompted, allow Clippy in System Settings → Privacy & Security → Accessibility."
