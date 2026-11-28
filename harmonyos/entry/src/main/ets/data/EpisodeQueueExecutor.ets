import { EpisodeStore, QueueEntry } from './EpisodeStore';
import { SyncAccount, readSyncAccount } from './TraktSyncPreview';
import { traktAuth } from './TraktAuth';
import { reconcileQueue } from './TraktQueueReconcile';
import { uploadBatch } from './TraktSyncBatch';
import { safeSyncError } from './SyncDiagnostics';
import { queueIdentity } from '../model/SyncCoordinator';

// Existing caller owns foreground/consent guards; this executor owns network
// operations and preserves the existing reservation and readback semantics.
export async function executeEpisodeQueue(store: EpisodeStore, expected: string, clientId: string, manual: boolean,
  clientCurrent: () => boolean, allowed: () => boolean, visible: () => boolean,
  revoke: () => Promise<void>, publishAccount: (account: SyncAccount) => void,
  publishEmpty: () => void, publishStatus: (status: string) => void): Promise<string> {
    let status = '正在读取待同步队列…';
    let stage = '读取本机队列';
    let ids: number[] = [];
    try {
      let pending = await store.queueEntries(expected);
      ids = pending.map((entry: QueueEntry) => entry.episodeId);
      if (!pending.length) {
        publishEmpty();
        status = '没有待同步新增。'; publishStatus(status);
        return status;
      }
      stage = '恢复登录';
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Offline or sign-in required'); }
      stage = '核对账户';
      const account = await readSyncAccount(session);
      if (account.uuid !== expected || !clientCurrent() || await store.boundAccount() !== expected) {
        if (!manual) { await revoke(); }
        throw new Error('Account mismatch');
      }
      publishAccount(account);
      const canSend = (): boolean => {
        return allowed() && clientCurrent() && traktAuth.isCurrent(clientId, session.generation);
      };
      let reconciled = 0;
      if (pending.some((entry: QueueEntry) => entry.blocked)) {
        stage = '只读核对受保护队列';
        status = '正在只读核对已有凭证，不会重复上传…'; publishStatus(status);
        const checked = await reconcileQueue(store, session, expected, pending);
        reconciled += checked.completed.length;
        pending = checked.remaining;
        if (checked.completed.length) {
          await store.logSync(expected, 'reconcile', checked.completed,
            '只读核对确认云端存在 ' + checked.completed.length + ' 集，已清理队列；未重发。');
        }
      }
      const eligible = pending.filter((entry: QueueEntry) => !entry.blocked);
      if (!eligible.length) {
        status = '只读核对完成：已清理 ' + reconciled + ' 集；剩余 ' + pending.length +
          ' 集受保护或目录异常，未发送新增请求。'; publishStatus(status);
        return;
      }
      stage = '上传未发送的新增分集';
      if (!canSend()) { throw new Error('Foreground ended'); }
      status = '正在校验并处理 ' + eligible.length + ' 集未发送记录…'; publishStatus(status);
      const result = await uploadBatch(store, session, expected,
        eligible.map((entry: QueueEntry) => entry.episodeId), new Date().toISOString(),
        'queue', undefined, eligible, canSend);
      stage = '保存已完成队列';
      const completed = new Set<number>(result.completedIds);
      for (const entry of eligible) {
        if (completed.has(entry.episodeId)) { await store.finishQueue(expected, entry); }
      }
      status = result.message; publishStatus(status);
      // Only one additional fresh READ, never a second POST. If the app exits
      // or this read fails, the next foreground/network event can reconcile.
      const remaining = await store.queueEntries(expected);
      const sentIdentities = new Set<string>();
      for (const old of eligible) { sentIdentities.add(queueIdentity(old.episodeId, old.seq)); }
      const attempted = remaining.filter((entry: QueueEntry) => entry.blocked &&
        sentIdentities.has(queueIdentity(entry.episodeId, entry.seq)));
      if (attempted.length > 0 && visible()) {
        stage = '上传后补充只读核对';
        const checked = await reconcileQueue(store, session, expected, attempted);
        reconciled += checked.completed.length;
        await store.logSync(expected, 'reconcile', checked.completed,
          '上传后只读核对：确认 ' + checked.completed.length + ' 集，未重发；剩余队列 ' + checked.remaining.length + ' 集。');
      }
      if (reconciled) { status += ' 只读补充核对清理 ' + reconciled + ' 集。'; }
    } catch (error) {
      status = '队列未完成 · 阶段：' + stage + ' · ' + safeSyncError(error as Error) +
        '。本机记录保留，受保护项不会重发。'; publishStatus(status);
      try { await store.logSync(expected, 'queue', ids, status); } catch (failure) {}
    }
    return status;
}
