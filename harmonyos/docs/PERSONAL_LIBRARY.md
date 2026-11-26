# v0.9.3d — personal library foundation

Baseline: Android e08cb90ba0205ed9401a11265b912b0302f253b5, HarmonyOS 00b91ef2639186c943b39889b2d11d709d7ee524.

## Design
- Android MyShowsLoadShowsCase uses myShows membership, season first-air dates, season watched flags and show status; WatchlistLoadShowsCase uses separate watchlist membership. Reuse the existing local state model and Trakt paginated snapshot rather than creating a second database or generic state management dependency.
- A read-only union keyed by typed Trakt ID (movie/show namespaces stay distinct); explicit local negative overrides only its own domain. Unknown/legacy local records remain visible. A cloud-only record never creates local intent.
- A show cached with no viewing evidence is not followed just because a catalog exists. Counts from distinct sources are not combined or interpreted as full progress. No arbitrary threshold.
- Missing status/air dates prevent faithful watching/finished/upcoming classification; retain unknown, not a fabricated status. Next/calendar migration is separate.
- Risks: legacy membership may be stale; cloud snapshots require explicit refresh; local episode observations cover cached catalogs only and may include imported observations. Cloud snapshots use existing auth-generation guard; local records remain device-local as before.

## Acceptance (device)
1. Before reading cloud, local collection and independent movie/watchlist states remain visible; no database migration.
2. Tap read/refresh personal cloud library. Verify a watched cloud show without cached catalog appears in All and Tracking; cloud-only queued movies/shows appear in Watchlist; watched movies appear in Watched. Same ID appears once per filter, even if both sources contain it.
3. Open a cloud-only card. It has no quick local toggle; explicit detail actions remain local-only. Explicit local unwatch/remove from watchlist beats corresponding cloud positive; other domain remains independent.
4. Open a previously untracked show and download its catalog without watching: it must not appear solely because cached. Mark an episode locally and return; tracking now shows separate local count. Cached completion must not be labelled finished.
5. Logout or clear cloud preview: cloud-only rows disappear, existing local titles persist; verify pagination, posters, backup and synchronization protections remain unchanged. No new cloud mutation is expected from any library read.

## Verification
Run `python3 harmonyos/tools/test_personal_library.py` with TypeScript 5.8+ available on PATH. It compiles the actual pure .ets model copied to .ts and exercises membership and explicit-intent precedence. This is not an ArkTS/HAP or device test. Native HAP compilation and manual device acceptance remain separate.
