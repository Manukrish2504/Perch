import SwiftUI
import Combine

struct Settings: Codable, Equatable {
    var petSpecies: String = "pip"
    var showCost: Bool = true
    var shelfMetric: ShelfMetric = .today
    var pollSeconds: Double = 8
    /// Keyed by `WidgetKind.rawValue`.
    var widgets: [String: WidgetPlacement] = [:]
    /// Widgets normally sit just above the desktop icons; this floats them over
    /// every window instead.
    var widgetsFloat: Bool = false
    /// Heatmaps render as isometric cubes rather than a flat grid. Lives in
    /// settings because widgets are display-only and carry no controls.
    var heatmap3D: Bool = true
    /// Hide the notch shelf while an app is full-screen on that display, so it
    /// never covers full-screen content.
    var hideInFullscreen: Bool = true

    func placement(_ kind: WidgetKind) -> WidgetPlacement {
        widgets[kind.rawValue] ?? WidgetPlacement()
    }

    enum CodingKeys: String, CodingKey {
        case petSpecies, showCost, shelfMetric, pollSeconds
        case widgets, widgetsFloat, heatmap3D, hideInFullscreen
    }

    enum ShelfMetric: String, Codable, CaseIterable {
        case today, sevenDay, total

        var label: String {
            switch self {
            case .today: "Today"
            case .sevenDay: "Last 7 days"
            case .total: "All time"
            }
        }
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: PerchPaths.settings),
              let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: PerchPaths.settings, options: .atomic)
    }
}

/// Single source of UI truth. Everything here is main-actor; scanning happens
/// off it and lands in one hop. See `agent-os/standards/global/concurrency.md`.
/// Decoded key by key with per-key fallbacks.
///
/// Swift's synthesised `Codable` throws when a key is missing **even if the
/// property has a default value**, so simply adding a setting made every existing
/// `settings.json` undecodable — and `load()`'s fallback then silently reset the
/// user's widgets and pet. Every new setting would do it again. Decoding each key
/// with `decodeIfPresent` makes old files forward-compatible and new files
/// readable by older builds.
extension Settings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings()
        func value<T: Decodable>(_ key: CodingKeys, _ default: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? `default`
        }
        petSpecies = value(.petSpecies, fallback.petSpecies)
        showCost = value(.showCost, fallback.showCost)
        shelfMetric = value(.shelfMetric, fallback.shelfMetric)
        pollSeconds = value(.pollSeconds, fallback.pollSeconds)
        widgets = value(.widgets, fallback.widgets)
        widgetsFloat = value(.widgetsFloat, fallback.widgetsFloat)
        heatmap3D = value(.heatmap3D, fallback.heatmap3D)
        hideInFullscreen = value(.hideInFullscreen, fallback.hideInFullscreen)
    }
}

/// Same reasoning as `Settings`: a widget's saved size and position must survive
/// a new field being added.
extension WidgetPlacement {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) .flatMap { $0 } ?? false
        size = (try? container.decodeIfPresent(WidgetSize.self, forKey: .size)) .flatMap { $0 } ?? .medium
        x = (try? container.decodeIfPresent(Double.self, forKey: .x)) .flatMap { $0 }
        y = (try? container.decodeIfPresent(Double.self, forKey: .y)) .flatMap { $0 }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var rollup = Rollup()
    /// One rollup per selectable window, so every view reads consistent numbers.
    @Published private(set) var scoped: [DateRange: Rollup] = [:]
    @Published private(set) var pet = PetStatus()
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var limits: [LimitWindow] = []
    /// Arrange mode. Desktop-level widgets sit under your windows, so a click
    /// never reaches them — which makes them impossible to place. Arranging lifts
    /// every widget above the window stack and marks it as draggable until you
    /// are done. Not persisted: it is a mode, not a preference.
    @Published var isArranging = false
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var scanDuration: TimeInterval = 0
    /// Real scan progress, 0...1, and the source currently being read.
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var scanStage: String = ""
    /// Set while the dashboard plays its opening run. `nil` once the content is in.
    @Published private(set) var introStartedAt: Date?
    @Published var prices = PriceBook.bundled
    @Published var settings = Settings.load() {
        didSet { if settings != oldValue { settings.save() } }
    }

    private var store = UsageStore()
    /// Kept alongside the rollups so short-window questions (the trailing five
    /// hours, say) can be answered exactly rather than from day buckets.
    private var events: [UsageEvent] = []
    private var timer: AnyCancellable?
    private var petTicker: AnyCancellable?

    var species: PetSpecies { .named(settings.petSpecies) }

    var shelfTotals: Totals {
        switch settings.shelfMetric {
        case .today: rollup.today
        case .sevenDay: rollup.totals(inLast: 7)
        case .total: rollup.all
        }
    }

    func start() {
        prices = Ingest.loadPriceBook()

        if DemoData.isEnabled {
            // Synthetic data only: no real log is read and nothing is persisted.
            store = DemoData.store()
            notes = store.notes
            limits = store.limits.values.sorted { $0.id < $1.id }
            recompute()
            return
        }

        store = Ingest.load()
        if !store.events.isEmpty {
            limits = store.limits.values.sorted { $0.id < $1.id }
            recompute()
        }
        Task { await scan() }

        timer = Timer.publish(every: settings.pollSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.scan() } }

        // The pet's mood decays with time even when no new tokens arrive, so it
        // needs its own tick independent of scanning.
        petTicker = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshPet() }
    }

    func rescanNow() {
        Task { await scan(force: true) }
    }

    /// Discards watermarks and re-reads every log from scratch.
    func rebuildFromScratch() {
        store = UsageStore()
        Task { await scan(force: true) }
    }

    private func scan(force: Bool = false) async {
        guard !DemoData.isEnabled else { return }
        guard !isScanning else { return }
        isScanning = true
        let started = Date()
        let previous = store
        let scanned = await Task.detached(priority: .utility) {
            Ingest.scan(previous) { fraction, stage in
                Task { @MainActor in
                    self.scanProgress = fraction
                    self.scanStage = stage
                }
            }
        }.value

        store = scanned
        notes = scanned.notes
        limits = scanned.limits.values.sorted { $0.id < $1.id }
        recompute()
        lastScan = Date()
        scanDuration = Date().timeIntervalSince(started)
        isScanning = false

        // Persisting is pure I/O; it must not hold up the next frame.
        let snapshot = scanned
        Task.detached(priority: .background) { Ingest.save(snapshot) }
    }

    private func recompute() {
        let events = store.sortedEvents
        self.events = events
        let book = prices
        rollup = Rollup.build(events: events, prices: book)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var built: [DateRange: Rollup] = [:]
        for range in DateRange.allCases {
            guard let window = range.days else {
                built[range] = rollup
                continue
            }
            let start = calendar.date(byAdding: .day, value: -(window - 1), to: today) ?? today
            built[range] = Rollup.build(events: events, prices: book, since: start)
        }
        scoped = built
        refreshPet()
    }

    private func refreshPet() {
        pet = PetStatus.derive(from: rollup)
    }

    /// Plays the dashboard's opening run: the pet paces a real scan, and the
    /// content lands once the work is done.
    ///
    /// Held to a floor of just over a second so a warm launch (incremental scans
    /// finish in ~0.1s) still reads as a deliberate opening rather than a flash of
    /// something half-drawn — and never held longer than the work actually takes
    /// beyond that.
    func beginDashboardIntro() {
        guard introStartedAt == nil else { return }
        let started = Date()
        introStartedAt = started
        scanProgress = 0
        scanStage = "Waking up…"

        Task {
            if DemoData.isEnabled {
                // Still walk the stages so the opening run reads the same.
                for (fraction, stage) in [
                    (0.25, "Reading Claude Code…"), (0.5, "Reading Codex…"),
                    (0.75, "Reading Cursor…"), (1.0, "Building rollups…"),
                ] {
                    scanProgress = fraction
                    scanStage = stage
                    try? await Task.sleep(nanoseconds: 180_000_000)
                }
            } else {
                await scan()
            }
            let elapsed = Date().timeIntervalSince(started)
            let hold = max(0, 1.15 - elapsed)
            if hold > 0 {
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            }
            withAnimation(.easeOut(duration: 0.4)) {
                introStartedAt = nil
            }
        }
    }

    /// Tokens billed since `date`, exact to the event rather than to the day.
    func recentTokens(since date: Date) -> Int {
        var total = 0
        // Events are sorted ascending, so walk back from the end and stop early.
        for event in events.reversed() {
            if event.timestamp < date { break }
            total += event.totalTokens
        }
        return total
    }

    func updateRate(model: String, rate: ModelRate) {
        prices.rates[model] = rate
        Ingest.savePriceBook(prices)
        recompute()
    }

    func resetRates() {
        prices = .bundled
        Ingest.savePriceBook(prices)
        recompute()
    }
}
