#!/usr/bin/env bash
# Builds Clippy.app, installs it to ~/Applications and starts it.
# On first launch it adds itself to Login Items (toggle from the menu bar icon).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="$HOME/Applications"
mkdir -p "$DEST"
# Quit a running copy and wait until it has really exited. Opening too soon makes
# macOS fail with "_LSOpenURLsWithCompletionHandler() failed with error -600".
pkill -x clippy 2>/dev/null || true
for _ in $(seq 1 50); do pgrep -x clippy >/dev/null || break; sleep 0.1; done
pkill -9 -x clippy 2>/dev/null || true

rm -rf "$DEST/Clippy.app"
cp -R build/Clippy.app "$DEST/"

started=0
for _ in 1 2 3 4 5; do
    if open "$DEST/Clippy.app" 2>/dev/null; then started=1; break; fi
    sleep 1
done
if [[ $started -eq 0 ]]; then
    echo "Installed, but macOS wouldn't start it right now. Open $DEST/Clippy.app manually."
    exit 1
fi

echo
echo "Installed to $DEST/Clippy.app and started."
echo "If prompted, allow Clippy in System Settings → Privacy & Security → Accessibility."
