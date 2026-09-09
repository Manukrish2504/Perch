import SwiftUI

// Mark specs shared by every chart here: bars cap at 24pt and never fill their
// band, data-ends are 4pt rounded and square at the baseline, touching fills are
// separated by a 2pt surface gap rather than a stroke, and grid lines are solid
// hairlines one step off the surface. Text always wears text tokens — a coloured
// mark beside it carries identity.
enum Mark {
    static let maxBarThickness: CGFloat = 24
    static let dataEndRadius: CGFloat = 4
    static let surfaceGap: CGFloat = 2
}

/// A headline finding: the number leads, the sentence explains it.
///
/// Hero figures use proportional digits — tabular figures make a large standalone
/// number look loosely spaced.
struct InsightTile: View {
    let value: String
    let unit: String?
    let headline: String
    let detail: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    // A hairline of the tint along the top edge ties the tile to the
                    // panel it summarises without colouring any text.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [tint.opacity(0.55), Theme.hairline],
                                startPoint: .topLeading, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

/// A single ratio against its whole, on a same-ramp track.
///
/// A meter, not a two-slice pie: the reader compares one value to one limit.
struct Meter: View {
    let ratio: Double
    let label: String
    let caption: String
    var tint: Color = Theme.series[2]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: Mark.dataEndRadius, style: .continuous)
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
                }
            }
            .frame(height: 10)
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// Part-to-whole across a few classes, as one horizontal stacked bar.
///
/// Segments are separated by a surface gap, never a border. Labels ride the
/// legend rather than the segments, because interior segments have no free end to
/// put a label against.
struct CompositionBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let name: String
        let value: Int
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 18

    private var total: Int { max(1, segments.reduce(0) { $0 + $1.value }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let gaps = CGFloat(max(0, segments.filter { $0.value > 0 }.count - 1))
                let usable = max(0, geo.size.width - gaps * Mark.surfaceGap)
                HStack(spacing: Mark.surfaceGap) {
                    ForEach(segments.filter { $0.value > 0 }) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(2, usable * CGFloat(segment.value) / CGFloat(total)))
                            .help("\(segment.name): \(Format.full(segment.value)) tokens")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Mark.dataEndRadius, style: .continuous))
            }
            .frame(height: height)

            // A legend is always present for two or more series.
            FlowLegend(items: segments.map {
                (name: $0.name, color: $0.color,
                 note: Format.percent($0.value, of: total))
            })
        }
    }
}

/// Legend chips: a coloured mark carries identity, the text stays in text tokens.
struct FlowLegend: View {
    let items: [(name: String, color: Color, note: String)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.color)
                        .frame(width: 9, height: 9)
                    Text(item.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                    Text(item.note)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Hour-of-day volume: 24 ordered bins, so a column chart.
///
/// Emphasis form — the busiest hours carry the accent and the rest recede, because
/// the story is "when do you work", not "here are 24 equal categories". Only the
/// peak is direct-labelled; the rest is in the tooltip.
struct HourColumns: View {
    /// Tokens per local hour, 0...23.
    let hours: [Int: Int]
    var height: CGFloat = 132

    private var peak: Int { max(1, hours.values.max() ?? 1) }
    private var peakHour: Int { hours.max { $0.value < $1.value }?.key ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let slot = geo.size.width / 24
                let barWidth = min(Mark.maxBarThickness, slot * 0.62)
                ZStack(alignment: .bottom) {
                    // A single solid hairline baseline; no gridlines competing.
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            let value = hours[hour] ?? 0
                            let ratio = CGFloat(value) / CGFloat(peak)
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                UnevenRoundedRectangle(
                                    topLeadingRadius: Mark.dataEndRadius,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: Mark.dataEndRadius,
                                    style: .continuous
                                )
                                .fill(hour == peakHour ? Theme.series[1] : Theme.muted)
                                .frame(width: barWidth, height: max(value > 0 ? 3 : 0, geo.size.height * ratio))
                            }
                            .frame(width: slot)
                            .help("\(String(format: "%02d", hour)):00 · \(Format.full(value)) tokens")
                        }
                    }
                }
            }
            .frame(height: height)

            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    // Label every sixth hour; a tick under all 24 is unreadable.
                    Text(hour % 6 == 0 ? String(format: "%02d", hour) : "")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Change against a baseline: direction is carried by an arrow and a sign, so the
/// diverging colour is never the only channel.
struct DeltaChip: View {
    let current: Int
    let previous: Int
    var compact: Bool = false

    private var change: Double? {
        guard previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }

    var body: some View {
        let delta = change
        let rising = (delta ?? 0) >= 0
        let tint: Color = delta == nil ? Theme.neutralMid : (rising ? Theme.up : Theme.down)
        return HStack(spacing: 3) {
            Image(systemName: delta == nil ? "minus" : (rising ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            Text(delta.map { String(format: "%.0f%%", abs($0) * 100) } ?? "new")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Two-class part-to-whole per row — main thread against delegated subagents.
struct SplitBar: View {
    let primary: Int
    let secondary: Int
    var primaryColor: Color = Theme.series[0]
    var secondaryColor: Color = Theme.series[1]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, primary + secondary))
            let usable = max(0, geo.size.width - Mark.surfaceGap)
            HStack(spacing: Mark.surfaceGap) {
                if primary > 0 {
                    Rectangle().fill(primaryColor)
                        .frame(width: max(2, usable * CGFloat(primary) / total))
                }
                if secondary > 0 {
                    Rectangle().fill(secondaryColor)
                        .frame(width: max(2, usable * CGFloat(secondary) / total))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: height)
    }
}
