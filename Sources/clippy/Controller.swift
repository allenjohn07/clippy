import Cocoa

/// Key/mouse handling state machine.
final class Controller {
    enum State {
        case idle
        case opening   // ⌘⇧V swallowed; checking whether we can paste here
        case popup
    }

    let store: ClipboardStore
    let panel = PopupPanel()
    var tap: CFMachPort?

    private var state: State = .idle
    private var selected = 0
    private var vDown = false          // is the physical V key currently down?
    private var swallowV = false       // swallow leftover V events until V is released
    private var swallowMouseUp = false // swallow the mouse-up of a click we consumed
    private var clearArmed = false     // "Clear history" needs a second click/⌫ to confirm

    init(store: ClipboardStore) {
        self.store = store
        // Get each app's accessibility info ready as soon as it comes to the front.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                FocusInspector.prepare(app)
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication { FocusInspector.prepare(front) }
    }

    // Returns true to let the event through, false to swallow it.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return true
        }
        if event.getIntegerValueField(.eventSourceUserData) == Config.eventMarker { return true }

        switch type {
        case .keyDown:          return keyDown(event)
        case .keyUp:            return keyUp(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return mouseDown()
        case .leftMouseUp:
            if swallowMouseUp { swallowMouseUp = false; return false }
            return true
        default:
            return true
        }
    }

    // MARK: - Keyboard

    private func keyDown(_ event: CGEvent) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if key == KeyCode.v { vDown = true }

        switch state {
        case .idle:
            if key == KeyCode.v && swallowV { return false }
            let others: CGEventFlags = [.maskAlternate, .maskControl]
            if key == KeyCode.v && flags.contains([.maskCommand, .maskShift])
                && flags.intersection(others).isEmpty
                && !isRepeat && !store.items.isEmpty {
                // Do the Accessibility lookup outside the tap callback so the tap stays fast.
                state = .opening
                DispatchQueue.main.async { [weak self] in self?.resolveOpening() }
                return false
            }
            return true

        case .opening:
            return key != KeyCode.v

        case .popup:
            switch key {
            case KeyCode.v:                     if !isRepeat { move(+1) }
            case KeyCode.down:                  move(+1)
            case KeyCode.up:                    move(-1)
            case KeyCode.returnKey, KeyCode.enter: commit(selected)
            case KeyCode.escape:                cancel()
            case KeyCode.delete:                requestClear()
            default:
                if let idx = KeyCode.digits[key], idx < store.items.count {
                    commit(idx)
                } else {
                    // Any other key closes the popup and goes through as normal.
                    cancel()
                    return true
                }
            }
            return false
        }
    }

    private func keyUp(_ event: CGEvent) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if key == KeyCode.v { vDown = false }

        switch state {
        case .idle:
            if key == KeyCode.v && swallowV { swallowV = false; return false }
            return true
        case .opening:
            return key != KeyCode.v
        case .popup:
            return false
        }
    }

    // MARK: - Mouse

    private func mouseDown() -> Bool {
        guard state == .popup else { return true }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) {
            swallowMouseUp = true
            switch panel.hit(at: point) {
            case .item(let row): commit(row)
            case .clear:         requestClear()
            case nil:            break   // padding: ignore
            }
            return false
        }
        // Clicked anywhere else: close and let the click through.
        cancel()
        return true
    }

    // MARK: - Actions

    private func resolveOpening() {
        guard state == .opening else { return }
        FocusInspector.currentPasteTarget { [weak self] target in
            guard let self, self.state == .opening else { return }
            if let target {
                self.state = .popup
                self.selected = 0
                self.clearArmed = false
                self.panel.show(items: self.store.items, selected: self.selected, target: target)
            } else {
                // Nowhere to paste: give ⌘⇧V back to the app.
                self.state = .idle
                self.postKeystroke(flags: [.maskCommand, .maskShift])
            }
        }
    }

    private func move(_ delta: Int) {
        let n = store.items.count
        guard n > 0 else { return }
        selected = (selected + delta + n) % n
        panel.select(selected)
        disarmClear()
    }

    /// First press arms the footer ("click again to confirm"); the second clears everything.
    private func requestClear() {
        if clearArmed {
            store.clear()
            finish()
        } else {
            clearArmed = true
            panel.setClearArmed(true)
        }
    }

    private func disarmClear() {
        guard clearArmed else { return }
        clearArmed = false
        panel.setClearArmed(false)
    }

    private func finish() {
        state = .idle
        clearArmed = false
        swallowV = vDown      // if V is still physically held, ignore its repeats
        panel.orderOut(nil)
    }

    private func cancel() { finish() }

    private func commit(_ index: Int) {
        guard index < store.items.count else { finish(); return }
        let text = store.items[index]
        finish()
        store.setClipboard(text)
        postKeystroke(flags: .maskCommand)
    }

    /// Posts a synthetic V keystroke with the given modifiers (⌘V = paste).
    private func postKeystroke(flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(KeyCode.v), keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: Config.eventMarker)
            e?.post(tap: .cghidEventTap)
        }
    }
}
