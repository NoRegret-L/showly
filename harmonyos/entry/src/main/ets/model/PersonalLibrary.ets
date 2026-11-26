import { Media } from './Media';
import { MediaRecord, inLocalWatchlist } from './MediaState';

// Counts describe separate observations, not additive histories.
export interface LibraryShowEvidence {
  media: Media;
  watchedEpisodes: number;
  sections?: string[];
}
export interface PersonalLibraryRow {
  media: Media;
  localRecord?: MediaRecord;
  queued: boolean;
  watched: boolean;
  localEpisodes: number;
  cloudEpisodes: number;
  sections?: string[];
}

function addRow(rows: Map<string, PersonalLibraryRow>, media: Media): PersonalLibraryRow {
  const existing = rows.get(media.id);
  if (existing) { return existing; }
  const row: PersonalLibraryRow = { media: media, queued: false, watched: false,
    localEpisodes: -1, cloudEpisodes: -1 };
  rows.set(media.id, row);
  return row;
}

// Read-only union. Explicit device intents override positive cloud observations
// for the corresponding domain only. Legacy fallbacks are not sync intents.
// A missing catalog or remote observation is unknown, not a negative fact.
export function buildPersonalLibrary(records: MediaRecord[], cloudMovies: Media[], cloudWatchlist: Media[],
  cloudShows: LibraryShowEvidence[], localShows: LibraryShowEvidence[]): PersonalLibraryRow[] {
  const rows: Map<string, PersonalLibraryRow> = new Map<string, PersonalLibraryRow>();
  for (const record of records) {
    const row = addRow(rows, record.media);
    row.localRecord = record;
    row.queued = inLocalWatchlist(record);
    row.watched = record.media.watched;
  }
  for (const media of cloudMovies) {
    const row = addRow(rows, media);
    if (row.localRecord?.movieState !== 'no') { row.watched = true; }
  }
  for (const media of cloudWatchlist) {
    const row = addRow(rows, media);
    if (row.localRecord?.watchlistState !== 'no' && row.localRecord?.followState !== 'yes') { row.queued = true; }
  }
  for (const show of cloudShows) {
    const row = addRow(rows, show.media);
    row.cloudEpisodes = show.watchedEpisodes;
  }
  for (const show of localShows) {
    // Opening a detail page may cache a catalog without following the title.
    if (show.watchedEpisodes > 0 || rows.has(show.media.id)) {
      const row = addRow(rows, show.media);
      row.localEpisodes = show.watchedEpisodes;
      row.sections = show.sections;
    }
  }
  return Array.from(rows.values());
}

export function hasTrackingEvidence(row: PersonalLibraryRow): boolean {
  return row.media.kind === 'show' && (row.localRecord?.followState === 'yes' ||
    (row.localRecord?.followState !== 'no' && (row.localEpisodes > 0 || row.cloudEpisodes >= 0)));
}

export function filterPersonalLibrary(rows: PersonalLibraryRow[], filter: string): PersonalLibraryRow[] {
  if (filter === 'queue') { return rows.filter((row: PersonalLibraryRow) => row.queued); }
  if (filter === 'tracking') { return rows.filter((row: PersonalLibraryRow) => hasTrackingEvidence(row)); }
  if (filter === 'watching' || filter === 'finished' || filter === 'upcoming') {
    return rows.filter((row: PersonalLibraryRow) => hasTrackingEvidence(row) &&
      (row.sections?.includes(filter) ?? false) && row.cloudEpisodes <= row.localEpisodes);
  }
  if (filter === 'watched') { return rows.filter((row: PersonalLibraryRow) => row.watched); }
  return rows;
}

export function personalLibraryLabel(row: PersonalLibraryRow): string {
  const labels: string[] = [];
  if (row.queued) { labels.push('待看'); }
  if (row.watched) { labels.push(row.media.kind === 'show' ? '本机旧已看标记' : '已看'); }
  if (row.localEpisodes >= 0) { labels.push('本机已看 ' + row.localEpisodes + ' 集'); }
  if (row.cloudEpisodes >= 0) { labels.push('云端已看 ' + row.cloudEpisodes + ' 集'); }
  if (hasTrackingEvidence(row)) {
    if (row.localRecord?.followState === 'yes') { labels.push('本机追剧'); }
    const sections = row.sections ?? [];
    if (sections.length === 0 || row.cloudEpisodes > row.localEpisodes) { labels.push('追剧状态待核实'); }
    else {
      if (sections.includes('watching')) { labels.push('本机正在追'); }
      if (sections.includes('finished')) { labels.push('本机已追完结剧'); }
      if (sections.includes('upcoming')) { labels.push('本机等待更新'); }
    }
  }
  if (!row.localRecord) { labels.push('仅浏览'); }
  return labels.join(' · ');
}
