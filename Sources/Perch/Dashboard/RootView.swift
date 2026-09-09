import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview, projects, analysis, models, pet, widgets, sources, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .analysis: "Analysis"
        case .models: "Models"
        case .pet: "Pet"
        case .widgets: "Widgets"
        case .sources: "Sources"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "chart.bar.fill"
        case .projects: "folder.fill"
        case .analysis: "chart.xyaxis.line"
        case .models: "cpu.fill"
        case .pet: "pawprint.fill"
        case .widgets: "square.grid.2x2.fill"
        case .sources: "cable.connector"
        case .settings: "gearshape.fill"
        }
    }
}

/// The time window every view pivots on.
enum DateRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case total = "Total"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .day: "sun.max.fill"
        case .week: "calendar"
        case .month: "calendar.badge.clock"
        case .total: "infinity"
        }
    }

    var days: Int? {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .total: nil
        }
    }
}

struct RootView: View {
    @ObservedObject var state: AppState
    @Local private var tab: DashboardTab
    @Local private var range: DateRange = .month
    @Local private var analysisFocus: String?

    init(state: AppState, initialTab: DashboardTab = .overview) {
        self.state = state
        _tab = Local(wrappedValue: initialTab)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Theme.hairline)
                content
            }
            // The chrome is built underneath while the run plays, so the dashboard
            // is already laid out when it is revealed rather than assembling itself
            // in front of the reader.
            .opacity(state.introStartedAt == nil ? 1 : 0)

            if let started = state.introStartedAt {
                DashboardLoader(state: state, startedAt: started)
                    .transition(.opacity)
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.4), value: state.introStartedAt)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PetView(status: state.pet, species: state.species, showsExtras: false)
                    .frame(width: 34, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Perch").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(state.pet.caption).font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)

            group("GENERAL", [.overview, .projects, .analysis, .models])
            group("TOOLS", [.pet, .widgets, .sources])

            Spacer()

            group("", [.settings])

            HStack(spacing: 6) {
                Circle()
                    .fill(state.isScanning ? Theme.accent : Theme.positive)
                    .frame(width: 5, height: 5)
                Text(state.isScanning ? "Scanning…" : "Live")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if state.scanDuration > 0 {
                    Text(String(format: "%.1fs", state.scanDuration))
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 186)
        .background(Theme.surface)
    }

    private func group(_ title: String, _ tabs: [DashboardTab]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            ForEach(tabs) { item in
                Button { tab = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11))
                            .frame(width: 15)
                        Text(item.title).font(.system(size: 12.5))
                        Spacer()
                    }
                    .foregroundStyle(tab == item ? Theme.primaryText : Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(tab == item ? Color.white.opacity(0.09) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            ScrollView {
                Group {
                    switch tab {
                    case .overview: OverviewTab(state: state, range: range)
                    case .projects: ProjectsTab(state: state, range: range)
                    case .analysis: AnalysisTab(state: state, focus: $analysisFocus)
                    case .models: ModelsTab(state: state, range: range)
                    case .pet: PetTab(state: state)
                    case .widgets: WidgetsTab(state: state)
                    case .sources: SourcesTab(state: state)
                    case .settings: SettingsTab(state: state)
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(tab.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Spacer()

            // Search sits in the header on every page, so a project is always one
            // keystroke away regardless of where you are.
            SearchBar(
                state: state,
                onOpenProject: { path in
                    analysisFocus = path
                    tab = .analysis
                },
                onOpenModel: { _ in tab = .models }
            )
            .zIndex(10)

            if tab == .overview || tab == .projects || tab == .models {
                PillSegmented(
                    selection: $range,
                    options: DateRange.allCases.map { .init($0, $0.rawValue, $0.icon) }
                )
            }

            Button { state.rescanNow() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(6)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(state.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .zIndex(10)
    }
}

/// Shared helpers for the range-aware tabs.
enum RangeSlice {
    /// The rollup built for this window. Views must read this rather than
    /// filtering the all-time rollup, whose model and project totals are not
    /// day-bucketed and would report all-time figures under a range heading.
    @MainActor
    static func rollup(_ state: AppState, _ range: DateRange) -> Rollup {
        state.scoped[range] ?? state.rollup
    }

    static func days(_ rollup: Rollup, _ range: DateRange) -> [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = max(rollup.lastDay ?? today, today)
        let start: Date
        if let window = range.days {
            start = calendar.date(byAdding: .day, value: -(window - 1), to: today) ?? today
        } else {
            start = rollup.firstDay ?? today
        }
        return rollup.dayseries(from: start, to: end)
    }
}
