import { http } from '@kit.NetworkKit';
import { MediaRecord, isTraktMedia } from '../model/MediaState';
import { EpisodeStore } from './EpisodeStore';
import { MediaStore, MediaOperation } from './MediaStore';
import { MediaPreview, MediaDifference, buildMediaPreview } from './TraktMediaPreview';
import { TraktSession, traktAuth } from './TraktAuth';
import { readSyncAccount, invalidateWatchedCache } from './TraktSyncPreview';
import { CloudMediaSnapshot, readCloudMedia, readActivity } from './TraktLibrary';
import { readMovieHistory, MoviePlay } from './TraktMovieHistory';
import { sameMinute } from './TraktPlayHistory';

interface TitleIds { trakt: number; }
interface TitleItem { ids: TitleIds; watched_at?: string; }
interface TitleBody { movies?: TitleItem[]; shows?: TitleItem[]; }
interface HistoryRemoveBody { ids: number[]; }
interface Counts { movies?: number; shows?: number; episodes?: number; seasons?: number; }
interface Missing { movies?: TitleItem[]; }
interface AddResponse { added?: Counts; not_found?: Missing; }
export interface TitleSyncResult { message: string; }

function ensureCurrent(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Session changed'); }
}

async function verifyAccount(binding: EpisodeStore, session: TraktSession, uuid: string): Promise<void> {
  const account = await readSyncAccount(session);
  if (account.uuid !== uuid || await binding.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
  ensureCurrent(session);
}

function present(snapshot: CloudMediaSnapshot, domain: string, id: string): boolean {
  const rows = domain === 'movie' ? snapshot.watchedMovies : snapshot.watchlist;
  return rows.some((item) => item.id === id);
}

async function confirmPending(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  uuid: string, domain: string, id: string, op: MediaOperation): Promise<TitleSyncResult> {
  const snapshot = await readCloudMedia(session);
  let verified = present(snapshot, domain, id) === (op.action === 'add');
  if (domain === 'movie' && op.action === 'remove') {
    const history = await readMovieHistory(session, Number(id.substring(6)));
    verified = op.historyId > 0 && history.count <= 2 &&
      !history.plays.some((play: MoviePlay) => play.id === op.historyId);
  }
  await verifyAccount(binding, session, uuid);
  if (await readActivity(session) !== snapshot.activity) { throw new Error('Cloud changed'); }
  ensureCurrent(session);
  if (!verified) {
    return { message: '只读核对未能确认原操作；保护凭证保留，不会重发。' };
  }
  // A later presence observation is not proof that our POST created the play.
  const historyId = op.action === 'remove' ? op.historyId : 0;
  const watchedAt = op.action === 'remove' ? op.watchedAt : '';
  const message = '只读核对确认原操作目标已满足；未重发。' +
    (domain === 'movie' && op.action === 'add' ? ' 无法归属单次历史，不能撤销该云端记录。' : '');
  await store.finishOperation(uuid, op.seq, 'verified', historyId, watchedAt, message);
  return { message: message };
}

export async function syncSelectedMedia(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  preview: MediaPreview, selected: MediaDifference, watchedAt: string,
  canSend: () => boolean): Promise<TitleSyncResult> {
  const uuid = preview.account.uuid;
  if (preview.account.generation !== session.generation ||
      !preview.rows.some((row: MediaDifference) => row.id === selected.id && row.domain === selected.domain &&
        row.operation === selected.operation && row.operationSeq === selected.operationSeq) ||
      !['add', 'remove', 'reconcile'].includes(selected.operation) ||
      !Number.isFinite(Date.parse(watchedAt))) { throw new Error('Invalid reviewed selection'); }
  await verifyAccount(binding, session, uuid);
  const records = await store.load();
  const record = records.find((row: MediaRecord) => row.media.id === selected.id);
  if (!record || !isTraktMedia(record.media) ||
      (selected.domain === 'movie' && record.media.kind !== 'movie') ||
      (selected.domain !== 'movie' && selected.domain !== 'watchlist')) { throw new Error('Invalid title'); }
  const prior = await store.latestOperation(uuid, selected.domain, selected.id);
  if ((prior?.seq ?? 0) !== selected.operationSeq) { throw new Error('Operation changed'); }
  if (selected.operation === 'reconcile') {
    if (!prior || prior.state !== 'pending') { throw new Error('Operation changed'); }
    return await confirmPending(store, binding, session, uuid, selected.domain, selected.id, prior);
  }
  const fresh = await buildMediaPreview(binding, session, records, uuid, store);
  const row = fresh.rows.find((item: MediaDifference) => item.id === selected.id && item.domain === selected.domain);
  if (!row || row.local !== selected.local || row.remote !== selected.remote ||
      row.operation !== selected.operation || row.operationSeq !== selected.operationSeq) {
    return { message: '本机或云端状态已变化，未发送；请重新预览并确认。' };
  }
  // Watching may automatically remove the movie from the Trakt watchlist.
  // If watchlist membership changed since review, require another review.
  if (row.domain === 'movie' && row.operation === 'add') {
    const oldQueue = preview.rows.find((item: MediaDifference) => item.id === row.id && item.domain === 'watchlist');
    const newQueue = fresh.rows.find((item: MediaDifference) => item.id === row.id && item.domain === 'watchlist');
    if (!oldQueue || !newQueue || oldQueue.remote !== newQueue.remote) {
      return { message: '云端待看状态已变化，未上传电影；请重新确认。' };
    }
  }
  const id = Number(row.id.substring(row.id.indexOf(':') + 1));
  let historyId = 0;
  let historyAt = '';
  let path = '';
  let body = '';
  if (row.domain === 'movie') {
    const history = await readMovieHistory(session, id);
    if (row.operation === 'add') {
      if (history.count !== 0) { return { message: '云端已有电影历史，未重复上传；请刷新预览。' }; }
      const payload: TitleBody = { movies: [{ ids: { trakt: id }, watched_at: watchedAt }] };
      path = 'sync/history';
      body = JSON.stringify(payload);
    } else {
      if (!prior || prior.action !== 'add' || prior.state !== 'verified' || prior.historyId <= 0 ||
          history.count !== 1 || history.plays[0].id !== prior.historyId ||
          history.plays[0].action !== 'watch' ||
          Date.parse(history.plays[0].watched_at) !== Date.parse(prior.watchedAt)) {
        return { message: '电影历史有变化、多次观看或凭证不匹配；未删除。' };
      }
      historyId = prior.historyId;
      historyAt = prior.watchedAt;
      const payload: HistoryRemoveBody = { ids: [historyId] };
      path = 'sync/history/remove';
      body = JSON.stringify(payload);
    }
  } else {
    const item: TitleItem = { ids: { trakt: id } };
    const payload: TitleBody = record.media.kind === 'movie' ? { movies: [item] } : { shows: [item] };
    path = row.operation === 'add' ? 'sync/watchlist' : 'sync/watchlist/remove';
    body = JSON.stringify(payload);
  }
  await verifyAccount(binding, session, uuid);
  if (await readActivity(session) !== fresh.activity || !canSend()) {
    return { message: '发送前云端或应用状态变化，未发送。' };
  }
  const seq = await store.reserveOperation(uuid, row.domain, row.id, row.operation, historyId, historyAt);
  let sent = false;
  let accepted = false;
  let httpStatus = '未确认响应';
  try {
    await verifyAccount(binding, session, uuid);
    if (await readActivity(session) !== fresh.activity || !canSend()) {
      throw new Error('Preflight changed');
    }
    ensureCurrent(session);
    const request = http.createHttp();
    try {
      if (!canSend()) { throw new Error('Foreground ended'); }
      invalidateWatchedCache();
      sent = true;
      const res = await request.request('https://api.trakt.tv/' + path, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
        extraData: body, expectDataType: http.HttpDataType.STRING
      });
      httpStatus = 'HTTP ' + res.responseCode;
      if (row.domain === 'movie' && row.operation === 'add' &&
          (res.responseCode === 200 || res.responseCode === 201) && typeof res.result === 'string') {
        const data = JSON.parse(res.result) as AddResponse;
        accepted = data.added?.movies === 1 && (data.added?.episodes ?? 0) === 0 &&
          Array.isArray(data.not_found?.movies) && data.not_found?.movies?.length === 0;
      }
    } catch (error) {
      if (!sent) { throw new Error('Not sent'); }
      // POST result is ambiguous, even if no response arrived. Read only.
    } finally { request.destroy(); }
    await verifyAccount(binding, session, uuid);
    const snapshot = await readCloudMedia(session);
    let verified = present(snapshot, row.domain, row.id) === (row.operation === 'add');
    let receiptId = historyId;
    let receiptAt = historyAt;
    if (row.domain === 'movie') {
      const history = await readMovieHistory(session, id);
      if (row.operation === 'add') {
        verified = verified && history.count > 0;
        if (verified && accepted && history.count === 1 && history.plays[0].action === 'watch' &&
            sameMinute(history.plays[0].watched_at, watchedAt)) {
          receiptId = history.plays[0].id;
          receiptAt = history.plays[0].watched_at;
        }
      } else {
        verified = history.count <= 2 && !history.plays.some((play: MoviePlay) => play.id === historyId);
      }
    }
    await verifyAccount(binding, session, uuid);
    if (await readActivity(session) !== snapshot.activity) { throw new Error('Cloud changed during readback'); }
    ensureCurrent(session);
    if (verified) {
      let message = '云端回读已确认' + (row.operation === 'add' ? '存在' : '目标已移除') + ' · ' + httpStatus;
      if (row.domain === 'movie' && row.operation === 'add') {
        message += receiptId > 0 ? '；已保存单次历史凭证。' : '；未能归属单次历史，禁止撤销。';
        message += ' 云端待看：' + (present(snapshot, 'watchlist', row.id) ? '存在' : '不存在') + '，本机待看状态不变。';
      }
      if (row.domain === 'watchlist') { message += '；仅操作待看清单。'; }
      await store.finishOperation(uuid, seq, 'verified', receiptId, receiptAt, message);
      return { message: message };
    }
  } catch (error) {
    // Do not emit raw server responses or credentials.
  }
  if (!sent) {
    const message = '发送前检查失败，未发出请求；本次凭证标记未发送。';
    await store.finishOperation(uuid, seq, 'unsent', historyId, historyAt, message);
    return { message: message };
  }
  const message = '请求可能已发送 · ' + httpStatus + '；回读未确认，保留保护，只允许只读核对。';
  await store.finishOperation(uuid, seq, 'pending', historyId, historyAt, message);
  return { message: message };
}
