# Swift Style

## Types
- `struct` by default. `final class` only when AppKit demands a reference type
  (window controllers, delegates) or when identity is semantically required.
- Model types are `Sendable` value types. No shared mutable model state.
- Prefer `let`; make stored properties `private(set)` when only the owner mutates.

## Naming
- Types and files match: `NotchGeometry.swift` declares `NotchGeometry`.
- No `Manager`, `Helper`, `Util` suffixes. Name the job: `IngestCoordinator`,
  `ScanState`, `PetDirector`.
- Token fields carry their unit: `inputTokens`, not `input`.

## Functions
- Under ~40 lines. If a view body grows past that, extract a `private var` or subview.
- No force unwraps (`!`) outside `#if DEBUG` assertions. Use `guard let … else { return }`.
- No `try!`. Ingestion is best-effort: a malformed line is skipped, never fatal.

## Comments
- Explain *why*, never *what*. A comment restating the next line is deleted.
- Every parser carries one comment naming the on-disk shape it reads, because that
  shape is undocumented and reverse-engineered.
