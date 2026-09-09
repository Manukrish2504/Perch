import Foundation

/// Reads `~/.claude/projects/**/*.jsonl`.
///
/// On-disk shape: one JSON object per line. Billable rows are
/// `{type:"assistant", timestamp, cwd, requestId, message:{id, model, usage:{…}}}`.
/// `usage.iterations[]` is a per-attempt breakdown of the same totals — summing it
/// would double-count, so only the top-level counters are read.
struct ClaudeCodeSource: UsageSource {
    let id = SourceID.claudeCode
    let root: String

    private static let usageNeedle = Array("\"usage\"".utf8)
    private static let quotaNeedle = Array("\"quotaLimits\"".utf8)

    init(root: String = NSHomeDirectory() + "/.claude/projects") {
        self.root = root
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: root)
    }

    func scan(state: SourceScanState) -> ScanOutcome {
        guard isAvailable else {
            return ScanOutcome(state: state, note: "No ~/.claude/projects directory")
        }
        var state = state
        var events: [UsageEvent] = []
        var rejections: [(type: String, at: Date, resets: Date?)] = []

        for path in FileScan.files(under: root, ext: "jsonl") {
            guard let (size, mtime) = FileScan.stat(path),
                  let offset = state.pendingOffset(for: path, size: size, mtime: mtime)
            else { continue }

            let newOffset = FileScan.forEachLine(path: path, from: offset) { line in
                if line.contains(Self.quotaNeedle), let hit = parseQuota(line: line) {
                    rejections.append(hit)
                }
                // Cheap byte reject before paying for JSON parsing.
                guard line.contains(Self.usageNeedle) else { return }
                if let event = parse(line: line) { events.append(event) }
            }
            state.files[path] = .init(size: size, mtime: mtime, offset: newOffset)
        }
        return ScanOutcome(events: events, limits: limits(from: rejections), state: state, note: nil)
    }

    /// Claude Code writes `quotaLimits` only on a rejection, so the best available
    /// signal is "how often lately, and when does it reset" — never a percentage.
    private func parseQuota(line: LineBytes) -> (type: String, at: Date, resets: Date?)? {
        guard let obj = line.json,
              let quota = obj.dict("quotaLimits"),
              quota.str("status") == "rejected",
              let stamp = obj.str("timestamp"),
              let at = ISO8601.parse(stamp)
        else { return nil }
        let resets = quota["resetsAt"].flatMap { $0 as? NSNumber }
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return (quota.str("rateLimitType") ?? "limit", at, resets)
    }

    private func limits(from hits: [(type: String, at: Date, resets: Date?)]) -> [LimitWindow] {
        guard !hits.isEmpty else { return [] }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        var byType: [String: [(type: String, at: Date, resets: Date?)]] = [:]
        for hit in hits { byType[hit.type, default: []].append(hit) }

        return byType.compactMap { type, group in
            guard let latest = group.max(by: { $0.at < $1.at }) else { return nil }
            return LimitWindow(
                source: .claudeCode,
                label: type == "five_hour" ? "5-hour" : type.replacingOccurrences(of: "_", with: " "),
                usedPercent: nil,
                resetsAt: latest.resets,
                observedAt: latest.at,
                hits: group.filter { $0.at >= weekAgo }.count
            )
        }
    }

    private func parse(line: LineBytes) -> UsageEvent? {
        guard let obj = line.json,
              obj.str("type") == "assistant",
              let message = obj.dict("message"),
              let usage = message.dict("usage"),
              let model = message.str("model"),
              model != "<synthetic>",
              let stamp = obj.str("timestamp"),
              let timestamp = ISO8601.parse(stamp)
        else { return nil }

        // 1-hour cache writes bill at 2x input, 5-minute at 1.25x, so keep them apart.
        let creation = usage.dict("cache_creation")
        let write1h = creation?.int("ephemeral_1h_input_tokens") ?? 0
        let write5m = creation.map { $0.int("ephemeral_5m_input_tokens") }
            ?? usage.int("cache_creation_input_tokens")

        let thinking = usage.dict("output_tokens_details")?.int("thinking_tokens") ?? 0
        let messageID = message.str("id") ?? "?"
        let requestID = obj.str("requestId") ?? stamp

        return UsageEvent(
            dedupeKey: "cc:\(messageID):\(requestID)",
            timestamp: timestamp,
            source: .claudeCode,
            model: model,
            projectPath: obj.str("cwd"),
            inputTokens: usage.int("input_tokens"),
            outputTokens: usage.int("output_tokens"),
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h,
            cacheReadTokens: usage.int("cache_read_input_tokens"),
            reasoningTokens: thinking,
            isSubagent: (obj["isSidechain"] as? Bool) ?? false
        )
    }
}
