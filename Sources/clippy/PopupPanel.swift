import Cocoa

/// What a click inside the popup landed on.
enum PopupHit: Equatable {
    case item(Int)
    case clear
}

/// Draws the list of clipboard entries and the "Clear history" footer.
final class ListView: NSView {
    var items: [String] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
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

    /// Y offset (from the top) where the footer starts.
    var footerTop: CGFloat { 6 + CGFloat(items.count) * Config.rowHeight + 3 }

    override func draw(_ dirtyRect: NSRect) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail

        for (i, item) in items.enumerated() {
            let rect = NSRect(x: 6, y: 6 + CGFloat(i) * Config.rowHeight,
                              width: bounds.width - 12, height: Config.rowHeight)
            let isSel = (i == selected)
            if isSel {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            let color: NSColor = isSel ? .white : .labelColor
            let dim: NSColor = isSel ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor

            let num = i < 9 ? "\(i + 1)" : " "
            (num as NSString).draw(
                in: NSRect(x: rect.minX + 8, y: rect.minY + 5, width: 16, height: 16),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                 .foregroundColor: dim])

            (display(item) as NSString).draw(
                in: NSRect(x: rect.minX + 30, y: rect.minY + 5, width: rect.width - 40, height: 16),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13),
                                 .foregroundColor: color,
                                 .paragraphStyle: para])
        }

        // Separator + footer.
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: footerTop, width: bounds.width - 24, height: 1).fill()

        let label = clearArmed ? "Click again (or ⌫) to delete all history" : "Clear history"
        let hint = clearArmed ? "" : "⌫"
        let labelColor: NSColor = clearArmed ? .systemRed : .secondaryLabelColor
        (label as NSString).draw(
            in: NSRect(x: 20, y: footerTop + 7, width: bounds.width - 70, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: clearArmed ? .semibold : .regular),
                             .foregroundColor: labelColor])
        (hint as NSString).draw(
            in: NSRect(x: bounds.width - 36, y: footerTop + 7, width: 20, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor])
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

    func show(items: [String], selected: Int, target: PasteTarget) {
        list.items = items
        list.selected = selected
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

    func select(_ i: Int) { list.selected = i }

    func setClearArmed(_ armed: Bool) { list.clearArmed = armed }

    /// What's under a screen point (Cocoa coordinates), if anything.
    func hit(at point: NSPoint) -> PopupHit? {
        guard isVisible, frame.contains(point) else { return nil }
        let fromTop = frame.maxY - point.y
        if fromTop >= list.footerTop { return .clear }
        let i = Int(floor((fromTop - 6) / Config.rowHeight))
        return list.items.indices.contains(i) ? .item(i) : nil
    }
}
