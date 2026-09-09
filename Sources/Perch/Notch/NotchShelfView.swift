import SwiftUI

/// The black body of the shelf: square at the top where it meets the screen edge,
/// rounded at the bottom so it reads as the cutout having grown downward.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// A 14-day token sparkline, normalised to its own peak.
struct Sparkline: View {
    let values: [Int]
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 1, 1)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count) : geo.size.width
            HStack(alignment: .bottom, spacing: max(0.5, step * 0.22)) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let ratio = CGFloat(value) / CGFloat(peak)
                    RoundedRectangle(cornerRadius: 0.6)
                        .fill(color.opacity(value == 0 ? 0.18 : 0.55 + 0.45 * ratio))
                        .frame(height: max(1, geo.size.height * ratio))
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}

/// The pulsing activity dot: bright and beating when a request just landed.
struct ActivityDot: View {
    let mood: PetMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let t = timeline.date.timeIntervalSince1970
            let pulse = mood == .rest ? 0 : abs(sin(t * (mood == .burst ? 3.4 : 1.3)))
            Circle()
                .fill(color)
                .opacity(0.45 + 0.55 * pulse)
                .frame(width: 5, height: 5)
        }
    }

    private var color: Color {
        switch mood {
        case .burst: Theme.positive
        case .focus: Theme.accent
        case .calm: Theme.accent.opacity(0.7)
        case .rest: Theme.tertiaryText
        }
    }
}

struct NotchShelfView: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry
    let expanded: Bool
    var onOpenDashboard: () -> Void

    private var recentDays: [Int] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -13, to: end) ?? end
        return state.rollup.dayseries(from: start, to: end).map(\.totals.total)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: expanded ? 20 : Theme.notchRadius)
                .fill(Theme.notchBlack)

            VStack(spacing: 0) {
                // The cutout itself has no pixels, so nothing is ever drawn here.
                Color.clear.frame(height: geometry.notchHeight)
                if expanded { expandedBody } else { idleBody }
            }
        }
        .clipShape(NotchShape(bottomRadius: expanded ? 20 : Theme.notchRadius))
    }

    // MARK: - Idle

    private var idleBody: some View {
        HStack(spacing: 7) {
            PetView(status: state.pet, species: state.species, showsExtras: false)
                .frame(width: 42, height: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.compact(state.shelfTotals.total))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text(state.settings.shelfMetric == .today ? "today" : state.settings.shelfMetric.label.lowercased())
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if state.rollup.currentStreak > 0 {
                        Text("\(state.rollup.currentStreak)d")
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ActivityDot(mood: state.pet.mood)
                }
                Sparkline(values: recentDays)
                    .frame(width: 42, height: 13)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 3)
        .frame(height: NotchGeometry.idleDrop)
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                petColumn
                statsColumn
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer(minLength: 6)
            footer
        }
        .frame(height: NotchGeometry.expandedDrop)
    }

    private var petColumn: some View {
        VStack(spacing: 3) {
            PetView(status: state.pet, species: state.species)
                .frame(width: 96, height: 62)
            Text(state.species.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(state.pet.caption)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 92)
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                metric("TODAY", Format.compact(state.rollup.today.total))
                metric("7 DAYS", Format.compact(state.rollup.totals(inLast: 7).total))
                metric("STREAK", "\(state.rollup.currentStreak)d")
                if state.settings.showCost {
                    metric("COST", Format.money(state.rollup.today.cost))
                }
            }

            if let project = state.pet.topProjectToday {
                HStack(spacing: 5) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    Text(project)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text("busiest today")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Sparkline(values: recentDays)
                .frame(height: 26)

            HStack(spacing: 6) {
                ForEach(state.rollup.sourcesRanked.prefix(4), id: \.0) { source, stat in
                    HStack(spacing: 3) {
                        Text(source.glyph).font(.system(size: 8))
                        Text(Format.compact(stat.totals.total))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpenDashboard) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 9))
                    Text("Dashboard").font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.11), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if state.isScanning {
                Text("scanning…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
            } else if let last = state.rollup.lastEventAt {
                Text(Format.relative(last))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 11)
    }
}
