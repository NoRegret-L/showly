import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes, showSections } from './ShowCatalog';
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

export interface ShowMemoEntry {
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

export interface PersistedShowEntry { id: string; entry: ShowMemoEntry; }
export interface PersistedProjection { schema: number; scope: string; entries: PersistedShowEntry[]; }
export function persistentProjectionScope(client: string, uuid: string, cloudActive: boolean, localAllowed: boolean): string {
  return JSON.stringify([client, cloudActive ? 'account' : 'device', uuid, localAllowed]);
}
export function diskProjectionAllowed(input: ProjectionInput): boolean {
  // An unacknowledged decision must use the live resolver. Disk data never
  // provides new checkpoint evidence, even if the rest of its key matches.
  return !input.cloudActive || input.decisions.every((d: ReadDecision) =>
    input.checkpoints.some((cp: ReadCheckpoint) => cp.id === d.episodeId && cp.seq === d.seq && cp.watched === d.watched));
}
export function readPersistedShow(entry: ShowMemoEntry | undefined, input: ProjectionInput,
  key: string): ProjectionOutput | undefined {
  if (!entry || entry.key !== key || !diskProjectionAllowed(input) ||
      !Number.isSafeInteger(entry.from) || input.now < entry.from || !entry.output ||
      !Number.isSafeInteger(entry.output.validUntil) || input.now >= entry.output.validUntil) { return undefined; }
  const out = entry.output;
  if (!out.effective || !out.effective.complete || !Array.isArray(out.effective.ids) ||
      !Array.isArray(out.effective.matches) || out.effective.matches.length !== 0 ||
      !Array.isArray(out.sections) || !out.sections.every((s: string) => ['watching','finished','upcoming'].includes(s)) ||
      !out.source || out.source.media?.id !== input.full.media.id || !Array.isArray(out.source.episodes) ||
      !Number.isFinite(out.source.recentAt) || !Number.isFinite(out.source.randomOrder)) { return undefined; }
  const episodes = scheduleEpisodes(input.full);
  const watched = new Set<number>(out.effective.ids);
  if (watched.size !== out.effective.ids.length || out.source.episodes.length !== episodes.length) { return undefined; }
  const known = new Set<number>(episodes.map((ep: ScheduledEpisode) => ep.id));
  if (out.effective.ids.some((id: number) => !known.has(id))) { return undefined; }
  for (let i = 0; i < episodes.length; i++) {
    const row = out.source.episodes[i];
    if (!row || JSON.stringify(row.episode) !== JSON.stringify(episodes[i]) ||
        row.watched !== watched.has(episodes[i].id) || !Number.isFinite(row.watchedAt)) { return undefined; }
  }
  return out;
}
export function decodePersistedProjection(raw: string, scope: string): Map<string, ShowMemoEntry> {
  const result = new Map<string, ShowMemoEntry>();
  try {
    const parsed = JSON.parse(raw) as PersistedProjection;
    if (parsed.schema !== 1 || parsed.scope !== scope || !Array.isArray(parsed.entries)) { return result; }
    for (const row of parsed.entries) {
      if (!row || !/^show:[1-9][0-9]*$/.test(row.id) || !row.entry || result.has(row.id)) { return new Map<string, ShowMemoEntry>(); }
      result.set(row.id, row.entry);
    }
  } catch (error) { return new Map<string, ShowMemoEntry>(); }
  return result;
}
export function persistShow(key: string, from: number, output: ProjectionOutput): ShowMemoEntry {
  // Never serialize the checkpoint evidence to the display cache.
  const effective: EffectiveEpisodes = { ids: output.effective.ids, complete: output.effective.complete, matches: [] };
  return { key: key, from: from, output: { effective: effective, sections: output.sections,
    source: output.source, validUntil: output.validUntil } };
}
export function encodePersistedProjection(scope: string, entries: Map<string, ShowMemoEntry>): string {
  const rows: PersistedShowEntry[] = [];
  entries.forEach((entry: ShowMemoEntry, id: string) => { rows.push({ id: id, entry: entry }); });
  const payload: PersistedProjection = { schema: 1, scope: scope, entries: rows };
  return JSON.stringify(payload);
}
