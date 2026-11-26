import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { TraktSession, traktAuth } from './TraktAuth';

interface CalendarIds { trakt: number; }
interface CalendarTitle { title: string; year?: number; ids: CalendarIds; }
interface CalendarEpisode { season: number; number: number; title?: string; ids: CalendarIds; }
interface CalendarRow {
  first_aired?: string;
  released?: string;
  show?: CalendarTitle;
  movie?: CalendarTitle;
  episode?: CalendarEpisode;
}
export interface CalendarWindow {
  from: string;
  to: string;
  utcStart: string;
  utcDays: number;
  startMs: number;
  endMs: number;
}
export interface CalendarEntry {
  key: string;
  media: Media;
  day: string;
  time: string;
  season: number;
  number: number;
  episodeTitle: string;
  order: number;
}
export interface CalendarSnapshot {
  generation: number;
  window: CalendarWindow;
  entries: CalendarEntry[];
  skipped: number;
}
interface CalendarPage { rows: CalendarRow[]; pages: number; total: number; }

function validId(value: number): boolean { return Number.isSafeInteger(value) && value > 0; }
export function localDay(date: Date): string {
  return date.getFullYear().toString().padStart(4, '0') + '-' +
    (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0');
}
export function calendarWindow(now: Date, week: number): CalendarWindow {
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() + week * 7);
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7);
  const utcFirst = start.toISOString().substring(0, 10);
  const utcLast = new Date(end.getTime() - 1).toISOString().substring(0, 10);
  const from = localDay(start);
  const to = localDay(new Date(end.getFullYear(), end.getMonth(), end.getDate() - 1));
  // Cover both UTC broadcast instants and date-only movie release days.
  const first = utcFirst < from ? utcFirst : from;
  const last = utcLast > to ? utcLast : to;
  const utcDays = (Date.parse(last + 'T00:00:00Z') - Date.parse(first + 'T00:00:00Z')) / 86400000 + 1;
  return { from: from, to: to, utcStart: first, utcDays: utcDays, startMs: start.getTime(), endMs: end.getTime() };
}
function current(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Session changed'); }
}
function titleMedia(title: CalendarTitle, kind: string): Media {
  if (!title || !title.ids || !validId(title.ids.trakt) || typeof title.title !== 'string' || !title.title) {
    throw new Error('Invalid calendar title');
  }
  return { id: kind + ':' + title.ids.trakt, title: title.title, kind: kind,
    year: typeof title.year === 'number' && Number.isSafeInteger(title.year) ? title.year : 0, watched: false };
}
async function page(session: TraktSession, kind: string, window: CalendarWindow, number: number): Promise<CalendarPage> {
  current(session);
  const req = http.createHttp();
  try {
    const response = await req.request('https://api.trakt.tv/calendars/my/' + (kind === 'show' ? 'shows' : 'movies') +
      '/' + window.utcStart + '/' + window.utcDays + '?page=' + number + '&limit=250', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    current(session);
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Calendar HTTP ' + response.responseCode);
    }
    const rows = JSON.parse(response.result) as CalendarRow[];
    if (!Array.isArray(rows)) { throw new Error('Invalid calendar response'); }
    const headers = JSON.parse(JSON.stringify(response.header).toLowerCase()) as Record<string, string>;
    const count = headers['x-pagination-item-count'];
    const pageCount = headers['x-pagination-page-count'];
    const pageNumber = headers['x-pagination-page'];
    // Calendar endpoints may be unpaginated. If any pagination metadata is
    // provided, require the complete consistent set rather than silently truncate.
    if (count === undefined && pageCount === undefined && pageNumber === undefined && number === 1) {
      return { rows: rows, pages: 1, total: rows.length };
    }
    const total = Number(count);
    const pages = Number(pageCount);
    if (Number(pageNumber) !== number || !Number.isSafeInteger(total) || total < 0 ||
        !Number.isSafeInteger(pages) || pages < 0 ||
        (pages < number && !(number === 1 && pages === 0 && total === 0 && rows.length === 0))) {
      throw new Error('Invalid calendar pagination');
    }
    return { rows: rows, pages: pages, total: total };
  } finally { req.destroy(); }
}
export async function readCalendar(session: TraktSession, kind: string, week: number): Promise<CalendarSnapshot> {
  if (kind !== 'show' && kind !== 'movie') { throw new Error('Invalid calendar kind'); }
  const window = calendarWindow(new Date(), week);
  const first = await page(session, kind, window, 1);
  const rows = [...first.rows];
  for (let n = 2; n <= first.pages; n++) {
    const next = await page(session, kind, window, n);
    if (next.pages !== first.pages || next.total !== first.total || next.rows.length === 0) {
      throw new Error('Calendar changed while reading');
    }
    for (const item of next.rows) { rows.push(item); }
  }
  if (rows.length !== first.total) { throw new Error('Incomplete calendar'); }
  const entries: CalendarEntry[] = [];
  const seen: Set<string> = new Set<string>();
  let skipped = 0;
  for (const row of rows) {
    if (kind === 'show') {
      const ep = row.episode;
      const date = typeof row.first_aired === 'string' ? Date.parse(row.first_aired) : NaN;
      if (!ep || !row.show || !ep.ids || !validId(ep.ids.trakt) || !validId(ep.number) ||
          !Number.isSafeInteger(ep.season) || ep.season < 0 || !Number.isFinite(date)) { skipped++; continue; }
      if (date < window.startMs || date >= window.endMs) { continue; }
      const media = titleMedia(row.show, 'show');
      const key = 'episode:' + ep.ids.trakt;
      if (seen.has(key)) { continue; }
      seen.add(key);
      const instant = new Date(date);
      const time = instant.getHours().toString().padStart(2, '0') + ':' + instant.getMinutes().toString().padStart(2, '0');
      entries.push({ key: key, media: media, day: localDay(instant), time: time,
        season: ep.season, number: ep.number, episodeTitle: ep.title ?? '', order: date });
    } else {
      const day = row.released;
      if (!row.movie || typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day) ||
          !Number.isFinite(Date.parse(day + 'T00:00:00Z')) ||
          new Date(day + 'T00:00:00Z').toISOString().substring(0, 10) !== day) { skipped++; continue; }
      if (day < window.from || day > window.to) { continue; }
      const media = titleMedia(row.movie, 'movie');
      const key = media.id + ':' + day;
      if (seen.has(key)) { continue; }
      seen.add(key);
      entries.push({ key: key, media: media, day: day, time: '', season: 0, number: 0,
        episodeTitle: '', order: Date.parse(day + 'T00:00:00Z') });
    }
  }
  current(session);
  entries.sort((a: CalendarEntry, b: CalendarEntry) => a.order - b.order || a.key.localeCompare(b.key));
  return { generation: session.generation, window: window, entries: entries, skipped: skipped };
}
