import { FullEpisodeCatalog, ScheduledEpisode, aired } from './ShowCatalog';

// Pure projection helpers. No authorization, sync intents or database writes.
export interface ReadEpisodeIdentity { id: number; season: number; }
export interface ReadJournalEvent { ids: number[]; watched: boolean; }
export function validReadIds(ids: number[], unique: boolean, nonempty: boolean): boolean {
  return Array.isArray(ids) && (!nonempty || ids.length > 0) &&
    ids.every((id: number) => Number.isSafeInteger(id) && id > 0) &&
    (!unique || new Set<number>(ids).size === ids.length);
}
// Exact equivalent to materialize(...).seasons flattened to watched IDs.
// Season order follows first encounter; events override both baseline sources.
export function replayWatchedIds(episodes: ReadEpisodeIdentity[], baseline: Set<number>,
  restored: number[], events: ReadJournalEvent[]): number[] {
  const restoredSet = new Set<number>(restored);
  const decisions = new Map<number, boolean>();
  for (const event of events) {
    for (const id of event.ids) { decisions.set(id,event.watched); }
  }
  const seasons = new Map<number, number[]>();
  for (const episode of episodes) {
    let season = seasons.get(episode.season);
    if (!season) { season = []; seasons.set(episode.season,season); }
    const watched = decisions.get(episode.id) ?? (baseline.has(episode.id) || restoredSet.has(episode.id));
    if (watched) { season.push(episode.id); }
  }
  const ids: number[] = [];
  for (const season of seasons.values()) { for (const id of season) { ids.push(id); } }
  return ids;
}

export interface AiredSummary {
  total: number;
  completed: number;
  nextSeason: number;
  nextNumber: number;
  nextTitle: string;
}
// Equivalent to projectShow(eligibleCatalog(full, now), ids), but with
// one traversal, no copy of the catalog and no O(n log n) sort.
export function summarizeAired(full: FullEpisodeCatalog, ids: number[], now: number): AiredSummary {
  const watched = new Set<number>(ids);
  let total = 0;
  let completed = 0;
  let next: ScheduledEpisode | undefined;
  for (const season of full.seasons) {
    for (const episode of season.episodes) {
      if (!aired(episode,now)) { continue; }
      total++;
      if (watched.has(episode.id)) { completed++; }
      else if (!next || episode.season < next.season ||
        (episode.season === next.season && episode.number < next.number)) { next = episode; }
    }
  }
  return { total: total, completed: completed, nextSeason: next?.season ?? 0,
    nextNumber: next?.number ?? 0, nextTitle: next?.title ?? '' };
}
