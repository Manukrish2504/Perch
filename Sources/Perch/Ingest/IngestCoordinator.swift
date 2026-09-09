import Foundation

/// Where Perch keeps its own state. Nothing is ever written outside this folder.
enum PerchPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var store: URL { supportDirectory.appendingPathComponent("store.json") }
    static var rates: URL { supportDirectory.appendingPathComponent("rates.json") }
    static var settings: URL { supportDirectory.appendingPathComponent("settings.json") }
}

/// Deduplicated events plus each source's watermarks.
struct UsageStore: Codable, Sendable {
    /// Bumped whenever a parser changes meaning, which forces a clean re-scan
    /// rather than mixing old and new arithmetic.
    static let currentVersion = 6

    var version = currentVersion
    /// Keyed by `dedupeKey`, so re-reading a file can only overwrite, never duplicate.
    var events: [String: UsageEvent] = [:]
    var states: [String: SourceScanState] = [:]
    var notes: [String: String] = [:]
    /// Latest quota reading per window, keyed by `LimitWindow.id`.
    var limits: [String: LimitWindow] = [:]
    var lastScan: Date?

    var sortedEvents: [UsageEvent] {
        events.values.sorted { $0.timestamp < $1.timestamp }
    }
}

enum Ingest {
    static let sources: [any UsageSource] = [
        ClaudeCodeSource(),
        CodexSource(),
        CursorSource(),
        AntigravitySource(),
    ]

    /// Runs every source. Never throws: a source that fails contributes a note and
    /// zero events, leaving the others untouched.
    ///
    /// `progress` reports real completion — the fraction of sources finished and
    /// the name of the one being read — so the UI can show actual work rather than
    /// an indeterminate spinner.
    static func scan(
        _ previous: UsageStore,
        progress: ((Double, String) -> Void)? = nil
    ) -> UsageStore {
        var store = previous
        store.notes.removeAll(keepingCapacity: true)

        for (index, source) in sources.enumerated() {
            progress?(Double(index) / Double(sources.count), "Reading \(source.id.displayName)…")
            let key = source.id.rawValue
            let outcome = source.scan(state: store.states[key] ?? SourceScanState())
            store.states[key] = outcome.state
            if let note = outcome.note { store.notes[key] = note }
            for window in outcome.limits {
                // A source re-reports its windows every scan; newest wins.
                if let existing = store.limits[window.id], existing.observedAt > window.observedAt {
                    continue
                }
                store.limits[window.id] = window
            }
            for event in outcome.events {
                store.events[event.dedupeKey] = event
            }
        }
        progress?(1, "Building rollups…")
        store.lastScan = Date()
        return store
    }

    static func load() -> UsageStore {
        guard let data = try? Data(contentsOf: PerchPaths.store),
              let store = try? JSONDecoder().decode(UsageStore.self, from: data),
              store.version == UsageStore.currentVersion
        else {
            // A missing or stale snapshot is not an error — the logs on disk are
            // the source of truth and a cold scan takes about a second.
            return UsageStore()
        }
        return store
    }

    static func save(_ store: UsageStore) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: PerchPaths.store, options: .atomic)
    }

    static func loadPriceBook() -> PriceBook {
        guard let data = try? Data(contentsOf: PerchPaths.rates),
              let book = try? JSONDecoder().decode(PriceBook.self, from: data)
        else { return .bundled }
        // Models added to the bundled table since the user's file was written
        // should still price, without clobbering rates they edited.
        var merged = book
        for (model, rate) in PriceBook.bundled.rates where merged.rates[model] == nil {
            merged.rates[model] = rate
        }
        return merged
    }

    static func savePriceBook(_ book: PriceBook) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(book) else { return }
        try? data.write(to: PerchPaths.rates, options: .atomic)
    }
}
