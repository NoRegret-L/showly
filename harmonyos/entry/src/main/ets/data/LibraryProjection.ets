import { Media } from '../model/Media';
import { MediaRecord } from '../model/MediaState';
import { LibraryShowEvidence, PersonalLibraryRow, buildPersonalLibrary, hasTrackingEvidence } from '../model/PersonalLibrary';
import { RemoteLibraryObservation, RemoteShowObservation, RemotePlayPosition, EpisodeDecision, observedSections } from '../model/RemoteObservation';
import { scheduleEpisodes } from '../model/ShowCatalog';
import { EpisodeStore, EpisodeBackupState, JournalIntent, fetchFullEpisodeCatalog } from './EpisodeStore';

export interface LibraryProjection {
  evidence: LibraryShowEvidence[];
  missing: number;
  failed: number;
}
export async function projectLibrary(store: EpisodeStore, records: MediaRecord[],
  cloud: RemoteLibraryObservation | undefined, uuid: string, clientId: string, fill: boolean,
  current: () => boolean, progress: (done: number, total: number) => void): Promise<LibraryProjection> {
  const bound = await store.boundAccount();
  const localAllowed = !cloud || !bound || bound === uuid;
  const states: EpisodeBackupState[] = localAllowed ? await store.backupStates() : [];
  const intents: JournalIntent[] = localAllowed ? await store.journalIntents() : [];
  const local: LibraryShowEvidence[] = states.map((state: EpisodeBackupState): LibraryShowEvidence => {
    const media: Media = { id: state.catalog.showId, kind: 'show', title: state.catalog.title,
      year: state.catalog.year, watched: false };
    return { media: media, watchedEpisodes: state.watchedIds.length };
  });
  const remote: LibraryShowEvidence[] = (cloud?.shows ?? []).map((show: RemoteShowObservation): LibraryShowEvidence => {
    const media: Media = { id: show.id, kind: 'show', title: show.title, year: show.year ?? 0, watched: false };
    return { media: media, watchedEpisodes: show.watchedEpisodes };
  });
  const members = buildPersonalLibrary(records, cloud?.watchedMovies ?? [], cloud?.watchlist ?? [], remote, local);
  const targets = members.filter((row: PersonalLibraryRow) => row.media.kind === 'show' && (hasTrackingEvidence(row) || row.queued));
  const byId: Map<string, EpisodeBackupState> = new Map<string, EpisodeBackupState>();
  for (const state of states) { byId.set(state.catalog.showId, state); }
  const remoteById: Map<string, RemoteShowObservation> = new Map<string, RemoteShowObservation>();
  for (const show of cloud?.shows ?? []) { remoteById.set(show.id, show); }
  const decisionsByShow: Map<string, EpisodeDecision[]> = new Map<string, EpisodeDecision[]>();
  for (const intent of intents) {
    let decisions = decisionsByShow.get(intent.showId);
    if (!decisions) { decisions = []; decisionsByShow.set(intent.showId, decisions); }
    decisions.push({ episodeId: intent.episodeId, watched: intent.watched });
  }
  const result: LibraryShowEvidence[] = [];
  let missing = 0;
  let failed = 0;
  let done = 0;
  const now = Date.now();
  for (const row of targets) {
    if (!current()) { throw new Error('Observation session changed'); }
    const show = remoteById.get(row.media.id);
    let full = await store.fullCatalog(row.media.id);
    const stale = !!show?.updatedAt && !!full && Date.parse(show.updatedAt) > full.fetchedAt;
    // Existing missing positions also force repair, even when activity is unchanged.
    const positions: Set<string> = new Set<string>();
    if (full) {
      for (const episode of scheduleEpisodes(full)) { positions.add(episode.season + ':' + episode.number); }
    }
    const unmatched = (show?.positions ?? []).some((pos: RemotePlayPosition) => pos.season > 0 && !positions.has(pos.season + ':' + pos.number));
    if (fill && clientId && (!full || stale || unmatched || !full.status)) {
      try {
        const fresh = await fetchFullEpisodeCatalog(row.media, clientId);
        if (!current()) { throw new Error('Observation session changed'); }
        await store.saveObservedSchedule(fresh);
        full = fresh;
      } catch (error) {
        if (!current()) { throw new Error('Observation session changed'); }
        failed++;
        // Stop additional network attempts on failure (including 429); other
        // cached targets can still be projected. Next refresh resumes missing.
        fill = false;
      }
    }
    if (!full) { missing++; }
    const state = byId.get(row.media.id);
    const ids = state?.watchedIds ?? [];
    // With a complete current-account observation, absent remote show means
    // no cloud plays; retain only explicit local decisions, not stale imports.
    const localIds = cloud ? [] : ids;
    const sections = full ? observedSections(full, show, localIds,
      decisionsByShow.get(row.media.id) ?? [], now) : [];
    result.push({ media: row.media, watchedEpisodes: state ? ids.length : -1,
      sections: sections, merged: !!cloud });
    progress(++done, targets.length);
  }
  return { evidence: result, missing: missing, failed: failed };
}
