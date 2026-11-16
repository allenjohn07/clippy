import Cocoa

/// What a click inside the popup landed on.
enum PopupHit: Equatable {
    case item(Int)
    case clear
}

/// Draws the visible slice of clipboard entries, a scrollbar, and the footer.
final class ListView: NSView {
    var items: [ClipItem] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    /// Index of the first visible row.
    var scrollOffset = 0 { didSet { needsDisplay = true } }
    /// e.g. "245 items · 1.2 MB"
    var footerInfo = "" { didSet { needsDisplay = true } }
    /// When true the footer asks for confirmation.
    var clearArmed = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    private func display(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                    .trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(200))
    }

    /// Rect that fills `box` with an image of `size`, cropping the overflow.
    static func aspectFill(_ size: NSSize, in box: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = max(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// YouTube-style red rounded rectangle with a white triangle.
    static func drawPlayBadge(in r: NSRect) {
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height * 0.25, yRadius: r.height * 0.25).fill()
        let t = NSBezierPath()
        let s = r.height * 0.45
        t.move(to: NSPoint(x: r.midX - s * 0.4, y: r.midY - s / 2))
        t.line(to: NSPoint(x: r.midX - s * 0.4, y: r.midY + s / 2))
        t.line(to: NSPoint(x: r.midX + s * 0.5, y: r.midY))
        t.close()
        NSColor.white.setFill()
        t.fill()
    }

    var visibleRows: Int { PopupLayout.visibleRows(itemCount: items.count) }
    var canScroll: Bool { items.count > visibleRows }

    /// Y offset (from the top) where the footer starts.
    var footerTop: CGFloat { 6 + CGFloat(visibleRows) * Config.rowHeight + 3 }

    override func draw(_ dirtyRect: NSRect) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail

        let scrollbarSpace: CGFloat = canScroll ? 10 : 0
        for row in 0..<visibleRows {
            let i = scrollOffset + row
            guard i < items.count else { break }
            let item = items[i]
            let rect = NSRect(x: 6, y: 6 + CGFloat(row) * Config.rowHeight,
                              width: bounds.width - 12 - scrollbarSpace, height: Config.rowHeight)
            let isSel = (i == selected)
            if isSel {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            let color: NSColor = isSel ? .white : .labelColor
            let dim: NSColor = isSel ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor

            let num = row < 9 ? "\(row + 1)" : " "   // 1–9 paste the visible rows
            (num as NSString).draw(
                in: NSRect(x: rect.minX + 8, y: rect.minY + 5, width: 16, height: 16),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                 .foregroundColor: dim])

            // Thumbnail (images, YouTube) or a red play badge for YouTube links without one yet.
            var textX = rect.minX + 30
            if item.thumbnail != nil || item.kind == .youtube {
                let thumbRect = NSRect(x: textX, y: rect.minY + 4, width: 18, height: 18)
                if let thumb = item.thumbnail {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3).addClip()
                    thumb.draw(in: Self.aspectFill(thumb.size, in: thumbRect), from: .zero,
                               operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    NSGraphicsContext.restoreGraphicsState()
                }
                if item.kind == .youtube { Self.drawPlayBadge(in: item.thumbnail == nil
                    ? thumbRect : NSRect(x: thumbRect.maxX - 9, y: thumbRect.maxY - 7, width: 10, height: 7)) }
                textX += 24
            }

            (display(item.label) as NSString).draw(
                in: NSRect(x: textX, y: rect.minY + 5, width: rect.maxX - textX - 10, height: 16),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13),
                                 .foregroundColor: color,
                                 .paragraphStyle: para])
        }

        // Scrollbar: shows where the visible rows sit in the whole list.
        if canScroll {
            let track = NSRect(x: bounds.width - 12, y: 8, width: 5, height: CGFloat(visibleRows) * Config.rowHeight - 4)
            let fraction = CGFloat(visibleRows) / CGFloat(items.count)
            let knobHeight = max(18, track.height * fraction)
            let maxOffset = CGFloat(items.count - visibleRows)
            let knobY = track.minY + (track.height - knobHeight) * CGFloat(scrollOffset) / maxOffset
            NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: knobY, width: track.width, height: knobHeight),
                         xRadius: 2.5, yRadius: 2.5).fill()
        }

        // Separator + footer.
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: footerTop, width: bounds.width - 24, height: 1).fill()

        let label = clearArmed ? "Click again (or ⌫) to delete all history" : "Clear history  ⌫"
        let labelColor: NSColor = clearArmed ? .systemRed : .secondaryLabelColor
        (label as NSString).draw(
            in: NSRect(x: 20, y: footerTop + 7, width: bounds.width - 40, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: clearArmed ? .semibold : .regular),
                             .foregroundColor: labelColor])
        if !clearArmed {
            let right = NSMutableParagraphStyle()
            right.alignment = .right
            (footerInfo as NSString).draw(
                in: NSRect(x: bounds.width - 220, y: footerTop + 7, width: 200, height: 16),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                                 .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: right])
        }
    }
}

/// Non-activating floating panel, so the app being typed into keeps focus.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    let list = ListView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Config.popupWidth, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true   // clicks are handled by the event tap instead
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Config.popupWidth, height: 100))
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        list.frame = effect.bounds
        list.autoresizingMask = [.width, .height]
        effect.addSubview(list)
        contentView = effect
    }

    func show(items: [ClipItem], selected: Int, target: PasteTarget, footerInfo: String) {
        list.items = items
        list.selected = selected
        list.scrollOffset = 0
        list.footerInfo = footerInfo
        list.clearArmed = false

        let size = NSSize(width: Config.popupWidth, height: PopupLayout.height(itemCount: items.count))
        let probeRect = target.caret ?? target.inputFrame
            ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let probe = NSPoint(x: probeRect.minX, y: probeRect.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(probe, $0.frame, false) } ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
            .insetBy(dx: 8, dy: 8)

        let origin = PopupLayout.origin(size: size, target: target,
                                        mouse: NSEvent.mouseLocation, visible: visible)
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    /// Selects row `i`, scrolling just enough to keep it visible.
    func select(_ i: Int) {
        list.selected = i
        list.scrollOffset = PopupLayout.scrollOffset(keeping: i, current: list.scrollOffset,
                                                     itemCount: list.items.count)
    }

    /// Scrolls by whole rows (positive = further down the list). Keeps the selection on screen.
    func scroll(byRows delta: Int) {
        let n = list.items.count
        list.scrollOffset = PopupLayout.clampOffset(list.scrollOffset + delta, itemCount: n)
        let visible = list.visibleRows
        if list.selected < list.scrollOffset { list.selected = list.scrollOffset }
        if list.selected >= list.scrollOffset + visible { list.selected = list.scrollOffset + visible - 1 }
    }

    var scrollOffset: Int { list.scrollOffset }

    /// Refreshes the items in place (e.g. a YouTube title arrived) without moving the popup.
    func refresh(items: [ClipItem], footerInfo: String) {
        list.items = items
        list.footerInfo = footerInfo
    }
    var selectedIndex: Int { list.selected }

    func setClearArmed(_ armed: Bool) { list.clearArmed = armed }

    /// What's under a screen point (Cocoa coordinates), if anything.
    func hit(at point: NSPoint) -> PopupHit? {
        guard isVisible, frame.contains(point) else { return nil }
        let fromTop = frame.maxY - point.y
        if fromTop >= list.footerTop { return .clear }
        let row = Int(floor((fromTop - 6) / Config.rowHeight))
        guard row >= 0, row < list.visibleRows else { return nil }
        let i = list.scrollOffset + row
        return list.items.indices.contains(i) ? .item(i) : nil
    }
}
