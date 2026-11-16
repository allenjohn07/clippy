import Cocoa

/// Pure placement math for the popup, kept separate so it can be unit-tested.
enum PopupLayout {
    /// Total popup height for `itemCount` rows plus the footer.
    static func height(itemCount: Int) -> CGFloat {
        CGFloat(itemCount) * Config.rowHeight + 12 + Config.footerHeight
    }

    /// Bottom-left origin for a popup of `size`:
    /// 1. directly below the input box, else directly above it;
    /// 2. if the input is too tall for either (big editors), below/above the caret line;
    /// 3. otherwise at the mouse.
    /// The result is always clamped inside `visible`.
    static func origin(size: NSSize, target: PasteTarget, mouse: NSPoint,
                       visible: NSRect, gap: CGFloat = 6) -> NSPoint {
        func below(_ r: NSRect) -> CGFloat? {
            let y = r.minY - gap - size.height
            return y >= visible.minY ? y : nil
        }
        func above(_ r: NSRect) -> CGFloat? {
            let y = r.maxY + gap
            return y + size.height <= visible.maxY ? y : nil
        }

        let mouseRect = NSRect(origin: mouse, size: .zero)
        var x: CGFloat
        var y: CGFloat
        if let f = target.inputFrame, let fy = below(f) ?? above(f) {
            x = f.minX; y = fy
        } else if let c = target.caret, let cy = below(c) ?? above(c) {
            x = c.minX; y = cy
        } else {
            x = mouse.x; y = below(mouseRect) ?? (mouse.y + gap)
        }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}
