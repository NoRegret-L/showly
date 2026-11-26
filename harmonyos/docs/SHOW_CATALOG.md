# v0.9.3e.1 — schedule and followed foundation

Reference Android e08cb90ba0205ed9401a11265b912b0302f253b5: MyShowsLoadShowsCase, MyShowsSection, ShowStatus, MyShowsRepository, WatchlistShowsRepository, EpisodesManager. Reuse existing Trakt seasons endpoint and SQLite, no new library or heuristic weights.

- A separate validated full ordinary-episode schedule stores future and unknown dates, season premiere and show status. Specials excluded as in upstream progress/calendar. Existing eligible catalog derives only aired dated episodes at refresh time; its schema and all journal/guard/receipt paths remain unchanged. Both catalog rows commit in a transaction; no destructive migration. Newly aired episodes require refresh. Old data is not a complete schedule.
- Followed membership is explicit on local action, independent of history. Joining followed moves out of local watchlist; joining watchlist moves out of followed. Existing unknown records are not rewritten. New explicit removal of watchlist may appear in reviewed title sync, never automatically sent. Remote adoption of watchlist membership uses same local state transition. No new authorization.
- Collection sections use exact local episode IDs and independent upstream predicates, not cloud counts; unknown/empty season metadata cannot prove completion. Cloud count greater than local count blocks classification; otherwise labels explicitly local, not proof of merged cloud state. No inference from equal counts. Schedule freshness is explicit, not a claim of live completeness.
- Backup v1 optional followed display field; old backups readable; restores do not create watchlist or episode intent. Schedule metadata is not exported; refresh from Trakt. No change to history, account binding, consent, guards, undo, or common baselines.

## Device acceptance
1. Upgrade without reinstall; verify previous episode and movie records, backup and sync guards unchanged.
2. Refresh a returning show with future episodes. Verify all ordinary episodes counted in full metadata, future/unknown dates in read-only list, no mark buttons or automatic sync for them. Mark an already aired episode as before; restart and confirm persistence.
3. Join a show to followed, then move back to watchlist; verify one member category after each action and unchanged episode history. Review sync preview without executing remote writes.
4. Refresh completed/returning/planned shows; verify local classification and unknown for missing or insufficient evidence. No cached-only show becomes followed without evidence or explicit action.
5. Export/reselect backup, verify no overwrite; followed display state survives additive restore with unknown sync intent. Simulate offline refresh: previous data remains.

Host test: python3 harmonyos/tools/test_show_catalog.py (requires tsc and node). HAP compilation/device/Trakt tests separate. e.2/e.3 must consume full schedule and unified membership; this release does not make those algorithms complete.
