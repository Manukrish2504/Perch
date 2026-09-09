import Foundation

/// Accumulated counts for any slice of events.
struct Totals: Sendable, Hashable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var reasoning = 0
    var events = 0
    var cost = 0.0
    /// Tokens attributable to delegated subagents; the rest is the main thread.
    var subagent = 0
    var subagentEvents = 0

    var total: Int { input + output + cacheWrite + cacheRead }
    var mainThread: Int { max(0, total - subagent) }

    /// Share of all tokens served from cache. The dominant cost lever: a cache
    /// read bills at a tenth of an input token.
    var cacheHitRate: Double {
        let readable = cacheRead + cacheWrite + input
        return readable > 0 ? Double(cacheRead) / Double(readable) : 0
    }

    var subagentShare: Double {
        total > 0 ? Double(subagent) / Double(total) : 0
    }

    mutating func add(_ e: UsageEvent, cost eventCost: Double) {
        input += e.inputTokens
        output += e.outputTokens
        cacheWrite += e.cacheWriteTokens
        cacheRead += e.cacheReadTokens
        reasoning += e.reasoningTokens
        events += 1
        cost += eventCost
        if e.isSubagent {
            subagent += e.totalTokens
            subagentEvents += 1
        }
    }

    static func + (a: Totals, b: Totals) -> Totals {
        Totals(
            input: a.input + b.input, output: a.output + b.output,
            cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead,
            reasoning: a.reasoning + b.reasoning, events: a.events + b.events,
            cost: a.cost + b.cost,
            subagent: a.subagent + b.subagent,
            subagentEvents: a.subagentEvents + b.subagentEvents
        )
    }
}

struct DayStat: Sendable, Identifiable {
    let day: Date
    var totals = Totals()
    var bySource: [SourceID: Totals] = [:]
    var id: Date { day }
}

struct ProjectStat: Sendable, Identifiable {
    let path: String
    var name: String
    var totals = Totals()
    var byModel: [String: Totals] = [:]
    var sources: Set<SourceID> = []
    var days: Set<Date> = []
    /// Tokens by local hour of day (0-23) and by day, so every analysis view can
    /// be scoped to one project without rescanning.
    var byHour: [Int: Int] = [:]
    var byDay: [Date: Int] = [:]
    var first: Date = .distantFuture
    var last: Date = .distantPast
    var id: String { path }

    var topModel: String? {
        byModel.max { $0.value.total < $1.value.total }?.key
    }

    /// Tokens in a window of `length` days ending `daysAgo` days before today, so
    /// the same call yields both sides of a period comparison.
    func tokens(inLast length: Int, endingDaysAgo daysAgo: Int = 0) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: -daysAgo, to: today),
              let start = calendar.date(byAdding: .day, value: -(length - 1), to: end)
        else { return 0 }
        return byDay.reduce(0) { sum, entry in
            entry.key >= start && entry.key <= end ? sum + entry.value : sum
        }
    }
}

struct NamedStat: Sendable, Identifiable {
    let name: String
    var totals = Totals()
    var days: Set<Date> = []
    var id: String { name }
}

/// Every aggregate the UI reads. Built once per scan, off the main actor.
struct Rollup: Sendable {
    var all = Totals()
    var byDay: [Date: DayStat] = [:]
    var byProject: [String: ProjectStat] = [:]
    var byModel: [String: NamedStat] = [:]
    var bySource: [SourceID: NamedStat] = [:]
    /// Local hour-of-day 0..23, for the "when do you code" ring.
    var byHour: [Int: Totals] = [:]

    var firstDay: Date?
    var lastDay: Date?
    var lastEventAt: Date?
    var eventCount = 0

    var activeDays: Int { byDay.count }

    /// Consecutive days with usage, counting back from today (or from the last
    /// active day if that was yesterday — a streak survives an unfinished today).
    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let last = lastDay else { return 0 }
        let gap = cal.dateComponents([.day], from: last, to: today).day ?? 0
        guard gap <= 1 else { return 0 }
        var streak = 0
        var cursor = last
        while byDay[cursor] != nil {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    var longestStreak: Int {
        let cal = Calendar.current
        let days = byDay.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, cal.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    func totals(inLast days: Int) -> Totals {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))
        else { return Totals() }
        return byDay.values.filter { $0.day >= cutoff }.reduce(Totals()) { $0 + $1.totals }
    }

    var today: Totals {
        byDay[Calendar.current.startOfDay(for: Date())]?.totals ?? Totals()
    }

    var thisMonth: Totals {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        guard let start = cal.date(from: comps) else { return Totals() }
        return byDay.values.filter { $0.day >= start }.reduce(Totals()) { $0 + $1.totals }
    }

    /// Mean tokens per active day — matches the "avg" pill in the header.
    var dailyAverage: Int {
        guard activeDays > 0 else { return 0 }
        return all.total / activeDays
    }

    var projectsRanked: [ProjectStat] {
        byProject.values.sorted { $0.totals.total > $1.totals.total }
    }

    var modelsRanked: [NamedStat] {
        byModel.values.sorted { $0.totals.total > $1.totals.total }
    }

    var sourcesRanked: [(SourceID, NamedStat)] {
        bySource.sorted { $0.value.totals.total > $1.value.totals.total }
    }

    /// Days ordered oldest-first, gaps filled with empty stats so charts and the
    /// heatmap get a continuous axis.
    func dayseries(from start: Date, to end: Date) -> [DayStat] {
        let cal = Calendar.current
        var out: [DayStat] = []
        var cursor = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while cursor <= last {
            out.append(byDay[cursor] ?? DayStat(day: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// Builds every aggregate over `events`, optionally restricted to a window.
    ///
    /// Range-scoped views get their own rollup rather than filtering an all-time
    /// one: model and project totals are not day-bucketed, so filtering after the
    /// fact would show all-time numbers under a range heading. Rebuilding is ~10ms
    /// for 15k events, which is cheaper than carrying a per-day index for each.
    /// Two different paths can reduce to the same leaf name — `code/api` and
    /// `archive/api` both read as "api", which puts two identically labelled rows
    /// in every list. Extend each clashing name with as many parent segments as it
    /// takes to become unique.
    private mutating func disambiguateProjectNames() {
        var pathsByName: [String: [String]] = [:]
        for (path, stat) in byProject {
            pathsByName[stat.name, default: []].append(path)
        }

        for (_, paths) in pathsByName where paths.count > 1 {
            for path in paths {
                let components = path.split(separator: "/").map(String.init)
                var depth = 2
                while depth <= components.count {
                    let label = components.suffix(depth).joined(separator: "/")
                    let clashes = paths.contains { other in
                        other != path
                            && other.split(separator: "/").map(String.init)
                                .suffix(depth).joined(separator: "/") == label
                    }
                    if !clashes {
                        byProject[path]?.name = label
                        break
                    }
                    depth += 1
                }
            }
        }
    }

    static func build(events: [UsageEvent], prices: PriceBook, since: Date? = nil) -> Rollup {
        let cal = Calendar.current
        var r = Rollup()

        for e in events {
            if let since, e.timestamp < since { continue }
            r.eventCount += 1
            let cost = prices.cost(of: e)
            let day = cal.startOfDay(for: e.timestamp)
            let hour = cal.component(.hour, from: e.timestamp)

            r.all.add(e, cost: cost)

            var dayStat = r.byDay[day] ?? DayStat(day: day)
            dayStat.totals.add(e, cost: cost)
            var sourceDay = dayStat.bySource[e.source] ?? Totals()
            sourceDay.add(e, cost: cost)
            dayStat.bySource[e.source] = sourceDay
            r.byDay[day] = dayStat

            let key = e.projectPath ?? "—unattributed—"
            var proj = r.byProject[key] ?? ProjectStat(
                path: key, name: UsageEvent.projectName(for: e.projectPath)
            )
            proj.totals.add(e, cost: cost)
            var projModel = proj.byModel[e.model] ?? Totals()
            projModel.add(e, cost: cost)
            proj.byModel[e.model] = projModel
            proj.sources.insert(e.source)
            proj.days.insert(day)
            proj.byHour[hour, default: 0] += e.totalTokens
            proj.byDay[day, default: 0] += e.totalTokens
            proj.first = min(proj.first, e.timestamp)
            proj.last = max(proj.last, e.timestamp)
            r.byProject[key] = proj

            var model = r.byModel[e.model] ?? NamedStat(name: e.model)
            model.totals.add(e, cost: cost)
            model.days.insert(day)
            r.byModel[e.model] = model

            var src = r.bySource[e.source] ?? NamedStat(name: e.source.displayName)
            src.totals.add(e, cost: cost)
            src.days.insert(day)
            r.bySource[e.source] = src

            var hourly = r.byHour[hour] ?? Totals()
            hourly.add(e, cost: cost)
            r.byHour[hour] = hourly

            if let last = r.lastEventAt {
                if e.timestamp > last { r.lastEventAt = e.timestamp }
            } else {
                r.lastEventAt = e.timestamp
            }
        }

        r.disambiguateProjectNames()
        r.firstDay = r.byDay.keys.min()
        r.lastDay = r.byDay.keys.max()
        return r
    }
}
