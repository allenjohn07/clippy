import Cocoa

/// Pure placement math for the popup, kept separate so it can be unit-tested.
enum PopupLayout {
    /// Rows actually shown at once.
    static func visibleRows(itemCount: Int) -> Int { min(itemCount, Config.popupVisibleRows) }

    /// Total popup height: the visible rows plus padding and the footer.
    static func height(itemCount: Int) -> CGFloat {
        CGFloat(visibleRows(itemCount: itemCount)) * Config.rowHeight + 12 + Config.footerHeight
    }

    /// Scroll offset that keeps `selected` on screen, moving as little as possible.
    static func scrollOffset(keeping selected: Int, current: Int, itemCount: Int) -> Int {
        let visible = visibleRows(itemCount: itemCount)
        guard visible > 0 else { return 0 }
        var offset = current
        if selected < offset { offset = selected }
        if selected >= offset + visible { offset = selected - visible + 1 }
        return clampOffset(offset, itemCount: itemCount)
    }

    static func clampOffset(_ offset: Int, itemCount: Int) -> Int {
        max(0, min(offset, itemCount - visibleRows(itemCount: itemCount)))
    }

    /// Where the preview panel goes: to the right of the list if it fits, else to the left,
    /// top-aligned with the list and kept on screen.
    static func previewOrigin(listFrame: NSRect, previewSize: NSSize, visible: NSRect, gap: CGFloat = 8) -> NSPoint {
        var x = listFrame.maxX + gap
        if x + previewSize.width > visible.maxX {
            x = listFrame.minX - gap - previewSize.width
        }
        x = min(max(x, visible.minX), visible.maxX - previewSize.width)
        var y = listFrame.maxY - previewSize.height
        y = min(max(y, visible.minY), visible.maxY - previewSize.height)
        return NSPoint(x: x, y: y)
    }

    /// Footer text, e.g. "245 items · 1.2 MB".
    static func footerInfo(count: Int, bytes: Int64) -> String {
        let items = count == 1 ? "1 item" : "\(count) items"
        return "\(items) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
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
