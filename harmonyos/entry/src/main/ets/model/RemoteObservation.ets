import { Media } from './Media';
import { CollectionDate } from './CollectionRules';
import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes, showSections } from './ShowCatalog';

export interface RemotePlayPosition {
  season: number;
  number: number;
  plays: number;
  lastWatchedAt: string;
}
export interface RemoteShowObservation {
  id: string;
  title: string;
  year?: number;
  watchedEpisodes: number;
  positions: RemotePlayPosition[];
  updatedAt: string;
}
export interface RemoteMovieObservation {
  id: string;
  plays: number;
  lastWatchedAt: string;
}
export interface RemoteLibraryObservation {
  generation: number;
  activity: string;
  observedAt: number;
  watchlist: Media[];
  watchedMovies: Media[];
  shows: RemoteShowObservation[];
  moviePlays: RemoteMovieObservation[];
  queueDates?: CollectionDate[];
}
export interface EpisodeDecision {
  episodeId: number;
  watched: boolean;
}
function validMedia(item: Media, kind: string): boolean {
  return !!item && item.kind === kind && item.id.startsWith(kind + ':') &&
    /^(movie|show):[1-9][0-9]*$/.test(item.id) &&
    Number.isSafeInteger(Number(item.id.substring(kind.length + 1))) &&
    typeof item.title === 'string' && Number.isFinite(item.year) && typeof item.watched === 'boolean';
}
function dateOrUnknown(s: string): boolean {
  return typeof s === 'string' && (!s || Number.isFinite(Date.parse(s)));
}
export function validateObservation(snapshot: RemoteLibraryObservation): void {
  if (!snapshot || !snapshot.activity || typeof snapshot.activity !== 'string' ||
      !Number.isSafeInteger(snapshot.observedAt) || snapshot.observedAt <= 0 ||
      !Array.isArray(snapshot.watchlist) || !Array.isArray(snapshot.watchedMovies) ||
      !Array.isArray(snapshot.shows) || !Array.isArray(snapshot.moviePlays)) {
    throw new Error('Invalid cloud observation');
  }
  const queued: Set<string> = new Set<string>();
  const movies: Set<string> = new Set<string>();
  const shows: Set<string> = new Set<string>();
  for (const item of snapshot.watchlist) {
    if (!item || (item.kind !== 'movie' && item.kind !== 'show') || !validMedia(item, item.kind) || queued.has(item.id)) {
      throw new Error('Invalid observed watchlist');
    }
    queued.add(item.id);
  }
  if (snapshot.queueDates !== undefined) {
    if (!Array.isArray(snapshot.queueDates)) { throw new Error('Invalid watchlist dates'); }
    const dates = new Set<string>();
    for (const row of snapshot.queueDates) {
      if (!row || !queued.has(row.id) || dates.has(row.id) || !Number.isSafeInteger(row.at) || row.at <= 0) { throw new Error('Invalid watchlist date'); }
      dates.add(row.id);
    }
  }
  for (const item of snapshot.watchedMovies) {
    if (!validMedia(item, 'movie') || movies.has(item.id)) { throw new Error('Invalid observed movie'); }
    movies.add(item.id);
  }
  const plays: Set<string> = new Set<string>();
  for (const item of snapshot.moviePlays) {
    if (!item || !movies.has(item.id) || plays.has(item.id) || !Number.isSafeInteger(item.plays) ||
        item.plays <= 0 || !dateOrUnknown(item.lastWatchedAt)) { throw new Error('Invalid movie plays'); }
    plays.add(item.id);
  }
  if (plays.size !== movies.size) { throw new Error('Missing movie plays'); }
  for (const show of snapshot.shows) {
    if (!show || !/^show:[1-9][0-9]*$/.test(show.id) || !Number.isSafeInteger(Number(show.id.substring(5))) ||
        shows.has(show.id) || typeof show.title !== 'string' ||
        (show.year !== undefined && !Number.isFinite(show.year)) || !dateOrUnknown(show.updatedAt) ||
        !Array.isArray(show.positions) || show.watchedEpisodes !== show.positions.length) {
      throw new Error('Invalid observed show');
    }
    shows.add(show.id);
    const positions: Set<string> = new Set<string>();
    for (const pos of show.positions) {
      const key = pos.season + ':' + pos.number;
      if (!Number.isSafeInteger(pos.season) || pos.season < 0 ||
          !Number.isSafeInteger(pos.number) || pos.number <= 0 || !Number.isSafeInteger(pos.plays) ||
          pos.plays <= 0 || !dateOrUnknown(pos.lastWatchedAt) || positions.has(key)) {
        throw new Error('Invalid observed episode');
      }
      positions.add(key);
    }
  }
}
// Read-only projection: cloud season/number -> exact catalog IDs, then local
// explicit decisions by ID. No event, common baseline or receipt is created.
// Missing ordinary positions mean incomplete metadata; never guess completion.
export function observedSections(full: FullEpisodeCatalog, remote: RemoteShowObservation | undefined,
  localIds: number[], decisions: EpisodeDecision[], now: number): string[] {
  const episodes = scheduleEpisodes(full);
  const ids: Set<number> = new Set<number>(episodes.map((episode: ScheduledEpisode) => episode.id));
  const positions: Map<string, number> = new Map<string, number>();
  for (const episode of episodes) { positions.set(episode.season + ':' + episode.number, episode.id); }
  const watched: Set<number> = new Set<number>();
  if (remote) {
    for (const position of remote.positions) {
      if (position.season === 0) { continue; }
      const id = positions.get(position.season + ':' + position.number);
      if (id === undefined) { return []; }
      watched.add(id);
    }
  } else {
    for (const id of localIds) { if (ids.has(id)) { watched.add(id); } }
  }
  for (const decision of decisions) {
    if (!ids.has(decision.episodeId)) { continue; }
    if (decision.watched) { watched.add(decision.episodeId); }
    else { watched.delete(decision.episodeId); }
  }
  return showSections(full, Array.from(watched), now);
}
