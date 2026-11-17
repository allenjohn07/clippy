// Native end-to-end tests. Opens real windows with text inputs, drives them with real
// keyboard/mouse events, and checks what Clippy does (popup position, what gets pasted,
// what's in the database).
//
//   harness <phase A|B> <clippy pid> <database path>
//
// Phase A runs against a fresh Clippy; phase B runs after scripts/e2e.sh restarts it
// (to prove history survives a restart).
import Cocoa

let args = CommandLine.arguments
guard args.count == 4, pid_t(args[2]) != nil else {
    print("usage: harness <A|B> <clippy pid> <db path>"); exit(2)
}
let phase = args[1]
let clippyPid = pid_t(args[2])!
let dbPath = args[3]

final class Harness: NSObject, NSApplicationDelegate {
    var topWindow: NSWindow!
    var bottomWindow: NSWindow!
    var field: NSTextField!
    var scroll: NSScrollView!
    var textView: NSTextView!
    var passed = 0
    var failed = 0

    // MARK: Setup

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            phase == "A" ? self.phaseA() : self.phaseB()
            print("\n\(self.passed) passed, \(self.failed) failed (phase \(phase))")
            exit(self.failed == 0 ? 0 : 1)
        }
    }

    /// A real Edit menu, so ⌘V pastes like in any normal app.
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func buildWindows() {
        let vis = NSScreen.main!.visibleFrame

        // Near the top of the screen: popup should open *below* the field.
        topWindow = NSWindow(contentRect: NSRect(x: vis.minX + 120, y: vis.maxY - 200, width: 640, height: 140),
                             styleMask: [.titled], backing: .buffered, defer: false)
        topWindow.title = "Clippy E2E — top"
        topWindow.level = .floating        // above the terminal, so our clicks land on it
        field = NSTextField(frame: NSRect(x: 20, y: 70, width: 400, height: 24))
        topWindow.contentView!.addSubview(field)
        topWindow.makeKeyAndOrderFront(nil)

        // Near the bottom of the screen: popup should open *above* the text area.
        bottomWindow = NSWindow(contentRect: NSRect(x: vis.minX + 120, y: vis.minY + 10, width: 640, height: 110),
                                styleMask: [.titled], backing: .buffered, defer: false)
        bottomWindow.title = "Clippy E2E — bottom"
        bottomWindow.level = .floating
        scroll = NSScrollView(frame: NSRect(x: 20, y: 15, width: 400, height: 70))
        textView = NSTextView(frame: scroll.bounds)
        textView.isRichText = true
        textView.importsGraphics = true     // so pasted images show up as attachments
        scroll.documentView = textView
        scroll.borderType = .bezelBorder
        bottomWindow.contentView!.addSubview(scroll)
        bottomWindow.orderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func heightFor(items n: Int) -> CGFloat { CGFloat(min(n, 9)) * 26 + 12 + 30 }

    // MARK: Helpers

    /// Waits while still delivering keyboard/mouse events to our windows
    /// (a plain RunLoop wait would leave them queued).
    func wait(_ s: Double) {
        let end = Date().addingTimeInterval(s)
        while Date() < end {
            if let e = NSApp.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.01)),
                                       inMode: .default, dequeue: true) {
                NSApp.sendEvent(e)
            }
        }
    }

    @discardableResult
    func waitFor(_ timeout: Double = 2.5, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            wait(0.05)
        }
        return cond()
    }

    func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("  ✔ \(name)") }
        else { failed += 1; print("  ✘ \(name)  \(detail())") }
    }

    /// Screen rect of a view in CG coordinates (top-left origin), like CGWindowList uses.
    func cgRect(_ v: NSView) -> CGRect {
        let r = v.window!.convertToScreen(v.convert(v.bounds, to: nil))
        let h = NSScreen.screens[0].frame.height
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    var fieldText: String { field.currentEditor()?.string ?? field.stringValue }

    func clearField() {
        field.stringValue = ""
        field.currentEditor()?.string = ""
    }

    func popup() -> CGRect? { E2E.popupFrame(pid: clippyPid) }

    /// Safety: never type unless *we* are the frontmost app.
    func ensureFront() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if front != ProcessInfo.processInfo.processIdentifier {
            print("  ✘ ABORT: test window is not frontmost (front pid \(front ?? -1)); not sending keys")
            exit(3)
        }
    }

    func key(_ spec: String) { ensureFront(); E2E.key(spec) }

    func focusField() {
        let r = cgRect(field)
        E2E.click(CGPoint(x: r.midX, y: r.midY))
        waitFor { self.topWindow.firstResponder === self.field.currentEditor() }
        clearField()
    }

    func openPopup() -> CGRect? {
        key("cmd+shift+v")
        waitFor { self.popup() != nil }
        return popup()
    }

    func popupClosed() -> Bool { waitFor { self.popup() == nil } }

    func db(_ sql: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [dbPath, sql]
        let out = Pipe(); p.standardOutput = out
        try! p.run(); p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return s.split(separator: "\n").map(String.init)
    }

    /// Database + write-ahead log size in bytes (what the footer reports).
    func diskSize() -> Int {
        [dbPath, dbPath + "-wal"].reduce(0) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0)
        }
    }

    func history() -> [String] { db("SELECT content FROM clips ORDER BY last_used_at DESC;") }

    let expectedHeight: CGFloat = 3 * 26 + 12 + 30   // 3 rows + padding + footer

    // MARK: Phase A

    func phaseA() {
        print("Recording copies")
        for s in ["alpha", "bravo", "charlie"] { E2E.copy(s); wait(0.9) }
        check("copies are saved newest-first", waitFor { self.history() == ["charlie", "bravo", "alpha"] },
              "got \(history())")

        E2E.copy("secret-xyz", extraTypes: ["org.nspasteboard.ConcealedType"]); wait(1.0)
        check("password-manager copies are not saved", !history().contains("secret-xyz"), "got \(history())")
        E2E.copy("charlie"); wait(0.9)

        print("Plain ⌘V")
        focusField()
        key("cmd+v")
        check("⌘V pastes normally", waitFor { self.fieldText == "charlie" }, "field=\(fieldText)")
        wait(0.4)
        check("⌘V does not open the popup", popup() == nil)

        print("⌘⇧V popup")
        clearField()
        if let p = openPopup() {
            let f = cgRect(field)
            check("popup opens", true)
            check("popup sits just below the field", p.minY >= f.maxY && p.minY - f.maxY < 20,
                  "popup=\(p) field=\(f)")
            check("popup is left-aligned with the field", abs(p.minX - f.minX) < 2, "popup=\(p) field=\(f)")
            check("popup shows 3 items + footer", abs(p.height - expectedHeight) < 1, "height=\(p.height)")
            if waitFor(2.5, { E2E.previewFrame(pid: clippyPid) != nil }), let pv = E2E.previewFrame(pid: clippyPid) {
                check("preview panel sits beside the list", !pv.intersects(p) && abs(pv.minY - p.minY) < 2,
                      "preview=\(pv) popup=\(p)")
            } else { check("preview panel appears", false) }
        } else { check("popup opens", false) }

        key("2")
        check("pressing 2 pastes the 2nd item", waitFor { self.fieldText == "bravo" }, "field=\(fieldText)")
        check("popup closes after pasting", popupClosed())
        check("pasted item moves to the top", waitFor { self.history().first == "bravo" }, "got \(history())")

        print("Esc")
        clearField()
        _ = openPopup()
        key("esc")
        check("Esc closes the popup", popupClosed())
        wait(0.3)
        check("Esc pastes nothing", fieldText.isEmpty, "field=\(fieldText)")

        print("Arrow keys + Return")
        _ = openPopup()          // order now: bravo, charlie, alpha
        key("down")
        key("return")
        check("↓ then Return pastes the 2nd item", waitFor { self.fieldText == "charlie" }, "field=\(fieldText)")
        check("popup closes", popupClosed())

        print("Mouse")
        clearField()
        if let p = openPopup() { // order now: charlie, bravo, alpha
            E2E.click(CGPoint(x: p.minX + 120, y: p.minY + 6 + 2 * 26 + 13))
            check("clicking a row pastes it", waitFor { self.fieldText == "alpha" }, "field=\(fieldText)")
            check("popup closes after click", popupClosed())
        } else { check("popup opens for click test", false) }

        clearField()
        _ = openPopup()
        let tw = cgRect(topWindow.contentView!)
        // Top-left of the window: above the field, so clear of both the list and the preview.
        E2E.click(CGPoint(x: tw.minX + 15, y: tw.minY + 15))
        check("clicking outside closes the popup", popupClosed())
        check("clicking outside pastes nothing", fieldText.isEmpty, "field=\(fieldText)")

        print("Other keys")
        focusField()
        _ = openPopup()
        key("x")
        check("typing another key closes the popup", popupClosed())
        check("…and the key is typed normally", waitFor { self.fieldText == "x" }, "field=\(fieldText)")

        print("Input near the bottom of the screen")
        let s = cgRect(scroll)
        E2E.click(CGPoint(x: s.midX, y: s.midY))
        waitFor { self.bottomWindow.firstResponder === self.textView }
        wait(0.3)   // macOS takes a moment to report the new focus to other apps; people are never this fast
        textView.string = ""
        if let p = openPopup() {
            check("popup flips above the input", p.maxY <= s.minY && s.minY - p.maxY < 20, "popup=\(p) input=\(s)")
        } else { check("popup opens near bottom of screen", false) }
        key("1")
        check("pastes into a multi-line text area", waitFor { self.textView.string == "alpha" },
              "text=\(textView.string)")

        print("Nothing typeable focused")
        E2E.click(CGPoint(x: tw.maxX - 60, y: tw.maxY - 20))
        topWindow.makeKeyAndOrderFront(nil)
        topWindow.makeFirstResponder(nil)
        wait(0.3)
        key("cmd+shift+v")
        wait(0.8)
        check("no popup when nothing typeable is focused", popup() == nil)
        if popup() != nil { key("esc"); _ = popupClosed() }
    }

    // MARK: Phase B (after Clippy was restarted)

    func phaseB() {
        print("After restart")
        let saved = history()
        check("database still has the history", saved.count >= 3, "got \(saved)")
        focusField()
        if let p = openPopup() {
            check("popup lists the saved history after restart",
                  abs(p.height - heightFor(items: saved.count)) < 1, "height=\(p.height) items=\(saved.count)")
        } else { check("history survives a restart (popup opens)", false) }
        key("1")
        check("newest item is still first", waitFor { self.fieldText == saved.first },
              "field=\(fieldText) expected=\(saved.first ?? "")")

        print("Things that should not be saved")
        let before = history()
        E2E.copy("  \n\u{200B} "); wait(0.9)
        E2E.copy("Tr0ub4dor&3"); wait(0.9)
        E2E.copy("ghp_" + String(repeating: "a1B2", count: 9)); wait(0.9)
        check("blank and password-like copies are not saved", history() == before,
              "new rows: \(history().filter { !before.contains($0) })")
        E2E.copy("hello world"); wait(0.9)
        check("normal text copied right after is saved", waitFor { self.history().first == "hello world" },
              "first=\(history().first ?? "")")

        print("Images")
        E2E.copyImage(png: E2E.makePNG(width: 200, height: 100, color: .systemRed)); wait(1.0)
        check("copied image is saved", waitFor {
            self.db("SELECT kind || ':' || width || 'x' || height FROM clips ORDER BY last_used_at DESC LIMIT 1;")
                == ["image:200x100"] }, "got \(db("SELECT kind FROM clips ORDER BY last_used_at DESC LIMIT 1;"))")
        let s2 = cgRect(scroll)
        E2E.click(CGPoint(x: s2.midX, y: s2.midY))
        waitFor { self.bottomWindow.firstResponder === self.textView }
        wait(0.3)
        textView.string = ""
        if let p = openPopup() {
            if waitFor(2.5, { E2E.previewFrame(pid: clippyPid) != nil }), let pv = E2E.previewFrame(pid: clippyPid) {
                check("image preview shows beside the list", !pv.intersects(p), "preview=\(pv) popup=\(p)")
            } else { check("image preview appears", false) }
        } else { check("popup opens for image test", false) }
        key("1")
        check("pasting puts the image into the document",
              waitFor { self.textView.textStorage?.containsAttachments ?? false })
        check("preview closes with the popup", waitFor { E2E.previewFrame(pid: clippyPid) == nil })

        print("Image file copied in Finder")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-e2e-\(UUID().uuidString).png")
        try? E2E.makePNG(width: 300, height: 150, color: .systemBlue).write(to: file)
        E2E.copyFile(file); wait(1.0)
        check("Finder image file is saved as a picture", waitFor {
            self.db("SELECT kind || ':' || width || 'x' || height FROM clips ORDER BY last_used_at DESC LIMIT 1;")
                == ["image:300x150"] }, "got \(db("SELECT kind, content FROM clips ORDER BY last_used_at DESC LIMIT 1;"))")
        try? FileManager.default.removeItem(at: file)

        print("YouTube (needs internet)")
        let yt = "https://youtu.be/dQw4w9WgXcQ"
        E2E.copy(yt)
        let fetched = waitFor(15) {
            self.db("SELECT kind || ':' || (title IS NOT NULL) || ':' || (thumb IS NOT NULL) FROM clips WHERE content = '\(yt)';")
                == ["youtube:1:1"]
        }
        check("YouTube link gets its title and thumbnail", fetched,
              "row=\(db("SELECT kind, title IS NOT NULL, thumb IS NOT NULL FROM clips WHERE content = '\(yt)';"))")

        print("Scrolling past 9 items")
        // Text on top, so the rows these checks paste into a text field are all text (not images).
        for i in 1...6 { E2E.copy("scroll text \(i)"); wait(0.9) }
        var h = history()
        check("enough history to scroll", h.count > 9, "count=\(h.count)")
        focusField()
        if let p = openPopup() {
            check("popup shows 9 rows at most", abs(p.height - heightFor(items: h.count)) < 1, "height=\(p.height)")
        }
        for _ in 0..<10 { key("down") }
        key("return")
        check("↓ ten times then Return pastes the 11th item", waitFor { self.fieldText == h[10] },
              "field=\(fieldText) expected=\(h[10])")
        check("popup closes", popupClosed())

        h = history()
        clearField()
        if let p = openPopup() {
            E2E.scroll(pixels: -3 * 26, at: CGPoint(x: p.midX, y: p.minY + 60))
            wait(0.3)
            key("1")
            check("trackpad scroll by 3 rows, then 1 pastes the 4th item", waitFor { self.fieldText == h[3] },
                  "field=\(fieldText) expected=\(h[3])")
        } else { check("popup opens for scroll test", false) }
        _ = popupClosed()

        h = history()
        clearField()
        if let p = openPopup() {
            E2E.scroll(pixels: -5 * 26, at: CGPoint(x: p.midX, y: p.minY + 60))
            wait(0.3)
            E2E.click(CGPoint(x: p.minX + 120, y: p.minY + 6 + 13))       // first visible row
            check("clicking the top row after scrolling pastes the 6th item", waitFor { self.fieldText == h[5] },
                  "field=\(fieldText) expected=\(h[5])")
        } else { check("popup opens for scroll+click test", false) }
        _ = popupClosed()

        h = history()
        clearField()
        if let p = openPopup() {
            E2E.scroll(pixels: -3 * 26, at: CGPoint(x: p.midX, y: p.minY + 60))
            E2E.scroll(pixels: 3 * 26, at: CGPoint(x: p.midX, y: p.minY + 60))
            wait(0.3)
            key("1")
            check("scrolling back up returns to the top", waitFor { self.fieldText == h[0] },
                  "field=\(fieldText) expected=\(h[0])")
        }
        _ = popupClosed()

        print("Clear history")
        clearField()
        if let p = openPopup() {
            key("delete")
            wait(0.4)
            check("first ⌫ only asks for confirmation", popup() != nil)
            let sizeBefore = diskSize()
            E2E.click(CGPoint(x: p.minX + 120, y: p.maxY - 15))      // footer
            check("confirming closes the popup", popupClosed())
            check("database is empty", waitFor { self.db("SELECT COUNT(*) FROM clips;") == ["0"] },
                  "count=\(db("SELECT COUNT(*) FROM clips;"))")
            check("clearing shrinks the files on disk", waitFor { self.diskSize() < 100_000 },
                  "before=\(sizeBefore) after=\(diskSize())")
        } else { check("popup opens for clear test", false) }
        wait(0.3)
        check("clearing pastes nothing", fieldText.isEmpty, "field=\(fieldText)")

        key("cmd+shift+v")
        wait(0.8)
        check("no popup once history is empty", popup() == nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let harness = Harness()
app.delegate = harness
app.run()
