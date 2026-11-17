import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A row as loaded for the list (never includes the full image bytes).
struct StoredClip {
    let id: Int64
    let kind: String
    let content: String
    let title: String?
    let thumbnail: Data?
    let width: Int?
    let height: Int?
}

/// Persists clipboard history in a local SQLite database.
final class HistoryDatabase {
    private var db: OpaquePointer?
    private let url: URL

    init?(url: URL) {
        self.url = url
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            print("clippy: could not create \(dir.path): \(error)")
            return nil
        }

        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            print("clippy: could not open database: \(errorMessage)")
            sqlite3_close(db)
            return nil
        }
        // Clipboard contents can be private: keep the file readable by this user only.
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let schema = """
        PRAGMA journal_mode = WAL;
        PRAGMA journal_size_limit = 524288;  -- shrink the write-ahead log back to ≤512 KB after checkpoints
        PRAGMA wal_autocheckpoint = 200;     -- checkpoint every ~800 KB instead of ~4 MB
        CREATE TABLE IF NOT EXISTS clips (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            content      TEXT    NOT NULL UNIQUE,
            created_at   REAL    NOT NULL,
            last_used_at REAL    NOT NULL,
            use_count    INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_clips_last_used ON clips(last_used_at DESC);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK, migrate() else {
            print("clippy: could not set up the database: \(errorMessage)")
            sqlite3_close(db)
            return nil
        }
        // Shrink a write-ahead log left large by older versions (or by the upgrade above).
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    // MARK: - Schema upgrades

    /// Adds columns introduced after 1.0 to databases created by older versions, and turns on
    /// incremental vacuum so deleted items give their space back.
    private func migrate() -> Bool {
        if pragmaInt("auto_vacuum") != 2 {   // 2 = INCREMENTAL; changing it needs a one-time VACUUM
            guard sqlite3_exec(db, "PRAGMA auto_vacuum = INCREMENTAL; VACUUM;", nil, nil, nil) == SQLITE_OK else {
                return false
            }
        }
        let existing = Set(columns())
        let wanted: [(String, String)] = [
            ("kind", "TEXT NOT NULL DEFAULT 'text'"),
            ("title", "TEXT"),
            ("thumb", "BLOB"),
            ("image", "BLOB"),
            ("width", "INTEGER"),
            ("height", "INTEGER"),
        ]
        for (name, def) in wanted where !existing.contains(name) {
            guard sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN \(name) \(def);", nil, nil, nil) == SQLITE_OK else {
                return false
            }
        }
        return true
    }

    private func pragmaInt(_ name: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA \(name);", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : -1
    }

    /// After deleting rows: hand the freed pages back to the file system and
    /// shrink the write-ahead log, so the size on disk actually goes down.
    private func reclaimSpace() {
        sqlite3_exec(db, "PRAGMA incremental_vacuum; PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    /// Column names of the clips table.
    func columns() -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(clips);", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) { out.append(String(cString: name)) }
        }
        return out
    }

    // MARK: - Writing

    private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data?) {
        guard let data else { sqlite3_bind_null(stmt, index); return }
        data.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
    }

    /// Inserts a text (or YouTube link) entry, or bumps an existing one to the top.
    /// Returns the row id.
    @discardableResult
    func record(_ text: String, kind: String = "text", at date: Date = Date(),
                keep: Int = Config.maxStoredItems) -> Int64? {
        let sql = """
        INSERT INTO clips (content, kind, created_at, last_used_at) VALUES (?1, ?2, ?3, ?3)
        ON CONFLICT(content) DO UPDATE SET
            last_used_at = excluded.last_used_at,
            use_count    = use_count + 1
        RETURNING id;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("clippy: prepare failed: \(errorMessage)"); return nil
        }
        sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, kind, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        let id: Int64? = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
        if id == nil { print("clippy: insert failed: \(errorMessage)") }
        sqlite3_finalize(stmt)
        prune(keep: keep)
        return id
    }

    /// Inserts an image (deduplicated by content hash), or bumps an existing one.
    @discardableResult
    func recordImage(png: Data, thumbnail: Data?, width: Int, height: Int, hash: String,
                     at date: Date = Date(), keep: Int = Config.maxStoredItems,
                     keepImages: Int = Config.maxStoredImages) -> Int64? {
        let sql = """
        INSERT INTO clips (content, kind, image, thumb, width, height, created_at, last_used_at)
        VALUES (?1, 'image', ?2, ?3, ?4, ?5, ?6, ?6)
        ON CONFLICT(content) DO UPDATE SET
            last_used_at = excluded.last_used_at,
            use_count    = use_count + 1
        RETURNING id;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, "image:" + hash, -1, SQLITE_TRANSIENT)
        bindBlob(stmt, 2, png)
        bindBlob(stmt, 3, thumbnail)
        sqlite3_bind_int(stmt, 4, Int32(width))
        sqlite3_bind_int(stmt, 5, Int32(height))
        sqlite3_bind_double(stmt, 6, date.timeIntervalSince1970)
        let id: Int64? = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
        if id == nil { print("clippy: image insert failed: \(errorMessage)") }
        sqlite3_finalize(stmt)
        pruneImages(keep: keepImages)
        prune(keep: keep)
        return id
    }

    /// Stores a YouTube link's title and thumbnail once fetched.
    func updateYouTube(id: Int64, title: String?, thumbnail: Data?) {
        var stmt: OpaquePointer?
        let sql = "UPDATE clips SET title = COALESCE(?1, title), thumb = COALESCE(?2, thumb) WHERE id = ?3;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        if let title { sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 1) }
        bindBlob(stmt, 2, thumbnail)
        sqlite3_bind_int64(stmt, 3, id)
        sqlite3_step(stmt)
    }

    /// Moves an entry to the top (used when it's pasted from the popup).
    func touch(id: Int64, at date: Date = Date()) {
        var stmt: OpaquePointer?
        let sql = "UPDATE clips SET last_used_at = ?1, use_count = use_count + 1 WHERE id = ?2;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func delete(id: Int64) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
        if sqlite3_changes(db) > 0 { reclaimSpace() }
    }

    /// Keeps only the newest `keep` entries.
    func prune(keep: Int) {
        let sql = """
        DELETE FROM clips WHERE id NOT IN
            (SELECT id FROM clips ORDER BY last_used_at DESC LIMIT ?1);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(max(keep, 0)))
        sqlite3_step(stmt)
        if sqlite3_changes(db) > 0 { reclaimSpace() }
    }

    /// Keeps only the newest `keep` images.
    func pruneImages(keep: Int) {
        let sql = """
        DELETE FROM clips WHERE kind = 'image' AND id NOT IN
            (SELECT id FROM clips WHERE kind = 'image' ORDER BY last_used_at DESC LIMIT ?1);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(max(keep, 0)))
        sqlite3_step(stmt)
        if sqlite3_changes(db) > 0 { reclaimSpace() }
    }

    /// Deletes all history and shrinks the files on disk to almost nothing.
    func clearAll() {
        let sql = "DELETE FROM clips; VACUUM; PRAGMA wal_checkpoint(TRUNCATE);"
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("clippy: clear failed: \(errorMessage)")
        }
    }

    // MARK: - Reading

    /// Size on disk in bytes, including SQLite's write-ahead log.
    func fileSize() -> Int64 {
        [url.path, url.path + "-wal"].reduce(Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
            return total + (size?.int64Value ?? 0)
        }
    }

    /// Total number of stored entries.
    func count() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clips;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    /// Most recently used entries, newest first (without full image bytes).
    func recent(limit: Int) -> [StoredClip] {
        let sql = """
        SELECT id, kind, content, title, thumb, width, height
        FROM clips ORDER BY last_used_at DESC LIMIT ?1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [StoredClip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
            func int(_ i: Int32) -> Int? {
                sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i))
            }
            var thumb: Data?
            if let p = sqlite3_column_blob(stmt, 4) {
                thumb = Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, 4)))
            }
            out.append(StoredClip(id: sqlite3_column_int64(stmt, 0), kind: text(1) ?? "text",
                                  content: text(2) ?? "", title: text(3), thumbnail: thumb,
                                  width: int(5), height: int(6)))
        }
        return out
    }

    /// Just the contents, newest first (handy for tests and debugging).
    func recentContents(limit: Int) -> [String] { recent(limit: limit).map(\.content) }

    /// Full PNG bytes of an image entry.
    func imageData(id: Int64) -> Data? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT image FROM clips WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_blob(stmt, 0) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, 0)))
    }
}
