# Showly HarmonyOS Preview v0.3.0

Unofficial independent native ArkTS prototype, not a full port of Showly. Your app uses Trakt but is not endorsed or certified by Trakt.

- Local watch queue and watched state stored as a single versioned Preferences snapshot. Unknown/corrupt schema stops writes; never silently resets data. A Trakt item's identity includes its media type and Trakt ID.
- Public Trakt title search uses the Standard host api.trakt.tv and the same show/movie search contract as upstream. CI injects the developer's authorized public Trakt Client ID from the repository Actions variable TRAKT_CLIENT_ID. The application never asks ordinary users to enter a Client ID. If unconfigured, online functionality is disabled. No Client Secret or paid Premium host.
- Manual entries work offline. No cloud account sync, seasons/episode history, TMDB artwork, or production signing yet. No real-device runtime tests yet.
- Privacy: local watch records remain on the device; search sends the query and Client ID to Trakt over HTTPS; login sends OAuth authorization parameters to Trakt, and reads account settings after consent. Tokens are not logged or persisted. No analytics added by this prototype.
- Preferences snapshot is intended for small preview libraries; storage failures stop further writes rather than report success. A relational database and migration tests are required before scaling or sync.

CI: see .github/workflows/harmonyos-bootstrap.yml. Target API 24; minimum API 12. HAP artifacts remain unsigned.

## Device smoke checklist

1. Add a manual title, mark it watched, restart the app, verify it is still watched.
2. Undo watched status, restart, verify the item is queued.
3. Search with a build configured with a valid Standard Client ID, add a result twice, verify one item exists.
4. Search offline, confirm the existing library remains unchanged.
5. Upgrade from 0.1.0 with the same signing identity; verify startup. 0.1.0 stored no persistent data.

## Development OAuth (not production-ready)

Set the repository Actions variable `TRAKT_CLIENT_ID` to a Client ID authorized for this integration. Register exactly `showlyharmony://trakt` on the Trakt Development app. Trakt allows custom schemes for development, but production requires HTTPS verified App Links on a domain you control. Do not reuse an unapproved third-party Client ID or secret.

Login uses the system browser, random state, SHA-256 PKCE, exact callback matching, one-time pending state, and token exchange on auth.trakt.tv. Only an access token is retained in process memory; refresh and secure persistent tokens are deferred. Closing the process requires login again. Disconnect clears only local state; revoke authorization on Trakt if desired. No cloud sync or live device validation yet.

References: https://developer.trakt.tv/docs/pkce and https://developer.trakt.tv/docs/create-an-app .
