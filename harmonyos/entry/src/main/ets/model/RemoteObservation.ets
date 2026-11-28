import { Media, CollectionDate, PersonalMovie, validReleaseDate } from './Media';
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
// Optional cache-only activity evidence. Missing or invalid domain stamps
// always require a complete observation; they never grant write permission.
export interface ObservationVersions { all: string; movies: string; shows: string; watchedShows?: string; queuedShows?: string; watchedMovies?: string; queuedMovies?: string; }
export function observationReadMask(old: ObservationVersions | undefined, next: ObservationVersions): number {
  if (!old || !old.all || !next.all || !old.movies || !old.shows || !next.movies || !next.shows) { return 3; }
  if (old.all === next.all) { return old.movies === next.movies && old.shows === next.shows ? 0 : 3; }
  const mask = (old.movies !== next.movies ? 1 : 0) | (old.shows !== next.shows ? 2 : 0);
  return mask || 3; // unclassified global activity: conservative full read
}
// Four endpoint bits: watched movies=1, watched shows=2, queued movies=4,
// queued shows=8. Movie metadata has joint provenance; keep its two reads
// together until a separate raw source cache is validated.
export function observationCollectionMask(old: ObservationVersions | undefined, next: ObservationVersions, movieSources: boolean = false): number {
  const group = observationReadMask(old,next);
  if (group === 0) { return 0; }
  if (!old || group === 3) { return 15; }
  if (group === 1) {
    if (!movieSources || !old.watchedMovies || !old.queuedMovies || !next.watchedMovies || !next.queuedMovies) { return 5; }
    const changed = (old.watchedMovies !== next.watchedMovies ? 1 : 0) | (old.queuedMovies !== next.queuedMovies ? 4 : 0);
    return changed || 5;
  }
  if (!old.watchedShows || !old.queuedShows || !next.watchedShows || !next.queuedShows) { return 10; }
  const changed = (old.watchedShows !== next.watchedShows ? 2 : 0) | (old.queuedShows !== next.queuedShows ? 8 : 0);
  return changed || 10;
}
export interface RemoteLibraryObservation {
  generation: number;
  activity: string;
  observedAt: number;
  versions?: ObservationVersions;
  verifiedAt?: number;
  watchlist: Media[];
  watchedMovies: Media[];
  shows: RemoteShowObservation[];
  moviePlays: RemoteMovieObservation[];
  queueDates?: CollectionDate[];
  // Display metadata only. Never used to establish membership or authorize writes.
  movieDetails?: PersonalMovie[];
  movieWatchedDetails?: PersonalMovie[];
  movieQueuedDetails?: PersonalMovie[];
}
// Normalize each endpoint separately before merging. This reproduces the
// watched-first, watchlist-second metadata priority without keeping raw HTTP.
export function mergeMovieSources(watched: PersonalMovie[], queued: PersonalMovie[]): PersonalMovie[] {
  const merged = new Map<string,PersonalMovie>();
  for (const item of watched) { merged.set(item.media.id,item); }
  for (const item of queued) {
    const old = merged.get(item.media.id);
    if (!old) { merged.set(item.media.id,item); continue; }
    const conflict = !!old.released && !!item.released && old.released !== item.released;
    const value: PersonalMovie = {media:old.media,released:conflict ? '' : (item.released || old.released),
      cloudWatched:true,cloudWatchlist:true,localOnly:false,runtime:item.runtime ?? old.runtime,
      rating:item.rating ?? old.rating,addedAt:item.addedAt ?? old.addedAt,
      dateUncertain:!!old.dateUncertain || !!item.dateUncertain || conflict};
    merged.set(item.media.id,value);
  }
  return Array.from(merged.values());
}
export function movieSourcesValid(snapshot: RemoteLibraryObservation): boolean {
  const watched = snapshot.movieWatchedDetails;
  const queued = snapshot.movieQueuedDetails;
  if (!Array.isArray(watched) || !Array.isArray(queued) || !snapshot.movieDetails) { return false; }
  const watchedIds = new Set<string>(snapshot.watchedMovies.map((item: Media)=>item.id));
  const queueIds = new Set<string>(snapshot.watchlist.filter((item: Media)=>item.kind==='movie').map((item: Media)=>item.id));
  if (watched.length !== watchedIds.size || queued.length !== queueIds.size) { return false; }
  for (const item of watched) {
    if (!item || !item.media || !watchedIds.delete(item.media.id) || !item.cloudWatched || item.cloudWatchlist || item.localOnly) { return false; }
  }
  for (const item of queued) {
    if (!item || !item.media || !queueIds.delete(item.media.id) || item.cloudWatched || !item.cloudWatchlist || item.localOnly) { return false; }
  }
  return JSON.stringify(mergeMovieSources(watched,queued)) === JSON.stringify(snapshot.movieDetails);
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
  if (snapshot.versions !== undefined && (snapshot.versions.all !== snapshot.activity ||
      typeof snapshot.versions.movies !== 'string' || typeof snapshot.versions.shows !== 'string')) { throw new Error('Invalid observation versions'); }
  if (snapshot.verifiedAt !== undefined && (!Number.isSafeInteger(snapshot.verifiedAt) || snapshot.verifiedAt <= 0)) { throw new Error('Invalid observation verification time'); }
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
  if (snapshot.movieDetails !== undefined) {
    if (!Array.isArray(snapshot.movieDetails)) { throw new Error('Invalid movie details'); }
    const ids = new Set<string>();
    const members = new Set<string>(movies);
    for (const item of snapshot.watchlist) { if (item.kind === 'movie') { members.add(item.id); } }
    for (const row of snapshot.movieDetails) {
      if (!row || !validMedia(row.media,'movie') || ids.has(row.media.id) || !members.has(row.media.id) ||
          row.cloudWatched !== movies.has(row.media.id) || row.cloudWatchlist !== queued.has(row.media.id) ||
          row.localOnly !== false || typeof row.released !== 'string' ||
          (row.released !== '' && validReleaseDate(row.released) !== row.released) ||
          typeof row.dateUncertain !== 'boolean' || row.userRating !== undefined ||
          (row.runtime !== undefined && (!Number.isFinite(row.runtime) || row.runtime < 0)) ||
          (row.rating !== undefined && (!Number.isFinite(row.rating) || row.rating < 0 || row.rating > 10)) ||
          (row.addedAt !== undefined && (!Number.isFinite(row.addedAt) || row.addedAt <= 0))) {
        throw new Error('Invalid movie details entry');
      }
      ids.add(row.media.id);
    }
    if (ids.size !== members.size) { throw new Error('Incomplete movie details'); }
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
