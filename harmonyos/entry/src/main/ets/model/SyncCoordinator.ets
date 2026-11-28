// Coalesced wakeups; existing durable journal and receipt stores are authoritative.
export class SyncCoordinator {
  private pending: Set<string> = new Set<string>();
  private revision: number = 0;
  has(lane: string): boolean { return this.pending.has(lane); }
  mark(lane: string, value: boolean): void {
    if (this.has(lane) === value) { return; }
    if (value) { this.pending.add(lane); } else { this.pending.delete(lane); }
    this.revision++;
  }
  version(): number { return this.revision; }
  reset(): void {
    if (this.pending.size > 0) { this.pending.clear(); this.revision++; }
  }
  next(episodes: boolean, media: boolean, observation: boolean, titles: boolean): string {
    if (episodes && this.has('episodes')) { return 'episodes'; }
    if (media && this.has('media')) { return 'media'; }
    if (observation && this.has('observation')) { return 'observation'; }
    if (titles && this.has('titles')) { return 'titles'; }
    return '';
  }
}
// Process-wide owner. A page is a consumer, not the owner of pending intents.
// Still no cross-process or background authorization.
export class SyncService {
  readonly coordinator: SyncCoordinator = new SyncCoordinator();
  private active: string = '';
  private serial: number = 0;
  acquire(scope: string): number {
    if (!scope || this.active) { return 0; }
    this.active = scope;
    this.serial++;
    return this.serial;
  }
  release(ticket: number): void {
    if (ticket === this.serial) { this.active = ''; }
  }
  busy(): boolean { return this.active !== ''; }
}
export const syncService = new SyncService();
export function queueIdentity(episodeId: number, seq: number): string {
  return episodeId + ':' + seq;
}
