import { Media } from '../model/Media';
import { MediaRecord, isTraktMedia } from '../model/MediaState';
import { CommonUpdate } from '../model/ThreeWay';
import { TitleConsent, TitleIntent, titleValue, quickDisposition, canAdoptTitle } from '../model/TitleQuickState';
import { RemoteLibraryObservation } from '../model/RemoteObservation';
import { MediaStore } from './MediaStore';
import { EpisodeStore } from './EpisodeStore';
import { TraktSession, traktAuth } from './TraktAuth';
import { readSyncAccount } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
import { MediaDifference, buildMediaPreview } from './TraktMediaPreview';
import { syncSelectedMedia, reconcilePendingMedia } from './TraktMediaSync';

async function currentAccount(binding: EpisodeStore, session: TraktSession, uuid: string): Promise<void> {
  const account = await readSyncAccount(session);
  if (account.uuid !== uuid || await binding.boundAccount() !== uuid ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Account changed'); }
}
async function currentSnapshot(binding: EpisodeStore, session: TraktSession, uuid: string, activity: string): Promise<void> {
  await currentAccount(binding, session, uuid);
  if (await readActivity(session) !== activity ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Snapshot changed'); }
}

// Reconcile only complete verified observations, never import them as new
// auto intents. A remote-only change is adopted only from a proven baseline.
export async function reconcileTitleObservation(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  uuid: string, snapshot: RemoteLibraryObservation, current: () => boolean): Promise<MediaRecord[]> {
  const records = await store.load();
  const intents = await store.titleIntents(uuid);
  for (const domain of ['movie','watchlist']) {
    const ids: Set<string> = new Set<string>((domain === 'movie' ? snapshot.watchedMovies : snapshot.watchlist)
      .map((item: Media) => item.id));
    const baseline = await store.commonStates(uuid, domain);
    const matches: CommonUpdate[] = [];
    const settled: number[] = [];
    for (const record of records) {
      if (!isTraktMedia(record.media) || (domain === 'movie' && record.media.kind !== 'movie')) { continue; }
      const local = titleValue(record, domain);
      if (local === 'unknown') { continue; }
      const id = record.media.id;
      const remote = ids.has(id);
      const intent = intents.find((row: TitleIntent) => row.id === id && row.domain === domain);
      const op = await store.latestOperation(uuid, domain, id);
      if (op?.state === 'pending') { continue; }
      if ((local === 'yes') === remote) {
        if (baseline.get(id)?.value !== remote) { matches.push({ id: id, value: remote }); }
        if (intent && intent.value === local && intent.state !== 'settled') { settled.push(intent.seq); }
      } else if (canAdoptTitle(local, remote, baseline.get(id), intent, false) &&
          !(domain === 'watchlist' && remote && record.followState === 'yes')) {
        await currentSnapshot(binding, session, uuid, snapshot.activity);
        if (!current()) { throw new Error('Session changed'); }
        await store.adoptRemote(uuid, domain, id, remote, snapshot.activity);
      }
    }
    if (matches.length || settled.length) {
      await currentSnapshot(binding, session, uuid, snapshot.activity);
      if (!current()) { throw new Error('Session changed'); }
      await store.saveCommonStates(uuid, domain, snapshot.activity, matches);
      for (const seq of settled) { await store.finishTitleIntent(uuid, seq, 'settled'); }
    }
  }
  return await store.load();
}
export interface TitleQuickResult {
  attempted: number;
  remaining: number;
  review: number;
  message: string;
}
export async function runTitleQuick(store: MediaStore, binding: EpisodeStore, session: TraktSession,
  consent: TitleConsent, current: () => boolean): Promise<TitleQuickResult> {
  let attempted = 0;
  const uuid = consent.uuid;
  await currentAccount(binding, session, uuid);
  if (!current()) { throw new Error('Foreground ended'); }
  // Recovery is read-only, and must precede every new write.
  const recovered = await reconcilePendingMedia(store, binding, session, uuid);
  if (recovered.remaining || recovered.failed) {
    return { attempted: 0, remaining: recovered.remaining, review: recovered.failed,
      message: '存在未确认操作，已暂停快捷同步；不会重发。' };
  }
  const intents = await store.titleIntents(uuid);
  for (const intent of intents) {
    if (intent.state !== 'open' || intent.epoch !== consent.epoch) { continue; }
    const durable = await store.titleConsent();
    if (!current() || durable?.epoch !== consent.epoch || durable.uuid !== uuid ||
        durable.clientId !== session.clientId) { break; }
    const records = await store.load();
    const record = records.find((row: MediaRecord) => row.media.id === intent.id);
    if (!record || titleValue(record, intent.domain) !== intent.value) {
      await store.finishTitleIntent(uuid, intent.seq, 'review');
      continue;
    }
    const preview = await buildMediaPreview(binding, session, records, uuid, store);
    const row = preview.rows.find((item: MediaDifference) => item.id === intent.id && item.domain === intent.domain);
    const prior = await store.latestOperation(uuid, intent.domain, intent.id);
    if (!row || !current()) { break; }
    const decision = quickDisposition(intent, row.local, row.remote, row.operation, prior?.seq ?? 0,
      prior?.state ?? '', prior?.action ?? '', consent.epoch);
    if (decision === 'readback') { break; }
    if (decision === 'matched') {
      await currentSnapshot(binding, session, uuid, preview.activity);
      if (!current()) { break; }
      await store.saveCommonStates(uuid, intent.domain, preview.activity, [{ id: intent.id, value: row.remote }]);
      await store.finishTitleIntent(uuid, intent.seq, 'settled');
      continue;
    }
    if (decision !== 'send') {
      await store.finishTitleIntent(uuid, intent.seq, decision === 'settled' ? 'settled' : 'review');
      continue;
    }
    // Reuse the reviewed single-target writer. It rechecks account, activity,
    // duplicate history and side effects, reserves before POST and reads back.
    attempted++;
    await syncSelectedMedia(store, binding, session, preview, row, intent.watchedAt, current);
    const after = await store.latestOperation(uuid, intent.domain, intent.id);
    if (!after || after.seq <= intent.operationSeq || after.state !== 'verified' ||
        after.action !== (intent.value === 'yes' ? 'add' : 'remove')) {
      await store.finishTitleIntent(uuid, intent.seq, 'review');
      break;
    }
    await store.finishTitleIntent(uuid, intent.seq, 'settled');
  }
  const rest = await store.titleIntents(uuid);
  const remaining = rest.filter((row: TitleIntent) => row.state === 'open' && row.epoch === consent.epoch).length;
  const review = rest.filter((row: TitleIntent) => row.state === 'review' ||
    (row.state === 'open' && row.epoch !== consent.epoch)).length;
  return { attempted: attempted, remaining: remaining, review: review,
    message: '快捷同步：待处理 ' + remaining + ' 项，需确认 ' + review + ' 项。' };
}
