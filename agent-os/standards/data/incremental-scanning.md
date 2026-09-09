# Incremental Scanning

A full cold scan of ~600 JSONL files (435 MB) takes ~1.2 s, so correctness beats
cleverness. But the app polls continuously, so steady-state scans must be near-free.

## Watermarks
`ScanState` persists per file: `path`, `size`, `mtime`, `byteOffset`.
- File unchanged (same size + mtime) → skip entirely, read nothing.
- File grew → `seek(byteOffset)` and parse only the new bytes.
- File shrank or mtime went backwards → treat as rewritten, re-read from 0.

For SQLite sources the watermark is the max `rowid` already ingested.

## Cadence
- Cold scan once at launch, off the main actor.
- Poll every 8 s. Directory `mtime` is checked first; if no directory changed,
  the poll costs a handful of `stat` calls and stops.

## Persistence
`ScanState` and the event snapshot are written to
`~/Library/Application Support/Perch/`. A corrupt or version-mismatched snapshot is
discarded and rebuilt from a cold scan — the logs on disk are always the truth.
