import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { canReadDetails } from './TraktDetails';

interface EpisodeIds { trakt: number; }
interface RemoteEpisode {
  number: number;
  title?: string;
  first_aired?: string;
  ids: EpisodeIds;
}
interface RemoteSeason { number: number; episodes?: RemoteEpisode[]; }

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
export interface JournalIntent {
  episodeId: number;
  showId: string;
  label: string;
  watched: boolean;
  catalogKnown: boolean;
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
function validateCatalog(catalog: EpisodeCatalog, showId: string): void {
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
export async function fetchEpisodeCatalog(item: Media, clientId: string): Promise<EpisodeCatalog> {
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
    const episodes: LocalEpisode[] = [];
    const now = Date.now();
    for (const season of rows) {
      if (season.number === 0) { continue; }
      if (!validId(season.number) || !Array.isArray(season.episodes)) {
        throw new Error('Missing season episodes');
      }
      for (const ep of season.episodes) {
        // Unknown and future air dates are not eligible for watched/bulk actions.
        const aired = typeof ep.first_aired === 'string' ? Date.parse(ep.first_aired) : NaN;
        if (!Number.isFinite(aired) || aired > now) { continue; }
        if (!ep.ids || !validId(ep.ids.trakt) || !validId(ep.number)) {
          throw new Error('Invalid aired episode identity');
        }
        episodes.push({ id: ep.ids.trakt, season: season.number, number: ep.number,
          title: typeof ep.title === 'string' ? ep.title : '' });
      }
    }
    episodes.sort((left: LocalEpisode, right: LocalEpisode) =>
      left.season - right.season || left.number - right.number);
    const result: EpisodeCatalog = { showId: item.id, title: item.title, year: item.year, episodes: episodes };
    validateCatalog(result, item.id);
    return result;
  } finally {
    request.destroy();
  }
}

// Event order (SQLite sequence), not the wall clock, determines final state.
function materialize(catalog: EpisodeCatalog, events: EpisodeEvent[]): LocalSeriesState {
  const state: Map<number, boolean> = new Map<number, boolean>();
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

export class EpisodeStore {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db = db; }

  static async open(context: common.UIAbilityContext): Promise<EpisodeStore> {
    const config: relationalStore.StoreConfig = {
      name: 'showly_episodes.db', securityLevel: relationalStore.SecurityLevel.S1
    };
    const db = await relationalStore.getRdbStore(context, config);
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_catalog (show_id TEXT PRIMARY KEY, catalog TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    // A single row represents one user action, including a whole season. SQLite
    // commits that row atomically: no partially marked seasons or split state/log.
    await db.executeSql('CREATE TABLE IF NOT EXISTS episode_event (seq INTEGER PRIMARY KEY AUTOINCREMENT, show_id TEXT NOT NULL, episode_ids TEXT NOT NULL, watched INTEGER NOT NULL CHECK(watched IN (0,1)), changed_at INTEGER NOT NULL)');
    await db.executeSql('CREATE INDEX IF NOT EXISTS episode_event_show_seq ON episode_event(show_id,seq)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS sync_binding (slot INTEGER PRIMARY KEY CHECK(slot=1), account_uuid TEXT NOT NULL)');
    return new EpisodeStore(db);
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

  async saveCatalog(catalog: EpisodeCatalog): Promise<void> {
    validateCatalog(catalog, catalog.showId);
    // Refuse an unexpectedly empty refresh of an existing nonempty catalog.
    const old = await this.catalog(catalog.showId);
    if (old && old.episodes.length > 0 && catalog.episodes.length === 0) {
      throw new Error('Empty replacement catalog');
    }
    await this.db.executeSql('INSERT OR REPLACE INTO episode_catalog(show_id,catalog,updated_at) VALUES(?,?,?)',
      [catalog.showId, JSON.stringify(catalog), Date.now()]);
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
    return materialize(catalog, events);
  }

  async mark(showId: string, ids: number[], watched: boolean): Promise<void> {
    const catalog = await this.catalog(showId);
    if (!catalog || ids.length === 0) { throw new Error('Missing episode catalog'); }
    const allowed: Set<number> = new Set<number>(catalog.episodes.map((ep: LocalEpisode) => ep.id));
    const unique: Set<number> = new Set<number>(ids);
    if (ids.some((id: number) => !allowed.has(id))) { throw new Error('Episode no longer available'); }
    await this.db.executeSql('INSERT INTO episode_event(show_id,episode_ids,watched,changed_at) VALUES(?,?,?,?)',
      [showId, JSON.stringify(Array.from(unique)), watched ? 1 : 0, Date.now()]);
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

  async journalIntents(): Promise<JournalIntent[]> {
    const rows = await this.db.querySql('SELECT e.show_id,e.episode_ids,e.watched,c.catalog FROM episode_event e LEFT JOIN episode_catalog c ON c.show_id=e.show_id ORDER BY e.seq');
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
        for (const id of ids) {
          const prior = latest.get(id);
          if (prior && prior.showId !== showId) { throw new Error('Conflicting episode identity'); }
          const episode = catalog?.episodes.find((ep: LocalEpisode) => ep.id === id);
          latest.set(id, { episodeId: id, showId: showId, watched: watched === 1,
            catalogKnown: !!episode, label: episode ?
              (catalog?.title ?? showId) + ' · S' + episode.season + 'E' + episode.number :
              showId + ' · Trakt episode ' + id });
        }
      }
    } finally { rows.close(); }
    return Array.from(latest.values());
  }

  async recent(): Promise<Media[]> {
    const rows = await this.db.querySql('SELECT c.show_id,c.catalog FROM episode_catalog c JOIN (SELECT show_id,MAX(seq) AS last_seq FROM episode_event GROUP BY show_id) e ON e.show_id=c.show_id ORDER BY e.last_seq DESC LIMIT 12');
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
