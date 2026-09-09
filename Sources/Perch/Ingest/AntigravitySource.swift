import Foundation

/// Reads Antigravity / Gemini transcripts at
/// `~/.gemini/{antigravity,antigravity-ide,antigravity-cli}/brain/**/transcript.jsonl`.
///
/// Antigravity only writes these transcripts in some configurations. When none
/// exist the source reports why rather than silently contributing nothing — see
/// `agent-os/standards/data/source-adapters.md`.
struct AntigravitySource: UsageSource {
    let id = SourceID.antigravity
    let roots: [String]

    private static let usageNeedle = Array("TokenCount".utf8)

    init(home: String = NSHomeDirectory() + "/.gemini") {
        roots = ["antigravity", "antigravity-ide", "antigravity-cli"].map { home + "/" + $0 + "/brain" }
    }

    var isAvailable: Bool {
        roots.contains { FileManager.default.fileExists(atPath: $0) }
    }

    func scan(state: SourceScanState) -> ScanOutcome {
        guard isAvailable else {
            return ScanOutcome(state: state, note: "Antigravity not installed")
        }
        var state = state
        var events: [UsageEvent] = []
        var sawTranscript = false

        for root in roots where FileManager.default.fileExists(atPath: root) {
            for path in FileScan.files(under: root, ext: "jsonl") {
                sawTranscript = true
                guard let (size, mtime) = FileScan.stat(path),
                      let offset = state.pendingOffset(for: path, size: size, mtime: mtime)
                else { continue }
                let newOffset = FileScan.forEachLine(path: path, from: offset) { line in
                    guard line.contains(Self.usageNeedle) else { return }
                    if let e = parse(line: line, file: path) { events.append(e) }
                }
                state.files[path] = .init(size: size, mtime: mtime, offset: newOffset)
            }
        }

        let note = sawTranscript
            ? nil
            : "Installed, but this build writes no transcripts with token counts"
        return ScanOutcome(events: events, state: state, note: note)
    }

    /// Gemini reports usage as `usageMetadata:{promptTokenCount, candidatesTokenCount,
    /// cachedContentTokenCount, thoughtsTokenCount}`.
    private func parse(line: LineBytes, file: String) -> UsageEvent? {
        guard let obj = line.json,
              let usage = obj.dict("usageMetadata") ?? obj.dict("usage_metadata")
        else { return nil }

        let prompt = usage.int("promptTokenCount") + usage.int("prompt_token_count")
        let output = usage.int("candidatesTokenCount") + usage.int("candidates_token_count")
        let cached = usage.int("cachedContentTokenCount") + usage.int("cached_content_token_count")
        guard prompt + output + cached > 0 else { return nil }

        let stamp = obj.str("timestamp") ?? obj.str("createTime") ?? ""
        guard let timestamp = ISO8601.parse(stamp) else { return nil }

        return UsageEvent(
            dedupeKey: "ag:\(obj.str("id") ?? stamp):\(file.hashValue)",
            timestamp: timestamp,
            source: .antigravity,
            model: obj.str("model") ?? "gemini",
            projectPath: obj.str("cwd") ?? obj.str("workspacePath"),
            inputTokens: max(0, prompt - cached),
            outputTokens: output,
            cacheWrite5mTokens: 0,
            cacheWrite1hTokens: 0,
            cacheReadTokens: cached,
            reasoningTokens: usage.int("thoughtsTokenCount")
        )
    }
}
