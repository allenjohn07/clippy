import Foundation
import Testing
@testable import clippy

/// Each test gets its own throwaway database file.
private func makeDatabase() throws -> (HistoryDatabase, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("history.db")
    let db = try #require(HistoryDatabase(url: url))
    return (db, dir)
}

private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

@Suite("HistoryDatabase")
struct HistoryDatabaseTests {
    @Test func newestFirst() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record("a", at: date(1))
        db.record("b", at: date(2))
        db.record("c", at: date(3))
        #expect(db.recent(limit: 10) == ["c", "b", "a"])
    }

    @Test func duplicateMovesToTopWithoutDuplicating() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record("a", at: date(1))
        db.record("b", at: date(2))
        db.record("a", at: date(3))
        #expect(db.recent(limit: 10) == ["a", "b"])
        #expect(db.count() == 2)
    }

    @Test func limitIsRespected() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<20 { db.record("item \(i)", at: date(Double(i))) }
        #expect(db.recent(limit: 5) == ["item 19", "item 18", "item 17", "item 16", "item 15"])
    }

    @Test func pruneKeepsOnlyNewest() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<10 { db.record("item \(i)", at: date(Double(i)), keep: 3) }
        #expect(db.count() == 3)
        #expect(db.recent(limit: 10) == ["item 9", "item 8", "item 7"])
    }

    @Test func clearAllRemovesEverything() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record("a"); db.record("b")
        db.clearAll()
        #expect(db.count() == 0)
        #expect(db.recent(limit: 10).isEmpty)
        db.record("c")   // still usable afterwards
        #expect(db.recent(limit: 10) == ["c"])
    }

    @Test(arguments: [
        "emoji 🎉👩‍💻",
        "quotes ' \" `; DROP TABLE clips; --",
        "multi\nline\r\ntext\twith tabs",
        "日本語テキスト",
    ])
    func roundTripsUnusualText(_ text: String) throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record(text)
        #expect(db.recent(limit: 1) == [text])
    }

    @Test func roundTripsVeryLongText() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        let text = String(repeating: "x", count: 100_000)
        db.record(text)
        #expect(db.recent(limit: 1).first?.count == 100_000)
    }

    @Test func persistsAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.db")
        do {
            let db = try #require(HistoryDatabase(url: url))
            db.record("kept", at: date(1))
        }
        let reopened = try #require(HistoryDatabase(url: url))
        #expect(reopened.recent(limit: 10) == ["kept"])
    }

    @Test func fileIsPrivateToUser() throws {
        let (_, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("history.db").path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }
}
