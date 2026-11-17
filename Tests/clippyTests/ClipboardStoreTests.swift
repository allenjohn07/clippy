import Cocoa
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
        #expect(store.items.count == 15)            // the whole history, not just one screenful
        #expect(store.items.first?.text == "item 14")
        #expect(store.items.last?.text == "item 0")
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

    @Test func reportsStorageSize() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        db.record(String(repeating: "x", count: 50_000))
        let store = ClipboardStore(database: db)
        #expect(store.storageBytes > 50_000)
        #expect(ClipboardStore(database: nil).storageBytes == 0)
    }

    @Test func loadsMixedKindsAndDropsBlankRows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        db.record("\u{200B}  ", at: Date(timeIntervalSince1970: 1))           // saved by an old version
        db.record("https://youtu.be/dQw4w9WgXcQ", kind: "youtube", at: Date(timeIntervalSince1970: 2))
        db.recordImage(png: Data([1, 2, 3]), thumbnail: nil, width: 640, height: 480, hash: "abc",
                       at: Date(timeIntervalSince1970: 3))
        db.record("hello", at: Date(timeIntervalSince1970: 4))

        let store = ClipboardStore(database: db)
        #expect(store.items.map(\.kind) == [.text, .image, .youtube])
        #expect(store.items[1].label == "Image · 640×480")
        #expect(db.count() == 3)                                  // blank row deleted from disk too
    }

    @Test func capturesTextButSkipsSecretsEmptyAndPasswordApps() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        let store = ClipboardStore(database: db)
        let pb = NSPasteboard(name: NSPasteboard.Name("clippy-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        func copy(_ s: String, from app: String? = "com.apple.TextEdit") {
            pb.clearContents(); pb.setString(s, forType: .string)
            store.capture(from: pb, frontApp: app)
        }
        copy("  \n\u{200B} ")
        copy("Tr0ub4dor&3")
        copy("ghp_" + String(repeating: "a1B2", count: 9))
        copy("my secret note", from: "com.bitwarden.desktop")
        #expect(store.items.isEmpty)

        copy("hello world")
        #expect(store.items.map(\.text) == ["hello world"])
    }

    @Test func capturesAndPastesImages() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        let store = ClipboardStore(database: db)
        let pb = NSPasteboard(name: NSPasteboard.Name("clippy-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        for _ in 0..<2 {                       // same image twice → one entry
            pb.clearContents(); pb.setData(png, forType: .png)
            store.capture(from: pb, frontApp: nil)
        }
        #expect(store.items.count == 1)
        #expect(store.items[0].kind == .image)
        #expect(store.items[0].pixelSize == CGSize(width: 200, height: 100))
        #expect(store.items[0].thumbnail != nil)
        #expect(store.imageData(for: store.items[0]) == png)
    }

    @Test func imageFileCopiedInFinderSavesThePicture() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        let store = ClipboardStore(database: db)
        let pb = NSPasteboard(name: NSPasteboard.Name("clippy-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let file = dir.appendingPathComponent("Holiday photo.png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)

        // Finder puts the file URL, and sometimes the file name as text too.
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        pb.setString("Holiday photo.png", forType: .string)
        store.capture(from: pb, frontApp: "com.apple.finder")

        #expect(store.items.count == 1)
        #expect(store.items.first?.kind == .image)
        #expect(store.items.first?.pixelSize == CGSize(width: 120, height: 80))
        #expect(store.items.first?.thumbnail != nil)
    }

    @Test func nonImageFileFromFinderIsNotAnImage() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        let store = ClipboardStore(database: db)
        let pb = NSPasteboard(name: NSPasteboard.Name("clippy-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let file = dir.appendingPathComponent("notes.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        store.capture(from: pb, frontApp: "com.apple.finder")
        #expect(!store.items.contains { $0.kind == .image })
    }

    @Test func browserCopyImageKeepsTheImageNotTheURL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try #require(HistoryDatabase(url: dir.appendingPathComponent("history.db")))
        let store = ClipboardStore(database: db)
        let pb = NSPasteboard(name: NSPasteboard.Name("clippy-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        pb.clearContents()
        pb.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        pb.setString("https://example.com/cat.png", forType: .string)
        store.capture(from: pb, frontApp: nil)
        #expect(store.items.first?.kind == .image)
    }

    @Test func worksWithoutDatabase() {
        let store = ClipboardStore(database: nil)
        #expect(store.items.isEmpty)
        store.clear()
        #expect(store.items.isEmpty)
    }
}
