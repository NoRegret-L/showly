import { Media } from './Media';
import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes } from './ShowCatalog';
import { RemoteShowObservation, RemotePlayPosition } from './RemoteObservation';
import { ReadCheckpoint } from './EffectiveState';
import { compareTitles, matchesText } from './MediaPresentation';

export interface ProgressEpisode {
  episode: ScheduledEpisode;
  watched: boolean;
  watchedAt: number;
}
export interface TimedDecision {
  episodeId: number;
  seq: number;
  watched: boolean;
  changedAt: number;
}
export interface ProgressSource {
  media: Media;
  episodes: ProgressEpisode[];
  recentAt: number;
  rating?: number;
  randomOrder: number;
  localizedTitle?: string;
  episodeNames?: Map<number, string>;
}
export interface ProgressPreferences {
  strategy: string;
  count: string;
  days: number;
  sort: string;
  descending: boolean;
  newAtTop: boolean;
  upcomingCollapsed: boolean;
  holdCollapsed: boolean;
  filter?: string;
}
export interface ProgressFlag {
  id: string;
  pinned: boolean;
  held: boolean;
}
export interface ProgressRow {
  media: Media;
  episode: ScheduledEpisode;
  total: number;
  completed: number;
  upcoming: boolean;
  fresh: boolean;
  pinned: boolean;
  held: boolean;
  group: string;
  recentAt: number;
  rating?: number;
  randomOrder: number;
  dateUnknown: boolean;
  localizedTitle?: string;
  localizedEpisode?: string;
}
const DAY = 86400000;
// Upstream Config.NEW_BADGE_DURATION = DAYS.toMillis(3).
const NEW_DURATION = 3 * DAY;
export function defaultProgress(): ProgressPreferences {
  return { strategy: 'last', count: 'aired', days: 30, sort: 'recent', descending: true,
    newAtTop: false, upcomingCollapsed: false, holdCollapsed: false, filter: 'all' };
}
export function validProgress(p: ProgressPreferences): boolean {
  return !!p && ['last','oldest'].includes(p.strategy) && ['aired','all'].includes(p.count) &&
    Number.isSafeInteger(p.days) && p.days >= 0 && Number.isFinite(new Date(Date.now() + p.days * DAY).getTime()) &&
    ['recent','remaining','title','newest','rating','random'].includes(p.sort) &&
    typeof p.descending === 'boolean' && typeof p.newAtTop === 'boolean' &&
    typeof p.upcomingCollapsed === 'boolean' && typeof p.holdCollapsed === 'boolean' &&
    (p.filter === undefined || ['all','upcoming','hold','both'].includes(p.filter));
}
export function validFlags(flags: ProgressFlag[]): boolean {
  if (!Array.isArray(flags)) { return false; }
  const seen: Set<string> = new Set<string>();
  for (const flag of flags) {
    if (!flag || !/^(show|movie):[1-9][0-9]*$/.test(flag.id) || seen.has(flag.id) ||
        typeof flag.pinned !== 'boolean' || typeof flag.held !== 'boolean' || (flag.id.startsWith('movie:') && flag.held)) { return false; }
    seen.add(flag.id);
  }
  return true;
}
export function toggleProgressFlag(flags: ProgressFlag[], id: string, kind: string): ProgressFlag[] {
  if (id.startsWith('movie:') && kind !== 'pin') { return flags; }
  const before = flags.find((flag: ProgressFlag) => flag.id === id);
  // Upstream ShowContextMenuPinnedCase and ShowContextMenuOnHoldCase
  // clear the opposite flag when adding a new flag.
  const pinned = kind === 'pin' ? !before?.pinned : false;
  const held = kind === 'hold' ? !before?.held : false;
  const next = flags.filter((flag: ProgressFlag) => flag.id !== id);
  if (pinned || held) { next.push({ id: id, pinned: pinned, held: held }); }
  return next;
}
function time(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
// Remote last-watched timestamps are real observations; the journal timestamp
// is a real explicit local mark, not a catalog download timestamp.
export function progressSource(full: FullEpisodeCatalog, ids: number[], remote: RemoteShowObservation | undefined,
  decisions: TimedDecision[], checkpoints: Map<number, ReadCheckpoint>, cloudActive: boolean): ProgressSource {
  const watched = new Set<number>(ids);
  const byId: Map<number, TimedDecision> = new Map<number, TimedDecision>();
  for (const decision of decisions) { byId.set(decision.episodeId, decision); }
  const positions: Map<string, RemotePlayPosition> = new Map<string, RemotePlayPosition>();
  for (const pos of remote?.positions ?? []) { positions.set(pos.season + ':' + pos.number, pos); }
  let recent = time(remote?.updatedAt ?? '');
  const episodes: ProgressEpisode[] = [];
  for (const ep of scheduleEpisodes(full)) {
    const isWatched = watched.has(ep.id);
    const intent = byId.get(ep.id);
    const checkpoint = checkpoints.get(ep.id);
    const remoteTime = time(positions.get(ep.season + ':' + ep.number)?.lastWatchedAt ?? '');
    let watchedAt = 0;
    if (isWatched) {
      watchedAt = remoteTime;
      if (intent?.watched && (!cloudActive || checkpoint?.seq !== intent.seq)) {
        watchedAt = Math.max(watchedAt, intent.changedAt);
      }
    }
    if (intent) { recent = Math.max(recent, intent.changedAt); }
    recent = Math.max(recent, watchedAt);
    episodes.push({ episode: ep, watched: isWatched, watchedAt: watchedAt });
  }
  return { media: full.media, episodes: episodes, recentAt: recent, rating: full.rating, randomOrder: Math.random() };
}
function position(a: ProgressEpisode, b: ProgressEpisode): number {
  return a.episode.season - b.episode.season || a.episode.number - b.episode.number;
}
export function selectProgress(source: ProgressSource, prefs: ProgressPreferences, flags: ProgressFlag[],
  now: number): ProgressRow | undefined {
  const ordered = source.episodes.filter((item: ProgressEpisode) => item.episode.season > 0).sort(position);
  const watched = ordered.filter((item: ProgressEpisode) => item.watched);
  const dated = watched.filter((item: ProgressEpisode) => item.watchedAt > 0)
    .sort((a: ProgressEpisode, b: ProgressEpisode) => b.watchedAt - a.watchedAt || position(a,b));
  const last = prefs.strategy === 'last' ? dated[0] : undefined;
  const limit = now + prefs.days * DAY;
  const next = ordered.find((item: ProgressEpisode) => !item.watched && !!item.episode.firstAired &&
    Number.isFinite(Date.parse(item.episode.firstAired)) && Date.parse(item.episode.firstAired) <= limit &&
    (!last || position(item, last) > 0));
  if (!next) { return undefined; }
  const aired = Date.parse(next.episode.firstAired);
  const upcoming = aired > now;
  if (upcoming && !prefs.days) { return undefined; }
  // Upstream SQL counts first_aired < now, while the candidate limit is <=.
  const counted = prefs.count === 'all' ? ordered : ordered.filter((item: ProgressEpisode) =>
    !!item.episode.firstAired && Date.parse(item.episode.firstAired) < now);
  const flag = flags.find((item: ProgressFlag) => item.id === source.media.id);
  const pinned = flag?.pinned ?? false;
  const held = flag?.held ?? false;
  const fresh = aired < now && now - aired < NEW_DURATION;
  const group = pinned ? 'pinned' : held ? 'hold' : prefs.newAtTop && fresh ? 'new' : upcoming ? 'upcoming' : 'aired';
  return { media: source.media, episode: next.episode, total: counted.length,
    completed: counted.filter((item: ProgressEpisode) => item.watched).length, upcoming: upcoming,
    fresh: fresh, pinned: pinned, held: held, group: group, recentAt: source.recentAt, rating: source.rating,
    randomOrder: source.randomOrder, dateUnknown: prefs.strategy === 'last' && watched.length > dated.length,
    localizedTitle: source.localizedTitle, localizedEpisode: source.episodeNames?.get(next.episode.id) };
}
function title(row: ProgressRow): string {
  return row.localizedTitle || row.media.title;
}
function order(a: ProgressRow, b: ProgressRow, prefs: ProgressPreferences): number {
  const sign = prefs.descending ? -1 : 1;
  if (prefs.sort === 'rating' && (a.rating === undefined || b.rating === undefined)) {
    if (a.rating !== b.rating) { return a.rating === undefined ? 1 : -1; }
  }
  let value = 0;
  if (prefs.sort === 'title') { value = compareTitles(title(a), title(b), a.localizedTitle || b.localizedTitle ? 'zh' : 'original'); }
  else if (prefs.sort === 'recent') { value = a.recentAt - b.recentAt; }
  else if (prefs.sort === 'remaining') { value = (a.total - a.completed) - (b.total - b.completed); }
  else if (prefs.sort === 'newest') { value = time(a.episode.firstAired) - time(b.episode.firstAired); }
  else if (prefs.sort === 'rating') { value = (a.rating ?? 0) - (b.rating ?? 0); }
  else if (prefs.sort === 'random') { value = a.randomOrder - b.randomOrder; }
  return sign * value || compareTitles(title(a), title(b), a.localizedTitle || b.localizedTitle ? 'zh' : 'original') || a.media.id.localeCompare(b.media.id);
}
export function progressRows(sources: ProgressSource[], prefs: ProgressPreferences, flags: ProgressFlag[],
  now: number, filter: string, query: string): ProgressRow[] {
  const q = query.trim();
  const result: ProgressRow[] = [];
  for (const source of sources) {
    const row = selectProgress(source, prefs, flags, now);
    if (row && (!q || matchesText(q, row.media.title, row.localizedTitle ?? '') || matchesText(q, row.episode.title, row.localizedEpisode ?? ''))) { result.push(row); }
  }
  const grouped: ProgressRow[] = [];
  for (const group of ['pinned','new','aired','upcoming','hold']) {
    if (filter !== 'all' && filter !== group && !(filter === 'both' && (group === 'upcoming' || group === 'hold'))) { continue; }
    const rows = result.filter((row: ProgressRow) => row.group === group);
    rows.sort((a: ProgressRow, b: ProgressRow) => {
      if (group === 'upcoming') { return time(a.episode.firstAired) - time(b.episode.firstAired) || order(a,b,prefs); }
      if (group === 'pinned' || group === 'hold') {
        if (a.fresh !== b.fresh) { return a.fresh ? -1 : 1; }
      }
      return order(a,b,prefs);
    });
    grouped.push(...rows);
  }
  return grouped;
}

export interface ProgressSection {
  key: string;
  label: string;
  collapsed: boolean;
  rows: ProgressRow[];
}
export interface ProgressEntry {
  key: string;
  group: string;
  label: string;
  collapsed: boolean;
  count: number;
  row?: ProgressRow;
}
// The Android list contains headers only for nonempty Upcoming and On Hold
// groups, even when collapsed. Headers follow ordinary candidates, rather
// than being detached controls at the top.
export function progressSections(rows: ProgressRow[], prefs: ProgressPreferences): ProgressSection[] {
  const sections: ProgressSection[] = [];
  for (const group of ['pinned','new','aired','upcoming','hold']) {
    const items = rows.filter((row: ProgressRow) => row.group === group);
    if (!items.length) { continue; }
    sections.push({ key: group, label: group === 'upcoming' ? '待播' : group === 'hold' ? '暂缓观看' : '',
      collapsed: group === 'upcoming' ? prefs.upcomingCollapsed : group === 'hold' ? prefs.holdCollapsed : false,
      rows: items });
  }
  return sections;
}
export function progressEntries(sections: ProgressSection[]): ProgressEntry[] {
  const result: ProgressEntry[] = [];
  for (const section of sections) {
    if (section.label) {
      result.push({ key: 'header:' + section.key, group: section.key, label: section.label,
        collapsed: section.collapsed, count: section.rows.length });
    }
    if (!section.collapsed) {
      for (const row of section.rows) {
        result.push({ key: 'show:' + row.media.id, group: section.key, label: '',
          collapsed: false, count: 0, row: row });
      }
    }
  }
  return result;
}
export function progressPage(entries: ProgressEntry[], page: number, size: number): ProgressEntry[] {
  const start = (page - 1) * size;
  const slice = entries.slice(start, start + size);
  const first = slice[0];
  // A continued paginated section keeps its own heading visible.
  if (start > 0 && first?.row && (first.group === 'upcoming' || first.group === 'hold')) {
    const header = entries.find((entry: ProgressEntry) => !entry.row && entry.group === first.group);
    if (header) { return [header, ...slice]; }
  }
  return slice;
}
export function effectiveProgressFilter(prefs: ProgressPreferences): string {
  const value = prefs.filter ?? 'all';
  return prefs.days > 0 ? value : value === 'both' ? 'hold' : value === 'upcoming' ? 'all' : value;
}
