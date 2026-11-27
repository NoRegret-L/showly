export interface Media {
  id: string;
  title: string;
  kind: string;
  year: number;
  watched: boolean;
}

// Shared date record, independent of collection UI or sync rules.
export interface CollectionDate { id: string; at: number; }

export interface Library {
  schema: number;
  items: Media[];
}

export function mediaLabel(item: Media): string {
  const year: string = item.year > 0 ? ' (' + item.year + ')' : '';
  const kind: string = item.kind === 'movie' ? '电影' : item.kind === 'show' ? '剧集' : '手动';
  return item.title + year + ' · ' + kind;
}

export function setWatched(items: Media[], id: string, watched: boolean): Media[] {
  return items.map((item: Media): Media => {
    if (item.id !== id) {
      return item;
    }
    return { id: item.id, title: item.title, kind: item.kind, year: item.year, watched: watched };
  });
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

