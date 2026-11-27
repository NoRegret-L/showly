import { ReadCancel } from './ReadFlight';
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
interface JobEntry { key: string; token: number; consumer: ReadCancel; }
// One latest request per logical result. Old completion cannot clear a newer
// request or publish into a changed account/route.
export class LatestDisplayJobs {
  private serial: number = 0;
  private entries: Map<string,JobEntry> = new Map<string,JobEntry>();
  begin(slot: string, key: string): number {
    if (this.entries.get(slot)?.key === key) { return 0; }
    this.entries.get(slot)?.consumer.cancel();
    const token = ++this.serial;
    this.entries.set(slot,{key:key,token:token,consumer:new ReadCancel()});
    return token;
  }
  current(slot: string, token: number): boolean { return this.entries.get(slot)?.token === token; }
  consumer(slot: string, token: number): ReadCancel {
    const entry=this.entries.get(slot);
    if (entry && entry.token===token) { return entry.consumer; }
    const stopped=new ReadCancel(); stopped.cancel(); return stopped;
  }
  pending(slot: string): boolean { return this.entries.has(slot); }
  matches(slot: string, key: string): boolean { return this.entries.get(slot)?.key === key; }
  finish(slot: string, token: number): boolean {
    if (!this.current(slot,token)) { return false; }
    this.entries.delete(slot); return true;
  }
  clear(): void { for (const entry of this.entries.values()) { entry.consumer.cancel(); } this.entries.clear(); }
}
