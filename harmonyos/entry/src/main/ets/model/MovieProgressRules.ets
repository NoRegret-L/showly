import { PersonalLibraryRow } from './PersonalLibrary';
import { ProgressFlag } from './ProgressRules';
import { matchesText } from './MediaPresentation';
import { isTraktMedia } from './MediaState';

export interface MovieProgressOptions { sort: string; descending: boolean; }
export interface MovieProgressMetadata {
  id: string;
  released: string;
  year: number;
  runtime?: number;
  rating?: number;
  addedAt?: number;
  userRating?: number;
}
export interface MovieProgressSource {
  row: PersonalLibraryRow;
  metadata: MovieProgressMetadata;
  translation: string;
}
export function defaultMovieProgress(): MovieProgressOptions {
  return { sort: 'added', descending: true };
}
export function validMovieProgress(value: MovieProgressOptions): boolean {
  return !!value && ['added','title','runtime','rating','userRating','newest','random'].includes(value.sort) &&
    typeof value.descending === 'boolean';
}
export function eligibleMovie(source: MovieProgressSource, utcDay: string): boolean {
  const row = source.row;
  const meta = source.metadata;
  if (row.media.kind !== 'movie' || !isTraktMedia(row.media) || meta.id !== row.media.id ||
      !row.queued || row.watched) { return false; }
  return meta.released ? meta.released <= utcDay : meta.year > 0;
}
function title(source: MovieProgressSource): string {
  const original = source.row.media.title;
  return (source.translation || (original.startsWith('The') ? original.substring(3).trim() : original)).toUpperCase();
}
function cmp(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }
function numberOrder(a: number | undefined, b: number | undefined, descending: boolean): number {
  if (a === undefined) { return b === undefined ? 0 : 1; }
  if (b === undefined) { return -1; }
  return descending ? b - a : a - b;
}
function randomKey(id: string, seed: number): number {
  let hash = seed | 0;
  for (let i = 0; i < id.length; i++) { hash = Math.imul(hash ^ id.charCodeAt(i), 16777619); }
  hash ^= hash >>> 16;
  hash = Math.imul(hash, 0x45d9f3b);
  return (hash ^ (hash >>> 16)) >>> 0;
}
export function movieProgressRows(sources: MovieProgressSource[], flags: ProgressFlag[],
  options: MovieProgressOptions, utcDay: string, query: string, seed: number): PersonalLibraryRow[] {
  const pins = new Set<string>(flags.filter((flag: ProgressFlag) => flag.pinned).map((flag: ProgressFlag) => flag.id));
  const filtered = sources.filter((source: MovieProgressSource) => eligibleMovie(source, utcDay) &&
    matchesText(query, source.row.media.title, source.translation));
  const direction = options.descending ? -1 : 1;
  filtered.sort((a: MovieProgressSource, b: MovieProgressSource): number => {
    const pinned = Number(pins.has(b.row.media.id)) - Number(pins.has(a.row.media.id));
    if (pinned) { return pinned; }
    const am = a.metadata; const bm = b.metadata;
    if (options.sort === 'title') { return direction * cmp(title(a), title(b)); }
    if (options.sort === 'runtime') { return numberOrder(am.runtime, bm.runtime, options.descending); }
    if (options.sort === 'rating') { return numberOrder(am.rating, bm.rating, options.descending); }
    if (options.sort === 'userRating') {
      return numberOrder(am.userRating, bm.userRating, options.descending) || cmp(title(a), title(b));
    }
    if (options.sort === 'newest') {
      return direction * (cmp(am.released, bm.released) || (am.year - bm.year));
    }
    if (options.sort === 'random') { return randomKey(a.row.media.id, seed) - randomKey(b.row.media.id, seed); }
    return numberOrder(am.addedAt, bm.addedAt, options.descending);
  });
  return filtered.map((source: MovieProgressSource) => source.row);
}
export function clearMoviePin(flags: ProgressFlag[], id: string): ProgressFlag[] {
  return flags.filter((flag: ProgressFlag) => flag.id !== id);
}
