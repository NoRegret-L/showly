import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';
import { readActivity } from './TraktLibrary';
import { EpisodeStore, JournalIntent } from './EpisodeStore';

interface UserIds { uuid: string; }
interface UserIdentity { username: string; ids: UserIds; }
interface UserSettings { user: UserIdentity; }
export interface SyncAccount { uuid: string; username: string; generation: number; }
interface EpisodeIds { trakt: number; }
interface WatchedEpisode { ids: EpisodeIds; }
interface WatchedRow { episode: WatchedEpisode; plays: number; }
interface WatchedPage { items: WatchedRow[]; pages: number; total: number; }
export interface SyncDifference {
  episodeId: number;
  label: string;
  localWatched: boolean;
  cloudWatched: boolean;
  kind: string;
  undoHistoryId: number;
  undoWatchedAt: string;
  undoState: number;
  uploadBlocked: boolean;
}
export interface SyncPreview {
  account: SyncAccount;
  activity: string;
  localCount: number;
  cloudCount: number;
  cloudIds: number[];
  cloudOnly: number;
  additions: number;
  matches: number;
  conflicts: number;
  unknown: number;
  rows: SyncDifference[];
}

function ensureCurrent(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Account session changed');
  }
}

export async function readSyncAccount(session: TraktSession): Promise<SyncAccount> {
  ensureCurrent(session);
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/users/settings', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Account verification failed');
    }
    const settings = JSON.parse(response.result) as UserSettings;
    const user = settings.user;
    if (!user || typeof user.username !== 'string' || !user.username ||
        !user.ids || typeof user.ids.uuid !== 'string' || !user.ids.uuid ||
        user.ids.uuid.trim() !== user.ids.uuid) {
      throw new Error('Stable account identity missing');
    }
    return { uuid: user.ids.uuid, username: user.username, generation: session.generation };
  } finally { request.destroy(); }
}

async function watchedPage(session: TraktSession, page: number): Promise<WatchedPage> {
  ensureCurrent(session);
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/sync/watched/episodes?page=' + page + '&limit=250', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Watched episode HTTP ' + response.responseCode);
    }
    const items = JSON.parse(response.result) as WatchedRow[];
    const headers = JSON.parse(JSON.stringify(response.header).toLowerCase()) as Record<string, string>;
    const pages = Number(headers['x-pagination-page-count']);
    const total = Number(headers['x-pagination-item-count']);
    const current = Number(headers['x-pagination-page']);
    if (!Array.isArray(items) || current !== page || !Number.isSafeInteger(pages) || pages < 0 ||
        !Number.isSafeInteger(total) || total < 0 ||
        (pages < page && !(page === 1 && items.length === 0 && pages === 0))) {
      throw new Error('Invalid watched pagination');
    }
    return { items: items, pages: pages, total: total };
  } finally { request.destroy(); }
}

function addWatched(ids: Set<number>, rows: WatchedRow[]): void {
  for (const row of rows) {
    const id = row.episode?.ids?.trakt;
    if (typeof id !== 'number' || !Number.isSafeInteger(id) || id <= 0 ||
        !Number.isSafeInteger(row.plays) || row.plays <= 0 || ids.has(id)) {
      throw new Error('Invalid or duplicate watched episode');
    }
    ids.add(id);
  }
}

async function readWatched(session: TraktSession): Promise<Set<number>> {
  const first = await watchedPage(session, 1);
  const ids: Set<number> = new Set<number>();
  addWatched(ids, first.items);
  for (let page = 2; page <= first.pages; page++) {
    const next = await watchedPage(session, page);
    if (next.pages !== first.pages || next.total !== first.total || next.items.length === 0) {
      throw new Error('Watched list changed while reading');
    }
    addWatched(ids, next.items);
  }
  if (ids.size !== first.total) { throw new Error('Incomplete watched list'); }
  return ids;
}

// No baseline means no inferred deletion. Only explicit local intent is compared.
export function classifyIntent(intent: JournalIntent, cloudWatched: boolean): string {
  if (!intent.catalogKnown) { return 'unknown'; }
  if (intent.watched === cloudWatched) { return 'match'; }
  return intent.watched ? 'addition' : 'conflict';
}

interface WatchedCache {
  uuid: string;
  clientId: string;
  generation: number;
  activity: string;
  ids: Set<number>;
}
let watchedCache: WatchedCache | undefined;

export function invalidateWatchedCache(): void { watchedCache = undefined; }

export async function buildSyncPreview(store: EpisodeStore, session: TraktSession,
  force: boolean = false): Promise<SyncPreview> {
  const account = await readSyncAccount(session);
  if (await store.boundAccount() !== account.uuid) { throw new Error('Account not bound'); }
  const local = await store.journalIntents();
  const before = await readActivity(session);
  const cache = watchedCache;
  const reused = !force && cache && cache.uuid === account.uuid && cache.clientId === session.clientId &&
    cache.generation === session.generation && cache.activity === before;
  const cloud = reused && cache ? cache.ids : await readWatched(session);
  const after = await readActivity(session);
  const verified = await readSyncAccount(session);
  ensureCurrent(session);
  if (before !== after || verified.uuid !== account.uuid || await store.boundAccount() !== account.uuid) {
    invalidateWatchedCache();
    throw new Error('Snapshot or account changed');
  }
  watchedCache = { uuid: account.uuid, clientId: session.clientId, generation: session.generation, activity: after, ids: cloud };
  const rows: SyncDifference[] = [];
  let additions = 0;
  let matches = 0;
  let conflicts = 0;
  let unknown = 0;
  let cloudOnly = cloud.size;
  for (const intent of local) {
    const remote = cloud.has(intent.episodeId);
    if (remote) { cloudOnly--; }
    const kind = classifyIntent(intent, remote);
    if (kind === 'addition') { additions++; }
    else if (kind === 'match') { matches++; }
    else if (kind === 'conflict') { conflicts++; }
    else { unknown++; }
    const receipt = kind === 'conflict' ? await store.undoReceipt(account.uuid, intent.episodeId) : undefined;
    rows.push({ episodeId: intent.episodeId, label: intent.label, localWatched: intent.watched,
      cloudWatched: remote, kind: kind, undoHistoryId: receipt?.historyId ?? 0,
      undoWatchedAt: receipt?.watchedAt ?? '', undoState: receipt?.removalState ?? -1,
      uploadBlocked: kind === 'addition' ? await store.hasUploadAttempt(account.uuid, intent.episodeId) : false });
  }
  return { account: verified, activity: after, localCount: local.length, cloudCount: cloud.size, cloudIds: Array.from(cloud),
    cloudOnly: cloudOnly, additions: additions, matches: matches, conflicts: conflicts, unknown: unknown, rows: rows };
}
