import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';
import { EpisodeStore, QueueEntry } from './EpisodeStore';
import { SyncPreview, SyncDifference, buildSyncPreview, readSyncAccount, invalidateWatchedCache } from './TraktSyncPreview';
import { readEpisodeHistory, sameMinute } from './TraktPlayHistory';
import { readActivity } from './TraktLibrary';
import { safeSyncError } from './SyncDiagnostics';

interface BatchIds { trakt: number; }
interface BatchEpisode { ids: BatchIds; watched_at: string; }
interface BatchBody { episodes: BatchEpisode[]; }
interface AddedCounts { episodes: number; movies?: number; }
interface MissingItems { episodes?: BatchEpisode[]; }
interface BatchResponse { added: AddedCounts; not_found?: MissingItems; }
export interface BatchResult { message: string; completedIds: number[]; }

function current(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Session changed'); }
}

// Both the explicit selection and the automatic action pass through this gate.
// Do not upload an implicit default or an imported baseline record.
export async function uploadBatch(store: EpisodeStore, session: TraktSession,
  uuid: string, selectedIds: number[], watchedAt: string, mode: string,
  preview?: SyncPreview, queued: QueueEntry[] = [], canSend?: () => boolean): Promise<BatchResult> {
  if (!selectedIds.length || new Set<number>(selectedIds).size !== selectedIds.length ||
      selectedIds.some((id: number) => !Number.isSafeInteger(id) || id <= 0) ||
      !Number.isFinite(Date.parse(watchedAt)) ||
      (mode !== 'manual' && mode !== 'auto' && mode !== 'queue')) { throw new Error('Invalid batch'); }
  if (mode === 'manual' && (!preview || preview.account.uuid !== uuid ||
      preview.account.generation !== session.generation ||
      selectedIds.some((id: number) => !preview.rows.some((row: SyncDifference) =>
        row.episodeId === id && row.kind === 'addition' && !row.uploadBlocked)))) {
    throw new Error('Invalid reviewed selection');
  }
  if (mode === 'queue') {
    const currentQueue = await store.queueEntries(uuid);
    if (selectedIds.some((id: number) => !queued.some((entry: QueueEntry) => entry.episodeId === id &&
      currentQueue.some((current: QueueEntry) => current.episodeId === id && current.seq === entry.seq &&
        current.watchedAt === entry.watchedAt)))) { throw new Error('Queue changed'); }
  }
  const completedIds: number[] = [];
  const account = await readSyncAccount(session);
  if (account.uuid !== uuid || await store.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
  const fresh = await buildSyncPreview(store, session);
  if (fresh.account.uuid !== uuid) { throw new Error('Account changed'); }
  const send: number[] = [];
  let skipped = 0;
  let blocked = 0;
  for (const id of selectedIds) {
    const row = fresh.rows.find((value: SyncDifference) => value.episodeId === id);
    if (!row || !row.localWatched || (row.kind !== 'addition' && row.kind !== 'match')) {
      blocked++;
      continue;
    }
    if (row.cloudWatched) { skipped++; completedIds.push(id); continue; }
    if (row.uploadBlocked || await store.hasUploadAttempt(uuid, id)) { blocked++; continue; }
    const history = await readEpisodeHistory(session, id);
    if (history.count > 0) { skipped++; completedIds.push(id); continue; }
    send.push(id);
  }
  if (!send.length) {
    const message = '未发送；已存在 ' + skipped + ' 集，受保护或不符合条件 ' + blocked + ' 集。';
    await store.logSync(uuid, mode, selectedIds, message);
    return { message: message, completedIds: completedIds };
  }
  if (await readActivity(session) !== fresh.activity) { throw new Error('Cloud changed before batch'); }
  const reserved: number[] = [];
  let sent = false;
  let stage = '保留上传凭证';
  let postStatus = '未发送';
  let readErrors = 0;
  let firstReadError = '';
  try {
    if (canSend && !canSend()) { throw new Error('Foreground ended'); }
    for (const id of send) {
      current(session);
      await store.reserveUpload(uuid, id);
      reserved.push(id);
    }
    await store.logSync(uuid, mode, send, '已保留凭证，准备发送；若中断需核对');
    stage = '发送前活动及账户复核';
    if (await readActivity(session) !== fresh.activity) { throw new Error('Cloud changed'); }
    current(session);
    const verified = await readSyncAccount(session);
    if (verified.uuid !== uuid || await store.boundAccount() !== uuid) { throw new Error('Account changed'); }
    current(session);
    const body: BatchBody = { episodes: send.map((id: number): BatchEpisode => {
      return { ids: { trakt: id }, watched_at: queued.find((entry: QueueEntry) => entry.episodeId === id)?.watchedAt ?? watchedAt };
    }) };
    const request = http.createHttp();
    let accepted = false;
    try {
      // Any failure after entering request() is ambiguous, even an HTTP error.
      if (canSend && !canSend()) { throw new Error('Foreground ended'); }
      invalidateWatchedCache();
      stage = '发送历史新增';
      sent = true;
      const response = await request.request('https://api.trakt.tv/sync/history', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
        extraData: JSON.stringify(body), expectDataType: http.HttpDataType.STRING
      });
      postStatus = 'HTTP ' + response.responseCode;
      if ((response.responseCode === 200 || response.responseCode === 201) && typeof response.result === 'string') {
        const result = JSON.parse(response.result) as BatchResponse;
        accepted = result.added?.episodes === send.length && (result.added?.movies ?? 0) === 0 &&
          Array.isArray(result.not_found?.episodes) && result.not_found?.episodes?.length === 0;
      }
    } catch (error) {
      if (!sent) { throw new Error('Foreground ended'); }
      postStatus = '响应未确认：' + safeSyncError(error as Error);
      // No retransmission; verify readback below.
    } finally { request.destroy(); }
    let present = 0;
    let receipts = 0;
    stage = '上传后账户复核';
    const readback = await readSyncAccount(session);
    if (readback.uuid !== uuid) { throw new Error('Account changed after POST'); }
    stage = '逐集历史回读及本机保存';
    for (const id of send) {
      current(session);
      try {
        const history = await readEpisodeHistory(session, id);
        if (history.count > 0) {
          await store.confirmUpload(uuid, id);
          present++;
          completedIds.push(id);
          if (accepted && history.count === 1 && history.plays[0].action === 'watch' &&
              sameMinute(history.plays[0].watched_at, queued.find((entry: QueueEntry) => entry.episodeId === id)?.watchedAt ?? watchedAt)) {
            await store.saveUndoReceipt(uuid, id, history.plays[0].id, history.plays[0].watched_at);
            receipts++;
          }
        }
      } catch (error) {
        readErrors++;
        if (!firstReadError) { firstReadError = safeSyncError(error as Error); }
        // Each unverifiable episode stays protected; no retry.
      }
    }
    const message = '请求 ' + send.length + ' 集，回读存在 ' + present + ' 集，未确认 ' +
      (send.length - present) + ' 集，撤销凭证 ' + receipts + ' 集，跳过 ' + skipped +
      ' 集，受保护 ' + blocked + ' 集。' + (accepted ? '' : ' 服务端新增数量未完整确认。') +
      ' 发送结果：' + postStatus + (readErrors ? '；回读/保存异常 ' + readErrors + ' 次：' + firstReadError : '');
    stage = '保存批量结果日志';
    await store.logSync(uuid, mode, send, message);
    // Only an accepted POST with every exact readback and durable receipt
    // qualifies. Merely observing a pre-existing record is not upload success.
    if (accepted && present === send.length && receipts === send.length && readErrors === 0) {
      await store.logSync(uuid, 'episode-upload-confirmed', send, '分集上传及回执全部确认');
    }
    return { message: message, completedIds: completedIds };
  } catch (error) {
    if (!sent) {
      // Only this live invocation knows no POST was issued.
      for (const id of reserved) { await store.releaseUnsentUpload(uuid, id); }
      const message = '发送前失败，未上传；已释放本次未发送凭证。阶段：' + stage + '；' + safeSyncError(error as Error);
      await store.logSync(uuid, mode, selectedIds, message);
      return { message: message, completedIds: completedIds };
    }
    const message = '请求可能已发送，保留全部凭证，禁止盲目重试。阶段：' + stage + '；' + postStatus + '；' + safeSyncError(error as Error);
    await store.logSync(uuid, mode, send, message);
    return { message: message, completedIds: completedIds };
  }
}
