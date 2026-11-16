#!/usr/bin/env bash
# End-to-end tests: drives a real Clippy with real keyboard/mouse events.
#
# ⚠  Takes over your keyboard and mouse for about a minute. Don't type or move the mouse
#    while it runs. Your clipboard is saved and restored, a running Clippy is paused and
#    restarted, and a throwaway database is used, so your history is not touched.
#
# Needs: Accessibility permission for your terminal app, Node.js (for the browser part).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK="$(mktemp -d)"
DB="$WORK/history.db"
LOG="$WORK/clippy.log"
CLIP="$WORK/clipboard.plist"
STATUS=0

# Use Xcode's toolchain if present (Command Line Tools alone can lack test plugins).
if [[ -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi

echo "==> Building"
swift build 2>&1 | grep -E "error|Build complete" || exit 1
CLIPPY="$(swift build --show-bin-path)/clippy"
swiftc -O Tests/E2E/Support.swift Tests/E2E/ctl/main.swift -o "$WORK/e2ectl" 2>&1 | grep -v "search path" || true
swiftc -O Tests/E2E/Support.swift Tests/E2E/harness/main.swift -o "$WORK/harness" 2>&1 | grep -v "search path" || true
[[ -x "$WORK/e2ectl" && -x "$WORK/harness" ]] || { echo "failed to build e2e tools"; exit 1; }

# Pause any Clippy that's already running (it would grab ⌘⇧V too), remembering how to restart it.
RUNNING_APP="$(ps -axo command= | grep -E '/Clippy\.app/Contents/MacOS/clippy$' | head -1 | sed 's|/Contents/MacOS/clippy$||')"
pkill -x clippy 2>/dev/null && sleep 0.5

"$WORK/e2ectl" save-clipboard "$CLIP"

CLIPPY_PID=""
start_clippy() {
    : > "$LOG"
    CLIPPY_DB_PATH="$DB" "$CLIPPY" >> "$LOG" 2>&1 &
    CLIPPY_PID=$!
    for _ in $(seq 1 50); do grep -q "clippy running" "$LOG" && return 0; sleep 0.1; done
    echo "Clippy didn't start:"; cat "$LOG"; return 1
}
stop_clippy() { [[ -n "$CLIPPY_PID" ]] && kill "$CLIPPY_PID" 2>/dev/null; wait "$CLIPPY_PID" 2>/dev/null; CLIPPY_PID=""; }

cleanup() {
    stop_clippy
    "$WORK/e2ectl" restore-clipboard "$CLIP"
    [[ -n "$RUNNING_APP" ]] && open "$RUNNING_APP"
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Native app tests (phase A)"
start_clippy || exit 1
"$WORK/harness" A "$CLIPPY_PID" "$DB" || STATUS=1

if [[ -d Tests/E2E/browser/node_modules/playwright ]]; then
    echo "==> Browser tests"
    node Tests/E2E/browser/browser.test.mjs "$WORK/e2ectl" "$CLIPPY_PID" || STATUS=1
else
    echo "==> Browser tests skipped (run: cd Tests/E2E/browser && npm install && npx playwright install chromium)"
fi

echo "==> Restarting Clippy (phase B: persistence, scrolling, clear)"
stop_clippy
# Add 20 older entries so there's more than one screenful to scroll through.
for i in $(seq 1 20); do
    sqlite3 "$DB" "INSERT OR IGNORE INTO clips (content, created_at, last_used_at) VALUES ('older item $i', $i, $i);"
done
start_clippy || exit 1
"$WORK/harness" B "$CLIPPY_PID" "$DB" || STATUS=1

echo
if [[ $STATUS -eq 0 ]]; then echo "==> All end-to-end tests passed"; else echo "==> Some end-to-end tests FAILED"; fi
exit $STATUS
