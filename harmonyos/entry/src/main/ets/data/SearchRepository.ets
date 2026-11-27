import { relationalStore, ValuesBucket } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SearchRead, SearchStorage, SearchTransport } from '../model/SearchRead';
import { SearchRecord, validSearchRecord, SEARCH_RECENTS } from '../model/SearchRules';
import { searchTrakt } from './TraktSearch';
class DiskSearch implements SearchStorage {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db=db; }
  async read(scope: string): Promise<SearchRecord[]> {
    const result=await this.db.querySql('SELECT payload FROM search_catalog WHERE scope=? ORDER BY id',[scope]);
    const rows: SearchRecord[]=[];
    try {
      while (result.goToNextRow()) {
        try { const row=JSON.parse(result.getString(0)) as SearchRecord; if (validSearchRecord(row)) { rows.push(row); } } catch (error) {}
      }
    } finally { result.close(); }
    return rows;
  }
  async write(scope: string,rows: SearchRecord[]): Promise<void> {
    const values: ValuesBucket[]=rows.map((row: SearchRecord): ValuesBucket=>({scope:scope,id:row.media.id,payload:JSON.stringify(row)}));
    if (values.length && await this.db.batchInsert('search_catalog',values)!==values.length) { throw new Error('Search index write failed'); }
  }
  async recents(scope: string): Promise<string[]> {
    const result=await this.db.querySql('SELECT query FROM search_recent WHERE scope=? ORDER BY seq DESC LIMIT ?',[scope,SEARCH_RECENTS]);
    const rows: string[]=[];
    try { while (result.goToNextRow()) { rows.push(result.getString(0)); } } finally { result.close(); }
    return rows;
  }
  async remember(scope: string,query: string): Promise<void> {
    await this.db.executeSql('INSERT INTO search_recent(scope,query) VALUES (?,?)',[scope,query]);
    await this.db.executeSql('DELETE FROM search_recent WHERE scope=? AND seq NOT IN (SELECT seq FROM search_recent WHERE scope=? ORDER BY seq DESC LIMIT ?)',[scope,scope,SEARCH_RECENTS]);
  }
  async clear(scope: string): Promise<void> { await this.db.executeSql('DELETE FROM search_recent WHERE scope=?',[scope]); }
}
class MemorySearch implements SearchStorage {
  private catalog: Map<string,Map<string,SearchRecord>>=new Map<string,Map<string,SearchRecord>>();
  private history: Map<string,string[]>=new Map<string,string[]>();
  async read(scope: string): Promise<SearchRecord[]> {
    const index=this.catalog.get(scope); return index ? Array.from(index.values()) : [];
  }
  async write(scope: string,rows: SearchRecord[]): Promise<void> {
    const index=this.catalog.get(scope) ?? new Map<string,SearchRecord>();
    for (const row of rows) { index.set(row.media.id,row); }
    this.catalog.set(scope,index);
  }
  async recents(scope: string): Promise<string[]> { return this.history.get(scope) ?? []; }
  async remember(scope: string,query: string): Promise<void> { this.history.set(scope,[query,...(this.history.get(scope) ?? [])].slice(0,SEARCH_RECENTS)); }
  async clear(scope: string): Promise<void> { this.history.delete(scope); }
}
class TraktSearchTransport implements SearchTransport {
  async read(client: string,query: string): Promise<SearchRecord[]> { return searchTrakt(query,client); }
}
export async function openSearch(context: common.UIAbilityContext): Promise<SearchRead> {
  try {
    const db=await relationalStore.getRdbStore(context,{name:'showly_search.db',securityLevel:relationalStore.SecurityLevel.S1});
    await db.executeSql('CREATE TABLE IF NOT EXISTS search_catalog (scope TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS search_recent (seq INTEGER PRIMARY KEY AUTOINCREMENT,scope TEXT NOT NULL,query TEXT NOT NULL)');
    await db.executeSql('CREATE INDEX IF NOT EXISTS search_recent_scope ON search_recent(scope,seq)');
    return new SearchRead(new DiskSearch(db),new TraktSearchTransport());
  } catch (error) { return new SearchRead(new MemorySearch(),new TraktSearchTransport()); }
}
