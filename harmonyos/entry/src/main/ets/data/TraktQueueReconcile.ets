import { TraktSession, traktAuth } from './TraktAuth';
import { EpisodeStore, QueueEntry } from './EpisodeStore';
import { buildSyncPreview } from './TraktSyncPreview';

export interface ReconcileResult {
  completed: number[];
  remaining: QueueEntry[];
}

// Fresh, complete, activity-checked snapshot. Never sends a history mutation.
// Complete only the exact still-current event, even if ownership is unknown.
export async function reconcileQueue(store: EpisodeStore, session: TraktSession,
  uuid: string, entries: QueueEntry[]): Promise<ReconcileResult> {
  const completed: number[] = [];
  if (!entries.length) { return { completed: completed, remaining: [] }; }
  const snapshot = await buildSyncPreview(store, session, true);
  if (snapshot.account.uuid !== uuid || await store.boundAccount() !== uuid ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Account mismatch'); }
  const remote: Set<number> = new Set<number>(snapshot.cloudIds);
  const latest = await store.queueEntries(uuid);
  for (const entry of entries) {
    if (!traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Session changed'); }
    if (latest.some((row: QueueEntry) => row.episodeId === entry.episodeId && row.seq === entry.seq) &&
        remote.has(entry.episodeId)) {
      // This confirms presence only. Never invent an undo receipt.
      if (await store.hasUploadAttempt(uuid, entry.episodeId)) {
        await store.confirmUpload(uuid, entry.episodeId);
      }
      await store.finishQueue(uuid, entry);
      completed.push(entry.episodeId);
    }
  }
  return { completed: completed, remaining: await store.queueEntries(uuid) };
}
