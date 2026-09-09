import SwiftUI

/// Per-project attribution — the view the whole app exists for.
struct ProjectsTab: View {
    @ObservedObject var state: AppState
    let range: DateRange
    @Local private var expanded: String?
    @Local private var sort: Sort = .tokens

    enum Sort: String, CaseIterable, Identifiable {
        case tokens = "Tokens"
        case recent = "Recent"
        case days = "Active days"
        case cost = "Cost"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .tokens: "number"
            case .recent: "clock.arrow.circlepath"
            case .days: "calendar"
            case .cost: "dollarsign.circle.fill"
            }
        }
    }

    private var scoped: Rollup { RangeSlice.rollup(state, range) }

    private var projects: [ProjectStat] {
        let inRange = scoped.byProject.values
        return switch sort {
        case .tokens: inRange.sorted { $0.totals.total > $1.totals.total }
        case .recent: inRange.sorted { $0.last > $1.last }
        case .days: inRange.sorted { $0.days.count > $1.days.count }
        case .cost: inRange.sorted { $0.totals.cost > $1.totals.cost }
        }
    }

    private var whole: Int { projects.reduce(0) { $0 + $1.totals.total } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            HStack {
                Text("\(projects.count) projects")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                PillSegmented(
                    selection: $sort,
                    options: Sort.allCases.map { .init($0, $0.rawValue, $0.icon) }
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    row(index: index, project: project)
                    if index < projects.count - 1 {
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                }
            }
            .perchCard(padding: 0)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            summaryCard("Projects", "\(projects.count)", "tracked")
            summaryCard(
                "Busiest",
                projects.first?.name ?? "—",
                projects.first.map { Format.compact($0.totals.total) + " tokens" } ?? ""
            )
            summaryCard(
                "Most days",
                projects.max { $0.days.count < $1.days.count }?.name ?? "—",
                projects.max { $0.days.count < $1.days.count }.map { "\($0.days.count) days" } ?? ""
            )
            summaryCard(
                "Last touched",
                projects.max { $0.last < $1.last }?.name ?? "—",
                projects.max { $0.last < $1.last }.map { Format.relative($0.last) } ?? ""
            )
        }
    }

    private func summaryCard(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func row(index: Int, project: ProjectStat) -> some View {
        VStack(spacing: 0) {
            Button {
                expanded = expanded == project.id ? nil : project.id
            } label: {
                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 22, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                            Text(project.path == "—unattributed—"
                                 ? "no path recorded by the tool"
                                 : Format.tildePath(project.path))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 10)

                        HStack(spacing: 4) {
                            ForEach(Array(project.sources).sorted { $0.rawValue < $1.rawValue }, id: \.self) { source in
                                Text(source.glyph)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(width: 52, alignment: .leading)

                        stat("\(project.byModel.count)", "models", width: 54)
                        stat("\(project.days.count)", "days", width: 48)
                        stat(Format.relative(project.last), "last", width: 68)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Format.compact(project.totals.total))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.primaryText)
                            Text(Format.percent(project.totals.total, of: whole))
                                .font(.system(size: 9.5)).monospacedDigit()
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .frame(width: 66, alignment: .trailing)

                        if state.settings.showCost {
                            Text(Format.money(project.totals.cost))
                                .font(.system(size: 11.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.positive)
                                .frame(width: 62, alignment: .trailing)
                        }

                        Image(systemName: expanded == project.id ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 14)
                    }

                    GeometryReader { geo in
                        let ratio = whole > 0 ? CGFloat(project.totals.total) / CGFloat(whole) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.05))
                            Capsule().fill(Theme.seriesColor(index)).frame(width: max(2, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded == project.id { detail(project) }
        }
        .background(expanded == project.id ? Color.white.opacity(0.03) : .clear)
    }

    private func stat(_ value: String, _ label: String, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
        }
        .frame(width: width, alignment: .trailing)
    }

    private func detail(_ project: ProjectStat) -> some View {
        let models = project.byModel.sorted { $0.value.total > $1.value.total }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODELS USED HERE")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                    ForEach(Array(models.enumerated()), id: \.offset) { index, entry in
                        ShareRow(
                            rank: index + 1, title: entry.key, subtitle: nil,
                            value: entry.value.total, whole: project.totals.total,
                            color: Theme.seriesColor(index)
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("BREAKDOWN")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                    detailRow("Input", Format.full(project.totals.input))
                    detailRow("Output", Format.full(project.totals.output))
                    detailRow("Cache write", Format.full(project.totals.cacheWrite))
                    detailRow("Cache read", Format.full(project.totals.cacheRead))
                    detailRow("Reasoning", Format.full(project.totals.reasoning))
                    detailRow("Requests", Format.full(project.totals.events))
                    detailRow("First seen", Format.day.string(from: project.first))
                    detailRow("Last seen", Format.day.string(from: project.last))
                }
                .frame(width: 240)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }
}
