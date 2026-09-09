import SwiftUI

struct ModelsTab: View {
    @ObservedObject var state: AppState
    let range: DateRange

    private var scoped: Rollup { RangeSlice.rollup(state, range) }

    private var models: [NamedStat] { scoped.modelsRanked }

    private var whole: Int { models.reduce(0) { $0 + $1.totals.total } }

    /// Which projects each model was used in — the cross-tab the Projects view
    /// answers in the other direction.
    private func projects(using model: String) -> [String] {
        scoped.byProject.values
            .filter { $0.byModel[model] != nil }
            .sorted { ($0.byModel[model]?.total ?? 0) > ($1.byModel[model]?.total ?? 0) }
            .prefix(4)
            .map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    row(index: index, model: model)
                    if index < models.count - 1 {
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                }
            }
            .perchCard(padding: 0)
        }
    }

    private func row(index: Int, model: NamedStat) -> some View {
        let rate = state.prices.rate(for: model.name)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(Theme.seriesColor(index)).frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                        if rate == .unknown {
                            tag("unpriced", Theme.tertiaryText)
                        } else if rate.estimated {
                            tag("estimated rate", Theme.accent)
                        }
                    }
                    Text(projects(using: model.name).joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                metric("\(model.days.count)", "days")
                metric(Format.compact(model.totals.events), "requests")
                metric(Format.compact(model.totals.output), "output")

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.compact(model.totals.total))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text(Format.percent(model.totals.total, of: whole))
                        .font(.system(size: 9.5)).monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(width: 66, alignment: .trailing)

                if state.settings.showCost {
                    Text(Format.money(model.totals.cost))
                        .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.positive)
                        .frame(width: 66, alignment: .trailing)
                }
            }

            GeometryReader { geo in
                let ratio = whole > 0 ? CGFloat(model.totals.total) / CGFloat(whole) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Capsule().fill(Theme.seriesColor(index)).frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
        }
        .frame(width: 62, alignment: .trailing)
    }
}
