import Cocoa

/// Larger preview of the highlighted item, shown beside the list.
final class PreviewView: NSView {
    static let width: CGFloat = 340
    private static let pad: CGFloat = 12
    private static let contentWidth = width - 2 * pad
    private static let maxImageHeight: CGFloat = 240
    private static let maxTextLines = 14

    var item: ClipItem? { didSet { needsDisplay = true } }
    /// Extra caption for images (e.g. byte size), filled in by the controller.
    var imageBytes: Int?
    override var isFlipped: Bool { true }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let textFont = NSFont.systemFont(ofSize: 12)
    private static let captionFont = NSFont.systemFont(ofSize: 11)

    /// Height needed for `item`.
    static func height(for item: ClipItem) -> CGFloat {
        switch item.kind {
        case .image:
            return pad + imageSize(item).height + 8 + 14 + pad
        case .youtube:
            return pad + contentWidth * 9 / 16 + 8 + 36 + 14 + pad
        case .text:
            let lines = min(maxTextLines, max(1, textLineCount(item.text)))
            return pad + CGFloat(lines) * 16 + 8 + 14 + pad
        }
    }

    private static func imageSize(_ item: ClipItem) -> NSSize {
        let s = item.pixelSize ?? item.thumbnail?.size ?? NSSize(width: 4, height: 3)
        guard s.width > 0, s.height > 0 else { return NSSize(width: contentWidth, height: 120) }
        let scale = min(contentWidth / s.width, maxImageHeight / s.height)
        return NSSize(width: s.width * scale, height: s.height * scale)
    }

    /// Rough count of wrapped lines, so short text gets a short panel.
    private static func textLineCount(_ text: String) -> Int {
        let charsPerLine = 48
        return String(text.prefix(4000)).split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + charsPerLine - 1) / charsPerLine) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let pad = Self.pad, w = Self.contentWidth
        var y = pad

        func caption(_ s: String) {
            (s as NSString).draw(in: NSRect(x: pad, y: y, width: w, height: 14),
                                 withAttributes: [.font: Self.captionFont, .foregroundColor: NSColor.secondaryLabelColor])
        }
        func picture(_ image: NSImage?, size: NSSize, fill: Bool) {
            let box = NSRect(x: pad + (w - size.width) / 2, y: y, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).addClip()
            if let image {
                let target = fill ? ListView.aspectFill(image.size, in: box) : box
                image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                NSColor.quaternaryLabelColor.setFill()
                box.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        switch item.kind {
        case .image:
            let size = Self.imageSize(item)
            picture(item.thumbnail, size: size, fill: false)
            y += size.height + 8
            var parts: [String] = []
            if let s = item.pixelSize { parts.append("\(Int(s.width))×\(Int(s.height))") }
            parts.append("PNG")
            if let b = imageBytes { parts.append(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)) }
            caption(parts.joined(separator: " · "))

        case .youtube:
            let size = NSSize(width: w, height: w * 9 / 16)
            picture(item.thumbnail, size: size, fill: true)
            ListView.drawPlayBadge(in: NSRect(x: pad + w / 2 - 22, y: y + size.height / 2 - 15, width: 44, height: 30))
            y += size.height + 8
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byWordWrapping
            ((item.title ?? item.text) as NSString).draw(
                with: NSRect(x: pad, y: y, width: w, height: 36),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: Self.titleFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para],
                context: nil)
            y += 36
            caption("youtube.com")

        case .text:
            let lines = min(Self.maxTextLines, max(1, Self.textLineCount(item.text)))
            let height = CGFloat(lines) * 16
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byWordWrapping
            para.minimumLineHeight = 16
            para.maximumLineHeight = 16
            (String(item.text.prefix(4000)) as NSString).draw(
                with: NSRect(x: pad, y: y, width: w, height: height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: Self.textFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para],
                context: nil)
            y += height + 8
            let lineCount = item.text.split(separator: "\n", omittingEmptySubsequences: false).count
            caption("\(item.text.count) characters · \(lineCount) line\(lineCount == 1 ? "" : "s")")
        }
    }
}

/// Floating, click-through panel that hosts the preview.
final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    let preview = PreviewView()
    private let effect = NSVisualEffectView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PreviewView.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.frame = NSRect(x: 0, y: 0, width: PreviewView.width, height: 100)
        preview.frame = effect.bounds
        preview.autoresizingMask = [.width, .height]
        effect.addSubview(preview)
        contentView = effect
    }

    /// Shows `item` beside the list panel at `listFrame`.
    func show(_ item: ClipItem, imageBytes: Int?, beside listFrame: NSRect) {
        preview.item = item
        preview.imageBytes = imageBytes
        let size = NSSize(width: PreviewView.width, height: PreviewView.height(for: item))
        let probe = NSPoint(x: listFrame.midX, y: listFrame.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(probe, $0.frame, false) } ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 8, dy: 8)
        let origin = PopupLayout.previewOrigin(listFrame: listFrame, previewSize: size, visible: visible)
        setFrame(NSRect(origin: origin, size: size), display: true)
        preview.needsDisplay = true
        orderFrontRegardless()
    }
}
