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
        #expect(db.recentContents(limit: 10) == ["c", "b", "a"])
    }

    @Test func duplicateMovesToTopWithoutDuplicating() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record("a", at: date(1))
        db.record("b", at: date(2))
        db.record("a", at: date(3))
        #expect(db.recentContents(limit: 10) == ["a", "b"])
        #expect(db.count() == 2)
    }

    @Test func limitIsRespected() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<20 { db.record("item \(i)", at: date(Double(i))) }
        #expect(db.recentContents(limit: 5) == ["item 19", "item 18", "item 17", "item 16", "item 15"])
    }

    @Test func pruneKeepsOnlyNewest() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<10 { db.record("item \(i)", at: date(Double(i)), keep: 3) }
        #expect(db.count() == 3)
        #expect(db.recentContents(limit: 10) == ["item 9", "item 8", "item 7"])
    }

    @Test func clearAllRemovesEverything() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.record("a"); db.record("b")
        db.clearAll()
        #expect(db.count() == 0)
        #expect(db.recentContents(limit: 10).isEmpty)
        db.record("c")   // still usable afterwards
        #expect(db.recentContents(limit: 10) == ["c"])
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
        #expect(db.recentContents(limit: 1) == [text])
    }

    @Test func roundTripsVeryLongText() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        let text = String(repeating: "x", count: 100_000)
        db.record(text)
        #expect(db.recentContents(limit: 1).first?.count == 100_000)
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
        #expect(reopened.recentContents(limit: 10) == ["kept"])
    }

    @Test func upgradesDatabaseFromVersion1() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("history.db")

        // Build a 1.0-style database by hand.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [url.path, """
            CREATE TABLE clips (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL UNIQUE,
              created_at REAL NOT NULL, last_used_at REAL NOT NULL, use_count INTEGER NOT NULL DEFAULT 1);
            INSERT INTO clips (content, created_at, last_used_at) VALUES ('old entry', 1, 1);
            """]
        try p.run(); p.waitUntilExit()

        let db = try #require(HistoryDatabase(url: url))
        for column in ["kind", "title", "thumb", "image", "width", "height"] {
            #expect(db.columns().contains(column), "missing \(column)")
        }
        let rows = db.recent(limit: 10)
        #expect(rows.map(\.content) == ["old entry"])
        #expect(rows.first?.kind == "text")
    }

    @Test func imagesAreDedupedAndCapped() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        db.recordImage(png: Data([1]), thumbnail: Data([9]), width: 1, height: 1, hash: "same", at: date(1))
        db.recordImage(png: Data([1]), thumbnail: Data([9]), width: 1, height: 1, hash: "same", at: date(2))
        #expect(db.count() == 1)

        for i in 0..<5 {
            db.recordImage(png: Data([UInt8(i)]), thumbnail: nil, width: 1, height: 1, hash: "h\(i)",
                           at: date(Double(10 + i)), keepImages: 3)
        }
        db.record("text stays", at: date(100))
        let rows = db.recent(limit: 20)
        #expect(rows.filter { $0.kind == "image" }.count == 3)
        #expect(rows.contains { $0.content == "text stays" })
        #expect(db.imageData(id: rows.first { $0.content == "image:h4" }!.id) == Data([4]))
    }

    @Test func youTubeDetailsAreStored() throws {
        let (db, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        let id = try #require(db.record("https://youtu.be/dQw4w9WgXcQ", kind: "youtube"))
        db.updateYouTube(id: id, title: "A video", thumbnail: Data([7, 7]))
        let row = try #require(db.recent(limit: 1).first)
        #expect(row.kind == "youtube")
        #expect(row.title == "A video")
        #expect(row.thumbnail == Data([7, 7]))
    }

    @Test func fileIsPrivateToUser() throws {
        let (_, dir) = try makeDatabase(); defer { try? FileManager.default.removeItem(at: dir) }
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("history.db").path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }
}
