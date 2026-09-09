import Foundation
import SQLite3

/// Minimal read-only SQLite reader. Perch never writes to another tool's database.
final class SQLiteDB {
    private var handle: OpaquePointer?

    /// Opens read-only. Tries a plain `mode=ro` first so a live database's WAL is
    /// still visible; falls back to `immutable=1`, which ignores the WAL but works
    /// when the sidecar files cannot be opened.
    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        for suffix in ["?mode=ro", "?mode=ro&immutable=1"] {
            if sqlite3_open_v2("file:" + encoded + suffix, &handle, flags, nil) == SQLITE_OK {
                sqlite3_busy_timeout(handle, 2_000)
                return
            }
            if let handle { sqlite3_close(handle) }
            handle = nil
        }
        return nil
    }

    deinit { if let handle { sqlite3_close(handle) } }

    var hasTable: (String) -> Bool {
        { [weak self] name in
            guard let self else { return false }
            var found = false
            self.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(name)' LIMIT 1") { _ in
                found = true
            }
            return found
        }
    }

    /// Streams rows so a 1.5 GB store never lands in memory at once.
    func query(_ sql: String, _ row: (Row) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(Row(statement: statement))
        }
    }

    struct Row {
        let statement: OpaquePointer?

        func text(_ index: Int32) -> String? {
            guard let c = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: c)
        }

        func int(_ index: Int32) -> Int64 {
            sqlite3_column_int64(statement, index)
        }
    }
}
