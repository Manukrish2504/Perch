import Foundation

/// Which AI coding tool produced a record.
enum SourceID: String, Codable, Sendable, CaseIterable, Hashable {
    case claudeCode
    case codex
    case cursor
    case antigravity

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        }
    }

    /// Single-glyph mark used on the shelf and the tool cards.
    var glyph: String {
        switch self {
        case .claudeCode: "✳"
        case .codex: "◆"
        case .cursor: "▶"
        case .antigravity: "▲"
        }
    }
}

/// One billable exchange, normalised across every tool.
///
/// Counts only. No prompt or response text ever reaches this type — see
/// `agent-os/standards/data/source-adapters.md`.
struct UsageEvent: Codable, Sendable, Hashable {
    /// Stable across rescans, so re-reading a file cannot double-count.
    let dedupeKey: String
    let timestamp: Date
    let source: SourceID
    let model: String
    /// Absolute working directory. `nil` when the tool did not record one.
    let projectPath: String?

    let inputTokens: Int
    let outputTokens: Int
    /// Split because 5-minute and 1-hour cache writes bill at different multiples.
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheReadTokens: Int
    /// A subset of `outputTokens`; reported for display, never added to the total.
    let reasoningTokens: Int
    /// True when the work was done by a delegated subagent rather than the main
    /// thread. Roughly half of Claude Code's records, and invisible without this.
    var isSubagent: Bool = false

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens
    }

    var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }

    enum CodingKeys: String, CodingKey {
        case dedupeKey = "k", timestamp = "t", source = "s", model = "m"
        case projectPath = "p", inputTokens = "i", outputTokens = "o"
        case cacheWrite5mTokens = "w5", cacheWrite1hTokens = "w1"
        case cacheReadTokens = "r", reasoningTokens = "th", isSubagent = "sa"
    }
}

extension UsageEvent {
    /// Short label for a project path: the last two components when the leaf is
    /// generic (`ios`, `frontend`, `app`), otherwise just the leaf.
    static func projectName(for path: String?) -> String {
        guard let path, !path.isEmpty else { return "Unattributed" }
        let parts = path.split(separator: "/").map(String.init)
        guard let leaf = parts.last else { return "Unattributed" }
        let generic: Set<String> = [
            "ios", "android", "web", "app", "frontend", "backend", "ui", "api",
            "src", "client", "server", "packages", "apps",
        ]
        if generic.contains(leaf.lowercased()), parts.count >= 2 {
            return parts[parts.count - 2] + "/" + leaf
        }
        return leaf
    }
}
