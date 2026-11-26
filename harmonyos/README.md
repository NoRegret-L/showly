# Showly HarmonyOS Preview v0.5.0

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
