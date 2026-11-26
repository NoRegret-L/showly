import { Media } from '../model/Media';
import { MediaRecord, isTraktMedia } from '../model/MediaState';
import { MediaStore, MediaOperation } from './MediaStore';
import { EpisodeStore } from './EpisodeStore';
import { SyncAccount, readSyncAccount } from './TraktSyncPreview';
import { TraktSession, traktAuth } from './TraktAuth';
import { readCloudMedia } from './TraktLibrary';

export interface MediaDifference {
  id: string;
  title: string;
  domain: string;
  local: string;
  remote: boolean;
  category: string;
  operation: string;
  operationNote: string;
  operationSeq: number;
}
export interface MediaPreview {
  account: SyncAccount;
  activity: string;
  watchedCount: number;
  watchlistCount: number;
  excluded: number;
  rows: MediaDifference[];
}

export function classifyMedia(local: string, remote: boolean, exists: boolean): string {
  if (!exists) { return 'cloud'; }
  if (local === 'unknown') { return 'unknown'; }
  if ((local === 'yes') === remote) { return 'match'; }
  return local === 'yes' ? 'addition' : 'conflict';
}

function compareDomain(records: MediaRecord[], remote: Media[], domain: string): MediaDifference[] {
  const remoteIds: Map<string, Media> = new Map<string, Media>();
  for (const media of remote) { remoteIds.set(media.id, media); }
  const rows: MediaDifference[] = [];
  for (const record of records) {
    const media = record.media;
    if (!isTraktMedia(media) || (domain === 'movie' && media.kind !== 'movie')) { continue; }
    const local = domain === 'movie' ? record.movieState : record.watchlistState;
    const exists = remoteIds.has(media.id);
    rows.push({ id: media.id, title: media.title, domain: domain, local: local, remote: exists,
      category: classifyMedia(local, exists, true), operation: '', operationNote: '', operationSeq: 0 });
    remoteIds.delete(media.id);
  }
  for (const media of remoteIds.values()) {
    rows.push({ id: media.id, title: media.title, domain: domain, local: 'unknown', remote: true,
      category: classifyMedia('unknown', true, false), operation: '', operationNote: '', operationSeq: 0 });
  }
  return rows;
}

export async function buildMediaPreview(store: EpisodeStore, session: TraktSession,
  records: MediaRecord[], expectedUuid: string, mediaStore?: MediaStore): Promise<MediaPreview> {
  const account = await readSyncAccount(session);
  if (account.uuid !== expectedUuid || await store.boundAccount() !== expectedUuid) {
    throw new Error('Account mismatch');
  }
  const snapshot = await readCloudMedia(session);
  const verified = await readSyncAccount(session);
  if (verified.uuid !== expectedUuid || await store.boundAccount() !== expectedUuid ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Account changed'); }
  const rows = [...compareDomain(records, snapshot.watchedMovies, 'movie'),
    ...compareDomain(records, snapshot.watchlist, 'watchlist')];
  if (mediaStore) {
    for (const row of rows) {
      if (row.local === 'unknown') { continue; }
      const prior = await mediaStore.latestOperation(expectedUuid, row.domain, row.id);
      row.operationSeq = prior?.seq ?? 0;
      row.operation = mediaAction(row, prior);
      if (prior?.state === 'pending') { row.operationNote = '已有未确认操作；仅允许只读核对，不重发。'; }
      else if (row.category === 'conflict' && row.domain === 'movie' && !row.operation) {
        row.operationNote = '缺少本应用确认的单次历史凭证，不允许撤销云端电影记录。';
      } else if (row.category === 'addition' && !row.operation) {
        row.operationNote = '已有电影上传凭证；云端缺失原因不明，不允许重复上传。';
      }
    }
  }
  return { account: verified, activity: snapshot.activity, watchedCount: snapshot.watchedMovies.length,
    watchlistCount: snapshot.watchlist.length,
    excluded: records.filter((record: MediaRecord) => !isTraktMedia(record.media)).length,
    rows: rows };
}

// One operation per explicit reviewed state. A successful prior movie add
// is not permission to create a second play after an external deletion.
export function mediaAction(row: MediaDifference, prior?: MediaOperation): string {
  if (row.local === 'unknown') { return ''; }
  if (prior?.state === 'pending') { return 'reconcile'; }
  if (row.category === 'addition' && row.local === 'yes' && !row.remote) {
    if (row.domain === 'movie' && prior && prior.action !== 'remove') { return ''; }
    return 'add';
  }
  if (row.category === 'conflict' && row.local === 'no' && row.remote) {
    if (row.domain === 'watchlist') { return 'remove'; }
    if (prior?.action === 'add' && prior.state === 'verified' && prior.historyId > 0) { return 'remove'; }
  }
  return '';
}
