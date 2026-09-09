import Foundation

/// Reads Cursor's global store at
/// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
///
/// On-disk shape (all reverse-engineered — Cursor documents none of it):
///  - `cursorDiskKV` rows keyed `bubbleId:<composerId>:<bubbleId>` hold a JSON blob
///    whose `tokenCount` is `{"inputTokens":N,"outputTokens":N}`. 33k bubbles exist
///    but only ~1.5k ever billed, so the zero ones are rejected in SQL.
///  - `composerData:<composerId>` rows carry `createdAt` and `unifiedMode`. These
///    blobs total ~240 MB, so every field is pulled with `json_extract` rather than
///    transferred and parsed in Swift.
///  - `composerHeaders` additionally maps a composer to a `workspaceId`, and
///    `workspaceStorage/<workspaceId>/workspace.json` names the project folder.
///
/// Two honest limits, surfaced in Settings rather than papered over:
/// Cursor records no model name locally, so usage is attributed to
/// `cursor (<mode>)`; and most conversations record no path, so they land in
/// "Unattributed" rather than being assigned to a guessed project.
struct CursorSource: UsageSource {
    let id = SourceID.cursor
    let storageRoot: String

    init(storageRoot: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User") {
        self.storageRoot = storageRoot
    }

    private var databasePath: String { storageRoot + "/globalStorage/state.vscdb" }
    private var workspaceRoot: String { storageRoot + "/workspaceStorage" }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: databasePath)
    }

    func scan(state: SourceScanState) -> ScanOutcome {
        guard isAvailable else {
            return ScanOutcome(state: state, note: "Cursor not installed")
        }
        var state = state
        guard let (size, mtime) = FileScan.stat(databasePath),
              state.pendingOffset(for: databasePath, size: size, mtime: mtime) != nil
        else {
            return ScanOutcome(state: state, note: nil)
        }
        guard let db = SQLiteDB(path: databasePath) else {
            return ScanOutcome(state: state, note: "Could not open state.vscdb (Cursor may be writing)")
        }

        let folders = readWorkspaceFolders()
        let roots = Array(folders.values)
        let composers = readComposers(db)
        var events: [UsageEvent] = []
        var undated = 0

        // A bubble is rewritten in place as it streams, so every billed row is
        // re-read whenever the database changes; the bubble key keeps it idempotent.
        let sql = """
            SELECT key, \
            json_extract(value,'$.tokenCount.inputTokens'), \
            json_extract(value,'$.tokenCount.outputTokens') \
            FROM cursorDiskKV \
            WHERE key LIKE 'bubbleId:%' \
            AND value LIKE '%"tokenCount"%' \
            AND value NOT LIKE '%"tokenCount":{"inputTokens":0,"outputTokens":0}%'
            """
        db.query(sql) { row in
            guard let key = row.text(0) else { return }
            let input = Int(row.int(1))
            let output = Int(row.int(2))
            guard input > 0 || output > 0 else { return }

            // key == "bubbleId:<composerId>:<bubbleId>"
            let parts = key.split(separator: ":")
            guard parts.count >= 3 else { return }
            // A bubble carries no timestamp of its own; without its composer there
            // is no date, and an undated event would corrupt every time series.
            guard let composer = composers[String(parts[1])] else {
                undated += 1
                return
            }

            events.append(UsageEvent(
                dedupeKey: "cu:\(key)",
                timestamp: composer.created,
                source: .cursor,
                model: "cursor (\(composer.mode))",
                projectPath: project(for: composer, folders: folders, roots: roots),
                inputTokens: input,
                outputTokens: output,
                cacheWrite5mTokens: 0,
                cacheWrite1hTokens: 0,
                cacheReadTokens: 0,
                reasoningTokens: 0
            ))
        }

        state.files[databasePath] = .init(size: size, mtime: mtime, offset: size)
        var note: String?
        if events.isEmpty { note = "No billed conversations found in Cursor's store" }
        if undated > 0 { note = "\(undated) conversations skipped — no date recorded" }
        return ScanOutcome(events: events, state: state, note: note)
    }

    private struct Composer {
        var workspaceID: String?
        var created: Date
        var mode: String
        /// A file touched by the conversation, used to locate its project.
        var pathHint: String?
    }

    /// `composerHeaders` is authoritative (it alone carries `workspaceId`) but covers
    /// only a fraction of conversations; `composerData` dates the rest.
    private func readComposers(_ db: SQLiteDB) -> [String: Composer] {
        var out: [String: Composer] = [:]

        db.query("""
            SELECT substr(key,14), \
            json_extract(value,'$.createdAt'), \
            json_extract(value,'$.unifiedMode'), \
            json_extract(value,'$.context.fileSelections[0].uri.path') \
            FROM cursorDiskKV WHERE key LIKE 'composerData:%' AND json_valid(value)
            """) { row in
            guard let id = row.text(0), row.int(1) > 0 else { return }
            out[id] = Composer(
                workspaceID: nil,
                created: Date(timeIntervalSince1970: Double(row.int(1)) / 1000),
                mode: row.text(2) ?? "unknown",
                pathHint: row.text(3)
            )
        }

        guard db.hasTable("composerHeaders") else { return out }
        db.query("""
            SELECT composerId, workspaceId, createdAt, json_extract(value,'$.unifiedMode') \
            FROM composerHeaders
            """) { row in
            guard let id = row.text(0), row.int(2) > 0 else { return }
            out[id] = Composer(
                workspaceID: row.text(1),
                created: Date(timeIntervalSince1970: Double(row.int(2)) / 1000),
                mode: row.text(3) ?? out[id]?.mode ?? "unknown",
                pathHint: out[id]?.pathHint
            )
        }
        return out
    }

    /// Workspace folder if known, else the workspace root that contains a file the
    /// conversation touched. Never a guess — an unmatched path yields `nil`.
    private func project(for composer: Composer, folders: [String: String], roots: [String]) -> String? {
        if let id = composer.workspaceID, let folder = folders[id] { return folder }
        guard let hint = composer.pathHint else { return nil }
        return roots
            .filter { hint.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    /// workspaceId -> project directory, from each workspace's `workspace.json`.
    private func readWorkspaceFolders() -> [String: String] {
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(atPath: workspaceRoot) else { return [:] }
        var out: [String: String] = [:]
        for id in ids {
            let manifest = workspaceRoot + "/" + id + "/workspace.json"
            guard let data = fm.contents(atPath: manifest),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = obj.str("folder"),
                  let url = URL(string: folder), url.isFileURL
            else { continue }
            out[id] = url.path
        }
        return out
    }
}
