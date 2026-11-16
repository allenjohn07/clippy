import Cocoa

/// One entry in the history. Full image bytes are not kept here; they're read from the
/// database only when pasting.
struct ClipItem {
    enum Kind: String { case text, image, youtube }

    let id: Int64
    var kind: Kind
    /// The text, or the URL for YouTube links. Empty for images.
    var text: String
    /// Video title for YouTube links (fetched in the background).
    var title: String?
    /// Small preview: image thumbnail or YouTube thumbnail.
    var thumbnail: NSImage?
    /// Pixel size of an image.
    var pixelSize: CGSize?

    /// One-line label used in the list.
    var label: String {
        switch kind {
        case .text:
            return text
        case .image:
            if let s = pixelSize { return "Image · \(Int(s.width))×\(Int(s.height))" }
            return "Image"
        case .youtube:
            return title ?? text
        }
    }
}
