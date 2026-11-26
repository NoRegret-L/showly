# Showly HarmonyOS Preview v0.7.3

Unofficial native ArkTS prototype, not a complete Showly port. Your app uses Trakt but is not endorsed or certified by Trakt.

## Personal BYOK configuration

The HAP contains no developer Client ID or secret. No GitHub Actions credential is required.
1. Open https://developer.trakt.tv/apps in the system browser and connect a verified GitHub account.
2. Create a personal Development app (Standard). Use the actual project description and register exactly `showlyharmony://trakt` for development testing. Follow Trakt's terms and branding requirements. This is for personal use, not rate-limit evasion.
3. Paste the Client ID into the app. The app validates it using one read-only Standard API request, persists it in Preferences, and optionally starts PKCE authorization. No Client Secret is requested.
4. Sign in at Trakt. The app checks state and PKCE; it stores the refresh token using HarmonyOS Asset Store, with local-only synchronization and device-unlocked access. Access tokens are in memory. On restart or foreground after expiration the app attempts renewal; retry is available. Rotated refresh tokens replace the previous token. If secure storage fails or token exceeds its 1024-byte limit, login may need repeating; no plaintext fallback.
5. Change or clear credentials via settings. Switching first clears the old local authorization; local watch records are preserved. Local logout does not revoke remote grants. Use Trakt website to revoke.

Production integration requires Trakt approval and HTTPS verified app links; this development custom scheme is not production-ready. App creation is manual on the official website: no scraping, cookie access or automated account registration.
Privacy: credentials and watch records stay on device except the HTTPS requests to Trakt needed to validate, search and authorize. No analytics. No remote writes. User-initiated authenticated cloud preview and explicit additive local import are supported.

## Test checklist

- First launch without ID: local library works, login disabled, guide opens.
- Invalid ID or offline validation does not replace existing configuration.
- Valid ID saves across restart; search and PKCE login require live verification.
- Successful login, restart, refresh, cancellation, logout, change ID, and expired grant must be tested on device.
- Upgrade from v0.3.0 preserves the unchanged local library schema.
- CI builds unsigned preview HAP only; no device runtime tests in CI.

References: https://developer.trakt.tv/docs/create-an-app ; https://developer.trakt.tv/docs/pkce ; https://developer.trakt.tv/docs/authentication-oauth ; https://developer.trakt.tv/docs/api-use-policy .

## Read-only Trakt library preview / import

The user explicitly requests a cloud read. GET /sync/last_activities brackets the four paginated datasets (watched movies, watched shows with extended=progress, movie and show watchlists). Pagination uses returned page and item counts; incomplete or duplicate results abort without changes. Changed activity revision aborts the snapshot. Session generation is checked on every page and before import. HTTP 429 or other failures stop without retries. Cloud preview is in memory and cleared on account change or disconnect.
The user may import only new watchlist titles and watched movies; existing local records take precedence. If a movie appears in both cloud lists, watched wins for a new local title. Watched shows are shown as counts of unique episodes with positive plays, not marked completed. No cloud episode data is persisted or written back. Season zero is counted if supplied by Trakt. Local schema stays v1; Preferences size limits still apply. Very large imports may require a future relational store.
Refs: https://developer.trakt.tv/docs/pagination ; https://github.com/trakt/trakt-api/discussions/775 ; https://developer.trakt.tv/docs/api-use-policy .
Device test: verify multi-page lists, no duplicates, correct partial-show counts, invalid/expired authorization, rate limiting, offline requests, account switch, repeated import (zero new records), and preservation of existing local entries. CI does not validate live account behavior.

## v0.6.0 navigation and details

Four native navigation destinations (library, search, cloud, account) share the existing state and local schema. Detail view opens from an identified movie/show in search, local library or cloud show progress. Read the public Trakt summary endpoint with extended=full only on user selection, using the configured client ID. Cache metadata for the current app process, explicit refresh available. No TMDB API key required. Download the documented WebP image from an allowlisted Trakt HTTPS host without API credentials, cache it under the app cacheDir keyed by media ID and image filename, and render the local sandbox URI. No direct CDN links in Image. Missing or failed artwork does not block metadata. The OS can purge the cache. No full-grid poster prefetch or episode detail yet; large list virtualization remains future work.
References: https://developer.trakt.tv/docs/images ; https://developer.trakt.tv/docs/extended-info ; Huawei Image and Core File Kit APIs. Evaluated ImageKnife; deferred third-party dependency until grid-scale caching is required.
Device tests: navigate tabs and back, open movie and show details, verify poster cached and re-open, invalid/offline request, rapid back and tab switching, check original library and auth after upgrade. 

## v0.6.1 artwork diagnostics

The app distinguishes absent API artwork, rejected URL shape, DNS/connect/timeout, CDN HTTP status, invalid binary/WebP signature, cache write and ArkUI image rendering failures. Select the first eligible URL in the API poster array; permit variable artwork size path segments while retaining strict HTTPS Trakt host and media-path checks. Use a truthful app User-Agent and accept WebP. No API key or token is sent to the CDN. Copyable diagnostics contain only stage, CDN hostname and numeric error/status, not credentials or user account data. No proxy, extra image service or new key. Official Trakt images guide prefers extended=full, so leave that query unchanged. Device verification required to establish the actual failure stage.

## v0.6.2 poster URL compatibility

Device diagnostics from v0.6.1 confirmed rejection before any CDN request. The URL validator now accepts HTTPS (including protocol-relative and bare host variants), case-insensitive Trakt subdomains, safe variable paths under /images/, and ordinary image paths on known Trakt media/walter CDN hosts. Optional query parameters are preserved on download but excluded from cache filenames and diagnostics. Host boundaries, traversal rejection, actual WebP signature checks, and local caching remain. If rejected, diagnostics show a sanitized address without query, fragment, or embedded credentials. No external hosts, proxy, HTTP downgrade or TLS bypass. The exact rejected URL from the original device is not yet known. Evaluated 16 URL examples (including malformed hosts, traversal, old and new CDN formats) against the equivalent JavaScript validator; ArkTS build and live device check pending.
References: https://developer.trakt.tv/docs/images ; https://docs.cantinarr.com/reference/generated/api/discover-media-user/ .

## v0.7.0 discovery grid (first UI migration)

References upstream bottom_navigation_menu.xml, fragment_discover.xml, TraktMoviesService.kt and TraktShowsService.kt. Native discovery tab supports movie/show trending, popular and anticipated charts; the existing four destinations remain available. Uses the Standard Trakt API, extended=full and explicit pages of 12 (two columns × six rows). No per-card summary call. Download sequentially into the existing local WebP cache, only on requested pages. Revision/client checks discard obsolete responses; local records and auth schema unchanged. Concurrent detail/discovery downloads have separate temporary filenames. Grid is bounded rather than a full lazy collection; no new image library dependency. Missing images leave usable title cards. No personalized recommendations, full library poster grid, episode management, system theme overhaul or cloud writes yet.
Device tests: movie/show modes, all three charts, previous/next page, quick mode changes, opening detail while posters load, back navigation, offline behavior, and upgrading with previous credentials/library.
References: https://developer.trakt.tv/docs/images ; https://developer.trakt.tv/docs/pagination ; https://github.com/trakt/showly .

## v0.7.1 collection and episode progress

Collection now has local queue/watched filters and a read-only cloud watched-show view (includes completed shows, not a precise in-progress classification). Each view is paged using the existing 12-card convention. List mode works offline; poster mode requests only the selected page on explicit user action, reusing metadata and disk cache. Existing local schema and credentials unchanged. Per-show progress uses authenticated GET /shows/{id}/progress/watched, excludes hidden seasons and specials, uses server-provided aired/completed totals, and displays expandable season episode status. No cloud writes, no local episode persistence. Chinese translation is optional, chooses zh/cn first and falls back to other zh or original. Theme and full navigation redesign deferred. Native bounded rendering avoids loading all hundreds of titles; no extra dependency. Test paging, toggling watched, changing account, loading posters, season progress, translations, offline mode and preserving old library. See https://trakt.docs.apiary.io/reference/sync and upstream TraktShowsService.kt / TraktMoviesService.kt. 

## v0.7.2 native UI refinement

Based on upstream ui-base/src/main/res/values/colors.xml and app/src/main/res/menu/bottom_navigation_menu.xml, the three main destinations are Progress, Discover, Collection. The three navigation SVG paths are ported from upstream ui-base drawable resources. Search, cloud import and account settings remain accessible from the header. Default progress view uses the existing read-only snapshot; it is not a full next-episode or calendar implementation. Progress list is paged and filterable; the unbounded duplicate list is removed from the cloud page. Native resource-qualified colors and ApplicationContext.setColorMode implement system/light/dark, saved separately from account/library. Native Refresh triggers the relevant read-only refresh; collection poster grid loads on entry, page or filter selection, and detail requests Chinese translations automatically with an in-process cache and original-language fallback. Existing 12-item paging remains (not true LazyForEach virtualization); evaluated native LazyForEach and ImageKnife, deferred until larger data-source refactor. No new API credentials, dependencies, schema or remote writes. Test theme persistence, system theme changes, all navigation routes, discovery paging and pull refresh, collection auto artwork, progress filtering and Chinese fallback on device. 
References: https://github.com/trakt/showly ; https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-rendering-control-lazyforeach/ ; https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-arkui-componentcontent/ .

## v0.7.3 local episode journal

New independent SQLite-backed RelationalStore database showly_episodes.db. Existing Preferences library, account, and appearance stores remain authoritative and unchanged; migration of old titles into RDB is deliberately deferred, avoiding a destructive or dual-write migration. Public Trakt seasons?extended=full,episodes provides the catalog; only episodes with confirmed past air dates and positive ordinary season/episode/Trakt IDs are eligible. Cache a catalog on explicit refresh, preserve prior data on failure. Local marks are separate from cloud watched status; the event log stores one atomic row per action (including season batch), ordered by an autoincrement sequence, with stable Trakt episode IDs and timestamp. Replay yields local state, progress and next earliest unwatched aired episode; no second mutable watched table and no partial season writes. Local actions do not imply whole-show watched, do not use OAuth and are not queued for automatic upload to any account. Cloud progress still read-only. Recent 12 locally modified shows accessible offline from progress tab; old local library and all previous tabs unchanged. Future cloud reconciliation requires explicit account binding and conflict policy. 
Device tests: catalog download, mark one and undo, confirm season batch and undo, kill/relaunch offline, next episode and totals, verify original library and Trakt remain unchanged, offline without cached catalog, future episodes and specials excluded. 
References: https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/data-persistence-by-rdb-store/ ; https://github.com/trakt/showly (EpisodesDao, EpisodesSyncLogDao, TraktShowsService) ; https://trakt.docs.apiary.io/ .
