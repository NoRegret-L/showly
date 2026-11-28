import { SearchRecord, validSearchRecord, publicSearchRecord, SEARCH_RECENTS } from './SearchRules';
import { ReadFlight, ReadCancel, ConsumerReadFlight } from './ReadFlight';
export interface SearchStorage {
  read(scope: string): Promise<SearchRecord[]>;
  write(scope: string,rows: SearchRecord[]): Promise<void>;
  recents(scope: string): Promise<string[]>;
  remember(scope: string,query: string): Promise<void>;
  clear(scope: string): Promise<void>;
}
export interface SearchTransport { read(client: string,query: string,scope?: ReadCancel): Promise<SearchRecord[]>; }
export class SearchRead {
  private store: SearchStorage;
  private transport: SearchTransport;
  private loads: ReadFlight<SearchRecord[]>=new ReadFlight<SearchRecord[]>();
  private flights: ConsumerReadFlight<SearchRecord[]>=new ConsumerReadFlight<SearchRecord[]>();
  private catalogs: Map<string,Map<string,SearchRecord>>=new Map<string,Map<string,SearchRecord>>();
  private snapshots: Map<string,SearchRecord[]>=new Map<string,SearchRecord[]>();
  private writes: Map<string,Promise<void>>=new Map<string,Promise<void>>();
  private historyWrites: Map<string,Promise<void>>=new Map<string,Promise<void>>();
  private controlled: boolean=false;
  private residentScope: string='';
  private residencyVersion: number=0;
  constructor(store: SearchStorage,transport: SearchTransport) { this.store=store; this.transport=transport; }
  setResidentScope(scope: string): void {
    if (this.controlled && scope===this.residentScope) { return; }
    this.controlled=true; this.residentScope=scope; this.releaseCatalogs();
  }
  releaseCatalogs(): void { this.residencyVersion++; this.catalogs.clear(); this.snapshots.clear(); }
  private resident(scope: string,version: number): boolean {
    return version===this.residencyVersion && (!this.controlled || scope===this.residentScope);
  }
  async catalog(scope: string): Promise<SearchRecord[]> {
    if (!scope) { return []; }
    const cached=this.snapshots.get(scope);
    if (cached) { return cached; }
    const version=this.residencyVersion;
    return this.loads.run(JSON.stringify([scope,version]),async (): Promise<SearchRecord[]>=>{
      const current=this.snapshots.get(scope);
      if (current) { return current; }
      const rows=await this.store.read(scope);
      const index=new Map<string,SearchRecord>();
      for (const row of rows) { if (validSearchRecord(row)) { index.set(row.media.id,publicSearchRecord(row.media,row.votes)); } }
      if (this.resident(scope,version)) { this.catalogs.set(scope,index); }
      return this.publishCatalog(scope,index,version);
    });
  }
  private publishCatalog(scope: string,index: Map<string,SearchRecord>,version: number): SearchRecord[] {
    // Stable warm/cold order; the source DAO has no explicit ordering.
    const rows=Array.from(index.values());
    rows.sort((a: SearchRecord,b: SearchRecord)=>a.media.id<b.media.id ? -1 : a.media.id>b.media.id ? 1 : 0);
    if (this.resident(scope,version)) { this.snapshots.set(scope,rows); }
    return rows;
  }
  async rememberCatalog(scope: string,rows: SearchRecord[]): Promise<void> {
    if (!scope || !rows.length) { return; }
    const prior=this.writes.get(scope) ?? Promise.resolve();
    const work=prior.catch((): void=>{}).then(async (): Promise<void>=>{
      const version=this.residencyVersion;
      const rowsBefore=await this.catalog(scope);
      const index=new Map<string,SearchRecord>();
      for (const row of rowsBefore) { index.set(row.media.id,row); }
      const changed: SearchRecord[]=[];
      for (const row of rows) {
        if (!validSearchRecord(row)) { continue; }
        const old=index.get(row.media.id);
        const next=publicSearchRecord(row.media,row.votes || old?.votes || 0);
        if (old && old.media.title===next.media.title && old.media.year===next.media.year && old.votes===next.votes) { continue; }
        changed.push(next);
      }
      if (!changed.length) { return; }
      await this.store.write(scope,changed);
      for (const row of changed) { index.set(row.media.id,row); }
      if (this.resident(scope,version)) { this.catalogs.set(scope,index); this.publishCatalog(scope,index,version); }
      else { this.catalogs.delete(scope); this.snapshots.delete(scope); }
    });
    this.writes.set(scope,work);
    try { await work; }
    finally { if (this.writes.get(scope)===work) { this.writes.delete(scope); } }
  }
  async remote(client: string,query: string,consumer?: ReadCancel): Promise<SearchRecord[]> {
    return this.flights.run(JSON.stringify([client,query.trim()]),(scope: ReadCancel)=>this.transport.read(client,query.trim(),scope),consumer);
  }
  private async history(scope: string,work: ()=>Promise<void>): Promise<void> {
    if (!scope) { return; }
    const prior=this.historyWrites.get(scope) ?? Promise.resolve();
    const task=prior.catch((): void=>{}).then(work);
    this.historyWrites.set(scope,task);
    try { await task; }
    finally { if (this.historyWrites.get(scope)===task) { this.historyWrites.delete(scope); } }
  }
  async recents(scope: string): Promise<string[]> {
    if (!scope) { return []; }
    await (this.historyWrites.get(scope) ?? Promise.resolve()).catch((): void=>{});
    return Array.from(new Set<string>(await this.store.recents(scope))).slice(0,SEARCH_RECENTS);
  }
  async remember(scope: string,query: string): Promise<void> {
    const text=query.trim();
    if (text) { await this.history(scope,()=>this.store.remember(scope,text)); }
  }
  async clear(scope: string): Promise<void> { await this.history(scope,()=>this.store.clear(scope)); }
}
