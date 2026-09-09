# Concurrency

## Rules
- All UI state lives on `@MainActor`. `AppState` is `@MainActor @Observable`.
- Ingestion runs off the main actor on a `Task.detached(priority: .utility)`.
- Sources return plain `[UsageEvent]` values; they never touch UI or shared state.
- Cross back to the main actor exactly once per scan, with the finished snapshot:
  `await MainActor.run { state.apply(snapshot) }`.

## Anti-patterns
- No `DispatchQueue.main.async` inside SwiftUI views — use `@MainActor`.
- No locks. If two things need the same mutable state, one of them is on the wrong actor.
- Never `await` a full rescan from a UI callback without showing the scanning state.
