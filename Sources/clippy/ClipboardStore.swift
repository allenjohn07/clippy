import Cocoa
import CryptoKit

/// Watches the system pasteboard and keeps the history (backed by SQLite).
final class ClipboardStore {
    private(set) var items: [ClipItem] = []
    /// Called on the main thread when an item changes in the background (YouTube title/thumbnail arrived).
    var onChange: (() -> Void)?

    private var lastChange = NSPasteboard.general.changeCount
    private let database: HistoryDatabase?
    private var nextLocalID: Int64 = -1   // ids for items when running without a database

    init(database: HistoryDatabase?) {
        self.database = database
        reload()
        // Clean out blank-looking entries saved by older versions.
        for item in items where item.kind == .text && !TextFilter.isMeaningful(item.text) {
            database?.delete(id: item.id)
        }
        items.removeAll { $0.kind == .text && !TextFilter.isMeaningful($0.text) }
    }

    private func reload() {
        items = (database?.recent(limit: Config.maxStoredItems) ?? []).map { row in
            ClipItem(id: row.id, kind: ClipItem.Kind(rawValue: row.kind) ?? .text,
                     text: row.kind == "image" ? "" : row.content, title: row.title,
                     thumbnail: row.thumbnail.flatMap(NSImage.init(data:)),
                     pixelSize: row.width.flatMap { w in row.height.map { CGSize(width: w, height: $0) } })
        }
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: Config.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = Config.pollTolerance
        // YouTube links whose thumbnail couldn't be fetched earlier get one more try per launch.
        for item in items where item.kind == .youtube && item.thumbnail == nil { fetchYouTube(item) }
    }

    // MARK: - Capturing

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        capture(from: pb, frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Records whatever is on `pb`, unless it's private, empty, or looks like a password.
    func capture(from pb: NSPasteboard, frontApp: String?) {
        let types = (pb.types ?? []).map { $0.rawValue }
        if types.contains(where: { Config.ignoredPasteboardTypes.contains($0) }) { return }
        if let app = frontApp, Config.passwordApps.contains(app) { return }

        let hasImage = Config.imageTypes.contains { types.contains($0.rawValue) }
        if let text = pb.string(forType: .string), TextFilter.isMeaningful(text),
           !(hasImage && TextFilter.isSingleURL(text)) {      // browser "Copy Image" also puts the URL
            if SecretFilter.looksLikeSecret(text) { return }
            addText(text)
        } else if hasImage {
            addImage(from: pb)
        }
    }

    private func addText(_ text: String) {
        let isYouTube = YouTube.videoID(from: text) != nil
        let previous = items.first { $0.kind != .image && $0.text == text }
        let id = database?.record(text, kind: isYouTube ? "youtube" : "text") ?? previous?.id ?? newLocalID()
        let item = ClipItem(id: id, kind: isYouTube ? .youtube : .text, text: text,
                            title: previous?.title, thumbnail: previous?.thumbnail, pixelSize: nil)
        moveToTop(item)
        if item.kind == .youtube && item.thumbnail == nil { fetchYouTube(item) }
    }

    private func addImage(from pb: NSPasteboard) {
        guard let database else { return }   // images only make sense with storage
        guard let (png, rep) = Self.pngData(from: pb), png.count <= Config.maxImageBytes else { return }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let thumb = Self.thumbnailJPEG(from: rep)
        guard let id = database.recordImage(png: png, thumbnail: thumb, width: rep.pixelsWide,
                                            height: rep.pixelsHigh, hash: hash) else { return }
        moveToTop(ClipItem(id: id, kind: .image, text: "", thumbnail: thumb.flatMap(NSImage.init(data:)),
                           pixelSize: CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)))
        // Respect the image cap in memory too.
        let imageIDs = items.filter { $0.kind == .image }.map(\.id)
        if imageIDs.count > Config.maxStoredImages {
            let drop = Set(imageIDs.dropFirst(Config.maxStoredImages))
            items.removeAll { drop.contains($0.id) }
        }
    }

    private func moveToTop(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > Config.maxStoredItems { items.removeLast(items.count - Config.maxStoredItems) }
    }

    private func newLocalID() -> Int64 { defer { nextLocalID -= 1 }; return nextLocalID }

    // MARK: - Images

    /// PNG bytes plus a bitmap of whatever image is on the pasteboard.
    static func pngData(from pb: NSPasteboard) -> (Data, NSBitmapImageRep)? {
        if let png = pb.data(forType: .png), let rep = NSBitmapImageRep(data: png) { return (png, rep) }
        guard let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, rep)
    }

    /// A small JPEG used for the list icon and the preview panel.
    static func thumbnailJPEG(from rep: NSBitmapImageRep) -> Data? {
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, Config.thumbnailMaxPixels / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor.white.setFill()                       // JPEG has no transparency
        NSRect(x: 0, y: 0, width: tw, height: th).fill()
        rep.draw(in: NSRect(x: 0, y: 0, width: tw, height: th), from: .zero, operation: .sourceOver,
                 fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Full PNG bytes of an image item (read from disk).
    func imageData(for item: ClipItem) -> Data? { database?.imageData(id: item.id) }

    // MARK: - YouTube

    private func fetchYouTube(_ item: ClipItem) {
        guard Config.networkEnabled, let videoID = YouTube.videoID(from: item.text) else { return }
        let id = item.id, url = item.text
        Task {
            let (title, thumb) = await YouTube.fetchMetadata(url: url, videoID: videoID)
            await MainActor.run {
                guard title != nil || thumb != nil else { return }
                self.database?.updateYouTube(id: id, title: title, thumbnail: thumb)
                if let i = self.items.firstIndex(where: { $0.id == id }) {
                    if let title { self.items[i].title = title }
                    if let thumb { self.items[i].thumbnail = NSImage(data: thumb) }
                }
                self.onChange?()
            }
        }
    }

    // MARK: - Other

    /// Bytes the history takes on disk (0 when running without a database).
    var storageBytes: Int64 { database?.fileSize() ?? 0 }

    /// Deletes all history (in memory and on disk).
    func clear() {
        items.removeAll()
        database?.clearAll()
    }

    /// Puts `item` on the pasteboard (without recording it as a fresh copy) and moves it
    /// to the top. Returns false if there was nothing to paste.
    @discardableResult
    func paste(_ item: ClipItem) -> Bool {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text, .youtube:
            pb.clearContents()
            pb.setString(item.text, forType: .string)
        case .image:
            guard let png = imageData(for: item) else { return false }
            pb.clearContents()
            pb.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
        lastChange = pb.changeCount
        database?.touch(id: item.id)
        moveToTop(item)
        return true
    }
}
