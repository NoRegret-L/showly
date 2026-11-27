import { ProgressSource, ProgressPreferences } from './ProgressRules';

// Read-only memo; it never participates in synchronization eligibility.
export class RevisionMemo<T> {
  private key: string = '';
  private value?: T;
  private from: number = 0;
  private until: number = 0;
  get(key: string, now: number): T | undefined {
    return key === this.key && now >= this.from && now < this.until ? this.value : undefined;
  }
  put(key: string, value: T, from: number, until: number): void {
    this.key = key; this.value = value; this.from = from; this.until = until;
  }
  clear(): void { this.value = undefined; this.key = ''; }
}
export function projectionKey(client: string, uuid: string, generation: number, activity: string,
  revision: number, records: string): string {
  return JSON.stringify([client, uuid, generation, activity, revision, records]);
}
// Preserve the exact boundaries in ProgressRules: entering upcoming window,
// first air, strict aired/new predicates and expiry of the upstream 3-day badge.
export function progressExpiry(sources: ProgressSource[], prefs: ProgressPreferences, now: number): number {
  let until = Number.MAX_SAFE_INTEGER;
  for (const source of sources) {
    for (const item of source.episodes) {
      const air = Date.parse(item.episode.firstAired);
      if (!Number.isFinite(air)) { continue; }
      const boundaries = [air - prefs.days * 86400000, air, air + 1, air + 3 * 86400000];
      for (const boundary of boundaries) {
        if (boundary > now) { until = Math.min(until, boundary); }
      }
    }
  }
  return until;
}
