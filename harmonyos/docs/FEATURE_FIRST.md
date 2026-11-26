# Feature-first presentation — v0.9.3e.1b.1
Android baseline e08cb90ba0205ed9401a11265b912b0302f253b5: MainActivity, MyShowsLoadShowsCase, ProgressItemsCase, ShowDetailsViewModel, MovieDetailsViewModel, TraktSyncViewModel. Harmony baseline 7210155bc6e2395e18ecdccae9ab20d4fd0179e3. Reuse effective resolver and feature navigation; no new runtime library or heuristic weights.
- Ordinary navigation has no cloud tab or duplicate progress list. Settings contains advanced previews, manual import and existing consent/review functions.
- Collection uses single effective aired count. Unknown stays explicit. Movie toggles effective state, not stale local boolean. No whole-show movie toggle.
- Detail shows one effective aired list and read-only other episodes. Missing schedules fetched as public metadata. Explicit edit still validates eligible catalog. Repeated history and title-domain write reconciliation remain future work.
- Next candidates are followed members with usable metadata; effective IDs and aired counts match detail. Offline old catalog fallback retained. Full Android strategies/grouping/upcoming pending.
- Movie calendar membership and status use effective library; show rows filtered by membership and ordinary season. Weekly remote endpoint still limits coverage; offline calendar and complete date caching pending.
- Unbound/other account remains read-only. No automatic movie/watchlist upload or destructive removal. Existing write guards and receipts unchanged.
- Acceptance: upgrade; compare cloud-only show across collection/next/detail; no duplicate source views; mark/revoke; check future episodes not editable; switch accounts; verify advanced actions accessible; calendar after local removal; no new remote mutation without consent. CI checks not device tests.
