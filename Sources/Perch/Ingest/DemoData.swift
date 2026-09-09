import Foundation

/// A synthetic dataset, used for screenshots and for trying the app without any
/// local AI-tool logs.
///
/// Deterministic: the same seed produces the same numbers every run, so the
/// documentation screenshots are reproducible rather than a snapshot of whatever
/// the generator happened to roll. Enable with `PERCH_DEMO=1`.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PERCH_DEMO"] == "1"
    }

    private struct Project {
        let path: String
        /// Rough share of the total, before daily variation.
        let weight: Double
        let sources: [SourceID]
        /// How much of the work this project delegates to subagents.
        let delegation: Double
    }

    private static let projects: [Project] = [
        .init(path: "~/code/atlas-web", weight: 1.00, sources: [.claudeCode], delegation: 0.34),
        .init(path: "~/code/atlas-api", weight: 0.72, sources: [.claudeCode], delegation: 0.51),
        .init(path: "~/code/design-system", weight: 0.44, sources: [.claudeCode], delegation: 0.12),
        .init(path: "~/code/data-pipeline", weight: 0.38, sources: [.claudeCode, .codex], delegation: 0.28),
        .init(path: "~/code/atlas-web/mobile", weight: 0.31, sources: [.claudeCode], delegation: 0.19),
        .init(path: "~/code/infra", weight: 0.22, sources: [.codex], delegation: 0),
        .init(path: "~/code/docs-site", weight: 0.17, sources: [.claudeCode], delegation: 0.08),
        .init(path: "~/code/ml-notebooks", weight: 0.13, sources: [.cursor], delegation: 0),
        .init(path: "~/code/cli-tools", weight: 0.09, sources: [.claudeCode], delegation: 0.41),
        .init(path: "~/code/scratchpad", weight: 0.05, sources: [.cursor], delegation: 0),
    ]

    private static let models: [SourceID: [String]] = [
        .claudeCode: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"],
        .codex: ["gpt-5-codex"],
        .cursor: ["cursor (agent)", "cursor (chat)"],
        .antigravity: [],
    ]

    /// A small deterministic generator — no dependency on the platform's RNG,
    /// which is not guaranteed stable across releases.
    private struct Seeded {
        private var state: UInt64

        init(_ seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 1_000_000) / 1_000_000
        }

        mutating func inRange(_ low: Double, _ high: Double) -> Double {
            low + next() * (high - low)
        }

        mutating func pick<T>(_ values: [T]) -> T? {
            guard !values.isEmpty else { return nil }
            return values[min(values.count - 1, Int(next() * Double(values.count)))]
        }
    }

    static func store() -> UsageStore {
        var random = Seeded(0x5E_ED_10_24)
        var store = UsageStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let home = NSHomeDirectory()

        for dayOffset in 0..<150 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            // Weekends are quieter, and a fifth of days are skipped entirely.
            let weekendFactor = (weekday == 1 || weekday == 7) ? 0.35 : 1.0
            // Today always has activity, so the pet and the "today" figures are
            // showing something in a fresh screenshot.
            if dayOffset > 0, random.next() < 0.2 { continue }
            let dayIntensity = random.inRange(0.3, 2.1) * weekendFactor * 3.2

            for project in projects {
                if random.next() > min(0.95, project.weight + 0.25) { continue }
                let sessions = Int(random.inRange(4, 16))

                for session in 0..<sessions {
                    guard let source = random.pick(project.sources),
                          let model = random.pick(models[source] ?? [])
                    else { continue }

                    // Work clusters late morning and late evening.
                    let hour = random.next() < 0.55
                        ? Int(random.inRange(9, 13))
                        : Int(random.inRange(18, 24))
                    let minute = Int(random.inRange(0, 60))
                    guard let stamp = calendar.date(
                        bySettingHour: min(23, hour), minute: minute, second: 0, of: day
                    ) else { continue }

                    let scale = project.weight * dayIntensity * random.inRange(0.4, 1.8)
                    // Tools that report no cache carry their whole context in the
                    // input count, so their per-turn numbers are far larger — without
                    // this they round to 0% of a cache-dominated total.
                    let uncached = source != .claudeCode
                    let output = Int(random.inRange(400, 3_000) * scale * (uncached ? 6 : 1))
                    let input = Int(
                        random.inRange(200, 1_400) * scale * (uncached ? 90 : 1)
                    )
                    let cacheRead = uncached ? 0 : Int(random.inRange(60_000, 320_000) * scale)
                    let cacheWrite = uncached ? 0 : Int(random.inRange(2_000, 14_000) * scale)

                    store.events["demo-\(dayOffset)-\(project.path)-\(session)"] = UsageEvent(
                        dedupeKey: "demo-\(dayOffset)-\(project.path)-\(session)",
                        timestamp: stamp,
                        source: source,
                        model: model,
                        projectPath: project.path.replacingOccurrences(of: "~", with: home),
                        inputTokens: input,
                        outputTokens: output,
                        cacheWrite5mTokens: cacheWrite / 3,
                        cacheWrite1hTokens: cacheWrite - cacheWrite / 3,
                        cacheReadTokens: cacheRead,
                        reasoningTokens: Int(Double(output) * random.inRange(0.05, 0.3)),
                        isSubagent: random.next() < project.delegation
                    )
                }
            }
        }

        store.limits = [
            "claudeCode-5-hour": LimitWindow(
                source: .claudeCode, label: "5-hour", usedPercent: nil,
                resetsAt: Date().addingTimeInterval(2 * 3_600 + 840),
                observedAt: Date().addingTimeInterval(-3_600), hits: 4
            ),
            "codex-5-hour": LimitWindow(
                source: .codex, label: "5-hour", usedPercent: 38,
                resetsAt: Date().addingTimeInterval(3 * 3_600),
                observedAt: Date().addingTimeInterval(-600)
            ),
            "codex-Weekly": LimitWindow(
                source: .codex, label: "Weekly", usedPercent: 61,
                resetsAt: Date().addingTimeInterval(4 * 86_400),
                observedAt: Date().addingTimeInterval(-600)
            ),
        ]
        store.notes = ["antigravity": "Not installed"]
        store.lastScan = Date()
        return store
    }
}
