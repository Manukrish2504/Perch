import Foundation

/// Reads `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// On-disk shape: a `session_meta` header carries `payload.cwd`; `turn_context`
/// rows carry the `payload.model` in force from that point on; billable rows are
/// `{type:"event_msg", payload:{type:"token_count", info:{last_token_usage:{…}}}}`.
/// `info.total_token_usage` is cumulative for the session — only `last_token_usage`
/// is a per-turn delta, so that is what gets summed.
struct CodexSource: UsageSource {
    let id = SourceID.codex
    let root: String

    private static let limitNeedle = Array("\"rate_limits\"".utf8)

    init(root: String = NSHomeDirectory() + "/.codex/sessions") {
        self.root = root
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: root)
    }

    func scan(state: SourceScanState) -> ScanOutcome {
        guard isAvailable else {
            return ScanOutcome(state: state, note: "No ~/.codex/sessions directory")
        }
        var state = state
        var events: [UsageEvent] = []
        var limits: [String: LimitWindow] = [:]

        for path in FileScan.files(under: root, ext: "jsonl") {
            guard let (size, mtime) = FileScan.stat(path),
                  state.pendingOffset(for: path, size: size, mtime: mtime) != nil
            else { continue }

            // Model and cwd are carried by earlier rows, so a Codex file is always
            // re-read whole; they are small and few (tens, not hundreds).
            var lines: [LineBytes] = []
            FileScan.forEachLine(path: path, from: 0) { lines.append($0) }
            events.append(contentsOf: parse(lines: lines, sessionKey: path))
            for window in parseLimits(lines: lines) {
                // Keep only the newest reading per window across all sessions.
                if let existing = limits[window.label], existing.observedAt >= window.observedAt {
                    continue
                }
                limits[window.label] = window
            }
            state.files[path] = .init(size: size, mtime: mtime, offset: size)
        }
        return ScanOutcome(
            events: events,
            limits: Array(limits.values),
            state: state,
            note: nil
        )
    }

    /// `rate_limits` rides along on every `token_count` event: `primary` is the
    /// rolling 5-hour window, `secondary` the weekly one.
    private func parseLimits(lines: [LineBytes]) -> [LimitWindow] {
        var out: [LimitWindow] = []
        for line in lines {
            guard line.contains(Self.limitNeedle), let obj = line.json,
                  let payload = obj.dict("payload"),
                  let limits = payload.dict("rate_limits"),
                  let stamp = obj.str("timestamp"),
                  let observedAt = ISO8601.parse(stamp)
            else { continue }

            for (key, label) in [("primary", "5-hour"), ("secondary", "Weekly")] {
                guard let window = limits.dict(key),
                      let percent = window["used_percent"] as? NSNumber
                else { continue }
                let resets = window["resets_at"].flatMap { $0 as? NSNumber }
                    .map { Date(timeIntervalSince1970: $0.doubleValue) }
                out.append(LimitWindow(
                    source: .codex, label: label,
                    usedPercent: percent.doubleValue,
                    resetsAt: resets, observedAt: observedAt
                ))
            }
        }
        return out
    }

    /// Codex re-emits `token_count` on every stream tick, so `last_token_usage`
    /// repeats and summing it over-counts (measured 2.5x on a real session).
    /// `total_token_usage` is cumulative and monotonic, so the per-turn cost is
    /// its delta. A decrease means the session restarted its counters; that row
    /// is treated as a fresh baseline rather than a negative turn.
    private func parse(lines: [LineBytes], sessionKey: String) -> [UsageEvent] {
        var cwd: String?
        var model = "unknown"
        var out: [UsageEvent] = []
        var previous = Cumulative()
        var index = 0

        for line in lines {
            index += 1
            guard let obj = line.json, let payload = obj.dict("payload")
            else { continue }

            switch obj.str("type") {
            case "session_meta":
                cwd = payload.str("cwd") ?? cwd
            case "turn_context":
                cwd = payload.str("cwd") ?? cwd
                model = payload.str("model") ?? model
            case "event_msg":
                guard payload.str("type") == "token_count",
                      let info = payload.dict("info"),
                      let running = info.dict("total_token_usage"),
                      let stamp = obj.str("timestamp"),
                      let timestamp = ISO8601.parse(stamp)
                else { continue }

                let current = Cumulative(running)
                let delta = current.delta(from: previous)
                previous = current
                guard delta.total > 0 else { continue }

                out.append(UsageEvent(
                    dedupeKey: "cx:\(sessionKey.hashValue):\(index)",
                    timestamp: timestamp,
                    source: .codex,
                    model: model,
                    projectPath: cwd,
                    inputTokens: delta.uncachedInput,
                    outputTokens: delta.output,
                    cacheWrite5mTokens: 0,
                    cacheWrite1hTokens: 0,
                    cacheReadTokens: delta.cached,
                    reasoningTokens: delta.reasoning
                ))
            default:
                continue
            }
        }
        return out
    }

    /// Running session counters. `input` includes `cached`, matching Codex's own
    /// arithmetic (`total_tokens == input_tokens + output_tokens`).
    private struct Cumulative {
        var input = 0
        var cached = 0
        var output = 0
        var reasoning = 0

        init() {}

        init(_ d: [String: Any]) {
            input = d.int("input_tokens")
            cached = d.int("cached_input_tokens")
            output = d.int("output_tokens")
            reasoning = d.int("reasoning_output_tokens")
        }

        var uncachedInput: Int { max(0, input - cached) }
        var total: Int { uncachedInput + cached + output }

        func delta(from previous: Cumulative) -> Cumulative {
            // Counters only ever climb within a session; a drop means a reset.
            guard input >= previous.input, output >= previous.output else { return self }
            return Cumulative(
                input: input - previous.input,
                cached: cached - previous.cached,
                output: output - previous.output,
                reasoning: reasoning - previous.reasoning
            )
        }

        private init(input: Int, cached: Int, output: Int, reasoning: Int) {
            self.input = input
            self.cached = max(0, cached)
            self.output = output
            self.reasoning = max(0, reasoning)
        }
    }
}
