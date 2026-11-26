import { EpisodeStore } from './EpisodeStore';
import { MediaStore } from './MediaStore';
import { MediaRecord } from '../model/MediaState';
import { CommonUpdate } from '../model/ThreeWay';
import { TraktSession, traktAuth } from './TraktAuth';
import { SyncPreview, SyncDifference, buildSyncPreview, readSyncAccount } from './TraktSyncPreview';
import { MediaPreview, MediaDifference, buildMediaPreview } from './TraktMediaPreview';
import { readActivity } from './TraktLibrary';

async function current(binding: EpisodeStore, session: TraktSession, uuid: string, activity: string): Promise<void> {
  const account = await readSyncAccount(session);
  if (account.uuid !== uuid || await binding.boundAccount() !== uuid ||
      await readActivity(session) !== activity || !traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Snapshot or account changed');
  }
}

export async function checkpointEpisodes(store: EpisodeStore, session: TraktSession, reviewed: SyncPreview): Promise<number> {
  if (reviewed.account.generation !== session.generation) { throw new Error('Session changed'); }
  const fresh = await buildSyncPreview(store, session, true);
  if (fresh.account.uuid !== reviewed.account.uuid || fresh.activity !== reviewed.activity) {
    throw new Error('Snapshot or account changed');
  }
  const rows = reviewed.rows.filter((row: SyncDifference) => row.kind === 'match');
  const verified = new Map<number, SyncDifference>();
  for (const row of fresh.rows) { verified.set(row.episodeId, row); }
  const updates: CommonUpdate[] = [];
  for (const row of rows) {
    const now = verified.get(row.episodeId);
    if (!now || now.kind !== 'match' || now.intentSeq !== row.intentSeq || now.localWatched !== row.localWatched ||
        now.cloudWatched !== row.cloudWatched) { throw new Error('Local intent changed'); }
    updates.push({ id: row.episodeId.toString(), value: row.localWatched });
  }
  await current(store, session, fresh.account.uuid, fresh.activity);
  return await store.saveCommonStates(fresh.account.uuid, 'episode', fresh.activity, updates);
}

export async function checkpointMedia(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  reviewed: MediaPreview, domain: string): Promise<number> {
  if (reviewed.account.generation !== session.generation || (domain !== 'movie' && domain !== 'watchlist')) {
    throw new Error('Invalid checkpoint');
  }
  const fresh = await buildMediaPreview(binding, session, await store.load(), reviewed.account.uuid, store);
  if (fresh.activity !== reviewed.activity) { throw new Error('Snapshot or account changed'); }
  const rows = reviewed.rows.filter((row: MediaDifference) => row.domain === domain && row.category === 'match' && !row.operation);
  const verified = new Map<string, MediaDifference>();
  for (const row of fresh.rows) { if (row.domain === domain) { verified.set(row.id, row); } }
  const updates: CommonUpdate[] = [];
  for (const row of rows) {
    const now = verified.get(row.id);
    if (!now || now.category !== 'match' || now.operation || now.local !== row.local || now.remote !== row.remote ||
        now.operationSeq !== row.operationSeq) { throw new Error('Local intent changed'); }
    updates.push({ id: row.id, value: row.remote });
  }
  await current(binding, session, fresh.account.uuid, fresh.activity);
  return await store.saveCommonStates(fresh.account.uuid, domain, fresh.activity, updates);
}

export async function adoptEpisodeCloud(store: EpisodeStore, session: TraktSession, reviewed: SyncPreview,
  selected: SyncDifference): Promise<void> {
  if (reviewed.account.generation !== session.generation || selected.kind !== 'remote' || selected.threeWay !== 'remote' ||
      !reviewed.rows.some((row: SyncDifference) => row.episodeId === selected.episodeId && row.intentSeq === selected.intentSeq &&
        row.kind === 'remote')) { throw new Error('Invalid reviewed selection'); }
  const fresh = await buildSyncPreview(store, session, true);
  const row = fresh.rows.find((item: SyncDifference) => item.episodeId === selected.episodeId);
  if (fresh.account.uuid !== reviewed.account.uuid || !row || row.kind !== 'remote' || row.threeWay !== 'remote' ||
      row.intentSeq !== selected.intentSeq || row.localWatched !== selected.localWatched ||
      row.cloudWatched !== selected.cloudWatched || row.baseline !== selected.baseline) {
    throw new Error('Snapshot or account changed');
  }
  await current(store, session, fresh.account.uuid, fresh.activity);
  await store.adoptRemote(fresh.account.uuid, row.episodeId, row.intentSeq, row.cloudWatched, fresh.activity);
}

export async function adoptMediaCloud(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  reviewed: MediaPreview, selected: MediaDifference): Promise<MediaRecord[]> {
  if (reviewed.account.generation !== session.generation || selected.category !== 'remote' ||
      selected.threeWay !== 'remote' || selected.operation ||
      !reviewed.rows.some((row: MediaDifference) => row.id === selected.id && row.domain === selected.domain &&
        row.category === 'remote' && !row.operation)) { throw new Error('Invalid reviewed selection'); }
  const fresh = await buildMediaPreview(binding, session, await store.load(), reviewed.account.uuid, store);
  const row = fresh.rows.find((item: MediaDifference) => item.id === selected.id && item.domain === selected.domain);
  if (!row || row.category !== 'remote' || row.threeWay !== 'remote' || row.operation ||
      row.operationSeq !== selected.operationSeq || row.local !== selected.local ||
      row.remote !== selected.remote || row.baseline !== selected.baseline) {
    throw new Error('Snapshot or account changed');
  }
  await current(binding, session, fresh.account.uuid, fresh.activity);
  return await store.adoptRemote(fresh.account.uuid, row.domain, row.id, row.remote, fresh.activity);
}
