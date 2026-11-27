import { FullEpisodeCatalog, validateFullCatalog } from './ShowCatalog';
import { ProjectionInput, ProjectionOutput, diskProjectionAllowed, readPersistedShow, persistShow } from './ProjectionCompute';

// Historical SQLite default host-parameter limit, not a tuning knob.
export const SQLITE_BIND_LIMIT: number = 999;
export function bindPlaceholders(count: number): string {
  return new Array<string>(count).fill('?').join(',');
}
interface ScheduleEntry {
  raw: string;
  value: FullEpisodeCatalog;
}
export class ScheduleReadCache {
  private entries: Map<string, ScheduleEntry> = new Map<string, ScheduleEntry>();
  private parses: number = 0;
  parseCount(): number { return this.parses; }
  read(id: string, raw: string): FullEpisodeCatalog {
    const old = this.entries.get(id);
    if (old && old.raw === raw) { return old.value; }
    this.parses++;
    const full = JSON.parse(raw) as FullEpisodeCatalog;
    validateFullCatalog(full,id);
    this.entries.set(id,{ raw: raw, value: full });
    return full;
  }
  key(full: FullEpisodeCatalog): string {
    const old = this.entries.get(full.media.id);
    return old && old.value === full ? old.raw : JSON.stringify(full);
  }
  retain(ids: Set<string>): void {
    for (const id of this.entries.keys()) { if (!ids.has(id)) { this.entries.delete(id); } }
  }
}
export interface IndexedProjectionRow {
  id: string;
  catalogKey: string;
  key: string;
  from: number;
  until: number;
  payload: string;
}
export function indexedProjectionMatches(row: IndexedProjectionRow | undefined, input: ProjectionInput,
  catalogKey: string, key: string): boolean {
  return !!row && row.id === input.full.media.id && row.catalogKey === catalogKey && row.key === key &&
    Number.isSafeInteger(row.from) && Number.isSafeInteger(row.until) &&
    input.now >= row.from && input.now < row.until && diskProjectionAllowed(input);
}
export function decodeIndexedProjection(row: IndexedProjectionRow, input: ProjectionInput,
  catalogKey: string, key: string): ProjectionOutput | undefined {
  if (!indexedProjectionMatches(row,input,catalogKey,key)) { return undefined; }
  try {
    const output = JSON.parse(row.payload) as ProjectionOutput;
    if (!output || output.validUntil !== row.until) { return undefined; }
    return readPersistedShow({ key: key, from: row.from, output: output },input,key);
  } catch (error) { return undefined; }
}
export function encodeIndexedProjection(input: ProjectionInput, catalogKey: string, key: string,
  output: ProjectionOutput): IndexedProjectionRow {
  const entry = persistShow(key,input.now,output);
  return { id: input.full.media.id, catalogKey: catalogKey, key: key, from: entry.from,
    until: output.validUntil, payload: JSON.stringify(entry.output) };
}
