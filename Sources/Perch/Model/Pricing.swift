import Foundation

/// Dollars per million tokens for one model.
struct ModelRate: Codable, Sendable, Hashable {
    var input: Double
    var output: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double
    /// True when the rate is Perch's guess rather than a published rate card.
    /// Surfaced in Settings so a wrong number is visible, not silently trusted.
    var estimated: Bool

    static func anthropic(input: Double, output: Double, cacheRead: Double? = nil) -> ModelRate {
        ModelRate(
            input: input,
            output: output,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 2.0,
            cacheRead: cacheRead ?? input * 0.1,
            estimated: false
        )
    }

    static func estimate(input: Double, output: Double) -> ModelRate {
        ModelRate(
            input: input,
            output: output,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 2.0,
            cacheRead: input * 0.1,
            estimated: true
        )
    }

    static let unknown = ModelRate(
        input: 0, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0, estimated: true
    )
}

/// Editable per-model rate table, persisted to Application Support.
struct PriceBook: Codable, Sendable {
    var rates: [String: ModelRate]

    /// Published Anthropic rates; non-Anthropic entries are flagged `estimated`.
    static let bundled = PriceBook(rates: [
        "claude-opus-5":     .anthropic(input: 5, output: 25),
        "claude-opus-4-8":   .anthropic(input: 5, output: 25),
        "claude-opus-4-7":   .anthropic(input: 5, output: 25),
        "claude-opus-4-6":   .anthropic(input: 5, output: 25),
        // Fable 5.1 prices cache reads at a flat $0.25/MTok, not 10% of input.
        "claude-fable-5-1":  .anthropic(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5":    .anthropic(input: 10, output: 50),
        "claude-sonnet-5":   .anthropic(input: 2, output: 10),
        "claude-sonnet-4-6": .anthropic(input: 3, output: 15),
        "claude-haiku-4-5":  .anthropic(input: 1, output: 5),
        "gpt-5.2-codex":     .estimate(input: 1.25, output: 10),
        "gpt-5.1-codex":     .estimate(input: 1.25, output: 10),
        "gpt-5-codex":       .estimate(input: 1.25, output: 10),
        "grok-4.6":          .estimate(input: 3, output: 15),
    ])

    /// Exact match first, then longest-prefix, so `claude-opus-5-20260401` still
    /// prices as `claude-opus-5` if a dated id ever shows up.
    func rate(for model: String) -> ModelRate {
        if let exact = rates[model] { return exact }
        let best = rates.keys
            .filter { model.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        return best.flatMap { rates[$0] } ?? .unknown
    }

    func cost(of event: UsageEvent) -> Double {
        let r = rate(for: event.model)
        let m = 1_000_000.0
        return Double(event.inputTokens) / m * r.input
            + Double(event.outputTokens) / m * r.output
            + Double(event.cacheWrite5mTokens) / m * r.cacheWrite5m
            + Double(event.cacheWrite1hTokens) / m * r.cacheWrite1h
            + Double(event.cacheReadTokens) / m * r.cacheRead
    }

    /// True when any model carrying real usage has no published rate.
    func hasUnpricedModels(_ models: some Sequence<String>) -> Bool {
        models.contains { rate(for: $0) == .unknown }
    }
}
