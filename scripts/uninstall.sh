#!/usr/bin/env bash
# Removes Clippy.app. Pass --purge to also delete your clipboard history.
set -euo pipefail

pkill -x clippy 2>/dev/null || true
rm -rf "$HOME/Applications/Clippy.app" "/Applications/Clippy.app"
defaults delete io.github.allenjohn07.clippy 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$HOME/Library/Application Support/clippy"
    echo "Deleted clipboard history."
fi
echo "Clippy removed. Also remove it from System Settings → Privacy & Security → Accessibility."
