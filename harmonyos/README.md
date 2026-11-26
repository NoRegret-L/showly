# Showly HarmonyOS Preview v0.2.0

Unofficial independent native ArkTS prototype, not a full port of Showly. Your app uses Trakt but is not endorsed or certified by Trakt.

- Local watch queue and watched state stored as a single versioned Preferences snapshot. Unknown/corrupt schema stops writes; never silently resets data. A Trakt item's identity includes its media type and Trakt ID.
- Public Trakt title search uses the Standard host api.trakt.tv and the same show/movie search contract as upstream. Supply your own registered Client ID inside the application (session-only, never checked into source). No Client Secret or OAuth tokens are used. No paid Premium host.
- Manual entries work offline. No cloud account sync, seasons/episode history, TMDB artwork, or production signing yet. No real-device runtime tests yet.
- Privacy: local watch records remain on the device; only when the user taps Search Trakt are the query and Client ID sent to Trakt over HTTPS. No analytics added by this prototype.
- Preferences snapshot is intended for small preview libraries; storage failures stop further writes rather than report success. A relational database and migration tests are required before scaling or sync.

CI: see .github/workflows/harmonyos-bootstrap.yml. Target API 24; minimum API 12. HAP artifacts remain unsigned.

## Device smoke checklist

1. Add a manual title, mark it watched, restart the app, verify it is still watched.
2. Undo watched status, restart, verify the item is queued.
3. Search with a valid Standard Client ID, add a result twice, verify one item exists.
4. Search with invalid ID or offline, confirm the existing library remains unchanged.
5. Upgrade from 0.1.0 with the same signing identity; verify startup. 0.1.0 stored no persistent data.
