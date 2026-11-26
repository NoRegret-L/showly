import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { MediaRecord, MediaSnapshot, migrateLegacy, validateMediaRecords } from '../model/MediaState';

// A single atomic row stores the ordered catalog and the two independent
// intent domains. The original Preferences store is never modified.
export class MediaStore {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db = db; }

  static async open(context: common.UIAbilityContext, legacy: Media[]): Promise<MediaStore> {
    const db = await relationalStore.getRdbStore(context, {
      name: 'showly_media_v2.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    await db.executeSql('CREATE TABLE IF NOT EXISTS media_snapshot (slot INTEGER PRIMARY KEY CHECK(slot=1), payload TEXT NOT NULL, legacy_backup TEXT NOT NULL)');
    const store = new MediaStore(db);
    const existing = await store.readOptional();
    if (existing !== undefined) { return store; }
    const records = migrateLegacy(legacy);
    validateMediaRecords(records);
    const snapshot: MediaSnapshot = { schema: 2, records: records };
    // Atomic initial insertion. An existing/corrupt snapshot is not overwritten.
    await db.executeSql('INSERT INTO media_snapshot(slot,payload,legacy_backup) VALUES(1,?,?)',
      [JSON.stringify(snapshot), JSON.stringify(legacy)]);
    const verified = await store.load();
    if (JSON.stringify(verified) !== JSON.stringify(records)) { throw new Error('Migration verification failed'); }
    return store;
  }

  private async readOptional(): Promise<MediaRecord[] | undefined> {
    const rows = await this.db.querySql('SELECT payload FROM media_snapshot WHERE slot=1');
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const data = JSON.parse(rows.getString(0)) as MediaSnapshot;
      if (data.schema !== 2) { throw new Error('Unknown media schema'); }
      validateMediaRecords(data.records);
      return data.records;
    } finally { rows.close(); }
  }

  async load(): Promise<MediaRecord[]> {
    const records = await this.readOptional();
    if (records === undefined) { throw new Error('Missing media snapshot'); }
    return records;
  }

  async save(records: MediaRecord[]): Promise<MediaRecord[]> {
    validateMediaRecords(records);
    const snapshot: MediaSnapshot = { schema: 2, records: records };
    await this.db.executeSql('UPDATE media_snapshot SET payload=? WHERE slot=1', [JSON.stringify(snapshot)]);
    const verified = await this.load();
    if (JSON.stringify(verified) !== JSON.stringify(records)) { throw new Error('Media write verification failed'); }
    return verified;
  }
}
