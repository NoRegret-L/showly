import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { CollectionDate } from '../model/CollectionRules';
import { TraktSession, traktAuth } from './TraktAuth';
import { RemotePlayPosition, RemoteMovieObservation, RemoteLibraryObservation, RemoteShowObservation, validateObservation } from '../model/RemoteObservation';

interface Ids {
  trakt: number;
}
interface Title {
  title: string;
  year?: number;
  released?: string;
  runtime?: number;
  rating?: number;
  ids: Ids;
}
interface Episode {
  number: number;
  plays?: number;
  last_watched_at?: string;
}
interface Season {
  number: number;
  episodes: Episode[];
}
interface SyncItem {
  listed_at?: string;
  rating?: number;
  plays?: number;
  last_watched_at?: string;
  last_updated_at?: string;
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
export type ShowProgress = RemoteShowObservation;
export type CloudLibrary = RemoteLibraryObservation;

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
    const positions: RemotePlayPosition[] = [];
    for (const season of row.seasons) {
      if (!Number.isInteger(season.number) || !Array.isArray(season.episodes)) {
        throw new Error('Invalid season progress');
      }
      for (const episode of season.episodes) {
        if (!Number.isInteger(episode.number) || typeof episode.plays !== 'number' || episode.plays < 0) {
          throw new Error('Invalid episode progress');
        }
        if (episode.plays > 0) {
          const key = season.number + ':' + episode.number;
          if (episodes.has(key)) { throw new Error('Duplicate observed episode'); }
          episodes.add(key);
          positions.push({ season: season.number, number: episode.number, plays: episode.plays,
            lastWatchedAt: episode.last_watched_at ?? '' });
        }
      }
    }
    result.push({ id: show.id, title: show.title, year: show.year, watchedEpisodes: episodes.size,
      positions: positions, updatedAt: row.last_updated_at ?? '' });
  }
  return result;
}

export interface CollectionRating { id: string; value: number; }
export async function readCollectionRatings(session: TraktSession, kind: string, activity: string): Promise<CollectionRating[]> {
  if (kind !== 'show' && kind !== 'movie') { throw new Error('Invalid rating kind'); }
  if (await readActivity(session) !== activity) { throw new Error('Activity changed'); }
  const rows = await readAll(session, 'sync/ratings/' + (kind === 'show' ? 'shows' : 'movies'));
  const ratings: CollectionRating[] = [];
  const seen = new Set<string>();
  for (const row of rows) {
    const item = titleToMedia(row,kind,false);
    if (seen.has(item.id) || typeof row.rating !== 'number' || !Number.isInteger(row.rating) || row.rating < 1 || row.rating > 10) {
      throw new Error('Invalid personal rating');
    }
    seen.add(item.id);
    ratings.push({ id: item.id, value: row.rating });
  }
  if (await readActivity(session) !== activity) { throw new Error('Activity changed'); }
  ensureCurrent(session);
  return ratings;
}
export async function readCloudLibrary(session: TraktSession): Promise<CloudLibrary> {
  const before = await readActivity(session);
  const movieRows = await readAll(session, 'sync/watched/movies');
  const movies = uniqueTitles(movieRows, 'movie', true);
  const moviePlays = movieRows.map((row: SyncItem): RemoteMovieObservation => {
    return { id: titleToMedia(row, 'movie', true).id, plays: row.plays ?? 0,
      lastWatchedAt: row.last_watched_at ?? '' };
  });
  const shows = showProgress(await readAll(session, 'sync/watched/shows?extended=progress'));
  const queueMovieRows = await readAll(session, 'sync/watchlist/movies');
  const queueShowRows = await readAll(session, 'sync/watchlist/shows');
  const queuedMovies = uniqueTitles(queueMovieRows, 'movie', false);
  const queuedShows = uniqueTitles(queueShowRows, 'show', false);
  const queueDates: CollectionDate[] = [];
  for (const row of [...queueMovieRows, ...queueShowRows]) {
    const at = Date.parse(row.listed_at ?? '');
    if (Number.isSafeInteger(at) && at > 0) {
      queueDates.push({ id: titleToMedia(row, row.movie ? 'movie' : 'show', false).id, at: at });
    }
  }
  const after = await readActivity(session);
  ensureCurrent(session);
  if (before !== after) {
    throw new Error('Trakt activity changed during import; retry');
  }
  const snapshot: CloudLibrary = { generation: session.generation, activity: after, observedAt: Date.now(),
    watchlist: [...queuedMovies, ...queuedShows], watchedMovies: movies, shows: shows, moviePlays: moviePlays, queueDates: queueDates };
  validateObservation(snapshot);
  return snapshot;
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

export interface CloudMediaSnapshot {
  generation: number;
  activity: string;
  watchedMovies: Media[];
  watchlist: Media[];
}

// No show history fetch: the title-level preview needs just three collections.
export async function readCloudMedia(session: TraktSession): Promise<CloudMediaSnapshot> {
  const before = await readActivity(session);
  const watched = await readAll(session, 'sync/watched/movies');
  if (watched.some((row: SyncItem) => typeof row.plays !== 'number' ||
    !Number.isSafeInteger(row.plays) || row.plays <= 0)) { throw new Error('Invalid movie plays'); }
  const movies = uniqueTitles(watched, 'movie', true);
  const queueMovies = uniqueTitles(await readAll(session, 'sync/watchlist/movies'), 'movie', false);
  const queueShows = uniqueTitles(await readAll(session, 'sync/watchlist/shows'), 'show', false);
  const after = await readActivity(session);
  ensureCurrent(session);
  if (before !== after) { throw new Error('Cloud changed during media preview'); }
  return { generation: session.generation, activity: after, watchedMovies: movies,
    watchlist: [...queueMovies, ...queueShows] };
}

// Read exactly the affected watchlist domain, not movie history or other titles.
export async function readWatchlistKind(session: TraktSession, kind: string): Promise<Media[]> {
  if (kind !== 'movie' && kind !== 'show') { throw new Error('Invalid watchlist kind'); }
  return uniqueTitles(await readAll(session, 'sync/watchlist/' + (kind === 'movie' ? 'movies' : 'shows')), kind, false);
}

export interface PersonalMovie {
  media: Media;
  released: string;
  cloudWatched: boolean;
  cloudWatchlist: boolean;
  localOnly: boolean;
  runtime?: number;
  rating?: number;
  addedAt?: number;
  userRating?: number;
  dateUncertain?: boolean;
}
export interface PersonalMovieSnapshot {
  generation: number;
  activity: string;
  movies: PersonalMovie[];
  ratingsComplete?: boolean;
}

// Release dates are calendar dates, not UTC instants. Reject rollover dates.
export function validReleaseDate(value?: string): string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) { return ''; }
  const ms = Date.parse(value + 'T00:00:00Z');
  return Number.isFinite(ms) && new Date(ms).toISOString().substring(0, 10) === value ? value : '';
}

function appendPersonalMovies(target: Map<string, PersonalMovie>, rows: SyncItem[], watched: boolean): void {
  const seen: Set<string> = new Set<string>();
  for (const row of rows) {
    const media = titleToMedia(row, 'movie', watched);
    if (seen.has(media.id)) { throw new Error('Duplicate library item; retry'); }
    seen.add(media.id);
    const prior = target.get(media.id);
    const date = validReleaseDate(row.movie?.released);
    // Conflicting nonempty dates are not silently arbitrated.
    const released = prior && prior.released && date && prior.released !== date ? '' : (date || prior?.released || '');
    const uncertain = !!prior?.dateUncertain || (!!row.movie?.released && !date) ||
      (!!prior?.released && !!date && prior.released !== date);
    const runtime = row.movie?.runtime;
    const rating = row.movie?.rating;
    const added = !watched && typeof row.listed_at === 'string' ? Date.parse(row.listed_at) : NaN;
    const item: PersonalMovie = { media: prior?.media ?? media, released: released,
      cloudWatched: watched || (prior?.cloudWatched ?? false),
      cloudWatchlist: !watched || (prior?.cloudWatchlist ?? false), localOnly: false,
      runtime: typeof runtime === 'number' && Number.isFinite(runtime) && runtime >= 0 ? runtime : prior?.runtime,
      rating: typeof rating === 'number' && Number.isFinite(rating) && rating >= 0 && rating <= 10 ? rating : prior?.rating,
      addedAt: Number.isFinite(added) ? added : prior?.addedAt, dateUncertain: uncertain };
    target.set(media.id, item);
  }
}

export async function readPersonalMovies(session: TraktSession): Promise<PersonalMovieSnapshot> {
  const before = await readActivity(session);
  const watched = await readAll(session, 'sync/watched/movies?extended=full');
  const watchlist = await readAll(session, 'sync/watchlist/movies?extended=full');
  const movies: Map<string, PersonalMovie> = new Map<string, PersonalMovie>();
  appendPersonalMovies(movies, watched, true);
  appendPersonalMovies(movies, watchlist, false);
  const after = await readActivity(session);
  ensureCurrent(session);
  if (before !== after) { throw new Error('Library changed while reading; retry'); }
  // Preserve the already verified movie snapshot if optional ratings fail.
  // No follow-up request after a failed read; never fabricate a rating.
  let ratingsComplete = false;
  try {
    const ratings = await readAll(session, 'sync/ratings/movies');
    const values = new Map<string, number>();
    for (const row of ratings) {
      const media = titleToMedia(row, 'movie', false);
      if (typeof row.rating !== 'number' || !Number.isInteger(row.rating) ||
          row.rating < 1 || row.rating > 10 || values.has(media.id)) { throw new Error('Invalid movie rating'); }
      values.set(media.id, row.rating);
    }
    if (await readActivity(session) === after) {
      for (const movie of movies.values()) { movie.userRating = values.get(movie.media.id); }
      ratingsComplete = true;
    }
  } catch (error) { ensureCurrent(session); }
  ensureCurrent(session);
  return { generation: session.generation, activity: after, movies: Array.from(movies.values()), ratingsComplete: ratingsComplete };
}

// A single explicit lookup for metadata omitted by an embedded list object.
export async function readPersonalMovieDate(session: TraktSession, media: Media): Promise<string> {
  if (media.kind !== 'movie' || !/^movie:[1-9][0-9]*$/.test(media.id) ||
      !Number.isSafeInteger(Number(media.id.substring(6)))) { throw new Error('Invalid movie identity'); }
  ensureCurrent(session);
  const req = http.createHttp();
  try {
    const res = await req.request('https://api.trakt.tv/movies/' + media.id.substring(6) + '?extended=full', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (res.responseCode !== 200 || typeof res.result !== 'string') {
      throw new Error('Trakt summary HTTP ' + res.responseCode);
    }
    const title = JSON.parse(res.result) as Title;
    if (!title.ids || title.ids.trakt !== Number(media.id.substring(6))) { throw new Error('Invalid movie identity'); }
    return validReleaseDate(title.released);
  } finally { req.destroy(); }
}
