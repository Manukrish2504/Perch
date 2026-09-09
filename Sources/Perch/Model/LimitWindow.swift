import Foundation

/// A provider quota window, as reported by the tool itself.
///
/// Perch makes no network calls, so this is strictly what the tools already wrote
/// to disk. That means the two providers report different things, and the UI says
/// which is which rather than inventing a common gauge:
///  - **Codex** logs a live `used_percent` per window on every turn.
///  - **Claude Code** logs nothing until you actually hit a limit, and then only
///    the reset time. So there is no percentage — only "hit N times, resets at X".
struct LimitWindow: Codable, Sendable, Hashable, Identifiable {
    let source: SourceID
    /// "5-hour", "Weekly" — the window the provider named.
    let label: String
    /// `nil` when the provider never reports a percentage (Claude Code).
    var usedPercent: Double?
    var resetsAt: Date?
    /// When this reading was written, so a stale one can be marked as such.
    var observedAt: Date
    /// Times the limit was hit in the trailing week. Only meaningful for Claude.
    var hits: Int = 0

    var id: String { "\(source.rawValue)-\(label)" }

    /// A reading older than a day is history, not a live gauge.
    var isStale: Bool { Date().timeIntervalSince(observedAt) > 86_400 }

    var resetsIn: TimeInterval? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// "2h 14m" / "3d 4h"
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
