import { Media } from '../model/Media';
import { MediaRecord, isTraktMedia } from '../model/MediaState';
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
}
export interface MediaPreview {
  account: SyncAccount;
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
      category: classifyMedia(local, exists, true) });
    remoteIds.delete(media.id);
  }
  for (const media of remoteIds.values()) {
    rows.push({ id: media.id, title: media.title, domain: domain, local: 'unknown', remote: true,
      category: classifyMedia('unknown', true, false) });
  }
  return rows;
}

export async function buildMediaPreview(store: EpisodeStore, session: TraktSession,
  records: MediaRecord[], expectedUuid: string): Promise<MediaPreview> {
  const account = await readSyncAccount(session);
  if (account.uuid !== expectedUuid || await store.boundAccount() !== expectedUuid) {
    throw new Error('Account mismatch');
  }
  const snapshot = await readCloudMedia(session);
  const verified = await readSyncAccount(session);
  if (verified.uuid !== expectedUuid || await store.boundAccount() !== expectedUuid ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Account changed'); }
  return { account: verified, watchedCount: snapshot.watchedMovies.length,
    watchlistCount: snapshot.watchlist.length,
    excluded: records.filter((record: MediaRecord) => !isTraktMedia(record.media)).length,
    rows: [...compareDomain(records, snapshot.watchedMovies, 'movie'),
      ...compareDomain(records, snapshot.watchlist, 'watchlist')] };
}
