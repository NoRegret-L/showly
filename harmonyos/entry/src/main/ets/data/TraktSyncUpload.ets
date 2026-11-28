import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';
import { EpisodeStore } from './EpisodeStore';
import { SyncPreview, SyncDifference, buildSyncPreview, readSyncAccount, invalidateWatchedCache } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
import { readEpisodeHistory, sameMinute } from './TraktPlayHistory';

interface UploadIds { trakt: number; }
interface UploadEpisode { ids: UploadIds; watched_at: string; }
interface UploadBody { episodes: UploadEpisode[]; }
interface AddedCounts { episodes: number; movies?: number; }
interface MissingItems { episodes?: UploadEpisode[]; }
interface UploadResponse { added: AddedCounts; not_found?: MissingItems; }
interface HistoryEpisode { ids: UploadIds; }
interface HistoryRow { episode: HistoryEpisode; }
export interface UploadResult { status: string; message: string; }

function ensureCurrent(session: TraktSession): void {
  if (!traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Session changed');
  }
}

async function hasHistory(session: TraktSession, episodeId: number): Promise<boolean> {
  ensureCurrent(session);
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/sync/history/episodes/' + episodeId + '?page=1&limit=1', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    ensureCurrent(session);
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('History verification HTTP ' + response.responseCode);
    }
    const rows = JSON.parse(response.result) as HistoryRow[];
    if (!Array.isArray(rows) || rows.length > 1 ||
        rows.some((row: HistoryRow) => row.episode?.ids?.trakt !== episodeId)) {
      throw new Error('Unexpected history response');
    }
    return rows.length === 1;
  } finally { request.destroy(); }
}

export async function uploadSelectedEpisode(store: EpisodeStore, session: TraktSession,
  preview: SyncPreview, episodeId: number, watchedAt: string): Promise<UploadResult> {
  const selected = preview.rows.find((row: SyncDifference) => row.episodeId === episodeId);
  if (!selected || selected.kind !== 'addition' || !selected.localWatched ||
      !Number.isSafeInteger(episodeId) || episodeId <= 0 ||
      !Number.isFinite(Date.parse(watchedAt)) || preview.account.generation !== session.generation) {
    throw new Error('Invalid selection');
  }
  const account = await readSyncAccount(session);
  if (account.uuid !== preview.account.uuid || await store.boundAccount() !== account.uuid) {
    throw new Error('Account mismatch');
  }
  const fresh = await buildSyncPreview(store, session);
  const current = fresh.rows.find((row: SyncDifference) => row.episodeId === episodeId);
  if (!current || !current.localWatched || fresh.account.uuid !== account.uuid) {
    throw new Error('Local intent or account changed');
  }
  if (current.cloudWatched && current.kind === 'match') {
    return { status: 'skipped', message: '云端已存在该集观看记录，已跳过，未重复上传。' };
  }
  if (current.kind !== 'addition'||current.intentSeq!==selected.intentSeq||!selected.watchedAt||current.watchedAt!==selected.watchedAt||Date.parse(watchedAt)!==Date.parse(selected.watchedAt)) { throw new Error('Selection or watch time changed'); }
  if (await store.hasUploadAttempt(account.uuid, episodeId)) {
    return { status: 'blocked', message: '该集已有上传尝试凭证，禁止再次写入。请在 Trakt 检查历史；本版不解除保护。' };
  }
  if (await hasHistory(session, episodeId)) {
    return { status: 'skipped', message: '云端已存在该集观看记录，已跳过。' };
  }
  if (await readActivity(session) !== fresh.activity) {
    throw new Error('Cloud changed before upload');
  }
  ensureCurrent(session);
  // Persist before POST; even a crash or timeout must not cause blind retries.
  await store.reserveUpload(account.uuid, episodeId);
  let accepted = false;
  try {
    ensureCurrent(session);
    if (await readActivity(session) !== fresh.activity) {
      return { status: 'blocked', message: '写入前云端发生变化，未发送新增请求；已保留保护凭证，请在 Trakt 核对。' };
    }
    ensureCurrent(session);
    const request = http.createHttp();
    try {
      const body: UploadBody = { episodes: [{ ids: { trakt: episodeId }, watched_at: watchedAt }] };
      invalidateWatchedCache();
      const response = await request.request('https://api.trakt.tv/sync/history', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
        extraData: JSON.stringify(body), expectDataType: http.HttpDataType.STRING
      });
      if ((response.responseCode === 201 || response.responseCode === 200) && typeof response.result === 'string') {
        const result = JSON.parse(response.result) as UploadResponse;
        accepted = result.added?.episodes === 1 && (result.added?.movies ?? 0) === 0 &&
          Array.isArray(result.not_found?.episodes) && result.not_found?.episodes?.length === 0;
      }
    } catch (error) {
      // The server might have committed before the connection failed. Never resend.
    } finally { request.destroy(); }
    const verified = await readSyncAccount(session);
    if (verified.uuid !== account.uuid || await store.boundAccount() !== account.uuid) {
      throw new Error('Account changed during write');
    }
    const exists = await hasHistory(session, episodeId);
    if (exists) {
      await store.confirmUpload(account.uuid, episodeId);
      if (accepted) {
        try {
          const history = await readEpisodeHistory(session, episodeId);
          if (history.count === 1 && history.plays.length === 1 &&
              history.plays[0].action === 'watch' && sameMinute(history.plays[0].watched_at, watchedAt) &&
              traktAuth.isCurrent(session.clientId, session.generation)) {
            await store.saveUndoReceipt(account.uuid, episodeId, history.plays[0].id, history.plays[0].watched_at);
            return { status: 'verified', message: '新增 1 集成功，已回读并保存单次历史 ID；撤销仍需单独确认。' };
          }
        } catch (error) {
          // Upload succeeded; missing/ambiguous provenance must never enable removal.
        }
      }
      return { status: 'verified', message: accepted ?
        '新增 1 集成功，已回读确认云端存在该集。' :
        '云端已存在该集，回读确认；无法确定本次请求是否新增，禁止重复上传。' };
    }
  } catch (error) {
    // Failed readback does not prove failed write.
  }
  return { status: 'uncertain', message: '上传结果尚无法确认；保护凭证已保存，不会自动重试。请在 Trakt 检查该集历史。' };
}
