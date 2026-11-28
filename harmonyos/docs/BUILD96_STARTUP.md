# Build 96 startup and synchronization
Android source: ProgressViewModel and ProgressItemsCase own independent local loading; TraktSyncViewModel owns authorization/sync status.
- UUID is stored atomically with the existing secure refresh record. Legacy credentials need one verified online observation. New login clears prior identity; invalid_grant/disconnect revoke it. No plaintext token or authoritative database schema migration.
- Offline snapshots use generation -1 and do not satisfy activeCloud or network write gates. Read-only projection can precede OAuth and pending recovery, but is serialized with durable writes. No polling timer.
- Failed local projection terminates loading. Existing display is retained only under the same credential identity. Existing receipt/checkpoint fences and no-resend rules remain.
- Isolated branch release uses exact SHA and digest verification. SDK closure probe compares Build 95 and current source; sibling branch cache misses use verified full fallback.
- Device cold start, real OAuth, actual process termination and performance measurements remain required before full acceptance.

CI #151 exposed three outdated source assertions and two ArkTS object-spread errors. Correct assertions to require displayCloud only in read paths and preserve activeCloud for action validation; use explicit typed snapshots instead of spread.
