import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { MediaRecord, isTraktMedia } from '../model/MediaState';
import { EpisodeStore } from './EpisodeStore';
import { MediaStore, MediaOperation } from './MediaStore';
import { MediaPreview, MediaDifference, buildMediaPreview } from './TraktMediaPreview';
import { TraktSession, traktAuth } from './TraktAuth';
import { readSyncAccount, invalidateWatchedCache } from './TraktSyncPreview';
import { readWatchlistKind, readActivity } from './TraktLibrary';
import { readMovieHistory, MoviePlay } from './TraktMovieHistory';
import { sameMinute } from './TraktPlayHistory';
import { safeSyncError } from './SyncDiagnostics';

interface TitleIds { trakt: number; }
interface TitleItem { ids: TitleIds; watched_at?: string; }
interface TitleBody { movies?: TitleItem[]; shows?: TitleItem[]; }
interface HistoryRemoveBody { ids: number[]; }
interface Counts { movies?: number; shows?: number; episodes?: number; seasons?: number; }
interface Missing { movies?: TitleItem[]; }
interface AddResponse { added?: Counts; not_found?: Missing; }
export interface TitleSyncResult { message: string; }
export interface PendingMediaResult { confirmed: number; remaining: number; failed: number; message: string; }
interface PendingCheck { verified: boolean; message: string; }

function ensureCurrent(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Session changed'); }
}

async function verifyAccount(binding: EpisodeStore, session: TraktSession, uuid: string): Promise<void> {
  const account = await readSyncAccount(session);
  if (account.uuid !== uuid || await binding.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
  ensureCurrent(session);
}

// Only the affected domain is read, independently of the full UI snapshot.
// An accepted response alone is never enough to prove a history receipt.
async function confirmPending(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  uuid: string, domain: string, id: string, op: MediaOperation,
  liveAccepted: boolean = false): Promise<PendingCheck> {
  await verifyAccount(binding, session, uuid);
  const before = await readActivity(session);
  const evidence = await store.responseEvidence(uuid, op.seq);
  let verified = false;
  let receiptId = op.action === 'remove' ? op.historyId : 0;
  let receiptAt = op.action === 'remove' ? op.watchedAt : '';
  const numericId = Number(id.substring(id.indexOf(':') + 1));
  if (domain === 'movie') {
    const history = await readMovieHistory(session, numericId);
    if (op.action === 'add') {
      verified = history.count > 0;
      // Do not infer ownership on a later invocation, even with a stored
      // accepted-response count. The contemporaneous read must succeed.
      if (verified && liveAccepted && evidence?.accepted === true && history.count === 1 &&
          history.plays[0].action === 'watch' && sameMinute(history.plays[0].watched_at, evidence.requestedAt)) {
        receiptId = history.plays[0].id;
        receiptAt = history.plays[0].watched_at;
      }
    } else {
      verified = op.historyId > 0 && history.count <= 2 &&
        !history.plays.some((play: MoviePlay) => play.id === op.historyId);
    }
  } else {
    const kind = id.startsWith('movie:') ? 'movie' : 'show';
    const list = await readWatchlistKind(session, kind);
    verified = list.some((item: Media) => item.id === id) === (op.action === 'add');
  }
  await verifyAccount(binding, session, uuid);
  if (await readActivity(session) !== before) { throw new Error('Cloud changed during readback'); }
  ensureCurrent(session);
  if (!verified) {
    return { verified: false, message: '只读核对未能确认原操作；保护凭证保留，不会重发。' };
  }
  const latest = await store.latestOperation(uuid, domain, id);
  if (!latest || latest.seq !== op.seq || latest.state !== 'pending') { throw new Error('Operation changed'); }
  let message = liveAccepted ? '云端目标历史回读已确认；未重发。' : '只读核对确认原操作目标已满足；未重发。';
  if (domain === 'movie' && op.action === 'add') {
    message += receiptId > 0 ? ' 已保存单次历史凭证。' : ' 无法归属单次历史，不能撤销该云端记录。';
    message += ' 本机待看不变；云端待看以最新预览为准。';
  }
  if (domain === 'watchlist') { message += ' 仅核对待看清单。'; }
  if (evidence) { message += ' HTTP ' + evidence.httpStatus + '。'; }
  await store.finishOperation(uuid, op.seq, 'verified', receiptId, receiptAt, message);
  const stored = await store.latestOperation(uuid, domain, id);
  if (!stored || stored.seq !== op.seq || stored.state !== 'verified' || stored.historyId !== receiptId) {
    throw new Error('Operation confirmation not persisted');
  }
  return { verified: true, message: message };
}

// Automatic recovery has no code path to POST. Only pre-existing pending
// operations of the current bound UUID are eligible, regardless of local edits.
export async function reconcilePendingMedia(store: MediaStore, binding: EpisodeStore,
  session: TraktSession, uuid: string): Promise<PendingMediaResult> {
  const pending = await store.pendingTargets(uuid);
  let confirmed = 0;
  let failed = 0;
  let detail = '';
  if (pending.length > 0) { await verifyAccount(binding, session, uuid); }
  for (const target of pending) {
    ensureCurrent(session);
    const op = await store.latestOperation(uuid, target.domain, target.id);
    if (!op || op.state !== 'pending') { continue; }
    try {
      const result = await confirmPending(store, binding, session, uuid, target.domain, target.id, op);
      if (result.verified) { confirmed++; }
      else { detail = result.message; }
    } catch (error) {
      failed++;
      detail = safeSyncError(error as Error);
      // Fail closed and stop this pass on a network, identity, or storage error.
      // No periodic polling and no automatic retransmission.
      break;
    }
  }
  const remaining = (await store.pendingTargets(uuid)).length;
  return { confirmed: confirmed, remaining: remaining, failed: failed,
    message: '自动只读核对：确认 ' + confirmed + ' 条，剩余 ' + remaining + ' 条保护；未重发。' +
      (detail ? ' ' + detail : '') };
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
    const checked = await confirmPending(store, binding, session, uuid, selected.domain, selected.id, prior);
    return { message: checked.message };
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
  const seq = await store.reserveOperation(uuid, row.domain, row.id, row.operation, historyId,
    row.domain === 'movie' && row.operation === 'add' ? watchedAt : historyAt);
  let sent = false;
  let accepted = false;
  let httpStatus = '未确认响应';
  let stage = '发送前账户与活动复核';
  let failure = '';
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
      stage = '发送单条操作';
      sent = true;
      const res = await request.request('https://api.trakt.tv/' + path, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
        extraData: body, expectDataType: http.HttpDataType.STRING
      });
      httpStatus = 'HTTP ' + res.responseCode;
      stage = '保存服务器响应证据';
      if (row.domain === 'movie' && row.operation === 'add' &&
          (res.responseCode === 200 || res.responseCode === 201) && typeof res.result === 'string') {
        try {
          const data = JSON.parse(res.result) as AddResponse;
          accepted = data.added?.movies === 1 && (data.added?.episodes ?? 0) === 0 &&
            Array.isArray(data.not_found?.movies) && data.not_found?.movies?.length === 0;
        } catch (error) { accepted = false; }
      }
      // Persist only validated counts/status/time, never raw response or token.
      await store.recordResponse(uuid, seq, watchedAt, res.responseCode, accepted);
    } catch (error) {
      if (!sent) { throw new Error('Not sent'); }
      failure = stage + '：' + safeSyncError(error as Error);
      accepted = false;
      // The server may have committed; only readback may follow.
    } finally { request.destroy(); }
    stage = row.domain === 'movie' ? '单部电影历史回读' : '对应待看清单回读';
    const pending = await store.latestOperation(uuid, row.domain, row.id);
    if (!pending || pending.seq !== seq || pending.state !== 'pending') { throw new Error('Operation changed'); }
    const result = await confirmPending(store, binding, session, uuid, row.domain, row.id, pending, accepted);
    if (result.verified) { return { message: result.message }; }
    failure = stage + '：云端尚未显示目标状态。' + (failure ? ' ' + failure : '');
  } catch (error) {
    failure = stage + '：' + safeSyncError(error as Error) + (failure ? '；' + failure : '');
  }
  if (!sent) {
    const message = '发送前检查失败，未发出请求；本次凭证标记未发送。' + failure;
    await store.finishOperation(uuid, seq, 'unsent', historyId, historyAt, message);
    return { message: message };
  }
  const message = '请求可能已发送 · ' + httpStatus + '；回读未确认，保留保护，只允许只读核对。' + failure;
  await store.finishOperation(uuid, seq, 'pending', historyId,
    row.domain === 'movie' && row.operation === 'add' ? watchedAt : historyAt, message);
  return { message: message };
}
