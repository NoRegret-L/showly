import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { MediaRecord, MediaSnapshot, migrateLegacy, validateMediaRecords } from '../model/MediaState';

// A single atomic row stores the ordered catalog and the two independent
// intent domains. The original Preferences store is never modified.
export interface MediaOperation {
  seq: number;
  action: string;
  state: string;
  historyId: number;
  watchedAt: string;
  message: string;
}
export interface PendingMediaTarget {
  domain: string;
  id: string;
}
export interface MediaResponseEvidence {
  httpStatus: number;
  accepted: boolean;
  requestedAt: string;
}
export interface MediaOperationLog {
  domain: string;
  mediaId: string;
  action: string;
  state: string;
  message: string;
  createdAt: number;
}

export class MediaStore {
  private db: relationalStore.RdbStore;
  constructor(db: relationalStore.RdbStore) { this.db = db; }

  static async open(context: common.UIAbilityContext, legacy: Media[]): Promise<MediaStore> {
    const db = await relationalStore.getRdbStore(context, {
      name: 'showly_media_v2.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    await db.executeSql('CREATE TABLE IF NOT EXISTS media_snapshot (slot INTEGER PRIMARY KEY CHECK(slot=1), payload TEXT NOT NULL, legacy_backup TEXT NOT NULL)');
    await db.executeSql("CREATE TABLE IF NOT EXISTS media_operation (seq INTEGER PRIMARY KEY AUTOINCREMENT, account_uuid TEXT NOT NULL, domain TEXT NOT NULL CHECK(domain IN ('movie','watchlist')), media_id TEXT NOT NULL, action TEXT NOT NULL CHECK(action IN ('add','remove')), state TEXT NOT NULL CHECK(state IN ('pending','verified','unsent')), history_id INTEGER NOT NULL DEFAULT 0, watched_at TEXT NOT NULL DEFAULT '', message TEXT NOT NULL, created_at INTEGER NOT NULL)");
    await db.executeSql('CREATE INDEX IF NOT EXISTS media_operation_lookup ON media_operation(account_uuid,domain,media_id,seq)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS media_response_evidence (seq INTEGER PRIMARY KEY, account_uuid TEXT NOT NULL, requested_at TEXT NOT NULL, http_status INTEGER NOT NULL, accepted INTEGER NOT NULL CHECK(accepted IN (0,1)))');
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
  async latestOperation(uuid: string, domain: string, id: string): Promise<MediaOperation | undefined> {
    const rows = await this.db.querySql("SELECT seq,action,state,history_id,watched_at,message FROM media_operation WHERE account_uuid=? AND domain=? AND media_id=? AND state<>'unsent' ORDER BY seq DESC LIMIT 1", [uuid, domain, id]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const op: MediaOperation = { seq: rows.getLong(0), action: rows.getString(1), state: rows.getString(2),
        historyId: rows.getLong(3), watchedAt: rows.getString(4), message: rows.getString(5) };
      if (!Number.isSafeInteger(op.seq) || op.seq <= 0 ||
          (op.action !== 'add' && op.action !== 'remove') ||
          (op.state !== 'pending' && op.state !== 'verified') ||
          !Number.isSafeInteger(op.historyId) || op.historyId < 0 ||
          (op.historyId > 0 && !Number.isFinite(Date.parse(op.watchedAt)))) {
        throw new Error('Invalid operation journal');
      }
      return op;
    } finally { rows.close(); }
  }

  // Only one live sync task may reserve. The new row survives crashes and
  // prevents replay until a positive readback establishes the result.
  async reserveOperation(uuid: string, domain: string, id: string, action: string,
    historyId: number, watchedAt: string): Promise<number> {
    if (!uuid || (domain !== 'movie' && domain !== 'watchlist') ||
        !/^(movie|show):[1-9][0-9]*$/.test(id) ||
        (domain === 'movie' && !id.startsWith('movie:')) ||
        !Number.isSafeInteger(Number(id.substring(id.indexOf(':') + 1))) ||
        (action !== 'add' && action !== 'remove') || !Number.isSafeInteger(historyId) || historyId < 0 ||
        (historyId > 0 && !Number.isFinite(Date.parse(watchedAt)))) { throw new Error('Invalid operation'); }
    const previous = await this.latestOperation(uuid, domain, id);
    if (previous?.state === 'pending') { throw new Error('Uncertain prior operation'); }
    await this.db.executeSql("INSERT INTO media_operation(account_uuid,domain,media_id,action,state,history_id,watched_at,message,created_at) VALUES(?,?,?,?,'pending',?,?,?,?)",
      [uuid, domain, id, action, historyId, watchedAt, '已保留操作凭证；结果未知时禁止重发', Date.now()]);
    const reserved = await this.latestOperation(uuid, domain, id);
    if (!reserved || reserved.state !== 'pending' || reserved.action !== action ||
        reserved.seq === previous?.seq) { throw new Error('Reservation verification failed'); }
    return reserved.seq;
  }

  async finishOperation(uuid: string, seq: number, state: string, historyId: number,
    watchedAt: string, message: string): Promise<void> {
    if ((state !== 'verified' && state !== 'unsent' && state !== 'pending') ||
        !Number.isSafeInteger(seq) || seq <= 0 || !Number.isSafeInteger(historyId) || historyId < 0 ||
        (historyId > 0 && !Number.isFinite(Date.parse(watchedAt)))) { throw new Error('Invalid operation result'); }
    await this.db.executeSql("UPDATE media_operation SET state=?,history_id=?,watched_at=?,message=? WHERE account_uuid=? AND seq=? AND state='pending'",
      [state, historyId, watchedAt, message, uuid, seq]);
  }

  async pendingTargets(uuid: string): Promise<PendingMediaTarget[]> {
    const rows = await this.db.querySql("SELECT domain,media_id FROM media_operation WHERE account_uuid=? AND state='pending' ORDER BY seq", [uuid]);
    const result: PendingMediaTarget[] = [];
    try {
      while (rows.goToNextRow()) {
        const domain = rows.getString(0);
        const id = rows.getString(1);
        if ((domain !== 'movie' && domain !== 'watchlist') || !/^(movie|show):[1-9][0-9]*$/.test(id) ||
            (domain === 'movie' && !id.startsWith('movie:')) ||
            !Number.isSafeInteger(Number(id.substring(id.indexOf(':') + 1)))) { throw new Error('Invalid pending target'); }
        result.push({ domain: domain, id: id });
      }
    } finally { rows.close(); }
    return result;
  }

  async recordResponse(uuid: string, seq: number, requestedAt: string, httpStatus: number,
    accepted: boolean): Promise<void> {
    if (!Number.isSafeInteger(seq) || seq <= 0 || !Number.isSafeInteger(httpStatus) ||
        httpStatus < 100 || httpStatus > 599 || !Number.isFinite(Date.parse(requestedAt)) ||
        (accepted && httpStatus !== 200 && httpStatus !== 201)) { throw new Error('Invalid response evidence'); }
    await this.db.executeSql('INSERT INTO media_response_evidence(seq,account_uuid,requested_at,http_status,accepted) VALUES(?,?,?,?,?)',
      [seq, uuid, requestedAt, httpStatus, accepted ? 1 : 0]);
  }

  async responseEvidence(uuid: string, seq: number): Promise<MediaResponseEvidence | undefined> {
    const rows = await this.db.querySql('SELECT requested_at,http_status,accepted FROM media_response_evidence WHERE account_uuid=? AND seq=?', [uuid, seq]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const requestedAt = rows.getString(0);
      const httpStatus = rows.getLong(1);
      const accepted = rows.getLong(2);
      if (!Number.isFinite(Date.parse(requestedAt)) || !Number.isSafeInteger(httpStatus) ||
          httpStatus < 100 || httpStatus > 599 || (accepted !== 0 && accepted !== 1) ||
          (accepted === 1 && httpStatus !== 200 && httpStatus !== 201)) { throw new Error('Invalid response evidence'); }
      return { requestedAt: requestedAt, httpStatus: httpStatus, accepted: accepted === 1 };
    } finally { rows.close(); }
  }

  async operationLogs(uuid: string): Promise<string[]> {
    const rows = await this.db.querySql('SELECT o.domain,o.media_id,o.action,o.state,o.message,o.created_at,e.http_status,e.accepted FROM media_operation o LEFT JOIN media_response_evidence e ON e.seq=o.seq AND e.account_uuid=o.account_uuid WHERE o.account_uuid=? ORDER BY o.seq DESC LIMIT 12', [uuid]);
    const result: string[] = [];
    try {
      while (rows.goToNextRow()) {
        result.push(new Date(rows.getLong(5)).toLocaleString() + ' · ' +
          (rows.getString(0) === 'movie' ? '电影观看' : '待看') + ' · ' + rows.getString(1) + ' · ' +
          (rows.getString(2) === 'add' ? '新增' : '移除') + ' · ' + rows.getString(4) +
          (rows.isColumnNull(6) ? '' : ' · 响应证据 HTTP ' + rows.getLong(6) + (rows.getLong(7) === 1 ? ' / 新增计数已验证' : '')));
      }
    } finally { rows.close(); }
    return result;
  }

}
