# Usage Source Adapters

Every AI tool Perch reads implements one protocol:

```swift
protocol UsageSource: Sendable {
    var id: SourceID { get }
    var isAvailable: Bool { get }
    func scan(since: ScanState) throws -> ScanResult
}
```

## Rules
1. **Read-only, always.** A source opens files `O_RDONLY` and SQLite with
   `mode=ro&immutable=1`. Perch never writes into another tool's directory,
   never installs a hook, never edits a config. This is the hard rule.
2. **Never read content.** Parse counts, model ids, paths, timestamps. If a parser
   touches a `text`, `content`, or `prompt` field it is a bug.
3. **Degrade, don't fail.** An unreadable file, a moved directory, or a schema change
   yields zero events for that source and a recorded reason — not a thrown error
   that kills the scan for every other source.
4. **Dedupe at the source.** Each event carries a stable `dedupeKey`. Claude Code uses
   `message.id + requestId`; Codex uses `sessionId + line offset`; Cursor uses the
   bubble key. Re-scanning must never double-count.
5. **Attribute to a project.** A source that cannot resolve a filesystem path
   reports `project: nil`, and the UI buckets it as "Unattributed" — it does not guess.

## Adding a source
Implement the protocol, add the case to `SourceID`, register it in
`IngestCoordinator.allSources`. Nothing else in the app changes.
