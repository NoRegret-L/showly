import { MediaRecord, isTraktMedia } from '../model/MediaState';
import { PersonalMovie, PersonalMovieSnapshot } from './TraktLibrary';
import { localDay } from './TraktCalendar';

export interface MovieCalendarItem {
  movie: PersonalMovie;
  group: string;
  heading: boolean;
}

// Cloud membership is authoritative for the cloud subset. Include only
// explicit local positive states outside it, never stale legacy guesses.
export function addLocalMovies(snapshot: PersonalMovieSnapshot, records: MediaRecord[]): PersonalMovieSnapshot {
  const movies = [...snapshot.movies];
  const seen: Set<string> = new Set<string>(movies.map((row: PersonalMovie) => row.media.id));
  for (const record of records) {
    if (record.media.kind !== 'movie' || !isTraktMedia(record.media) || seen.has(record.media.id) ||
        (record.movieState !== 'yes' && record.watchlistState !== 'yes')) { continue; }
    movies.push({ media: record.media, released: '', cloudWatched: false, cloudWatchlist: false, localOnly: true });
    seen.add(record.media.id);
  }
  return { generation: snapshot.generation, activity: snapshot.activity, movies: movies };
}

export function movieGroup(day: string, now: Date): string {
  if (!day) { return '日期待确认'; }
  const today = localDay(now);
  const offset = (n: number): string => localDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() + n));
  if (day === today) { return '今天'; }
  if (day < today) {
    if (day === offset(-1)) { return '昨天'; }
    if (day >= offset(-7)) { return '过去7天'; }
    if (day >= offset(-30)) { return '过去30天'; }
    if (day >= offset(-90)) { return '过去90天'; }
    return '更早上映';
  }
  if (day === offset(1)) { return '明天'; }
  const monday = (8 - now.getDay()) % 7 || 7;
  if (day < offset(monday)) { return '本周'; }
  if (day < offset(monday + 7)) { return '下周'; }
  if (day.substring(0, 7) === today.substring(0, 7)) { return '本月'; }
  if (day.substring(0, 7) === localDay(new Date(now.getFullYear(), now.getMonth() + 1, 1)).substring(0, 7)) { return '下月'; }
  if (day.substring(0, 4) === today.substring(0, 4)) { return '今年'; }
  return '更远日期';
}

export function filterMovies(movies: PersonalMovie[], mode: string, query: string, now: Date): PersonalMovie[] {
  const today = localDay(now);
  const q = query.trim().toLowerCase();
  return movies.filter((row: PersonalMovie) => {
    const matches = mode === 'unknown' ? !row.released :
      mode === 'past' ? !!row.released && row.released < today : !!row.released && row.released >= today;
    return matches && (!q || row.media.title.toLowerCase().includes(q) || row.released.includes(q));
  }).sort((a: PersonalMovie, b: PersonalMovie) => {
    const date = mode === 'past' ? b.released.localeCompare(a.released) : a.released.localeCompare(b.released);
    return date || a.media.title.localeCompare(b.media.title) || a.media.id.localeCompare(b.media.id);
  });
}
export function moviePage(rows: PersonalMovie[], start: number, size: number, now: Date): MovieCalendarItem[] {
  const result: MovieCalendarItem[] = [];
  let previous = '';
  for (const row of rows.slice(start, start + size)) {
    const group = movieGroup(row.released, now);
    result.push({ movie: row, group: group, heading: group !== previous });
    previous = group;
  }
  return result;
}
