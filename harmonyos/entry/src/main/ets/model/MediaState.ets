import { Media } from './Media';

export interface MediaRecord {
  media: Media;
  movieState: string;
  watchlistState: string;
  restoredWatchlist?: boolean;
}
export interface MediaSnapshot {
  schema: number;
  records: MediaRecord[];
}

export function isTraktMedia(item: Media): boolean {
  if (item.kind !== 'movie' && item.kind !== 'show') { return false; }
  if (!/^(movie|show):[1-9][0-9]*$/.test(item.id) || !item.id.startsWith(item.kind + ':')) { return false; }
  return Number.isSafeInteger(Number(item.id.substring(item.kind.length + 1)));
}

export function isState(value: string): boolean {
  return value === 'unknown' || value === 'yes' || value === 'no';
}

export function migrateLegacy(items: Media[]): MediaRecord[] {
  return items.map((item: Media): MediaRecord => {
    // Legacy false can be a watchlist, local title, or unwatch; true can
    // be an imported observation. Neither is a reliable explicit intent.
    return { media: item, movieState: 'unknown', watchlistState: 'unknown' };
  });
}

export function validateMediaRecords(records: MediaRecord[]): void {
  if (!Array.isArray(records)) { throw new Error('Invalid records'); }
  const seen: Set<string> = new Set<string>();
  for (const record of records) {
    const item = record.media;
    if (!item || typeof item.id !== 'string' || typeof item.title !== 'string' ||
        typeof item.kind !== 'string' || typeof item.year !== 'number' ||
        !Number.isFinite(item.year) || typeof item.watched !== 'boolean' || seen.has(item.id) ||
        !isState(record.movieState) || !isState(record.watchlistState) ||
        (record.restoredWatchlist !== undefined && typeof record.restoredWatchlist !== 'boolean') ||
        ((!isTraktMedia(item) || item.kind !== 'movie') && record.movieState !== 'unknown') ||
        (!isTraktMedia(item) && record.watchlistState !== 'unknown') ||
        (record.movieState !== 'unknown' && item.watched !== (record.movieState === 'yes'))) {
      throw new Error('Invalid media record');
    }
    seen.add(item.id);
  }
}

// The old collection projection is retained. Only a direct user action
// creates an explicit intent; cloud imports never do.
export function applyLegacyEdit(records: MediaRecord[], items: Media[], origin: string): MediaRecord[] {
  if (origin !== 'add' && origin !== 'import' && origin !== 'toggle') { throw new Error('Invalid origin'); }
  const old: Map<string, MediaRecord> = new Map<string, MediaRecord>();
  for (const record of records) { old.set(record.media.id, record); }
  const next: MediaRecord[] = [];
  for (const item of items) {
    const prior = old.get(item.id);
    if (!prior) {
      if (origin === 'toggle') { throw new Error('Unexpected new title'); }
      next.push({ media: item, movieState: 'unknown',
        watchlistState: origin === 'add' && isTraktMedia(item) ? 'yes' : 'unknown' });
    } else {
      let movieState = prior.movieState;
      if (prior.media.watched !== item.watched) {
        if (origin !== 'toggle') { throw new Error('Unexpected state overwrite'); }
        if (isTraktMedia(item) && item.kind === 'movie') { movieState = item.watched ? 'yes' : 'no'; }
      }
      next.push({ media: item, movieState: movieState, watchlistState: prior.watchlistState,
        restoredWatchlist: prior.restoredWatchlist });
      old.delete(item.id);
    }
  }
  if (old.size !== 0) { throw new Error('Unexpected title removal'); }
  validateMediaRecords(next);
  return next;
}

export function setMediaIntent(records: MediaRecord[], item: Media, domain: string, value: string): MediaRecord[] {
  if (!isTraktMedia(item) || (value !== 'yes' && value !== 'no') ||
      (domain !== 'watchlist' && (domain !== 'movie' || item.kind !== 'movie'))) {
    throw new Error('Invalid explicit intent');
  }
  const prior = records.find((record: MediaRecord) => record.media.id === item.id);
  const original = prior?.media ?? item;
  const media: Media = { id: original.id, kind: original.kind, title: original.title,
    year: original.year, watched: domain === 'movie' ? value === 'yes' : original.watched };
  const updated: MediaRecord = { media: media,
    movieState: domain === 'movie' ? value : prior?.movieState ?? 'unknown',
    watchlistState: domain === 'watchlist' ? value : prior?.watchlistState ?? 'unknown',
    restoredWatchlist: prior?.restoredWatchlist };
  const next = prior ? records.map((record: MediaRecord) => record.media.id === item.id ? updated : record) :
    [...records, updated];
  validateMediaRecords(next);
  return next;
}

export function inLocalWatchlist(record: MediaRecord): boolean {
  return record.watchlistState === 'unknown' ? (record.restoredWatchlist ?? !record.media.watched) : record.watchlistState === 'yes';
}
