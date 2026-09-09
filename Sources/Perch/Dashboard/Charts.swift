import SwiftUI
import Charts

/// Daily token volume, stacked by tool.
struct TrendChart: View {
    let days: [DayStat]
    var showCost: Bool = false

    private struct Bar: Identifiable {
        let id = UUID()
        let day: Date
        let source: SourceID
        let value: Int
    }

    private var bars: [Bar] {
        days.flatMap { day in
            day.bySource
                .filter { $0.value.total > 0 }
                .map { Bar(day: day.day, source: $0.key, value: $0.value.total) }
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Day", bar.day, unit: .day),
                y: .value("Tokens", bar.value)
            )
            .foregroundStyle(by: .value("Tool", bar.source.displayName))
        }
        .chartForegroundStyleScale(range: Theme.series)
        .chartLegend(position: .bottom, spacing: 8)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(Format.compact(n))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Format.monthDay.string(from: date))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
    }
}

/// Horizontal share bar used for model and project breakdowns.
struct ShareRow: View {
    let rank: Int
    let title: String
    let subtitle: String?
    let value: Int
    let whole: Int
    var color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.07)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(Format.compact(value))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text(Format.percent(value, of: whole))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 42, alignment: .trailing)
            }

            GeometryReader { geo in
                let ratio = whole > 0 ? CGFloat(value) / CGFloat(whole) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color).frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
    }
}

/// A smooth filled trace, for widgets where a bar sparkline would read as noise.
struct AreaSparkline: View {
    let values: [Int]
    var color: Color = Theme.cool

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard values.count > 1 else { return }
            let peak = CGFloat(max(values.max() ?? 1, 1))
            let step = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - (CGFloat(value) / peak) * (size.height - 2) - 1
                )
            }

            // Midpoint quad curves: smooth without overshooting below zero the way
            // a cubic spline through raw points does.
            var line = Path()
            line.move(to: points[0])
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                line.addQuadCurve(to: mid, control: previous)
            }
            line.addLine(to: points[points.count - 1])

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.42), color.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(color), lineWidth: 1.6)
        }
    }
}
