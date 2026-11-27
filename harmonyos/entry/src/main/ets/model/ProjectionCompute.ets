import { AiredSummary, summarizeAired } from './BatchEpisodeRead';
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
  summary?: AiredSummary;
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
    validUntil: validUntil, summary:effective.complete ? summarizeAired(input.full,effective.ids,input.now) : undefined };
}

export interface ShowMemoEntry {
  key: string;
  from: number;
  output: ProjectionOutput;
  catalogKey?: string;
  diskKnown?: boolean;
}
interface ProjectionSignature { input:ProjectionInput; key:string; }
// Cloud observations and derived store state are published by replacement.
// Reference equality applies only to the immutable remote snapshot. Other
// fields are compared exactly, including ordered decisions and evidence.
function sameSignatureInput(a:ProjectionInput,b:ProjectionInput):boolean {
  if(a.remote!==b.remote||a.cloudActive!==b.cloudActive||a.localIds.length!==b.localIds.length||
    a.decisions.length!==b.decisions.length||a.timed.length!==b.timed.length||a.checkpoints.length!==b.checkpoints.length||a.common.length!==b.common.length){return false;}
  for(let i=0;i<a.localIds.length;i++){if(a.localIds[i]!==b.localIds[i]){return false;}}
  for(let i=0;i<a.decisions.length;i++){const x=a.decisions[i],y=b.decisions[i];if(x.episodeId!==y.episodeId||x.seq!==y.seq||x.watched!==y.watched){return false;}}
  for(let i=0;i<a.timed.length;i++){const x=a.timed[i],y=b.timed[i];if(x.episodeId!==y.episodeId||x.seq!==y.seq||x.watched!==y.watched||x.changedAt!==y.changedAt){return false;}}
  for(let i=0;i<a.checkpoints.length;i++){const x=a.checkpoints[i],y=b.checkpoints[i];if(x.id!==y.id||x.seq!==y.seq||x.watched!==y.watched){return false;}}
  for(let i=0;i<a.common.length;i++){const x=a.common[i],y=b.common[i];if(x.id!==y.id||x.value!==y.value||x.activity!==y.activity){return false;}}
  return true;
}
// Exact input equality, no heuristic threshold. Only in-memory read models.
export class ShowProjectionCache {
  private scope: string = '';
  private entries: Map<string, ShowMemoEntry> = new Map<string, ShowMemoEntry>();
  private signatures: Map<string,ProjectionSignature>=new Map<string,ProjectionSignature>();
  begin(scope: string): void {
    if (this.scope !== scope) { this.clear(); this.scope = scope; }
  }
  clear(): void { this.scope = ''; this.entries.clear(); this.signatures.clear(); }
  stateKey(input:ProjectionInput):string {
    const id=input.full.media.id,old=this.signatures.get(id);
    if(old && sameSignatureInput(old.input,input)){return old.key;}
    const key=showProjectionStateKey(input);this.signatures.set(id,{input:input,key:key});return key;
  }
  get(id: string, key: string, now: number, catalogKey: string = ''): ProjectionOutput | undefined {
    const entry = this.entries.get(id);
    return entry && entry.key === key && (entry.catalogKey ?? '') === catalogKey && now >= entry.from && now < entry.output.validUntil ? entry.output : undefined;
  }
  diskKnown(id: string,key: string,now: number,catalogKey: string): boolean {
    return !!this.get(id,key,now,catalogKey) && this.entries.get(id)?.diskKnown===true;
  }
  markDiskKnown(id: string,key: string,catalogKey: string): void {
    const row=this.entries.get(id);
    if (row && row.key===key && (row.catalogKey??'')===catalogKey) { row.diskKnown=true; }
  }
  put(id: string, key: string, now: number, output: ProjectionOutput, catalogKey: string = ''): void {
    this.entries.set(id, { key: key, from: now, output: output, catalogKey: catalogKey });
  }
  retain(ids: Set<string>): void {
    for (const id of this.entries.keys()) { if (!ids.has(id)) { this.entries.delete(id); } }
    for (const id of this.signatures.keys()) { if (!ids.has(id)) { this.signatures.delete(id); } }
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
    const ep = episodes[i];
    // Compare every field consumed by the resolver/renderer, without
    // allocating two JSON strings per episode. The full input key is still exact.
    if (!row || !row.episode || row.episode.id !== ep.id || row.episode.season !== ep.season ||
        row.episode.number !== ep.number || row.episode.title !== ep.title ||
        row.episode.firstAired !== ep.firstAired || row.watched !== watched.has(ep.id) ||
        !Number.isFinite(row.watchedAt)) { return undefined; }
  }
  // Disk rows are untrusted derived data. Reconstruct the summary once from
  // validated episode inputs, not from a persisted summary supplied by disk.
  out.summary=summarizeAired(input.full,out.effective.ids,input.now);
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

// Compare the original schedule payload separately; only per-show state is serialized here.
export function showProjectionStateKey(input: ProjectionInput): string {
  return JSON.stringify([input.remote, input.cloudActive, input.localIds,
    input.decisions, input.timed, input.checkpoints, input.common]);
}
export function computeProjectionBatch(inputs: ProjectionInput[]): ProjectionOutput[] {
  return inputs.map((input: ProjectionInput): ProjectionOutput => computeProjection(input));
}
