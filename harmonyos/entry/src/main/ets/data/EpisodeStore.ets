import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { CommonEntry, CommonUpdate, commonId } from '../model/ThreeWay';
import { canReadDetails, readDetails } from './TraktDetails';
import { RemoteLibraryObservation, validateObservation } from '../model/RemoteObservation';
import { ReadCheckpoint } from '../model/EffectiveState';
import { FullEpisodeCatalog, ScheduledSeason, ScheduledEpisode, airDate, aired, scheduleEpisodes, validateFullCatalog } from '../model/ShowCatalog';

interface EpisodeIds { trakt: number; }
interface RemoteEpisode {
  number: number;
  title?: string;
  first_aired?: string;
  ids: EpisodeIds;
}
interface RemoteSeason { number: number; first_aired?: string; episodes?: RemoteEpisode[]; }

export interface LocalEpisode {
  id: number;
  season: number;
  number: number;
  title: string;
}
export interface EpisodeCatalog {
  showId: string;
  title: string;
  year: number;
  episodes: LocalEpisode[];
}
interface EpisodeEvent {
  ids: number[];
  watched: boolean;
}
export interface UndoReceipt {
  historyId: number;
  watchedAt: string;
  removalState: number;
}
export interface AutoConsent {
  uuid: string;
  clientId: string;
}
export interface QueueEntry {
  episodeId: number;
  seq: number;
  label: string;
  watchedAt: string;
  blocked: boolean;
  protection: string;
}
export interface JournalIntent {
  seq: number;
  autoUuid: string;
  changedAt: number;
  episodeId: number;
  showId: string;
  label: string;
  watched: boolean;
  catalogKnown: boolean;
}
export interface EpisodeBackupState {
  catalog: EpisodeCatalog;
  watchedIds: number[];
}
export interface LocalEpisodeState {
  episode: LocalEpisode;
  watched: boolean;
}
export interface LocalSeasonState {
  number: number;
  episodes: LocalEpisodeState[];
  completed: number;
}
export interface LocalSeriesState {
  catalog: EpisodeCatalog;
  seasons: LocalSeasonState[];
  completed: number;
  next: string;
}

function validId(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}
export function validateCatalog(catalog: EpisodeCatalog, showId: string): void {
  if (catalog.showId !== showId || !/^show:[1-9][0-9]*$/.test(showId) ||
      typeof catalog.title !== 'string' || typeof catalog.year !== 'number' || !Array.isArray(catalog.episodes)) {
    throw new Error('Invalid episode catalog');
  }
  const ids: Set<number> = new Set<number>();
  const positions: Set<string> = new Set<string>();
  for (const ep of catalog.episodes) {
    const position = ep.season + ':' + ep.number;
    if (!validId(ep.id) || !validId(ep.season) || !validId(ep.number) ||
        typeof ep.title !== 'string' || ids.has(ep.id) || positions.has(position)) {
      throw new Error('Invalid episode catalog entry');
    }
    ids.add(ep.id);
    positions.add(position);
  }
}

// Public catalog only; no account history, no Authorization header.
export async function fetchFullEpisodeCatalog(item: Media, clientId: string): Promise<FullEpisodeCatalog> {
  if (!clientId || item.kind !== 'show' || !canReadDetails(item)) {
    throw new Error('Invalid catalog request');
  }
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/shows/' + item.id.substring(5) +
      '/seasons?extended=full,episodes', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': clientId, 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.3' },
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Episode catalog HTTP ' + response.responseCode);
    }
    const rows = JSON.parse(response.result) as RemoteSeason[];
    if (!Array.isArray(rows)) { throw new Error('Invalid season catalog'); }
    const seasons: ScheduledSeason[] = [];
    for (const season of rows) {
      if (season.number === 0) { continue; }
      if (!validId(season.number) || !Array.isArray(season.episodes)) { throw new Error('Missing season episodes'); }
      const episodes: ScheduledEpisode[] = [];
      for (const episode of season.episodes) {
        if (!episode.ids || !validId(episode.ids.trakt) || !validId(episode.number)) {
          throw new Error('Invalid episode identity');
        }
        episodes.push({ id: episode.ids.trakt, season: season.number, number: episode.number,
          title: typeof episode.title === 'string' ? episode.title : '', firstAired: airDate(episode.first_aired) });
      }
      episodes.sort((left: ScheduledEpisode, right: ScheduledEpisode) => left.number - right.number);
      seasons.push({ number: season.number, firstAired: airDate(season.first_aired), episodes: episodes });
    }
    seasons.sort((left: ScheduledSeason, right: ScheduledSeason) => left.number - right.number);
    let status = '';
    let rating: number | undefined = undefined;
    try {
      const details = await readDetails(item, clientId, true);
      status = details.status;
      if (details.rating > 0 && details.rating <= 10) { rating = details.rating; }
    } catch (error) {}
    const result: FullEpisodeCatalog = { media: item, status: status, fetchedAt: Date.now(), seasons: seasons, rating: rating };
    validateFullCatalog(result, item.id);
    return result;
  } finally {
    request.destroy();
  }
}

// The existing write-eligible catalog remains an aired-only projection.
export function eligibleCatalog(full: FullEpisodeCatalog, now: number): EpisodeCatalog {
  validateFullCatalog(full, full.media.id);
  const episodes = scheduleEpisodes(full).filter((episode: ScheduledEpisode) => aired(episode, now))
    .map((episode: ScheduledEpisode): LocalEpisode => {
      return { id: episode.id, season: episode.season, number: episode.number, title: episode.title };
    });
  const catalog: EpisodeCatalog = { showId: full.media.id, title: full.media.title, year: full.media.year, episodes: episodes };
  validateCatalog(catalog, catalog.showId);
  return catalog;
}

export async function fetchEpisodeCatalog(item: Media, clientId: string): Promise<EpisodeCatalog> {
  const full = await fetchFullEpisodeCatalog(item, clientId);
  return eligibleCatalog(full, full.fetchedAt);
}

// Event order (SQLite sequence), not the wall clock, determines final state.
function materialize(catalog: EpisodeCatalog, events: EpisodeEvent[], baseline: number[]): LocalSeriesState {
  const state: Map<number, boolean> = new Map<number, boolean>();
  for (const id of baseline) { state.set(id, true); }
  for (const event of events) {
    for (const id of event.ids) { state.set(id, event.watched); }
  }
  const seasons: LocalSeasonState[] = [];
  let completed = 0;
  let next = '';
  for (const episode of catalog.episodes) {
    const watched = state.get(episode.id) === true;
    let season = seasons.find((value: LocalSeasonState) => value.number === episode.season);
    if (!season) {
      season = { number: episode.season, episodes: [], completed: 0 };
      seasons.push(season);
    }
    season.episodes.push({ episode: episode, watched: watched });
    if (watched) {
      season.completed++;
      completed++;
    } else if (!next) {
      next = 'S' + episode.season + 'E' + episode.number + (episode.title ? ' · ' + episode.title : '');
    }
  }
  return { catalog: catalog, seasons: seasons, completed: completed, next: next };
}

export function materializeEffective(catalog: EpisodeCatalog, ids: number[]): LocalSeriesState {
  return materialize(catalog, [], ids);
}

export class EpisodeStore {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db = db; }

  static async open(context: common.UIAbilityContext): Promise<EpisodeStore> {
    const config: relationalStore.StoreConfig = {
      name: 'showly_episodes.db', securityLevel: relationalStore.SecurityLevel.S1
    };
    const db = await relationalStore.getRdbStore(context, config);
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_catalog (show_id TEXT PRIMARY KEY, catalog TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_schedule (show_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS remote_library_observation (account_uuid TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_read_checkpoint (account_uuid TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    // A single row represents one user action, including a whole season. SQLite
    // commits that row atomically: no partially marked seasons or split state/log.
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_event (seq INTEGER PRIMARY KEY AUTOINCREMENT, show_id TEXT NOT NULL, episode_ids TEXT NOT NULL, watched INTEGER NOT NULL CHECK(watched IN (0,1)), changed_at INTEGER NOT NULL)');
    await db.executeSql('CREATE INDEX IF NOT EXISTS episode_event_show_seq ON episode_event(show_id,seq)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_binding (slot INTEGER PRIMARY KEY CHECK(slot=1), account_uuid TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_upload_guard (account_uuid TEXT NOT NULL, episode_id INTEGER NOT NULL, attempted_at INTEGER NOT NULL, confirmed INTEGER NOT NULL DEFAULT 0 CHECK(confirmed IN (0,1)), PRIMARY KEY(account_uuid,episode_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_play_receipt (account_uuid TEXT NOT NULL, episode_id INTEGER NOT NULL, history_id INTEGER NOT NULL, watched_at TEXT NOT NULL, removal_state INTEGER NOT NULL DEFAULT 0 CHECK(removal_state IN (0,1,2)), PRIMARY KEY(account_uuid,episode_id), UNIQUE(account_uuid,history_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_cloud_baseline (account_uuid TEXT PRIMARY KEY, episode_ids TEXT NOT NULL, imported_at INTEGER NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_run_log (seq INTEGER PRIMARY KEY AUTOINCREMENT, account_uuid TEXT NOT NULL, mode TEXT NOT NULL, episode_ids TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL)');
    // Additive, restart-safe migration. Legacy events default to no upload consent.
    const columns = await db.querySql('PRAGMA table_info(episode_event)');
    let hasAuto = false;
    try {
      while (columns.goToNextRow()) {
        if (columns.getString(1) === 'auto_uuid') { hasAuto = true; }
      }
    } finally { columns.close(); }
    if (!hasAuto) { await db.executeSql("ALTER TABLE episode_event ADD COLUMN auto_uuid TEXT NOT NULL DEFAULT ''"); }
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_auto_consent (slot INTEGER PRIMARY KEY CHECK(slot=1), account_uuid TEXT NOT NULL, client_id TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_queue_done (account_uuid TEXT NOT NULL, event_seq INTEGER NOT NULL, episode_id INTEGER NOT NULL, PRIMARY KEY(account_uuid,event_seq,episode_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_play_archive (account_uuid TEXT NOT NULL, episode_id INTEGER NOT NULL, history_id INTEGER NOT NULL, watched_at TEXT NOT NULL, archived_at INTEGER NOT NULL, PRIMARY KEY(account_uuid,history_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_restore_baseline (show_id TEXT PRIMARY KEY, episode_ids TEXT NOT NULL, verified INTEGER NOT NULL DEFAULT 0 CHECK(verified IN (0,1)))');
    await db.executeSql("CREATE TABLE IF NOT EXISTS sync_common_state (account_uuid TEXT NOT NULL, domain TEXT NOT NULL CHECK(domain='episode'), payload TEXT NOT NULL, PRIMARY KEY(account_uuid,domain))");
    return new EpisodeStore(db);
  }

  // Account/domain isolation; one validated JSON map per domain. No restored
  // backup, unknown local default, or pending mutation is a common baseline.
  async commonStates(uuid: string, domain: string): Promise<Map<string, CommonEntry>> {
    if (!uuid || await this.boundAccount() !== uuid || domain !== 'episode') { throw new Error('Invalid baseline scope'); }
    const rows = await this.db.querySql('SELECT payload FROM sync_common_state WHERE account_uuid=? AND domain=?', [uuid, domain]);
    const result: Map<string, CommonEntry> = new Map<string, CommonEntry>();
    try {
      if (!rows.goToFirstRow()) { return result; }
      const entries = JSON.parse(rows.getString(0)) as CommonEntry[];
      if (!Array.isArray(entries)) { throw new Error('Invalid common baseline'); }
      for (const entry of entries) {
        if (!entry || typeof entry.id !== 'string' || !commonId(domain, entry.id) ||
            typeof entry.value !== 'boolean' || typeof entry.activity !== 'string' || !entry.activity ||
            result.has(entry.id)) { throw new Error('Invalid common baseline entry'); }
        result.set(entry.id, entry);
      }
      return result;
    } finally { rows.close(); }
  }

  async saveCommonStates(uuid: string, domain: string, activity: string, updates: CommonUpdate[]): Promise<number> {
    if (typeof activity !== 'string' || !activity) { throw new Error('Missing baseline revision'); }
    const entries = await this.commonStates(uuid, domain);
    const seen: Set<string> = new Set<string>();
    for (const update of updates) {
      if (!commonId(domain, update.id) || typeof update.value !== 'boolean' || seen.has(update.id)) {
        throw new Error('Invalid baseline update');
      }
      seen.add(update.id);
      entries.set(update.id, { id: update.id, value: update.value, activity: activity });
    }
    if (!updates.length) { return 0; }
    // Single atomic row; unrelated or still divergent entries are retained.
    const payload = JSON.stringify(Array.from(entries.values()));
    await this.db.executeSql('INSERT OR REPLACE INTO sync_common_state(account_uuid,domain,payload) VALUES(?,?,?)',
      [uuid, domain, payload]);
    const verified = await this.commonStates(uuid, domain);
    if (JSON.stringify(Array.from(verified.values())) !== payload) { throw new Error('Baseline verification failed'); }
    return updates.length;
  }

  async adoptRemote(uuid: string, episodeId: number, expectedSeq: number, value: boolean, activity: string): Promise<void> {
    if (await this.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
    const intent = (await this.journalIntents()).find((row: JournalIntent) => row.episodeId === episodeId);
    if (!intent || !intent.catalogKnown || intent.seq !== expectedSeq || intent.watched === value) {
      throw new Error('Local intent changed');
    }
    this.db.beginTransaction();
    try {
      // No autoUuid: accepting a cloud state never authorizes a new upload.
      await this.mark(intent.showId, [episodeId], value);
      await this.saveCommonStates(uuid, 'episode', activity, [{ id: episodeId.toString(), value: value }]);
      this.db.commit();
    } catch (error) {
      this.db.rollBack();
      throw new Error('Episode adoption transaction failed');
    }
  }

  async catalog(showId: string): Promise<EpisodeCatalog | undefined> {
    const result = await this.db.querySql('SELECT catalog FROM episode_catalog WHERE show_id = ?', [showId]);
    try {
      if (!result.goToFirstRow()) { return undefined; }
      const catalog = JSON.parse(result.getString(0)) as EpisodeCatalog;
      validateCatalog(catalog, showId);
      return catalog;
    } finally {
      result.close();
    }
  }

  async fullCatalog(showId: string): Promise<FullEpisodeCatalog | undefined> {
    const rows = await this.db.querySql('SELECT payload FROM episode_schedule WHERE show_id=?', [showId]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const full = JSON.parse(rows.getString(0)) as FullEpisodeCatalog;
      validateFullCatalog(full, showId);
      return full;
    } finally { rows.close(); }
  }

  // Public schedule only: no eligible-catalog replacement, restore verification,
  // journal event, account binding, receipt or upload consent.
  async saveObservedSchedule(full: FullEpisodeCatalog): Promise<void> {
    validateFullCatalog(full, full.media.id);
    const old = await this.fullCatalog(full.media.id);
    if (old && scheduleEpisodes(old).length > 0 && scheduleEpisodes(full).length === 0) {
      throw new Error('Empty replacement schedule');
    }
    await this.db.executeSql('INSERT OR REPLACE INTO episode_schedule(show_id,payload) VALUES(?,?)',
      [full.media.id, JSON.stringify(full)]);
  }

  async readRemoteObservation(uuid: string): Promise<RemoteLibraryObservation | undefined> {
    if (!uuid || uuid.trim() !== uuid) { throw new Error('Invalid observation scope'); }
    const rows = await this.db.querySql('SELECT payload FROM remote_library_observation WHERE account_uuid=?', [uuid]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const snapshot = JSON.parse(rows.getString(0)) as RemoteLibraryObservation;
      validateObservation(snapshot);
      return snapshot;
    } finally { rows.close(); }
  }

  async saveRemoteObservation(uuid: string, snapshot: RemoteLibraryObservation): Promise<void> {
    if (!uuid || uuid.trim() !== uuid) { throw new Error('Invalid observation scope'); }
    validateObservation(snapshot);
    await this.db.executeSql('INSERT OR REPLACE INTO remote_library_observation(account_uuid,payload) VALUES(?,?)',
      [uuid, JSON.stringify(snapshot)]);
  }

  async readCheckpoints(uuid: string): Promise<Map<number, ReadCheckpoint>> {
    if (!uuid || await this.boundAccount() !== uuid) { throw new Error('Invalid read checkpoint scope'); }
    const result: Map<number, ReadCheckpoint> = new Map<number, ReadCheckpoint>();
    const rows = await this.db.querySql('SELECT payload FROM episode_read_checkpoint WHERE account_uuid=?', [uuid]);
    try {
      if (!rows.goToFirstRow()) { return result; }
      const entries = JSON.parse(rows.getString(0)) as ReadCheckpoint[];
      if (!Array.isArray(entries)) { throw new Error('Invalid read checkpoints'); }
      for (const entry of entries) {
        if (!entry || !validId(entry.id) || !validId(entry.seq) ||
            typeof entry.watched !== 'boolean' || result.has(entry.id)) { throw new Error('Invalid read checkpoint'); }
        result.set(entry.id, entry);
      }
      return result;
    } finally { rows.close(); }
  }

  // Read projection acknowledgements are NOT sync_common_state and are
  // never consumed by upload, removal, or queue eligibility.
  async saveReadCheckpoints(uuid: string, updates: ReadCheckpoint[]): Promise<void> {
    if (!updates.length) { return; }
    const entries = await this.readCheckpoints(uuid);
    for (const update of updates) {
      if (!validId(update.id) || !validId(update.seq) || typeof update.watched !== 'boolean') {
        throw new Error('Invalid read checkpoint update');
      }
      const prior = entries.get(update.id);
      if (!prior || update.seq >= prior.seq) { entries.set(update.id, update); }
    }
    await this.db.executeSql('INSERT OR REPLACE INTO episode_read_checkpoint(account_uuid,payload) VALUES(?,?)',
      [uuid, JSON.stringify(Array.from(entries.values()))]);
  }

  async saveFullCatalog(full: FullEpisodeCatalog): Promise<void> {
    const catalog = eligibleCatalog(full, full.fetchedAt);
    // Both projections commit together. Keep every journal, receipt and
    // baseline untouched; never make a future/unknown episode eligible.
    this.db.beginTransaction();
    try {
      await this.saveCatalog(catalog);
      await this.db.executeSql('INSERT OR REPLACE INTO episode_schedule(show_id,payload) VALUES(?,?)',
        [catalog.showId, JSON.stringify(full)]);
      this.db.commit();
    } catch (error) {
      this.db.rollBack();
      throw new Error('Catalog refresh failed; previous data retained');
    }
  }

  async saveCatalog(catalog: EpisodeCatalog): Promise<void> {
    validateCatalog(catalog, catalog.showId);
    // Refuse an unexpectedly empty refresh of an existing nonempty catalog.
    const old = await this.catalog(catalog.showId);
    if (old && old.episodes.length > 0 && catalog.episodes.length === 0) {
      throw new Error('Empty replacement catalog');
    }
    await this.db.executeSql('INSERT OR REPLACE INTO episode_catalog(show_id,catalog,updated_at) VALUES(?,?,?)',
      [catalog.showId, JSON.stringify(catalog), Date.now()]);
    // A catalog obtained from the public Trakt API is required before edits
    // to restored shows can create explicit synchronization intents.
    await this.db.executeSql('UPDATE episode_restore_baseline SET verified=1 WHERE show_id=?', [catalog.showId]);
  }

  async read(showId: string): Promise<LocalSeriesState | undefined> {
    const catalog = await this.catalog(showId);
    if (!catalog) { return undefined; }
    const result = await this.db.querySql('SELECT episode_ids,watched FROM episode_event WHERE show_id = ? ORDER BY seq', [showId]);
    const events: EpisodeEvent[] = [];
    try {
      while (result.goToNextRow()) {
        const ids = JSON.parse(result.getString(0)) as number[];
        const watched = result.getLong(1);
        if (!Array.isArray(ids) || ids.length === 0 || ids.some((id: number) => !validId(id)) ||
            (watched !== 0 && watched !== 1)) { throw new Error('Invalid episode journal'); }
        events.push({ ids: ids, watched: watched === 1 });
      }
    } finally {
      result.close();
    }
    const uuid = await this.boundAccount();
    const baseline = uuid ? await this.cloudBaseline(uuid) : [];
    const restored = await this.restoredIds(showId);
    return materialize(catalog, events, [...baseline, ...restored]);
  }

  async mark(showId: string, ids: number[], watched: boolean, autoUuid: string = ''): Promise<void> {
    const catalog = await this.catalog(showId);
    if (!catalog || ids.length === 0) { throw new Error('Missing episode catalog'); }
    if (await this.needsCatalogVerification(showId)) { throw new Error('Restored catalog must be refreshed'); }
    const allowed: Set<number> = new Set<number>(catalog.episodes.map((ep: LocalEpisode) => ep.id));
    const unique: Set<number> = new Set<number>(ids);
    if (ids.some((id: number) => !allowed.has(id))) { throw new Error('Episode no longer available'); }
    const consent = autoUuid ? await this.autoConsent() : undefined;
    const authorized = watched && consent?.uuid === autoUuid && await this.boundAccount() === autoUuid ? autoUuid : '';
    await this.db.executeSql('INSERT INTO episode_event(show_id,episode_ids,watched,changed_at,auto_uuid) VALUES(?,?,?,?,?)',
      [showId, JSON.stringify(Array.from(unique)), watched ? 1 : 0, Date.now(), authorized]);
  }

  async boundAccount(): Promise<string> {
    const rows = await this.db.querySql('SELECT account_uuid FROM sync_binding WHERE slot=1');
    try {
      if (!rows.goToFirstRow()) { return ''; }
      const uuid = rows.getString(0);
      if (!uuid || uuid.trim() !== uuid) { throw new Error('Invalid binding'); }
      return uuid;
    } finally { rows.close(); }
  }

  // One explicit, durable binding; never silently replace an existing account.
  async bindAccount(uuid: string): Promise<void> {
    if (!uuid || uuid.trim() !== uuid) { throw new Error('Invalid account'); }
    await this.db.executeSql('INSERT OR IGNORE INTO sync_binding(slot,account_uuid) VALUES(1,?)', [uuid]);
    if (await this.boundAccount() !== uuid) { throw new Error('Account binding mismatch'); }
  }

  async autoConsent(): Promise<AutoConsent | undefined> {
    const rows = await this.db.querySql('SELECT account_uuid,client_id FROM sync_auto_consent WHERE slot=1');
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const uuid = rows.getString(0);
      const clientId = rows.getString(1);
      if (!uuid || !clientId) { throw new Error('Invalid consent'); }
      return { uuid: uuid, clientId: clientId };
    } finally { rows.close(); }
  }

  async saveAutoConsent(uuid: string, clientId: string): Promise<void> {
    if (!clientId || await this.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
    await this.db.executeSql('INSERT OR REPLACE INTO sync_auto_consent(slot,account_uuid,client_id) VALUES(1,?,?)', [uuid, clientId]);
  }

  async clearAutoConsent(): Promise<void> {
    await this.db.executeSql('DELETE FROM sync_auto_consent WHERE slot=1');
  }

  async queueEntries(uuid: string): Promise<QueueEntry[]> {
    if (await this.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
    const done = await this.db.querySql('SELECT event_seq,episode_id FROM sync_queue_done WHERE account_uuid=?', [uuid]);
    const completed: Set<string> = new Set<string>();
    try {
      while (done.goToNextRow()) { completed.add(done.getLong(0) + ':' + done.getLong(1)); }
    } finally { done.close(); }
    const intents = await this.journalIntents();
    const result: QueueEntry[] = [];
    for (const intent of intents) {
      if (!intent.watched || intent.autoUuid !== uuid || completed.has(intent.seq + ':' + intent.episodeId)) { continue; }
      const guard = await this.hasUploadAttempt(uuid, intent.episodeId);
      result.push({ episodeId: intent.episodeId, seq: intent.seq, label: intent.label,
        watchedAt: new Date(intent.changedAt).toISOString(),
        blocked: !intent.catalogKnown || guard,
        protection: !intent.catalogKnown ? '目录异常' : guard ? '已有上传凭证，仅核对，不重发' : '' });
    }
    return result;
  }

  async finishQueue(uuid: string, entry: QueueEntry): Promise<void> {
    if (await this.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
    await this.db.executeSql('INSERT OR IGNORE INTO sync_queue_done(account_uuid,event_seq,episode_id) VALUES(?,?,?)',
      [uuid, entry.seq, entry.episodeId]);
  }

  async hasUploadAttempt(uuid: string, episodeId: number): Promise<boolean> {
    const rows = await this.db.querySql('SELECT episode_id FROM sync_upload_guard WHERE account_uuid=? AND episode_id=?', [uuid, episodeId]);
    let exists = false;
    try { exists = rows.goToFirstRow(); } finally { rows.close(); }
    if (!exists) { return false; }
    const receipt = await this.undoReceipt(uuid, episodeId);
    return receipt?.removalState !== 2;
  }

  async reserveUpload(uuid: string, episodeId: number): Promise<void> {
    if (!validId(episodeId) || await this.boundAccount() !== uuid) { throw new Error('Invalid upload identity'); }
    // Only a verified prior removal allows a fresh attempt. Archive the old
    // receipt and rotate its guard atomically, so a crash cannot erase provenance.
    const receipt = await this.undoReceipt(uuid, episodeId);
    if (receipt?.removalState === 2) {
      this.db.beginTransaction();
      try {
        await this.db.executeSql('INSERT INTO sync_play_archive(account_uuid,episode_id,history_id,watched_at,archived_at) SELECT account_uuid,episode_id,history_id,watched_at,? FROM sync_play_receipt WHERE account_uuid=? AND episode_id=? AND removal_state=2',
          [Date.now(), uuid, episodeId]);
        await this.db.executeSql('DELETE FROM sync_play_receipt WHERE account_uuid=? AND episode_id=? AND removal_state=2', [uuid, episodeId]);
        await this.db.executeSql('DELETE FROM sync_upload_guard WHERE account_uuid=? AND episode_id=? AND confirmed=1', [uuid, episodeId]);
        await this.db.executeSql('INSERT INTO sync_upload_guard(account_uuid,episode_id,attempted_at,confirmed) VALUES(?,?,?,0)', [uuid, episodeId, Date.now()]);
        this.db.commit();
      } catch (error) {
        this.db.rollBack();
        throw new Error('Rearm transaction failed');
      }
      return;
    }
    await this.db.executeSql('INSERT INTO sync_upload_guard(account_uuid,episode_id,attempted_at,confirmed) VALUES(?,?,?,0)',
      [uuid, episodeId, Date.now()]);
  }

  async confirmUpload(uuid: string, episodeId: number): Promise<void> {
    await this.db.executeSql('UPDATE sync_upload_guard SET confirmed=1 WHERE account_uuid=? AND episode_id=?',
      [uuid, episodeId]);
  }

  async undoReceipt(uuid: string, episodeId: number): Promise<UndoReceipt | undefined> {
    const rows = await this.db.querySql('SELECT history_id,watched_at,removal_state FROM sync_play_receipt WHERE account_uuid=? AND episode_id=?', [uuid, episodeId]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const id = rows.getLong(0);
      const at = rows.getString(1);
      const state = rows.getLong(2);
      if (!validId(id) || !Number.isFinite(Date.parse(at)) || (state !== 0 && state !== 1 && state !== 2)) {
        throw new Error('Invalid history receipt');
      }
      return { historyId: id, watchedAt: at, removalState: state };
    } finally { rows.close(); }
  }

  async saveUndoReceipt(uuid: string, episodeId: number, historyId: number, watchedAt: string): Promise<void> {
    if (!validId(episodeId) || !validId(historyId) || !Number.isFinite(Date.parse(watchedAt)) ||
        await this.boundAccount() !== uuid || !await this.hasUploadAttempt(uuid, episodeId)) {
      throw new Error('Invalid history receipt');
    }
    await this.db.executeSql('INSERT INTO sync_play_receipt(account_uuid,episode_id,history_id,watched_at,removal_state) VALUES(?,?,?,?,0)',
      [uuid, episodeId, historyId, watchedAt]);
  }

  async reserveRemoval(uuid: string, episodeId: number, historyId: number): Promise<void> {
    const receipt = await this.undoReceipt(uuid, episodeId);
    if (!receipt || receipt.historyId !== historyId || receipt.removalState !== 0 || await this.boundAccount() !== uuid) {
      throw new Error('Removal not eligible');
    }
    await this.db.executeSql('UPDATE sync_play_receipt SET removal_state=1 WHERE account_uuid=? AND episode_id=? AND history_id=? AND removal_state=0',
      [uuid, episodeId, historyId]);
  }

  async confirmRemoval(uuid: string, episodeId: number, historyId: number): Promise<void> {
    await this.db.executeSql('UPDATE sync_play_receipt SET removal_state=2 WHERE account_uuid=? AND episode_id=? AND history_id=? AND removal_state=1',
      [uuid, episodeId, historyId]);
  }

  async cloudBaseline(uuid: string): Promise<number[]> {
    const rows = await this.db.querySql('SELECT episode_ids FROM sync_cloud_baseline WHERE account_uuid=?', [uuid]);
    try {
      if (!rows.goToFirstRow()) { return []; }
      const ids = JSON.parse(rows.getString(0)) as number[];
      if (!Array.isArray(ids) || ids.some((id: number) => !validId(id)) ||
          new Set<number>(ids).size !== ids.length) { throw new Error('Invalid cloud baseline'); }
      return ids;
    } finally { rows.close(); }
  }

  // Add-only baseline. Never append cloud data to explicit local intent events.
  async importCloudBaseline(uuid: string, ids: number[]): Promise<number> {
    if (await this.boundAccount() !== uuid || ids.some((id: number) => !validId(id))) {
      throw new Error('Invalid baseline identity');
    }
    const old = await this.cloudBaseline(uuid);
    const next: Set<number> = new Set<number>(old);
    for (const id of ids) { next.add(id); }
    await this.db.executeSql('INSERT OR REPLACE INTO sync_cloud_baseline(account_uuid,episode_ids,imported_at) VALUES(?,?,?)',
      [uuid, JSON.stringify(Array.from(next)), Date.now()]);
    return next.size - old.length;
  }

  // Release only a guard created by this process before any POST was invoked.
  async releaseUnsentUpload(uuid: string, episodeId: number): Promise<void> {
    await this.db.executeSql('DELETE FROM sync_upload_guard WHERE account_uuid=? AND episode_id=? AND confirmed=0',
      [uuid, episodeId]);
  }

  async logSync(uuid: string, mode: string, ids: number[], status: string): Promise<void> {
    if (await this.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
    await this.db.executeSql('INSERT INTO sync_run_log(account_uuid,mode,episode_ids,status,created_at) VALUES(?,?,?,?,?)',
      [uuid, mode, JSON.stringify(ids), status, Date.now()]);
  }

  async syncLogs(uuid: string): Promise<string[]> {
    const rows = await this.db.querySql('SELECT mode,status,created_at,episode_ids FROM sync_run_log WHERE account_uuid=? ORDER BY seq DESC LIMIT 12', [uuid]);
    const result: string[] = [];
    try {
      while (rows.goToNextRow()) {
        const ids = JSON.parse(rows.getString(3)) as number[];
        if (!Array.isArray(ids)) { throw new Error('Invalid log'); }
        result.push(new Date(rows.getLong(2)).toLocaleString() + ' · ' + rows.getString(0) + ' · ' +
          rows.getString(1) + (ids.length ? ' · 分集 ID: ' + ids.join(', ') : ''));
      }
    } finally { rows.close(); }
    return result;
  }

  async journalIntents(): Promise<JournalIntent[]> {
    const rows = await this.db.querySql('SELECT e.show_id,e.episode_ids,e.watched,c.catalog,e.seq,e.auto_uuid,e.changed_at FROM episode_event e LEFT JOIN episode_catalog c ON c.show_id=e.show_id ORDER BY e.seq');
    const latest: Map<number, JournalIntent> = new Map<number, JournalIntent>();
    const catalogs: Map<string, EpisodeCatalog> = new Map<string, EpisodeCatalog>();
    try {
      while (rows.goToNextRow()) {
        const showId = rows.getString(0);
        if (!/^show:[1-9][0-9]*$/.test(showId)) { throw new Error('Invalid journal show'); }
        const ids = JSON.parse(rows.getString(1)) as number[];
        const watched = rows.getLong(2);
        if (!Array.isArray(ids) || ids.length === 0 || ids.some((id: number) => !validId(id)) ||
            (watched !== 0 && watched !== 1)) { throw new Error('Invalid journal event'); }
        let catalog = catalogs.get(showId);
        if (!catalog && !rows.isColumnNull(3)) {
          catalog = JSON.parse(rows.getString(3)) as EpisodeCatalog;
          validateCatalog(catalog, showId);
          catalogs.set(showId, catalog);
        }
        const seq = rows.getLong(4);
        const autoUuid = rows.getString(5);
        const changedAt = rows.getLong(6);
        if (!validId(seq) || !validId(changedAt)) { throw new Error('Invalid event sequence'); }
        for (const id of ids) {
          const prior = latest.get(id);
          if (prior && prior.showId !== showId) { throw new Error('Conflicting episode identity'); }
          const episode = catalog?.episodes.find((ep: LocalEpisode) => ep.id === id);
          latest.set(id, { seq: seq, autoUuid: autoUuid, changedAt: changedAt, episodeId: id, showId: showId, watched: watched === 1,
            catalogKnown: !!episode, label: episode ?
              (catalog?.title ?? showId) + ' · S' + episode.season + 'E' + episode.number :
              showId + ' · Trakt episode ' + id });
        }
      }
    } finally { rows.close(); }
    return Array.from(latest.values());
  }

  private async restoredIds(showId: string): Promise<number[]> {
    const rows = await this.db.querySql('SELECT episode_ids FROM episode_restore_baseline WHERE show_id=?', [showId]);
    try {
      if (!rows.goToFirstRow()) { return []; }
      const ids = JSON.parse(rows.getString(0)) as number[];
      if (!Array.isArray(ids) || ids.some((id: number) => !validId(id)) ||
          new Set<number>(ids).size !== ids.length) { throw new Error('Invalid restored baseline'); }
      return ids;
    } finally { rows.close(); }
  }

  async needsCatalogVerification(showId: string): Promise<boolean> {
    const rows = await this.db.querySql('SELECT verified FROM episode_restore_baseline WHERE show_id=?', [showId]);
    try { return rows.goToFirstRow() && rows.getLong(0) !== 1; } finally { rows.close(); }
  }

  async backupStates(): Promise<EpisodeBackupState[]> {
    const rows = await this.db.querySql('SELECT show_id FROM episode_catalog ORDER BY show_id');
    const ids: string[] = [];
    try {
      while (rows.goToNextRow()) { ids.push(rows.getString(0)); }
    } finally { rows.close(); }
    const result: EpisodeBackupState[] = [];
    for (const id of ids) {
      const state = await this.read(id);
      if (!state) { throw new Error('Catalog disappeared during backup'); }
      const watchedIds: number[] = [];
      for (const season of state.seasons) {
        for (const ep of season.episodes) {
          if (ep.watched) { watchedIds.push(ep.episode.id); }
        }
      }
      result.push({ catalog: state.catalog, watchedIds: watchedIds });
    }
    return result;
  }

  async missingBackupShows(states: EpisodeBackupState[]): Promise<EpisodeBackupState[]> {
    const rows = await this.db.querySql('SELECT show_id FROM episode_catalog UNION SELECT show_id FROM episode_event UNION SELECT show_id FROM episode_restore_baseline');
    const existing: Set<string> = new Set<string>();
    try {
      while (rows.goToNextRow()) { existing.add(rows.getString(0)); }
    } finally { rows.close(); }
    return states.filter((state: EpisodeBackupState) => !existing.has(state.catalog.showId));
  }

  async restoreMissingShows(states: EpisodeBackupState[]): Promise<number> {
    const missing = await this.missingBackupShows(states);
    if (!missing.length) { return 0; }
    // All episode additions are one transaction; no events, guards, receipts,
    // account IDs or auto-consent are restored from an external file.
    this.db.beginTransaction();
    try {
      for (const state of missing) {
        validateCatalog(state.catalog, state.catalog.showId);
        const allowed: Set<number> = new Set<number>(state.catalog.episodes.map((ep: LocalEpisode) => ep.id));
        if (!Array.isArray(state.watchedIds) ||
            state.watchedIds.some((id: number) => !allowed.has(id)) ||
            new Set<number>(state.watchedIds).size !== state.watchedIds.length) { throw new Error('Invalid backup watched IDs'); }
        await this.db.executeSql('INSERT INTO episode_catalog(show_id,catalog,updated_at) VALUES(?,?,?)',
          [state.catalog.showId, JSON.stringify(state.catalog), Date.now()]);
        await this.db.executeSql('INSERT INTO episode_restore_baseline(show_id,episode_ids,verified) VALUES(?,?,0)',
          [state.catalog.showId, JSON.stringify(state.watchedIds)]);
      }
      this.db.commit();
    } catch (error) {
      this.db.rollBack();
      throw new Error('Episode restore transaction failed');
    }
    return missing.length;
  }

  async recent(): Promise<Media[]> {
    const rows = await this.db.querySql('SELECT c.show_id,c.catalog FROM episode_catalog c LEFT JOIN (SELECT show_id,MAX(seq) AS last_seq FROM episode_event GROUP BY show_id) e ON e.show_id=c.show_id LEFT JOIN episode_restore_baseline r ON r.show_id=c.show_id WHERE e.last_seq IS NOT NULL OR r.show_id IS NOT NULL ORDER BY COALESCE(e.last_seq,0) DESC,c.updated_at DESC LIMIT 12');
    const items: Media[] = [];
    try {
      while (rows.goToNextRow()) {
        const id = rows.getString(0);
        const catalog = JSON.parse(rows.getString(1)) as EpisodeCatalog;
        validateCatalog(catalog, id);
        items.push({ id: id, title: catalog.title, year: catalog.year, kind: 'show', watched: false });
      }
    } finally {
      rows.close();
    }
    return items;
  }
}
