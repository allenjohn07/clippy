// clippy — press ⌘⇧V to pick from your clipboard history. ⌘V pastes as normal.
//
// Build & install:  ./scripts/install.sh      (builds Clippy.app into ~/Applications)
// Dev run:          swift run
//
// Usage (popup opens wherever you can paste, just below/above the input box):
//   • V / ↓ / ↑ ............ move selection
//   • 1–9 or click a row ... paste that item
//   • Return ............... paste the highlighted item
//   • Esc / any key / click elsewhere ... close
//   • ⌫ or "Clear history" (twice to confirm) ... delete all history
//
// History is stored in ~/Library/Application Support/clippy/history.db (SQLite),
// capped at the newest Config.maxStoredItems entries.
//
// First run: grant Accessibility (and Input Monitoring if asked) to the app you
// launched it from (e.g. Terminal) in System Settings → Privacy & Security.
// Quit from the menu bar icon, with Ctrl+C in the terminal, or `pkill clippy`.

import Cocoa
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar

let database = HistoryDatabase(url: Config.databaseURL)
if database == nil {
    print("clippy: running without persistence (history will not be saved).")
}

let store = ClipboardStore(database: database)
store.start()

let controller = Controller(store: store)
let statusMenu = StatusMenu(store: store)
LoginItem.enableOnFirstLaunch()

// Triggers the system Accessibility prompt if not yet trusted.
_ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

let readyMessage = "clippy running. Press ⌘⇧V in a text field to pick from history. Ctrl+C to quit."
if EventTap.install(for: controller) {
    print(readyMessage)
} else {
    print("Waiting for permission… grant Accessibility / Input Monitoring in System Settings → Privacy & Security.")
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
        if EventTap.install(for: controller) {
            print(readyMessage)
            timer.invalidate()
        }
    }
}

app.run()
