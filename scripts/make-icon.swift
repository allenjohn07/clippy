// Draws the Clippy icon (two overlapping pages on a dark rounded square) and writes:
//   assets/logo.png            512×512, for the README
//   Resources/AppIcon.icns     all macOS app icon sizes
//
// Run:  swift scripts/make-icon.swift
// The shapes are drawn by hand (not SF Symbols, whose license excludes app icons/logos).
import Cocoa

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A page with rounded corners and a folded top-right corner.
func pagePath(_ r: NSRect, radius: CGFloat, fold: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX + radius, y: r.minY))
    p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
    p.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
                startAngle: 270, endAngle: 0)
    p.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    p.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    p.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
    p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                startAngle: 90, endAngle: 180)
    p.line(to: NSPoint(x: r.minX, y: r.minY + radius))
    p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
                startAngle: 180, endAngle: 270)
    p.close()
    p.lineJoinStyle = .round
    return p
}

/// The little folded-over flap in the corner.
func flapPath(_ r: NSRect, fold: CGFloat) -> NSBezierPath {
    let inset: CGFloat = fold * 0.18
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    p.line(to: NSPoint(x: r.maxX - fold, y: r.maxY - fold + inset))
    p.curve(to: NSPoint(x: r.maxX - fold + inset, y: r.maxY - fold),
            controlPoint1: NSPoint(x: r.maxX - fold, y: r.maxY - fold),
            controlPoint2: NSPoint(x: r.maxX - fold, y: r.maxY - fold))
    p.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    p.close()
    p.lineJoinStyle = .round
    return p
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)   // draw in a 1024-point space at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Background squircle, following Apple's macOS icon grid (824pt body in a 1024 canvas).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1C1C1E).setFill()
    bg.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x4A4A4E), ending: color(0x1A1A1C))!.draw(in: bg, angle: -90)
    color(0xFFFFFF, 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
    rim.lineWidth = 6
    rim.stroke()

    // Two pages, the back one up and to the right.
    let w: CGFloat = 330, h: CGFloat = 420, radius: CGFloat = 38, fold: CGFloat = 112
    let back = NSRect(x: 395, y: 362, width: w, height: h)
    let front = NSRect(x: 300, y: 242, width: w, height: h)

    color(0xFFFFFF, 0.55).setFill()
    pagePath(back, radius: radius, fold: fold).fill()
    color(0x8E8E93, 0.9).setFill()
    flapPath(back, fold: fold).fill()

    // A dark outline around the front page separates it from the back one.
    let frontPath = pagePath(front, radius: radius, fold: fold)
    color(0x2E2E31).setStroke()
    frontPath.lineWidth = 30
    frontPath.stroke()
    NSColor.white.setFill()
    frontPath.fill()
    color(0xC7C7CC).setFill()
    flapPath(front, fold: fold).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// README logo
writePNG(drawIcon(size: 512), to: root.appendingPathComponent("assets/logo.png"))

// App icon: build an .iconset and convert it with iconutil.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(drawIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let icns = root.appendingPathComponent("Resources/AppIcon.icns")
try! FileManager.default.createDirectory(at: icns.deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote assets/logo.png and Resources/AppIcon.icns" : "iconutil failed")
exit(p.terminationStatus)
