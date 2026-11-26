import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { TraktSession, traktAuth } from './TraktAuth';

interface Ids {
  trakt: number;
}
interface Title {
  title: string;
  year?: number;
  ids: Ids;
}
interface Episode {
  number: number;
  plays?: number;
}
interface Season {
  number: number;
  episodes: Episode[];
}
interface SyncItem {
  movie?: Title;
  show?: Title;
  seasons?: Season[];
}
interface Activity {
  all: string;
}
interface Page {
  items: SyncItem[];
  current: number;
  pages: number;
  total: number;
}
export interface ShowProgress {
  id: string;
  title: string;
  watchedEpisodes: number;
}
export interface CloudLibrary {
  generation: number;
  watchlist: Media[];
  watchedMovies: Media[];
  shows: ShowProgress[];
}

function ensureCurrent(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Trakt session changed or expired');
  }
}

export async function readActivity(session: TraktSession): Promise<string> {
  ensureCurrent(session);
  const req = http.createHttp();
  try {
    const res = await req.request('https://api.trakt.tv/sync/last_activities', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (res.responseCode !== 200 || typeof res.result !== 'string') {
      throw new Error('Trakt activity HTTP ' + res.responseCode);
    }
    const data = JSON.parse(res.result) as Activity;
    if (typeof data.all !== 'string' || !data.all) {
      throw new Error('Missing activity revision');
    }
    return data.all;
  } finally {
    req.destroy();
  }
}

async function readPage(session: TraktSession, path: string, page: number): Promise<Page> {
  ensureCurrent(session);
  const req = http.createHttp();
  try {
    const res = await req.request('https://api.trakt.tv/' + path +
      (path.includes('?') ? '&' : '?') + 'page=' + page + '&limit=250', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (res.responseCode !== 200 || typeof res.result !== 'string') {
      throw new Error('Trakt library HTTP ' + res.responseCode);
    }
    const data = JSON.parse(res.result) as SyncItem[];
    if (!Array.isArray(data)) {
      throw new Error('Unexpected library response');
    }
    // HTTP header names are case insensitive. Only numeric values are consumed.
    const headers = JSON.parse(JSON.stringify(res.header).toLowerCase()) as Record<string, string>;
    const current = Number(headers['x-pagination-page']);
    const pages = Number(headers['x-pagination-page-count']);
    const total = Number(headers['x-pagination-item-count']);
    if (!Number.isInteger(current) || current !== page || !Number.isInteger(pages) ||
        pages < 0 || !Number.isInteger(total) || total < 0 ||
        (pages < page && !(page === 1 && data.length === 0 && pages === 0))) {
      throw new Error('Missing or invalid pagination headers');
    }
    return { items: data, current: current, pages: pages, total: total };
  } finally {
    req.destroy();
  }
}

async function readAll(session: TraktSession, path: string): Promise<SyncItem[]> {
  const first = await readPage(session, path, 1);
  const result: SyncItem[] = [...first.items];
  for (let page = 2; page <= first.pages; page++) {
    const next = await readPage(session, path, page);
    if (next.pages !== first.pages || next.total !== first.total || next.items.length === 0) {
      throw new Error('Library changed while reading; retry');
    }
    for (const item of next.items) {
      result.push(item);
    }
  }
  if (result.length !== first.total) {
    throw new Error('Incomplete library pagination');
  }
  return result;
}

function titleToMedia(item: SyncItem, kind: string, watched: boolean): Media {
  const title = kind === 'movie' ? item.movie : item.show;
  if (!title || !title.ids || !Number.isSafeInteger(title.ids.trakt) ||
      title.ids.trakt <= 0 || typeof title.title !== 'string') {
    throw new Error('Invalid media in library');
  }
  return { id: kind + ':' + title.ids.trakt, title: title.title, kind: kind,
    year: typeof title.year === 'number' ? title.year : 0, watched: watched };
}

function uniqueTitles(rows: SyncItem[], kind: string, watched: boolean): Media[] {
  const result: Media[] = [];
  const seen: Set<string> = new Set<string>();
  for (const row of rows) {
    const item = titleToMedia(row, kind, watched);
    if (seen.has(item.id)) {
      throw new Error('Duplicate library item; retry');
    }
    seen.add(item.id);
    result.push(item);
  }
  return result;
}

function showProgress(rows: SyncItem[]): ShowProgress[] {
  const result: ShowProgress[] = [];
  const seen: Set<string> = new Set<string>();
  for (const row of rows) {
    const show = titleToMedia(row, 'show', false);
    if (seen.has(show.id) || !Array.isArray(row.seasons)) {
      throw new Error('Missing or duplicate show progress');
    }
    seen.add(show.id);
    const episodes: Set<string> = new Set<string>();
    for (const season of row.seasons) {
      if (!Number.isInteger(season.number) || !Array.isArray(season.episodes)) {
        throw new Error('Invalid season progress');
      }
      for (const episode of season.episodes) {
        if (!Number.isInteger(episode.number) || typeof episode.plays !== 'number' || episode.plays < 0) {
          throw new Error('Invalid episode progress');
        }
        if (episode.plays > 0) {
          episodes.add(season.number + ':' + episode.number);
        }
      }
    }
    result.push({ id: show.id, title: show.title, watchedEpisodes: episodes.size });
  }
  return result;
}

export async function readCloudLibrary(session: TraktSession): Promise<CloudLibrary> {
  const before = await readActivity(session);
  const movies = uniqueTitles(await readAll(session, 'sync/watched/movies'), 'movie', true);
  const shows = showProgress(await readAll(session, 'sync/watched/shows?extended=progress'));
  const queuedMovies = uniqueTitles(await readAll(session, 'sync/watchlist/movies'), 'movie', false);
  const queuedShows = uniqueTitles(await readAll(session, 'sync/watchlist/shows'), 'show', false);
  const after = await readActivity(session);
  ensureCurrent(session);
  if (before !== after) {
    throw new Error('Trakt activity changed during import; retry');
  }
  return { generation: session.generation, watchlist: [...queuedMovies, ...queuedShows],
    watchedMovies: movies, shows: shows };
}

// Import only new titles; explicit local decisions always win.
// A watched show is never treated as a completed show.
export function mergeNewTitles(local: Media[], cloud: CloudLibrary): Media[] {
  const result: Media[] = [...local];
  const seen: Set<string> = new Set<string>(local.map((item: Media) => item.id));
  for (const item of [...cloud.watchedMovies, ...cloud.watchlist]) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      result.push(item);
    }
  }
  return result;
}
