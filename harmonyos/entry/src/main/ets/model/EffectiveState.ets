import { CommonEntry, classifyThreeWay } from './ThreeWay';
import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes } from './ShowCatalog';
import { RemoteShowObservation } from './RemoteObservation';

export interface ReadCheckpoint {
  id: number;
  seq: number;
  watched: boolean;
}
export interface ReadDecision {
  episodeId: number;
  seq: number;
  watched: boolean;
}
export interface EffectiveEpisodes {
  ids: number[];
  complete: boolean;
  matches: ReadCheckpoint[];
}
// Only a verified matching sequence is acknowledged. A newer local event
// remains visible as a new intent; this never authorizes a cloud write.
export function effectiveDecision(local: boolean, remote: boolean, seq: number,
  checkpoint?: ReadCheckpoint, common?: CommonEntry): boolean {
  if (checkpoint) {
    return checkpoint.seq === seq && checkpoint.watched === local ? remote : local;
  }
  return classifyThreeWay(local ? 'yes' : 'no', remote, common) === 'remote' ? remote : local;
}
export function allowLocalScope(cloudActive: boolean, bound: string, uuid: string): boolean {
  return !cloudActive || (!!bound && bound === uuid);
}
export function resolveEpisodes(full: FullEpisodeCatalog, remote: RemoteShowObservation | undefined,
  cloudActive: boolean, localIds: number[], decisions: ReadDecision[],
  checkpoints: Map<number, ReadCheckpoint>, common: Map<string, CommonEntry>): EffectiveEpisodes {
  const episodes = scheduleEpisodes(full);
  const valid: Set<number> = new Set<number>(episodes.map((episode: ScheduledEpisode) => episode.id));
  const byPosition: Map<string, number> = new Map<string, number>();
  for (const episode of episodes) { byPosition.set(episode.season + ':' + episode.number, episode.id); }
  const watched: Set<number> = new Set<number>();
  let complete = true;
  if (cloudActive) {
    for (const pos of remote?.positions ?? []) {
      if (pos.season === 0) { continue; }
      const id = byPosition.get(pos.season + ':' + pos.number);
      if (id === undefined) { complete = false; }
      else { watched.add(id); }
    }
  } else {
    for (const id of localIds) { if (valid.has(id)) { watched.add(id); } }
  }
  const matches: ReadCheckpoint[] = [];
  for (const decision of decisions) {
    if (!valid.has(decision.episodeId)) { continue; }
    const cloudWatched = watched.has(decision.episodeId);
    // An incomplete cloud mapping cannot establish a negative observation.
    const value = cloudActive && complete ? effectiveDecision(decision.watched, cloudWatched,
      decision.seq, checkpoints.get(decision.episodeId), common.get(decision.episodeId.toString())) : decision.watched;
    if (cloudActive && complete && decision.seq > 0 && decision.watched === cloudWatched) {
      matches.push({ id: decision.episodeId, seq: decision.seq, watched: decision.watched });
    }
    if (value) { watched.add(decision.episodeId); }
    else { watched.delete(decision.episodeId); }
  }
  return { ids: Array.from(watched), complete: complete, matches: matches };
}
