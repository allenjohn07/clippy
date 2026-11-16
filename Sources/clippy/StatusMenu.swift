import Cocoa

/// Menu bar icon with the few controls the app needs (it has no windows).
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: ClipboardStore
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(store: ClipboardStore) {
        self.store = store
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippy")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Clippy — press ⌘⇧V in a text field"
        }

        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "Press ⌘⇧V to open clipboard history", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.isEnabled = LoginItem.isAvailable
        loginItem.state = LoginItem.isEnabled ? .on : .off
        infoItem.title = "History: " + PopupLayout.footerInfo(count: store.items.count, bytes: store.storageBytes)
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "This removes every saved item from this Mac. It can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
