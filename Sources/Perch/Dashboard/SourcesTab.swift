import SwiftUI

struct SourcesTab: View {
    @ObservedObject var state: AppState

    /// What each adapter reads, and where it is honestly limited. Shown in the UI
    /// so a zero is never mistaken for "you didn't use this tool".
    private static let detail: [SourceID: (path: String, reads: String, limits: String?)] = [
        .claudeCode: (
            "~/.claude/projects/**/*.jsonl",
            "Per-message model, token split, and the session's working directory.",
            nil
        ),
        .codex: (
            "~/.codex/sessions/**/rollout-*.jsonl",
            "Cumulative session counters, differenced per turn; model from turn context.",
            "Codex re-emits its counters on every stream tick, so Perch reads the cumulative total and takes deltas rather than summing per-turn rows."
        ),
        .cursor: (
            "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "Per-conversation input/output tokens, dated from the conversation record.",
            "Cursor records no model name locally, so usage is grouped by mode instead. Most conversations record no folder, so they land in Unattributed rather than a guessed project."
        ),
        .antigravity: (
            "~/.gemini/antigravity*/brain/**/*.jsonl",
            "Gemini usageMetadata token counts, when transcripts are written.",
            "This install writes no transcripts carrying token counts, so it contributes nothing. The adapter stays wired up in case a later build does."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SourceID.allCases, id: \.self) { source in
                card(source)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Perch never writes to any of these", systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text("""
                     Every adapter opens files read-only and SQLite in read-only mode. \
                     No hooks are installed, no config is edited, and no prompt or response \
                     text is ever parsed — only counts, model ids, paths and timestamps.
                     """)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .perchCard()
        }
    }

    private func card(_ source: SourceID) -> some View {
        let stat = state.rollup.bySource[source]
        let note = state.notes[source.rawValue]
        let info = Self.detail[source]
        let active = (stat?.totals.total ?? 0) > 0

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(source.glyph)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? Theme.accent : Theme.tertiaryText)
                Text(source.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Text(active ? "reading" : "no data")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(active ? Theme.positive : Theme.tertiaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((active ? Theme.positive : Theme.tertiaryText).opacity(0.14), in: Capsule())

                Spacer()

                if let stat, active {
                    HStack(spacing: 16) {
                        figure(Format.compact(stat.totals.total), "tokens")
                        figure(Format.compact(stat.totals.events), "requests")
                        figure("\(stat.days.count)", "days")
                        if state.settings.showCost {
                            figure(Format.money(stat.totals.cost), "cost")
                        }
                    }
                }
            }

            if let info {
                Text(info.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                Text(info.reads)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            if let message = note ?? info?.limits {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
        }
    }
}
