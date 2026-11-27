import { FullEpisodeCatalog, scheduleEpisodes, showSections } from './ShowCatalog';
import { RemoteShowObservation } from './RemoteObservation';
import { CommonEntry } from './ThreeWay';
import { ReadCheckpoint, ReadDecision, EffectiveEpisodes, resolveEpisodes } from './EffectiveState';
import { ProgressSource, TimedDecision, progressSource } from './ProgressRules';

export interface ProjectionInput {
  full: FullEpisodeCatalog;
  remote?: RemoteShowObservation;
  cloudActive: boolean;
  localIds: number[];
  decisions: ReadDecision[];
  timed: TimedDecision[];
  checkpoints: ReadCheckpoint[];
  common: CommonEntry[];
  now: number;
}
export interface ProjectionOutput {
  effective: EffectiveEpisodes;
  sections: string[];
  source?: ProgressSource;
  validUntil: number;
}
export function computeProjection(input: ProjectionInput): ProjectionOutput {
  const checkpoints = new Map<number, ReadCheckpoint>();
  const common = new Map<string, CommonEntry>();
  for (const cp of input.checkpoints) { checkpoints.set(cp.id, cp); }
  for (const entry of input.common) { common.set(entry.id, entry); }
  const effective = resolveEpisodes(input.full, input.remote, input.cloudActive, input.localIds,
    input.decisions, checkpoints, common);
  let validUntil = Number.MAX_SAFE_INTEGER;
  // Aired eligibility and season sections change only at actual air times.
  for (const season of input.full.seasons) {
    const air = Date.parse(season.firstAired);
    if (Number.isFinite(air) && air >= input.now) { validUntil = Math.min(validUntil, air === input.now ? air + 1 : air); }
  }
  for (const episode of scheduleEpisodes(input.full)) {
    const air = Date.parse(episode.firstAired);
    if (Number.isFinite(air) && air >= input.now) { validUntil = Math.min(validUntil, air === input.now ? air + 1 : air); }
  }
  return { effective: effective, sections: effective.complete ? showSections(input.full, effective.ids, input.now) : [],
    source: effective.complete ? progressSource(input.full, effective.ids, input.remote, input.timed, checkpoints, input.cloudActive) : undefined,
    validUntil: validUntil };
}

interface ShowMemoEntry {
  key: string;
  from: number;
  output: ProjectionOutput;
}
// Exact input equality, no heuristic threshold. Only in-memory read models.
export class ShowProjectionCache {
  private scope: string = '';
  private entries: Map<string, ShowMemoEntry> = new Map<string, ShowMemoEntry>();
  begin(scope: string): void {
    if (this.scope !== scope) { this.clear(); this.scope = scope; }
  }
  clear(): void { this.scope = ''; this.entries.clear(); }
  get(id: string, key: string, now: number): ProjectionOutput | undefined {
    const entry = this.entries.get(id);
    return entry && entry.key === key && now >= entry.from && now < entry.output.validUntil ? entry.output : undefined;
  }
  put(id: string, key: string, now: number, output: ProjectionOutput): void {
    this.entries.set(id, { key: key, from: now, output: output });
  }
  retain(ids: Set<string>): void {
    for (const id of this.entries.keys()) { if (!ids.has(id)) { this.entries.delete(id); } }
  }
}
export function showProjectionKey(input: ProjectionInput): string {
  return JSON.stringify([input.full, input.remote, input.cloudActive, input.localIds,
    input.decisions, input.timed, input.checkpoints, input.common]);
}
