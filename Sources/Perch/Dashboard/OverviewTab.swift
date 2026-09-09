import SwiftUI

struct OverviewTab: View {
    @ObservedObject var state: AppState
    let range: DateRange

    /// Range-scoped. All-time facts (the pills, "started", streak) deliberately
    /// read `state.rollup` instead, because they are labelled as all-time.
    private var scoped: Rollup { RangeSlice.rollup(state, range) }
    private var days: [DayStat] { RangeSlice.days(scoped, range) }
    private var totals: Totals { scoped.all }

    var body: some View {
        VStack(spacing: 16) {
            headline
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    pills
                    topModels
                    heatmapCard
                }
                .frame(width: 372)

                VStack(spacing: 16) {
                    toolCards
                    trendCard
                    dailyTable
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 6) {
            Text("TOTAL TOKENS · \(range.rawValue.uppercased())")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.tertiaryText)

            Text(Format.full(totals.total))
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if state.settings.showCost {
                HStack(spacing: 5) {
                    Text(Format.money(totals.cost))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.positive)
                    Text("est. API cost")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            distributionBar
                .frame(height: 5)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .perchCard(padding: 16)
    }

    /// One continuous bar showing each tool's share of the selected range.
    private var distributionBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(sourceShares.enumerated()), id: \.offset) { index, entry in
                    let ratio = totals.total > 0 ? CGFloat(entry.1) / CGFloat(totals.total) : 0
                    Capsule()
                        .fill(Theme.seriesColor(index))
                        .frame(width: max(2, geo.size.width * ratio))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var sourceShares: [(SourceID, Int)] {
        var totalsBySource: [SourceID: Int] = [:]
        for day in days {
            for (source, stat) in day.bySource {
                totalsBySource[source, default: 0] += stat.total
            }
        }
        return totalsBySource.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: - Pills

    private var pills: some View {
        HStack(spacing: 8) {
            pill(Format.compact(state.rollup.today.total), "today")
            pill(Format.compact(state.rollup.totals(inLast: 7).total), "7d")
            pill(Format.compact(state.rollup.totals(inLast: 30).total), "30d")
            pill(Format.compact(state.rollup.dailyAverage), "avg/day")
        }
    }

    private func pill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Cards

    private var topModels: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP MODELS")
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)

            let ranked = modelsInRange
            let whole = ranked.reduce(0) { $0 + $1.1 }
            ForEach(Array(ranked.prefix(5).enumerated()), id: \.offset) { index, entry in
                ShareRow(
                    rank: index + 1, title: entry.0, subtitle: nil,
                    value: entry.1, whole: whole, color: Theme.seriesColor(index)
                )
            }

            Divider().overlay(Theme.hairline).padding(.vertical, 2)

            HStack {
                label("Started", state.rollup.firstDay.map { Format.day.string(from: $0) } ?? "—")
                Spacer()
                label("Active days", "\(state.rollup.activeDays)")
                Spacer()
                label("Streak", "\(state.rollup.currentStreak)d")
            }
        }
        .perchCard()
    }

    private var modelsInRange: [(String, Int)] {
        scoped.modelsRanked.map { ($0.name, $0.totals.total) }
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(Theme.tertiaryText)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }

    private var heatmapCard: some View {
        HeatmapCard(days: heatmapDays).perchCard()
    }

    private var heatmapDays: [DayStat] {
        let end = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -181, to: end) ?? end
        return state.rollup.dayseries(from: start, to: end)
    }

    private var toolCards: some View {
        let shares = sourceShares
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(entry.0.glyph)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.seriesColor(index))
                        Text(entry.0.displayName.uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Text(Format.percent(entry.1, of: totals.total))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text(Format.compact(entry.1) + " tokens")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("USAGE TREND")
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            TrendChart(days: days)
                .frame(height: 190)
        }
        .perchCard()
    }

    private var dailyTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DAILY BREAKDOWN")
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.bottom, 10)

            HStack(spacing: 0) {
                headerCell("Date", width: 96, alignment: .leading)
                headerCell("Total", width: 84)
                headerCell("Input", width: 74)
                headerCell("Output", width: 74)
                headerCell("Cached", width: 84)
                headerCell("Reasoning", width: 78)
                if state.settings.showCost { headerCell("Cost", width: 68) }
            }
            .padding(.bottom, 6)

            ForEach(days.reversed().filter { $0.totals.total > 0 }.prefix(14)) { day in
                HStack(spacing: 0) {
                    cell(Format.day.string(from: day.day), width: 96, alignment: .leading, color: Theme.secondaryText)
                    cell(Format.full(day.totals.total), width: 84, weight: .medium)
                    cell(Format.full(day.totals.input), width: 74)
                    cell(Format.full(day.totals.output), width: 74)
                    cell(Format.full(day.totals.cacheRead + day.totals.cacheWrite), width: 84)
                    cell(Format.full(day.totals.reasoning), width: 78)
                    if state.settings.showCost {
                        cell(Format.money(day.totals.cost), width: 68, color: Theme.positive)
                    }
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                }
            }
        }
        .perchCard()
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.tertiaryText)
            .frame(width: width, alignment: alignment)
    }

    private func cell(
        _ text: String, width: CGFloat, alignment: Alignment = .trailing,
        weight: Font.Weight = .regular, color: Color = Theme.primaryText
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: width, alignment: alignment)
            .lineLimit(1)
    }
}
