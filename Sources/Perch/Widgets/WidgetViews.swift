import SwiftUI

/// Shared widget chrome. Matches macOS widget geometry: one continuous corner
/// radius, generous padding, vibrancy, no visible border — the system draws the
/// separation with a shadow, and a stroked outline is what made these read as
/// "app window", not "widget".
struct WidgetChrome<Content: View>: View {
    let size: WidgetSize
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(size == .small ? 14 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(VibrantBackground())
            .background(Color.black.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: WidgetSize.cornerRadius, style: .continuous))
            .preferredColorScheme(.dark)
    }
}

struct WidgetRoot: View {
    let kind: WidgetKind
    let size: WidgetSize
    @ObservedObject var state: AppState

    var body: some View {
        WidgetChrome(size: size) {
            switch kind {
            case .usage: UsageWidget(state: state, size: size)
            case .heatmap: HeatmapWidget(state: state, size: size)
            case .models: ModelsWidget(state: state, size: size)
            case .trend: TrendWidget(state: state, size: size)
            case .limits: LimitsWidget(state: state, size: size)
            }
        }
        .overlay {
            if state.isArranging { arrangeBadge }
        }
        // Widgets are display-only so the entire face stays a drag handle.
        .allowsHitTesting(false)
    }
}

private extension WidgetRoot {
    /// Shown only while arranging, so it is obvious which surface can be dragged.
    var arrangeBadge: some View {
        RoundedRectangle(cornerRadius: WidgetSize.cornerRadius, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.85), lineWidth: 2)
            .overlay(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(kind.title)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
                .offset(y: -9)
            }
    }
}

// MARK: - Shared pieces

/// A widget's title row, in the system's widget-header idiom.
private struct WidgetHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

private struct WidgetFigure: View {
    let label: String
    let value: String
    var sub: String?
    var valueSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let sub {
                Text(sub)
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Theme.positive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func lastDays(_ rollup: Rollup, _ count: Int) -> [DayStat] {
    let end = Calendar.current.startOfDay(for: Date())
    let start = Calendar.current.date(byAdding: .day, value: -(count - 1), to: end) ?? end
    return rollup.dayseries(from: start, to: end)
}

// MARK: - Widgets

struct UsageWidget: View {
    @ObservedObject var state: AppState
    let size: WidgetSize

    private var cost: (Totals) -> String? {
        { state.settings.showCost ? Format.money($0.cost) : nil }
    }

    var body: some View {
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: "Today")
                Spacer(minLength: 2)
                Text(Format.compact(state.rollup.today.total))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let money = cost(state.rollup.today) {
                    Text(money).font(.system(size: 12)).foregroundStyle(Theme.positive)
                }
                Spacer(minLength: 4)
                AreaSparkline(values: lastDays(state.rollup, 14).map(\.totals.total))
                    .frame(height: 34)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    WidgetFigure(
                        label: "Today", value: Format.compact(state.rollup.today.total),
                        sub: cost(state.rollup.today)
                    )
                    WidgetFigure(
                        label: "7 days", value: Format.compact(state.rollup.totals(inLast: 7).total),
                        sub: cost(state.rollup.totals(inLast: 7))
                    )
                }
                AreaSparkline(values: lastDays(state.rollup, 14).map(\.totals.total))
                    .frame(maxHeight: .infinity)
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    WidgetFigure(
                        label: "Today", value: Format.compact(state.rollup.today.total),
                        sub: cost(state.rollup.today)
                    )
                    WidgetFigure(
                        label: "7 days", value: Format.compact(state.rollup.totals(inLast: 7).total),
                        sub: cost(state.rollup.totals(inLast: 7))
                    )
                }
                AreaSparkline(values: lastDays(state.rollup, 30).map(\.totals.total))
                    .frame(height: 92)
                Divider().overlay(Theme.hairline)
                WidgetHeader(title: "Top projects")
                ForEach(Array(state.rollup.projectsRanked.prefix(4).enumerated()), id: \.offset) { index, project in
                    HStack(spacing: 7) {
                        Circle().fill(Theme.seriesColor(index)).frame(width: 6, height: 6)
                        Text(project.name)
                            .font(.system(size: 11.5)).foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Format.compact(project.totals.total))
                            .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct HeatmapWidget: View {
    @ObservedObject var state: AppState
    let size: WidgetSize

    private var days: [DayStat] { lastDays(state.rollup, size == .large ? 182 : 119) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                title: "Activity",
                trailing: "\(state.rollup.currentStreak)d streak"
            )
            if state.settings.heatmap3D {
                ActivityHeatmap3D(
                    days: days,
                    tile: CGSize(width: size == .large ? 6.4 : 5.2, height: size == .large ? 3.2 : 2.6),
                    maxLift: size == .large ? 40 : 26
                )
                .frame(maxHeight: .infinity)
            } else {
                ActivityHeatmap(days: days, cell: size == .large ? 9 : 6.6, spacing: 2)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            HStack(spacing: 4) {
                Text(Format.compact(state.rollup.all.total))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text("tokens · \(state.rollup.activeDays) active days")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

struct ModelsWidget: View {
    @ObservedObject var state: AppState
    let size: WidgetSize

    var body: some View {
        let count = size == .large ? 8 : 4
        let models = state.rollup.modelsRanked.prefix(count)
        let whole = state.rollup.all.total
        return VStack(alignment: .leading, spacing: size == .large ? 9 : 7) {
            WidgetHeader(title: "Top Models")
            ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.seriesColor(index)).frame(width: 6, height: 6)
                        Text(model.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Format.compact(model.totals.total))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                        Text(Format.percent(model.totals.total, of: whole))
                            .font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 34, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        let ratio = whole > 0 ? CGFloat(model.totals.total) / CGFloat(whole) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.09))
                            Capsule().fill(Theme.seriesColor(index))
                                .frame(width: max(2, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct TrendWidget: View {
    @ObservedObject var state: AppState
    let size: WidgetSize

    var body: some View {
        let days = lastDays(state.rollup, 30)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WidgetFigure(
                    label: "Today", value: Format.compact(state.rollup.today.total), valueSize: 21
                )
                WidgetFigure(
                    label: "7 days", value: Format.compact(state.rollup.totals(inLast: 7).total),
                    valueSize: 21
                )
                WidgetFigure(
                    label: "30 days", value: Format.compact(state.rollup.totals(inLast: 30).total),
                    valueSize: 21
                )
            }
            TrendChart(days: days)
                .frame(maxHeight: .infinity)
        }
    }
}

struct LimitsWidget: View {
    @ObservedObject var state: AppState
    let size: WidgetSize

    /// Tokens consumed in the trailing five hours — Perch's own measure, shown
    /// because Claude reports no percentage of its 5-hour window.
    private var rollingFiveHour: Int {
        state.recentTokens(since: Date().addingTimeInterval(-5 * 3_600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetHeader(title: "Limits")

            if state.limits.isEmpty {
                Text("No tool has written a quota reading yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }

            ForEach(state.limits.prefix(size == .large ? 6 : 2)) { row($0, compact: size != .large) }

            Spacer(minLength: 0)
            Divider().overlay(Theme.hairline)
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text("Last 5h").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(Format.compact(rollingFiveHour) + " tokens")
                    .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }

    private func row(_ window: LimitWindow, compact: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(window.source.glyph)
                    .font(.system(size: 8)).foregroundStyle(Theme.secondaryText)
                Text("\(window.source.displayName) · \(window.label)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let percent = window.usedPercent {
                    Text("\(Int(percent))%")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                } else if window.hits > 0 {
                    Text("hit \(window.hits)× / 7d")
                        .font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
            if let percent = window.usedPercent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(percent > 80 ? Theme.accent : Theme.positive)
                            .frame(width: max(2, geo.size.width * CGFloat(percent / 100)))
                    }
                }
                .frame(height: 3)
            }
            if !compact || window.resetsIn != nil || window.isStale {
                HStack(spacing: 4) {
                    if let remaining = window.resetsIn {
                        Text("resets in \(LimitWindow.countdown(remaining))")
                            .font(.system(size: 9.5)).foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer()
                    if window.isStale {
                        // Never present an old reading as a live gauge.
                        Text("as of \(Format.relative(window.observedAt))")
                            .font(.system(size: 9.5)).foregroundStyle(Theme.tertiaryText)
                    }
                }
                .lineLimit(1)
            }
        }
    }
}
