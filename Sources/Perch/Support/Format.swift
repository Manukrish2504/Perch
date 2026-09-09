import Foundation

enum Format {
    /// 1.2K / 34.5M / 2.4B — the compact form used on the shelf and stat pills.
    static func compact(_ value: Int) -> String {
        let n = Double(value)
        switch abs(n) {
        case 1_000_000_000...:
            return trim(n / 1_000_000_000) + "B"
        case 1_000_000...:
            return trim(n / 1_000_000) + "M"
        case 1_000...:
            return trim(n / 1_000) + "K"
        default:
            return String(value)
        }
    }

    private static func trim(_ v: Double) -> String {
        // One decimal below 100, none above, so the shelf width stays stable.
        v < 100
            ? String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "")
            : String(format: "%.0f", v)
    }

    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    static func full(_ value: Int) -> String {
        grouped.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func money(_ value: Double) -> String {
        if value >= 1_000 { return String(format: "$%@", full(Int(value.rounded()))) }
        if value >= 10 { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "0%" }
        let p = Double(part) / Double(whole) * 100
        return p < 10 ? String(format: "%.1f%%", p) : String(format: "%.0f%%", p)
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "3m ago" / "2h ago" / "yesterday" — used for last-activity labels.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "yesterday" : "\(days)d ago"
    }

    /// Shortens a home-relative path for display: `~/projects/foo`.
    static func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
