import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persists every clipboard entry in a local SQLite database.
final class HistoryDatabase {
    private var db: OpaquePointer?

    init?(url: URL) {
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
        CREATE TABLE IF NOT EXISTS clips (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            content      TEXT    NOT NULL UNIQUE,
            created_at   REAL    NOT NULL,
            last_used_at REAL    NOT NULL,
            use_count    INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_clips_last_used ON clips(last_used_at DESC);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            print("clippy: could not create schema: \(errorMessage)")
            sqlite3_close(db)
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    /// Inserts a new entry (or bumps an existing one to the top), then drops anything
    /// beyond the newest `keep` entries.
    func record(_ text: String, at date: Date = Date(), keep: Int = Config.maxStoredItems) {
        let sql = """
        INSERT INTO clips (content, created_at, last_used_at) VALUES (?1, ?2, ?2)
        ON CONFLICT(content) DO UPDATE SET
            last_used_at = excluded.last_used_at,
            use_count    = use_count + 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("clippy: prepare failed: \(errorMessage)"); return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("clippy: insert failed: \(errorMessage)")
        }
        prune(keep: keep)
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
    }

    /// Deletes all history.
    func clearAll() {
        if sqlite3_exec(db, "DELETE FROM clips; VACUUM;", nil, nil, nil) != SQLITE_OK {
            print("clippy: clear failed: \(errorMessage)")
        }
    }

    /// Total number of stored entries.
    func count() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clips;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    /// Most recently used entries, newest first.
    func recent(limit: Int) -> [String] {
        let sql = "SELECT content FROM clips ORDER BY last_used_at DESC LIMIT ?1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }
}
