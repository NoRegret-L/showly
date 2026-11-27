import { Media, CollectionDate } from './Media';
import { isTraktMedia } from './MediaState';
import { PersonalLibraryRow, hasTrackingEvidence } from './PersonalLibrary';
import { collectionRows } from './NavigationModel';
import { CollectionMeta, matchesText } from './MediaPresentation';

export interface CollectionOptions { sort: string; descending: boolean; genres: string[]; networks: string[]; upcoming: string; }
export interface HiddenEntry { media: Media; at: number; }
export interface CollectionState { hidden: HiddenEntry[]; mine: CollectionDate[]; queue: CollectionDate[]; }
export interface CollectionCandidate { row: PersonalLibraryRow; translation: string; meta?: CollectionMeta; added?: number; recent?: number; userRating?: number; randomOrder: number; }

export function defaultCollection(): CollectionOptions { return { sort: 'added', descending: true, genres: [], networks: [], upcoming: 'all' }; }
export function validCollection(value: CollectionOptions): boolean {
  return !!value && ['title','added','rating','userRating','recent','runtime','newest','random'].includes(value.sort) &&
    typeof value.descending === 'boolean' && Array.isArray(value.genres) && value.genres.every((x: string) => typeof x === 'string') &&
    Array.isArray(value.networks) && value.networks.every((x: string) => typeof x === 'string') &&
    ['all','upcoming','released'].includes(value.upcoming);
}
export function emptyCollectionState(): CollectionState { return { hidden: [], mine: [], queue: [] }; }
function validDate(at: number): boolean { return Number.isSafeInteger(at) && at > 0; }
function validDates(rows: CollectionDate[]): boolean {
  if (!Array.isArray(rows)) { return false; }
  const seen = new Set<string>();
  for (const row of rows) {
    if (!row || !/^(show|movie):[1-9][0-9]*$/.test(row.id) || seen.has(row.id) || !validDate(row.at)) { return false; }
    seen.add(row.id);
  }
  return true;
}
export function validCollectionState(value: CollectionState): boolean {
  if (!value || !Array.isArray(value.hidden) || !validDates(value.mine) || !validDates(value.queue)) { return false; }
  const seen = new Set<string>();
  for (const row of value.hidden) {
    if (!row || !row.media || !isTraktMedia(row.media) || typeof row.media.title !== 'string' ||
        !Number.isFinite(row.media.year) || typeof row.media.watched !== 'boolean' || !validDate(row.at) || seen.has(row.media.id)) { return false; }
    seen.add(row.media.id);
  }
  return true;
}
export function hideMedia(state: CollectionState, media: Media, hidden: boolean, now: number): CollectionState {
  if (!isTraktMedia(media) || !validDate(now)) { return state; }
  const existing = state.hidden.some((x: HiddenEntry) => x.media.id === media.id);
  if (existing === hidden) { return state; }
  return { hidden: hidden ? [...state.hidden, { media: media, at: now }] :
    state.hidden.filter((x: HiddenEntry) => x.media.id !== media.id), mine: state.mine, queue: state.queue };
}
export function recordCollectionDate(state: CollectionState, id: string, section: string, present: boolean, now: number): CollectionState {
  if (!/^(show|movie):[1-9][0-9]*$/.test(id) || !validDate(now) || (section !== 'mine' && section !== 'queue')) { return state; }
  const old = section === 'mine' ? state.mine : state.queue;
  const next = old.filter((x: CollectionDate) => x.id !== id);
  if (present) { next.push({ id: id, at: now }); }
  return { hidden: state.hidden, mine: section === 'mine' ? next : state.mine, queue: section === 'queue' ? next : state.queue };
}
// Record only an explicit confirmed transition, never a migration or refresh.
export function transitionCollectionDates(state: CollectionState, before: PersonalLibraryRow[],
  after: PersonalLibraryRow[], ids: string[], now: number): CollectionState {
  let nextState = state;
  for (const id of new Set<string>(ids)) {
    const prior = before.find((row: PersonalLibraryRow) => row.media.id === id);
    const next = after.find((row: PersonalLibraryRow) => row.media.id === id);
    const wasMine = !!prior && (prior.watched || hasTrackingEvidence(prior));
    const isMine = !!next && (next.watched || hasTrackingEvidence(next));
    if (wasMine !== isMine) { nextState = recordCollectionDate(nextState,id,'mine',isMine,now); }
    if (!!prior?.queued !== !!next?.queued) { nextState = recordCollectionDate(nextState,id,'queue',!!next?.queued,now); }
  }
  return nextState;
}
export function collectionMembers(rows: PersonalLibraryRow[], state: CollectionState, kind: string, section: string, status: string): PersonalLibraryRow[] {
  const hidden = new Set<string>(state.hidden.map((x: HiddenEntry) => x.media.id));
  if (section === 'hidden') {
    return state.hidden.filter((x: HiddenEntry) => x.media.kind === kind).map((x: HiddenEntry): PersonalLibraryRow => {
      return rows.find((row: PersonalLibraryRow) => row.media.id === x.media.id) ??
        { media: x.media, queued: false, watched: false, localEpisodes: -1, cloudEpisodes: -1 };
    });
  }
  return collectionRows(rows, kind, section, status).filter((row: PersonalLibraryRow) => !hidden.has(row.media.id));
}
function title(x: CollectionCandidate): string {
  const original = x.row.media.title;
  return (x.translation || (original.startsWith('The') ? original.substring(3).trim() : original)).toUpperCase();
}
function cmp(a: string,b: string): number { return a < b ? -1 : a > b ? 1 : 0; }
function numeric(a: number | undefined,b: number | undefined,desc: boolean): number {
  if (a === undefined) { return b === undefined ? 0 : 1; }
  if (b === undefined) { return -1; }
  return desc ? b-a : a-b;
}
export function collectionReleased(x: CollectionCandidate, mode: string, now: number): boolean {
  if (mode === 'all') { return true; }
  if (!x.meta) { return false; }
  const date = Date.parse(x.meta.release);
  if (x.row.media.kind === 'show') { return Number.isFinite(date) && (mode === 'upcoming' ? date > now : date < now); }
  const day = new Date(now).toISOString().substring(0,10);
  const year = Number(day.substring(0,4));
  if (Number.isFinite(date)) { return mode === 'upcoming' ? x.meta.release.substring(0,10) > day : x.meta.release.substring(0,10) < day; }
  if (x.meta.release) { return false; }
  return mode === 'upcoming' ? x.row.media.year > year : x.row.media.year > 0 && x.row.media.year < year;
}
export function projectCollection(items: CollectionCandidate[], options: CollectionOptions, section: string, query: string, now: number): CollectionCandidate[] {
  const result = items.filter((x: CollectionCandidate) => matchesText(query,x.row.media.title,x.translation) &&
    (!options.genres.length || !!x.meta?.genres.some((g: string) => options.genres.includes(g.toLowerCase()))) &&
    (x.row.media.kind !== 'show' || !options.networks.length || (!!x.meta && options.networks.includes(x.meta.network))) &&
    (section !== 'queue' || collectionReleased(x,options.upcoming,now)));
  const dir = options.descending ? -1 : 1;
  result.sort((a: CollectionCandidate,b: CollectionCandidate): number => {
    if (options.sort === 'title') { return dir*cmp(title(a),title(b)); }
    if (options.sort === 'rating') { return numeric(a.meta?.rating,b.meta?.rating,options.descending); }
    if (options.sort === 'runtime') { return numeric(a.meta?.runtime,b.meta?.runtime,options.descending); }
    if (options.sort === 'userRating') { return numeric(a.userRating,b.userRating,options.descending) || cmp(title(a),title(b)); }
    if (options.sort === 'recent') { return numeric(a.recent,b.recent,options.descending); }
    if (options.sort === 'random') { return a.randomOrder-b.randomOrder; }
    if (options.sort === 'newest') {
      const ad = a.meta?.release ?? ''; const bd = b.meta?.release ?? '';
      const year = a.row.media.year-b.row.media.year;
      // My library sorts year first; watchlist/hidden sorts release first.
      if (section === 'mine') { return dir*(year || cmp(ad,bd)); }
      if (a.row.media.kind === 'movie' && !!ad !== !!bd) { return ad ? -1 : 1; }
      return dir*(cmp(ad,bd) || year);
    }
    return numeric(a.added,b.added,options.descending);
  });
  return result;
}
export function recentCollection(items: CollectionCandidate[], amount: number): PersonalLibraryRow[] {
  return items.filter((x: CollectionCandidate) => x.added !== undefined)
    .sort((a: CollectionCandidate,b: CollectionCandidate) => numeric(a.added,b.added,true))
    .slice(0,amount).map((x: CollectionCandidate) => x.row);
}
