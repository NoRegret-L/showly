import { Media } from './Media';

// Public schedule metadata. Never consumed as a sync journal or write authorization.
export interface ScheduledEpisode {
  id: number;
  season: number;
  number: number;
  title: string;
  firstAired: string;
}
export interface ScheduledSeason {
  number: number;
  firstAired: string;
  episodes: ScheduledEpisode[];
}
export interface FullEpisodeCatalog {
  media: Media;
  status: string;
  fetchedAt: number;
  rating?: number;
  seasons: ScheduledSeason[];
}

function positive(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}
export function airDate(value?: string): string {
  return typeof value === 'string' && Number.isFinite(Date.parse(value)) ? value : '';
}
export function validateFullCatalog(catalog: FullEpisodeCatalog, showId: string): void {
  if (!catalog || !catalog.media || catalog.media.id !== showId || catalog.media.kind !== 'show' ||
      !/^show:[1-9][0-9]*$/.test(showId) || !positive(Number(showId.substring(5))) ||
      typeof catalog.media.title !== 'string' || !Number.isFinite(catalog.media.year) ||
      typeof catalog.status !== 'string' || !positive(catalog.fetchedAt) ||
      (catalog.rating !== undefined && (!Number.isFinite(catalog.rating) || catalog.rating < 0 || catalog.rating > 10)) ||
      !Array.isArray(catalog.seasons)) { throw new Error('Invalid full catalog'); }
  const seasons: Set<number> = new Set<number>();
  const ids: Set<number> = new Set<number>();
  for (const season of catalog.seasons) {
    if (!positive(season.number) || seasons.has(season.number) ||
        typeof season.firstAired !== 'string' || airDate(season.firstAired) !== season.firstAired ||
        !Array.isArray(season.episodes)) { throw new Error('Invalid season metadata'); }
    seasons.add(season.number);
    const numbers: Set<number> = new Set<number>();
    for (const episode of season.episodes) {
      if (!positive(episode.id) || episode.season !== season.number || !positive(episode.number) ||
          ids.has(episode.id) || numbers.has(episode.number) || typeof episode.title !== 'string' ||
          typeof episode.firstAired !== 'string' || airDate(episode.firstAired) !== episode.firstAired) {
        throw new Error('Invalid episode metadata');
      }
      ids.add(episode.id);
      numbers.add(episode.number);
    }
  }
}
export function aired(episode: ScheduledEpisode, now: number): boolean {
  return !!episode.firstAired && Date.parse(episode.firstAired) <= now;
}
export function scheduleEpisodes(catalog: FullEpisodeCatalog): ScheduledEpisode[] {
  const episodes: ScheduledEpisode[] = [];
  for (const season of catalog.seasons) {
    for (const episode of season.episodes) { episodes.push(episode); }
  }
  return episodes;
}
export function scheduleLabel(episode: ScheduledEpisode, now: number): string {
  if (!episode.firstAired) { return '播出日期待确认'; }
  return (aired(episode, now) ? '已播 · ' : '待播 · ') + episode.firstAired.substring(0, 10);
}

// Same independent predicates as Android MyShowsLoadShowsCase, with
// conservative unknown handling for missing dates or empty metadata.
// Uses exact local watched IDs only; never infers individual plays from counts.
export function showSections(catalog: FullEpisodeCatalog, watchedIds: number[], now: number): string[] {
  const watched: Set<number> = new Set<number>(watchedIds);
  const result: string[] = [];
  const airedSeasons = catalog.seasons.filter((season: ScheduledSeason) =>
    !!season.firstAired && Date.parse(season.firstAired) < now);
  const complete = (season: ScheduledSeason): boolean =>
    season.episodes.length > 0 && season.episodes.every((episode: ScheduledEpisode) => watched.has(episode.id));
  const knownSeasons = catalog.seasons.length > 0 &&
    catalog.seasons.every((season: ScheduledSeason) => !!season.firstAired && season.episodes.length > 0);
  if (airedSeasons.some((season: ScheduledSeason) =>
    season.episodes.some((episode: ScheduledEpisode) => !watched.has(episode.id)))) { result.push('watching'); }
  if ((catalog.status === 'ended' || catalog.status === 'canceled') && knownSeasons &&
      catalog.seasons.every(complete)) { result.push('finished'); }
  if (catalog.status === 'planned' || catalog.status === 'upcoming' || catalog.status === 'in production' ||
      (catalog.status === 'returning series' && knownSeasons && airedSeasons.every(complete))) {
    result.push('upcoming');
  }
  return result;
}
