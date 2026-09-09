import Foundation

/// Watermarks for one source, so a rescan reads only what is new.
/// See `agent-os/standards/data/incremental-scanning.md`.
struct SourceScanState: Codable, Sendable {
    struct FileMark: Codable, Sendable {
        var size: Int64
        var mtime: Double
        var offset: Int64
    }

    var files: [String: FileMark] = [:]
    /// Highest SQLite rowid already ingested, for DB-backed sources.
    var rowids: [String: Int64] = [:]

    /// Decides how much of `path` still needs reading.
    /// Returns `nil` when the file is untouched since the last scan.
    func pendingOffset(for path: String, size: Int64, mtime: Double) -> Int64? {
        guard let mark = files[path] else { return 0 }
        if mark.size == size && abs(mark.mtime - mtime) < 0.001 { return nil }
        // Truncated or rewritten in place — the old offset is meaningless.
        if size < mark.offset { return 0 }
        return mark.offset
    }
}

struct ScanOutcome: Sendable {
    var events: [UsageEvent] = []
    /// Quota windows the tool reported, if it reports any.
    var limits: [LimitWindow] = []
    var state: SourceScanState
    /// Why a source produced nothing, shown in Settings. `nil` means it ran clean.
    var note: String?
}

/// Every tool Perch reads implements this. Read-only, counts only, never throws.
protocol UsageSource: Sendable {
    var id: SourceID { get }
    var isAvailable: Bool { get }
    func scan(state: SourceScanState) -> ScanOutcome
}

// MARK: - Shared file helpers

/// One complete line, as raw bytes inside the mapped file buffer.
///
/// Nothing is copied until a line actually matches, which is what keeps a cold
/// scan of ~435 MB of JSONL under a second.
struct LineBytes {
    let base: UnsafeRawPointer
    let count: Int

    /// Naive byte search. Needles here are short and lines are short, so this
    /// beats anything that has to build an index first.
    func contains(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let first = needle[0]
        let limit = count - needle.count
        var offset = 0
        while offset <= limit {
            if bytes[offset] == first {
                var k = 1
                while k < needle.count, bytes[offset + k] == needle[k] { k += 1 }
                if k == needle.count { return true }
            }
            offset += 1
        }
        return false
    }

    var json: [String: Any]? {
        let data = Data(bytes: base, count: count)
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

enum FileScan {
    /// Feeds each complete line between `offset` and EOF to `body`, and returns the
    /// new offset. A line still being appended stops at the last newline, so it is
    /// re-read whole next pass instead of being parsed in halves.
    @discardableResult
    static func forEachLine(
        path: String,
        from offset: Int64,
        _ body: (LineBytes) -> Void
    ) -> Int64 {
        guard let handle = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? handle.close() }
        do {
            if offset > 0 { try handle.seek(toOffset: UInt64(offset)) }
            guard let data = try handle.readToEnd(), !data.isEmpty else { return offset }
            var consumed = 0
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                var lineStart = 0
                for index in 0..<raw.count where bytes[index] == 0x0A {
                    if index > lineStart {
                        body(LineBytes(base: base + lineStart, count: index - lineStart))
                    }
                    lineStart = index + 1
                    consumed = lineStart
                }
            }
            return offset + Int64(consumed)
        } catch {
            return offset
        }
    }

    static func stat(_ path: String) -> (size: Int64, mtime: Double)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber,
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        return (size.int64Value, modified.timeIntervalSince1970)
    }

    /// Every file under `root` matching `ext`, depth-first, symlinks skipped.
    static func files(under root: String, ext: String) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [String] = []
        for case let url as URL in e where url.pathExtension == ext {
            out.append(url.path)
        }
        return out
    }
}

enum ISO8601 {
    /// Claude Code and Codex both stamp RFC3339 with fractional seconds; Codex
    /// occasionally omits them, so try both shapes.
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int {
        if let n = self[key] as? NSNumber { return n.intValue }
        return 0
    }

    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func str(_ key: String) -> String? { self[key] as? String }
}
