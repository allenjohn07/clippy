import Cocoa

/// Watches the system pasteboard and keeps the recent history (backed by SQLite).
final class ClipboardStore {
    private(set) var items: [String] = []
    private var lastChange = NSPasteboard.general.changeCount
    private let database: HistoryDatabase?

    init(database: HistoryDatabase?) {
        self.database = database
        items = database?.recent(limit: Config.popupItemCount) ?? []
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: Config.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = Config.pollTolerance
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount

        let types = (pb.types ?? []).map { $0.rawValue }
        if types.contains(where: { Config.ignoredPasteboardTypes.contains($0) }) { return }

        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add(s)
    }

    private func add(_ s: String) {
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > Config.popupItemCount {
            items.removeLast(items.count - Config.popupItemCount)
        }
        database?.record(s)
    }

    /// Deletes all history (in memory and on disk).
    func clear() {
        items.removeAll()
        database?.clearAll()
    }

    /// Puts `s` on the pasteboard without treating it as a fresh copy.
    func setClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChange = pb.changeCount
        add(s)
    }
}
