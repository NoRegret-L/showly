import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { CommonEntry, CommonUpdate, commonId } from '../model/ThreeWay';
import { MediaRecord, MediaSnapshot, migrateLegacy, validateMediaRecords, setMediaIntent } from '../model/MediaState';
import { TitleChange, TitleIntent, TitleConsent, autoEligible, titleValue } from '../model/TitleQuickState';

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
    await db.executeSql("CREATE TABLE IF NOT EXISTS sync_common_state (account_uuid TEXT NOT NULL, domain TEXT NOT NULL CHECK(domain IN ('movie','watchlist')), payload TEXT NOT NULL, PRIMARY KEY(account_uuid,domain))");
    await db.executeSql('CREATE TABLE IF NOT EXISTS title_quick_consent (slot INTEGER PRIMARY KEY CHECK(slot=1), account_uuid TEXT NOT NULL, client_id TEXT NOT NULL, epoch INTEGER NOT NULL, enabled INTEGER NOT NULL)');
    await db.executeSql("CREATE TABLE IF NOT EXISTS title_intent (seq INTEGER PRIMARY KEY AUTOINCREMENT, account_uuid TEXT NOT NULL, domain TEXT NOT NULL CHECK(domain IN ('movie','watchlist')), media_id TEXT NOT NULL, value TEXT NOT NULL CHECK(value IN ('yes','no')), epoch INTEGER NOT NULL, operation_seq INTEGER NOT NULL, watched_at TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('open','review','settled')), UNIQUE(account_uuid,domain,media_id))");
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

  async commonStates(uuid: string, domain: string): Promise<Map<string, CommonEntry>> {
    if (!uuid || (domain !== 'movie' && domain !== 'watchlist')) { throw new Error('Invalid baseline scope'); }
    const rows = await this.db.querySql('SELECT payload FROM sync_common_state WHERE account_uuid=? AND domain=?', [uuid, domain]);
    const result: Map<string, CommonEntry> = new Map<string, CommonEntry>();
    try {
      if (!rows.goToFirstRow()) { return result; }
      const entries = JSON.parse(rows.getString(0)) as CommonEntry[];
      if (!Array.isArray(entries)) { throw new Error('Invalid common baseline'); }
      for (const entry of entries) {
        if (!entry || typeof entry.id !== 'string' || !commonId(domain, entry.id) ||
            typeof entry.value !== 'boolean' || typeof entry.activity !== 'string' || !entry.activity ||
            result.has(entry.id)) { throw new Error('Invalid common baseline entry'); }
        result.set(entry.id, entry);
      }
      return result;
    } finally { rows.close(); }
  }

  async saveCommonStates(uuid: string, domain: string, activity: string, updates: CommonUpdate[]): Promise<number> {
    if (typeof activity !== 'string' || !activity) { throw new Error('Missing baseline revision'); }
    const entries = await this.commonStates(uuid, domain);
    const seen: Set<string> = new Set<string>();
    for (const update of updates) {
      if (!commonId(domain, update.id) || typeof update.value !== 'boolean' || seen.has(update.id)) {
        throw new Error('Invalid baseline update');
      }
      seen.add(update.id);
      entries.set(update.id, { id: update.id, value: update.value, activity: activity });
    }
    if (!updates.length) { return 0; }
    // Single atomic row; unrelated or still divergent entries are retained.
    const payload = JSON.stringify(Array.from(entries.values()));
    await this.db.executeSql('INSERT OR REPLACE INTO sync_common_state(account_uuid,domain,payload) VALUES(?,?,?)',
      [uuid, domain, payload]);
    const verified = await this.commonStates(uuid, domain);
    if (JSON.stringify(Array.from(verified.values())) !== payload) { throw new Error('Baseline verification failed'); }
    return updates.length;
  }

  // The local decision and its new common baseline commit together. Existing
  // operation/response evidence remains untouched.
  async adoptRemote(uuid: string, domain: string, id: string, value: boolean, activity: string): Promise<MediaRecord[]> {
    const current = await this.load();
    const record = current.find((row: MediaRecord) => row.media.id === id);
    if (!record || (await this.latestOperation(uuid, domain, id))?.state === 'pending') {
      throw new Error('Title missing or pending operation');
    }
    const next = setMediaIntent(current, record.media, domain, value ? 'yes' : 'no');
    this.db.beginTransaction();
    try {
      const saved = await this.save(next);
      await this.saveCommonStates(uuid, domain, activity, [{ id: id, value: value }]);
      this.db.commit();
      return saved;
    } catch (error) {
      this.db.rollBack();
      throw new Error('Title adoption transaction failed');
    }
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
  async titleConsent(): Promise<TitleConsent | undefined> {
    const rows = await this.db.querySql('SELECT account_uuid,client_id,epoch FROM title_quick_consent WHERE slot=1 AND enabled=1');
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      const uuid = rows.getString(0), clientId = rows.getString(1), epoch = rows.getLong(2);
      if (!uuid || !clientId || !Number.isSafeInteger(epoch) || epoch <= 0) { throw new Error('Invalid title consent'); }
      return { uuid: uuid, clientId: clientId, epoch: epoch };
    } finally { rows.close(); }
  }

  async setTitleConsent(uuid: string, clientId: string, enabled: boolean): Promise<TitleConsent | undefined> {
    if (!enabled) {
      await this.db.executeSql('UPDATE title_quick_consent SET enabled=0 WHERE slot=1');
      return undefined;
    }
    if (!uuid || !clientId) { throw new Error('Invalid consent scope'); }
    const previous = await this.db.querySql('SELECT epoch FROM title_quick_consent WHERE slot=1');
    let epoch = 1;
    try { if (previous.goToFirstRow()) { epoch = previous.getLong(0) + 1; } } finally { previous.close(); }
    if (!Number.isSafeInteger(epoch) || epoch <= 0) { throw new Error('Invalid consent epoch'); }
    await this.db.executeSql('INSERT OR REPLACE INTO title_quick_consent(slot,account_uuid,client_id,epoch,enabled) VALUES(1,?,?,?,1)',
      [uuid, clientId, epoch]);
    return await this.titleConsent();
  }

  async titleIntents(uuid: string): Promise<TitleIntent[]> {
    if (!uuid) { throw new Error('Invalid title intent scope'); }
    const rows = await this.db.querySql('SELECT seq,media_id,domain,value,epoch,operation_seq,watched_at,state FROM title_intent WHERE account_uuid=? ORDER BY seq', [uuid]);
    const result: TitleIntent[] = [];
    try {
      while (rows.goToNextRow()) {
        const item: TitleIntent = { seq: rows.getLong(0), id: rows.getString(1), domain: rows.getString(2),
          value: rows.getString(3), epoch: rows.getLong(4), operationSeq: rows.getLong(5), watchedAt: rows.getString(6), state: rows.getString(7) };
        if (!commonId(item.domain, item.id) || item.domain === 'episode' || !Number.isSafeInteger(item.seq) ||
            item.seq <= 0 || !Number.isSafeInteger(item.epoch) || item.epoch < 0 ||
            !Number.isSafeInteger(item.operationSeq) || item.operationSeq < 0 ||
            !['yes','no'].includes(item.value) || !['open','review','settled'].includes(item.state) ||
            !Number.isFinite(Date.parse(item.watchedAt))) { throw new Error('Invalid title intent'); }
        result.push(item);
      }
      return result;
    } finally { rows.close(); }
  }

  // Explicit feature action and its authorization provenance commit together.
  // No implicit queue from imports, restore, legacy records or enabling consent.
  async saveTitleEdit(records: MediaRecord[], changes: TitleChange[], uuid: string, clientId: string,
    watchedAt: string, allowAuto: boolean): Promise<MediaRecord[]> {
    if (!uuid || !changes.length || !Number.isFinite(Date.parse(watchedAt))) { throw new Error('Invalid title edit'); }
    const consent = allowAuto ? await this.titleConsent() : undefined;
    const epoch = consent?.uuid === uuid && consent.clientId === clientId ? consent.epoch : 0;
    this.db.beginTransaction();
    try {
      for (const change of changes) {
        const record = records.find((row: MediaRecord) => row.media.id === change.id);
        if (!record || !commonId(change.domain, change.id) || change.domain === 'episode' ||
            !['yes','no'].includes(change.value) || titleValue(record, change.domain) !== change.value) {
          throw new Error('Invalid title intent');
        }
        const prior = await this.latestOperation(uuid, change.domain, change.id);
        const permitted = epoch > 0 && autoEligible(change.domain, change.value) && prior?.state !== 'pending';
        await this.db.executeSql('INSERT OR REPLACE INTO title_intent(account_uuid,domain,media_id,value,epoch,operation_seq,watched_at,state) VALUES(?,?,?,?,?,?,?,?)',
          [uuid, change.domain, change.id, change.value, permitted ? epoch : 0, prior?.seq ?? 0, watchedAt, permitted ? 'open' : 'review']);
      }
      const saved = await this.save(records);
      this.db.commit();
      return saved;
    } catch (error) { this.db.rollBack(); throw new Error('Title edit transaction failed'); }
  }

  async finishTitleIntent(uuid: string, seq: number, state: string): Promise<void> {
    if (!uuid || !Number.isSafeInteger(seq) || seq <= 0 || !['settled','review'].includes(state)) {
      throw new Error('Invalid title intent result');
    }
    await this.db.executeSql("UPDATE title_intent SET state=? WHERE account_uuid=? AND seq=? AND state<>'settled'",
      [state, uuid, seq]);
  }

  // Confirm the existing operation and its actual verified common value in
  // one transaction. Receipt ownership rules are entirely unchanged.
  async confirmTitleOperation(uuid: string, domain: string, id: string, op: MediaOperation,
    activity: string, receiptId: number, receiptAt: string, message: string): Promise<void> {
    const target = op.action === 'add';
    this.db.beginTransaction();
    try {
      await this.finishOperation(uuid, op.seq, 'verified', receiptId, receiptAt, message);
      const verified = await this.latestOperation(uuid, domain, id);
      if (!verified || verified.seq !== op.seq || verified.state !== 'verified' || verified.historyId !== receiptId) {
        throw new Error('Operation confirmation not persisted');
      }
      const record = (await this.load()).find((row: MediaRecord) => row.media.id === id);
      if (record && titleValue(record, domain) === (target ? 'yes' : 'no')) {
        await this.saveCommonStates(uuid, domain, activity, [{ id: id, value: target }]);
        const intents = await this.titleIntents(uuid);
        const intent = intents.find((row: TitleIntent) => row.domain === domain && row.id === id);
        if (intent && intent.operationSeq < op.seq && intent.value === (target ? 'yes' : 'no')) {
          await this.finishTitleIntent(uuid, intent.seq, 'settled');
        }
      }
      this.db.commit();
    } catch (error) { this.db.rollBack(); throw new Error('Operation confirmation transaction failed'); }
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
