import Foundation
import Testing
@testable import clippy

@Suite("ClipboardStore")
struct ClipboardStoreTests {
    @Test func loadsRecentHistoryFromDatabase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        for i in 0..<15 { db.record("item \(i)", at: Date(timeIntervalSince1970: Double(i))) }

        let store = ClipboardStore(database: db)
        #expect(store.items.count == Config.popupItemCount)
        #expect(store.items.first == "item 14")
    }

    @Test func clearEmptiesMemoryAndDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        db.record("a"); db.record("b")

        let store = ClipboardStore(database: db)
        store.clear()
        #expect(store.items.isEmpty)
        #expect(db.count() == 0)
    }

    @Test func worksWithoutDatabase() {
        let store = ClipboardStore(database: nil)
        #expect(store.items.isEmpty)
        store.clear()
        #expect(store.items.isEmpty)
    }
}
