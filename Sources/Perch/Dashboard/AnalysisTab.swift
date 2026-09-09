import SwiftUI

/// Deep-dive analysis, scopeable to a single project.
///
/// Everything here answers a question the Overview cannot: how much of the spend
/// is cache, how much is delegated, when the work actually happens, and which
/// projects are moving week to week.
struct AnalysisTab: View {
    @ObservedObject var state: AppState
    /// `nil` scopes to every project. Owned by `RootView` so search can focus a
    /// project from anywhere in the app.
    @Binding var focus: String?

    private var projects: [ProjectStat] { state.rollup.projectsRanked }

    private var scoped: ProjectStat? {
        focus.flatMap { state.rollup.byProject[$0] }
    }

    private var totals: Totals {
        scoped?.totals ?? state.rollup.all
    }

    private var hours: [Int: Int] {
        if let scoped { return scoped.byHour }
        return state.rollup.byHour.mapValues(\.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            scopeBar
            insights
            HStack(alignment: .top, spacing: 16) {
                cachePanel
                delegationPanel
            }
            rhythmPanel
            momentumPanel
        }
    }

    // MARK: - Scope

    private var scopeBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All projects") { focus = nil }
                Divider()
                ForEach(projects.prefix(30)) { project in
                    Button(project.name) { focus = project.id }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scope").font(.system(size: 10))
                    Text(scoped?.name ?? "All projects")
                        .font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.raised, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let scoped {
                Text(Format.tildePath(scoped.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            } else {
                Text("\(projects.count) projects · \(Format.compact(totals.total)) tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
        }
    }

    // MARK: - Insights

    private var insights: some View {
        let peak = hours.max { $0.value < $1.value }
        let thisWeek = scoped?.tokens(inLast: 7) ?? state.rollup.totals(inLast: 7).total
        let lastWeek = scoped?.tokens(inLast: 7, endingDaysAgo: 7)
            ?? weekTotal(endingDaysAgo: 7)
        let change = lastWeek > 0
            ? (Double(thisWeek) - Double(lastWeek)) / Double(lastWeek) * 100
            : nil

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 12
        ) {
            InsightTile(
                value: "\(Int((totals.cacheHitRate * 100).rounded()))", unit: "%",
                headline: "served from cache",
                detail: "Cache reads bill at a tenth of an input token, so this is where the money is.",
                tint: Theme.series[2]
            )
            InsightTile(
                value: "\(Int((totals.subagentShare * 100).rounded()))", unit: "%",
                headline: "done by subagents",
                detail: "\(Format.compact(totals.subagent)) tokens of delegated work, invisible on the Overview.",
                tint: Theme.series[1]
            )
            InsightTile(
                value: peak.map { String(format: "%02d:00", $0.key) } ?? "—", unit: nil,
                headline: "busiest hour",
                detail: peak.map { "\(Format.compact($0.value)) tokens land in this hour across all days." } ?? "No activity recorded yet.",
                tint: Theme.series[0]
            )
            InsightTile(
                value: change.map { String(format: "%+.0f", $0) } ?? "—", unit: change != nil ? "%" : nil,
                headline: "vs last week",
                detail: "\(Format.compact(thisWeek)) this week against \(Format.compact(lastWeek)) the week before.",
                tint: (change ?? 0) >= 0 ? Theme.up : Theme.down
            )
        }
    }

    private func weekTotal(endingDaysAgo days: Int) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: -days, to: today),
              let start = calendar.date(byAdding: .day, value: -6, to: end) else { return 0 }
        return state.rollup.byDay.values
            .filter { $0.day >= start && $0.day <= end }
            .reduce(0) { $0 + $1.totals.total }
    }

    // MARK: - Cache

    private var cachePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelTitle("CACHE EFFICIENCY", "Where the tokens actually go")

            Meter(
                ratio: totals.cacheHitRate,
                label: "Cache hit rate",
                caption: "\(Format.compact(totals.cacheRead)) of \(Format.compact(totals.cacheRead + totals.cacheWrite + totals.input)) readable tokens came from cache.",
                tint: Theme.series[2]
            )

            CompositionBar(segments: [
                .init(name: "Cache read", value: totals.cacheRead, color: Theme.series[2]),
                .init(name: "Cache write", value: totals.cacheWrite, color: Theme.series[3]),
                .init(name: "Input", value: totals.input, color: Theme.series[0]),
                .init(name: "Output", value: totals.output, color: Theme.series[1]),
            ])

            if scoped == nil {
                Divider().overlay(Theme.hairline)
                HStack(spacing: 5) {
                    Text("LOWEST HIT RATE")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Text("Claude Code only")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                }
                ForEach(cacheRanking.prefix(6)) { project in
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .frame(width: 128, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.series[2])
                                    .frame(width: max(2, geo.size.width * CGFloat(project.totals.cacheHitRate)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int((project.totals.cacheHitRate * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    /// Worst first, and only projects where the ratio means something.
    ///
    /// Two filters, both load-bearing: a 100% hit rate on a thousand tokens is
    /// noise, and only Claude Code reports cache at all — listing a Cursor project
    /// at 0% would read as bad caching when it is simply unreported.
    private var cacheRanking: [ProjectStat] {
        projects
            .filter { $0.totals.total > 5_000_000 }
            .filter { $0.totals.cacheRead + $0.totals.cacheWrite > 0 }
            .sorted { $0.totals.cacheHitRate < $1.totals.cacheHitRate }
    }

    // MARK: - Delegation

    private var delegationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                panelTitle("DELEGATION", "Main thread against subagents")
                Spacer()
                // Only Claude Code marks delegated turns, so the share is diluted
                // by tools that cannot report it. Say so rather than let the
                // number read as lower delegation than actually happened.
                Text("Claude Code only")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
            }

            SplitBar(primary: totals.mainThread, secondary: totals.subagent, height: 18)
            FlowLegend(items: [
                ("Main thread", Theme.series[0], Format.percent(totals.mainThread, of: max(1, totals.total))),
                ("Subagents", Theme.series[1], Format.percent(totals.subagent, of: max(1, totals.total))),
            ])

            if scoped == nil {
                Divider().overlay(Theme.hairline)
                Text("BY PROJECT")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.tertiaryText)
                ForEach(delegationRanking.prefix(6)) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(project.name)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((project.totals.subagentShare * 100).rounded()))% delegated")
                                .font(.system(size: 10)).monospacedDigit()
                                .foregroundStyle(Theme.secondaryText)
                        }
                        SplitBar(
                            primary: project.totals.mainThread,
                            secondary: project.totals.subagent
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    private var delegationRanking: [ProjectStat] {
        projects.filter { $0.totals.total > 1_000_000 }
            .sorted { $0.totals.subagentShare > $1.totals.subagentShare }
    }

    // MARK: - Rhythm

    private var rhythmPanel: some View {
        let peak = hours.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                panelTitle("WORKING RHYTHM", "Tokens by hour of day, all days combined")
                Spacer()
                if let peak {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.series[1])
                            .frame(width: 9, height: 9)
                        Text("peak \(String(format: "%02d:00", peak.key))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            HourColumns(hours: hours)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    // MARK: - Momentum

    private var momentumPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelTitle("MOMENTUM", "Last 7 days against the 7 before")

            HStack(spacing: 0) {
                header("Project", width: 190, alignment: .leading)
                header("This week", width: 92)
                header("Last week", width: 92)
                header("Change", width: 82)
                Text("Volume")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
            }
            .padding(.bottom, 2)

            ForEach(momentum, id: \.project.id) { row in
                HStack(spacing: 0) {
                    Text(row.project.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .frame(width: 190, alignment: .leading)
                    Text(Format.compact(row.current))
                        .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 92, alignment: .trailing)
                    Text(Format.compact(row.previous))
                        .font(.system(size: 11.5)).monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 92, alignment: .trailing)
                    HStack {
                        Spacer()
                        DeltaChip(current: row.current, previous: row.previous, compact: true)
                    }
                    .frame(width: 82)
                    // A shared scale, so bar length is comparable between rows.
                    GeometryReader { geo in
                        let peak = CGFloat(max(1, momentum.map { max($0.current, $0.previous) }.max() ?? 1))
                        HStack(spacing: Mark.surfaceGap) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Theme.series[0])
                                .frame(width: max(1, geo.size.width * CGFloat(row.current) / peak))
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 12)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                }
            }

            HStack(spacing: 14) {
                FlowLegend(items: [("This week", Theme.series[0], "")])
                Spacer()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    private struct MomentumRow {
        let project: ProjectStat
        let current: Int
        let previous: Int
    }

    private var momentum: [MomentumRow] {
        let candidates = scoped.map { [$0] } ?? projects
        return candidates
            .map { MomentumRow(project: $0, current: $0.tokens(inLast: 7), previous: $0.tokens(inLast: 7, endingDaysAgo: 7)) }
            .filter { $0.current > 0 || $0.previous > 0 }
            .sorted { $0.current > $1.current }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Bits

    private func panelTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
        }
    }

    private func header(_ text: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.tertiaryText)
            .frame(width: width, alignment: alignment)
    }
}
