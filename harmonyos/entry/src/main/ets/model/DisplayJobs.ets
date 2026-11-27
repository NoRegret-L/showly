// Independent read-model dependencies, not synchronization revisions.
export class DisplayRevisions {
  show: number = 0;
  movie: number = 0;
  collection: number = 0;
  showsChanged(): void { this.show++; this.collection++; }
  moviesChanged(): void { this.movie++; this.collection++; }
  collectionChanged(): void { this.collection++; }
  reset(): void { this.show++; this.movie++; this.collection++; }
}
interface JobEntry { key: string; token: number; }
// One latest request per logical result. Old completion cannot clear a newer
// request or publish into a changed account/route.
export class LatestDisplayJobs {
  private serial: number = 0;
  private entries: Map<string,JobEntry> = new Map<string,JobEntry>();
  begin(slot: string, key: string): number {
    if (this.entries.get(slot)?.key === key) { return 0; }
    const token = ++this.serial;
    this.entries.set(slot,{key:key,token:token});
    return token;
  }
  current(slot: string, token: number): boolean { return this.entries.get(slot)?.token === token; }
  pending(slot: string): boolean { return this.entries.has(slot); }
  finish(slot: string, token: number): boolean {
    if (!this.current(slot,token)) { return false; }
    this.entries.delete(slot); return true;
  }
  clear(): void { this.entries.clear(); }
}
