import Cocoa
import Testing
@testable import clippy

@Suite("PopupLayout")
struct PopupLayoutTests {
    // A 1440×900 screen (Cocoa coordinates: origin bottom-left).
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = NSSize(width: 420, height: 200)
    let gap: CGFloat = 6
    let mouse = NSPoint(x: 700, y: 450)

    func origin(_ target: PasteTarget, visible: NSRect? = nil) -> NSPoint {
        PopupLayout.origin(size: size, target: target, mouse: mouse, visible: visible ?? screen, gap: gap)
    }

    @Test func placedBelowInputWhenThereIsRoom() {
        let input = NSRect(x: 100, y: 600, width: 300, height: 30)
        let o = origin(PasteTarget(inputFrame: input, caret: nil))
        #expect(o.x == 100)
        #expect(o.y == input.minY - gap - size.height)       // top edge sits just under the input
        #expect(o.y + size.height <= input.minY)               // never overlaps the input
    }

    @Test func flipsAboveInputNearBottomOfScreen() {
        let input = NSRect(x: 100, y: 40, width: 300, height: 30)
        let o = origin(PasteTarget(inputFrame: input, caret: nil))
        #expect(o.y == input.maxY + gap)                       // bottom edge sits just above the input
    }

    @Test func tallInputFallsBackToCaretLine() {
        // A full-height editor: no room above or below it.
        let editor = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 300, y: 500, width: 0, height: 16)
        let o = origin(PasteTarget(inputFrame: editor, caret: caret))
        #expect(o.x == 300)
        #expect(o.y == caret.minY - gap - size.height)
    }

    @Test func caretNearBottomFlipsAboveCaret() {
        let editor = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: 300, y: 50, width: 0, height: 16)
        let o = origin(PasteTarget(inputFrame: editor, caret: caret))
        #expect(o.y == caret.maxY + gap)
    }

    @Test func noPositionInfoUsesMouse() {
        let o = origin(PasteTarget(inputFrame: nil, caret: nil))
        #expect(o.x == mouse.x)
        #expect(o.y == mouse.y - gap - size.height)
    }

    @Test func clampedToRightEdge() {
        let input = NSRect(x: 1300, y: 600, width: 100, height: 30)
        let o = origin(PasteTarget(inputFrame: input, caret: nil))
        #expect(o.x + size.width <= screen.maxX)
    }

    @Test func clampedToLeftEdge() {
        let input = NSRect(x: -50, y: 600, width: 100, height: 30)
        let o = origin(PasteTarget(inputFrame: input, caret: nil))
        #expect(o.x >= screen.minX)
    }

    @Test func worksOnSecondaryScreenWithOffsetOrigin() {
        // Monitor to the right of the main one.
        let second = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let input = NSRect(x: 1600, y: 700, width: 300, height: 30)
        let o = origin(PasteTarget(inputFrame: input, caret: nil), visible: second)
        #expect(o.x == 1600)
        #expect(second.contains(NSRect(origin: o, size: size)))
    }

    @Test(arguments: [0, 1, 5, 10])
    func heightGrowsWithItems(count: Int) {
        let h = PopupLayout.height(itemCount: count)
        #expect(h == CGFloat(count) * Config.rowHeight + 12 + Config.footerHeight)
    }
}
