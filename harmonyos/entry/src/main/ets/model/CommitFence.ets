// Separate invalidation epoch (including rollback) from durable commit version.
// A failed non-atomic operation is uncertain and invalidates reusable reads
// without pretending that a successful commit occurred.
export class CommitFence {
  private epoch: number=0;
  private committed: number=0;
  private uncertain: number=0;
  private writing: boolean=false;
  private changed: Set<string>=new Set<string>();
  private global: boolean=false;
  private libraryDirty:Set<string>=new Set<string>();
  private libraryGlobal:boolean=true;
  begin(): number {
    if (this.writing) { throw new Error('Projection write already in progress'); }
    this.writing=true; return ++this.epoch;
  }
  finish(token: number,success: boolean,ids: string[],unknown: boolean=false): void {
    if (!this.writing || token!==this.epoch) { throw new Error('Invalid write token'); }
    if (success) {
      this.committed++;
      if (ids.length===0) { this.global=true; }
      for (const id of ids) { this.changed.add(id); }
    } else if (unknown) { this.uncertain++; this.global=true; }
    if ((success && !ids.length) || (!success && unknown)) { this.libraryGlobal=true; this.libraryDirty.clear(); }
    else if (success && !this.libraryGlobal) { for(const id of ids){this.libraryDirty.add(id);} }
    this.writing=false; this.epoch++;
  }
  revision(): number { return this.epoch; }
  version(): number { return this.committed; }
  cacheVersion(): string { return this.committed+':'+this.uncertain; }
  readable(revision: number): boolean { return !this.writing && revision===this.epoch; }
  assertReadable(): number {
    if (this.writing) { throw new Error('Projection write in progress'); }
    return this.epoch;
  }
  changedIds(): string[] { return Array.from(this.changed); }
  globalChanged(): boolean { return this.global; }
  clearChanges(): void { this.changed.clear(); this.global=false; }
  libraryChangedIds():string[]{return Array.from(this.libraryDirty);}
  libraryGlobalChanged():boolean{return this.libraryGlobal;}
  acknowledgeLibrary(revision:number):void{if(this.readable(revision)){this.libraryDirty.clear();this.libraryGlobal=false;}}
}
