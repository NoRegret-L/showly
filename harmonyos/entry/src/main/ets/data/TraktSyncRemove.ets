import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';
import { EpisodeStore, JournalIntent } from './EpisodeStore';
import { SyncPreview, SyncDifference, readSyncAccount, invalidateWatchedCache } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
import { readEpisodeHistory, SinglePlay } from './TraktPlayHistory';

interface RemoveBody { ids: number[]; }
export interface RemovalResult { message: string; }

export async function removeSelectedPlay(store: EpisodeStore, session: TraktSession,
  preview: SyncPreview, episodeId: number): Promise<RemovalResult> {
  const row = preview.rows.find((item: SyncDifference) => item.episodeId === episodeId);
  if (!row || row.kind !== 'conflict' || row.localWatched || !row.cloudWatched ||
      row.undoState !== 0 || !Number.isSafeInteger(row.undoHistoryId) || row.undoHistoryId <= 0 ||
      preview.account.generation !== session.generation) { throw new Error('Invalid removal selection'); }
  const account = await readSyncAccount(session);
  if (account.uuid !== preview.account.uuid || await store.boundAccount() !== account.uuid) {
    throw new Error('Account mismatch');
  }
  const receipt = await store.undoReceipt(account.uuid, episodeId);
  const intents = await store.journalIntents();
  const intent = intents.find((item: JournalIntent) => item.episodeId === episodeId);
  if (!receipt || receipt.removalState !== 0 || receipt.historyId !== row.undoHistoryId ||
      receipt.watchedAt !== row.undoWatchedAt || !intent || !intent.catalogKnown || intent.watched) {
    throw new Error('Local intent or receipt changed');
  }
  const before = await readActivity(session);
  const history = await readEpisodeHistory(session, episodeId);
  const after = await readActivity(session);
  if (before !== after || history.count !== 1 || history.plays[0].id !== receipt.historyId ||
      history.plays[0].action !== 'watch' || Date.parse(history.plays[0].watched_at) !== Date.parse(receipt.watchedAt)) {
    return { message: '云端记录已变化、存在多次观看或无法确认原历史 ID，未删除任何记录。' };
  }
  const verified = await readSyncAccount(session);
  if (verified.uuid !== account.uuid || !traktAuth.isCurrent(session.clientId, session.generation) ||
      await store.boundAccount() !== account.uuid) { throw new Error('Account changed'); }
  await store.reserveRemoval(account.uuid, episodeId, receipt.historyId);
  try {
    if (await readActivity(session) !== after || !traktAuth.isCurrent(session.clientId, session.generation)) {
      return { message: '发送前云端变化，未发送删除请求；已保留撤销保护，请到 Trakt 核对。' };
    }
    // History ID only. Never send episode/show/season identifiers to remove.
    const body: RemoveBody = { ids: [receipt.historyId] };
    const request = http.createHttp();
    try {
      invalidateWatchedCache();
      await request.request('https://api.trakt.tv/sync/history/remove', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
        extraData: JSON.stringify(body), expectDataType: http.HttpDataType.STRING
      });
    } catch (error) {
      // Uncertain write: only read back, never automatically send again.
    } finally { request.destroy(); }
    const current = await readSyncAccount(session);
    if (current.uuid !== account.uuid || await store.boundAccount() !== account.uuid) {
      throw new Error('Account changed after removal');
    }
    const result = await readEpisodeHistory(session, episodeId);
    if (result.count <= 2 && !result.plays.some((play: SinglePlay) => play.id === receipt.historyId)) {
      await store.confirmRemoval(account.uuid, episodeId, receipt.historyId);
      return { message: '回读确认目标单次观看历史已不存在；其他观看记录未被本应用删除。' };
    }
  } catch (error) {
    // Keep the one-time removal reservation on all uncertain results.
  }
  return { message: '撤销结果无法确认，已保留保护凭证，不会重复删除；请到 Trakt 核对。' };
}
