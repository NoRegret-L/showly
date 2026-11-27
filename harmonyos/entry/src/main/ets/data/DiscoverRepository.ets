import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DiscoverRead, DiscoverStorage } from '../model/DiscoverRead';
import { TraktDiscoverTransport } from './TraktDiscover';
class DiscoverDisk implements DiscoverStorage {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db=db; }
  async read(key: string): Promise<string> {
    const result = await this.db.querySql('SELECT payload FROM discover_feed WHERE feed_key=?',[key]);
    try { return result.goToFirstRow() ? result.getString(0) : ''; } finally { result.close(); }
  }
  async write(key: string, raw: string): Promise<void> {
    await this.db.executeSql('INSERT OR REPLACE INTO discover_feed(feed_key,payload) VALUES (?,?)',[key,raw]);
  }
}
class DiscoverMemoryFallback implements DiscoverStorage {
  private values: Map<string,string> = new Map<string,string>();
  async read(key: string): Promise<string> { return this.values.get(key) ?? ''; }
  async write(key: string, raw: string): Promise<void> { this.values.set(key,raw); }
}
export async function openDiscover(context: common.UIAbilityContext): Promise<DiscoverRead> {
  try {
    const db = await relationalStore.getRdbStore(context,{name:'showly_discover.db',securityLevel:relationalStore.SecurityLevel.S1});
    await db.executeSql('CREATE TABLE IF NOT EXISTS discover_feed (feed_key TEXT PRIMARY KEY,payload TEXT NOT NULL)');
    return new DiscoverRead(new DiscoverDisk(db),new TraktDiscoverTransport());
  } catch (error) { return new DiscoverRead(new DiscoverMemoryFallback(),new TraktDiscoverTransport()); }
}
