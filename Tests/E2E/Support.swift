// Shared helpers for the end-to-end tools. These post *real* OS-level input events,
// the same way a keyboard and mouse do, so Clippy's event tap sees them.
import Cocoa
import CoreGraphics

enum E2E {
    // MARK: Keyboard

    static let keyCodes: [String: CGKeyCode] = [
        "v": 9, "x": 7, "a": 0,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "esc": 53, "return": 36, "down": 125, "up": 126, "delete": 51, "tab": 48,
    ]

    /// Posts a key combo like "cmd+shift+v", "2", "esc".
    static func key(_ spec: String) {
        var flags: CGEventFlags = []
        var keyName = ""
        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd":   flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt":   flags.insert(.maskAlternate)
            case "ctrl":  flags.insert(.maskControl)
            default:      keyName = part
            }
        }
        guard let code = keyCodes[keyName] else { fatalError("unknown key \(keyName)") }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }

    // MARK: Mouse (CG coordinates: origin top-left of the main display, in points)

    static func click(_ p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(30_000)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(30_000)
        }
    }

    // MARK: Popup detection

    /// On-screen frame (CG coordinates) of Clippy's popup, if it's showing.
    static func popupFrame(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], abs(width - 420) < 1 else { continue }   // Config.popupWidth
            return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: b["Height"] ?? 0)
        }
        return nil
    }

    // MARK: Pasteboard

    static func copy(_ text: String, extraTypes: [String] = []) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for t in extraTypes { item.setData(Data(), forType: NSPasteboard.PasteboardType(t)) }
        pb.writeObjects([item])
    }

    /// Saves every item/type on the clipboard so it can be put back after the tests.
    static func saveClipboard(to path: String) {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item -> [String: Data] in
            var dict: [String: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t.rawValue] = d } }
            return dict
        }
        let data = try! PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
        try! data.write(to: URL(fileURLWithPath: path))
    }

    static func restoreClipboard(from path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let items = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Data]]
        else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let objects = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: NSPasteboard.PasteboardType(t)) }
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
}
