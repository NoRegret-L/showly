# Build 91 — first sync alignment slice
Android baseline e08cb90b: QuickSyncManager, QuickSyncWorker, TraktSyncWorker, TraktSyncViewModel, TraktSyncSchedule. Reuse existing persistent stores, receipts and activity observation. No new dependency, tuning threshold or authoritative schema change.
- Coalesce existing wakeups and retain during visibility loss, clear on auth change. Existing foreground, backup, account and DB gates retained. Network execution remains in the page.
- One-click sync enqueues existing authorized lanes plus cloud observation. No implicit binding, consent, old-history upload or automatic history deletion. Show actual lane progress and verified account episode count.
- Replace quadratic queue membership checks with exact identity sets.
- Closure probe #2 traces parent and current, measures local cache pack/restore and verifies HAP equivalence. Main CI keeps full SDK and existing release gates.
- Host fixture covers 100 cycles and 10k exact queue identities. Background process scheduling, true per-domain deltas, persisted last success, full title count, GitHub remote cache A/B and device verification remain outstanding.
