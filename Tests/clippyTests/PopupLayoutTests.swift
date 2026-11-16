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

    @Test(arguments: [0, 1, 5, 9, 10, 500])
    func heightShowsAtMostNineRows(count: Int) {
        let rows = min(count, 9)
        #expect(PopupLayout.height(itemCount: count) == CGFloat(rows) * Config.rowHeight + 12 + Config.footerHeight)
    }

    @Test func scrollingDownKeepsSelectionAtBottomRow() {
        // 20 items, 9 visible: selecting row 9 (the 10th) scrolls by one.
        #expect(PopupLayout.scrollOffset(keeping: 8, current: 0, itemCount: 20) == 0)
        #expect(PopupLayout.scrollOffset(keeping: 9, current: 0, itemCount: 20) == 1)
        #expect(PopupLayout.scrollOffset(keeping: 19, current: 0, itemCount: 20) == 11)
    }

    @Test func scrollingUpKeepsSelectionAtTopRow() {
        #expect(PopupLayout.scrollOffset(keeping: 5, current: 10, itemCount: 20) == 5)
        #expect(PopupLayout.scrollOffset(keeping: 0, current: 11, itemCount: 20) == 0)   // wrap to top
    }

    @Test func selectionAlreadyVisibleDoesNotScroll() {
        #expect(PopupLayout.scrollOffset(keeping: 7, current: 3, itemCount: 20) == 3)
    }

    @Test func scrollOffsetIsClamped() {
        #expect(PopupLayout.clampOffset(-4, itemCount: 20) == 0)
        #expect(PopupLayout.clampOffset(50, itemCount: 20) == 11)
        #expect(PopupLayout.clampOffset(3, itemCount: 5) == 0)          // fits on screen: no scrolling
    }

    @Test func previewGoesRightOfTheList() {
        let list = NSRect(x: 100, y: 400, width: 420, height: 200)
        let o = PopupLayout.previewOrigin(listFrame: list, previewSize: NSSize(width: 340, height: 150), visible: screen)
        #expect(o.x == list.maxX + 8)
        #expect(o.y + 150 == list.maxY)                 // top-aligned
    }

    @Test func previewFlipsLeftNearTheRightEdge() {
        let list = NSRect(x: 1000, y: 400, width: 420, height: 200)
        let o = PopupLayout.previewOrigin(listFrame: list, previewSize: NSSize(width: 340, height: 150), visible: screen)
        #expect(o.x + 340 <= list.minX)
    }

    @Test func previewStaysOnScreen() {
        let list = NSRect(x: 100, y: 10, width: 420, height: 100)   // tall preview, list near bottom
        let o = PopupLayout.previewOrigin(listFrame: list, previewSize: NSSize(width: 340, height: 300), visible: screen)
        #expect(o.y >= screen.minY)
    }

    @Test func footerInfoText() {
        #expect(PopupLayout.footerInfo(count: 1, bytes: 0).hasPrefix("1 item · "))
        let s = PopupLayout.footerInfo(count: 245, bytes: 1_200_000)
        #expect(s.hasPrefix("245 items · "))
        #expect(s.contains("MB"))
    }
}
