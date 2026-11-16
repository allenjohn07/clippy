import Cocoa
import ApplicationServices

/// Where the popup should be placed, in Cocoa screen coordinates.
struct PasteTarget {
    /// Frame of the focused input box, if known.
    var inputFrame: NSRect?
    /// Rect of the text caret (zero width, one line tall), if known.
    var caret: NSRect?
}

/// Uses the Accessibility API to decide whether the user is somewhere they can paste,
/// and where the focused input / caret is on screen.
enum FocusInspector {
    private static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField",
    ]

    /// Cached "Paste" menu item per app, so we don't walk the menu bar on every press.
    private static var pasteItemCache: [pid_t: AXUIElement] = [:]

    /// Returns a target if pasting makes sense right now, `nil` otherwise.
    static func currentPasteTarget() -> PasteTarget? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.3)
        // Electron apps (VS Code, Slack, …) only expose their AX tree when asked.
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        let focused = element(system, kAXFocusedUIElementAttribute)
                   ?? element(appEl, kAXFocusedUIElementAttribute)

        // 1. A recognisable text input has focus.
        // 2. Otherwise, trust the app: if its Edit ▸ Paste item is enabled, it accepts a paste.
        let editable = focused.map(isEditable) ?? false
        guard editable || pasteMenuEnabled(app: appEl, pid: pid) else { return nil }

        guard let el = focused else { return PasteTarget(inputFrame: nil, caret: nil) }
        return PasteTarget(inputFrame: elementFrame(el), caret: caretRect(el))
    }

    // MARK: - Editable check

    private static func isEditable(_ el: AXUIElement) -> Bool {
        if let role = attr(el, kAXRoleAttribute) as? String, textRoles.contains(role) { return true }
        if let sub = attr(el, kAXSubroleAttribute) as? String, sub == "AXSecureTextField" { return true }
        // Web content (Safari/Chrome contenteditable) reports an editable ancestor.
        if attr(el, "AXEditableAncestor") != nil { return true }
        // Anything with a text insertion point (custom editors, terminals, …).
        if attr(el, kAXInsertionPointLineNumberAttribute) != nil { return true }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue, attr(el, kAXSelectedTextRangeAttribute) != nil {
            return true
        }
        return false
    }

    /// Looks for the app's ⌘V menu item (whatever language it's in) and reports whether it's enabled.
    private static func pasteMenuEnabled(app: AXUIElement, pid: pid_t) -> Bool {
        if let item = pasteItemCache[pid], let enabled = attr(item, kAXEnabledAttribute) as? Bool {
            return enabled
        }
        pasteItemCache[pid] = nil
        guard let bar = element(app, kAXMenuBarAttribute) else { return false }
        for barItem in children(bar) {
            for menu in children(barItem) {
                for item in children(menu) {
                    guard (attr(item, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "V",
                          (attr(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0  // 0 = ⌘ only
                    else { continue }
                    pasteItemCache[pid] = item
                    return attr(item, kAXEnabledAttribute) as? Bool ?? false
                }
            }
        }
        return false
    }

    // MARK: - Geometry

    private static func caretRect(_ el: AXUIElement) -> NSRect? {
        guard let rv = attr(el, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rv) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &range) else { return nil }

        // Apps differ in what they return for an empty range, so try a few variants.
        if let r = bounds(el, CFRange(location: range.location, length: 0)) {
            return toCocoa(r)
        }
        if range.location > 0, let r = bounds(el, CFRange(location: range.location - 1, length: 1)) {
            return toCocoa(CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height))
        }
        if let r = bounds(el, CFRange(location: range.location, length: 1)) {
            return toCocoa(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height))
        }
        return nil
    }

    private static func bounds(_ el: AXUIElement, _ range: CFRange) -> CGRect? {
        var r = range
        guard let arg = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                el, kAXBoundsForRangeParameterizedAttribute as CFString, arg, &out) == .success,
              let o = out, CFGetTypeID(o) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(o as! AXValue, .cgRect, &rect), rect.height > 0,
              rect.origin != .zero else { return nil }
        return rect
    }

    private static func elementFrame(_ el: AXUIElement) -> NSRect? {
        guard let p = attr(el, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attr(el, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return toCocoa(CGRect(origin: origin, size: size))
    }

    /// AX uses top-left-origin global coordinates; Cocoa uses bottom-left of the primary screen.
    private static func toCocoa(_ r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - AX helpers

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
