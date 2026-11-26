import { Media } from '../model/Media';
import { MediaRecord } from '../model/MediaState';
import { LibraryShowEvidence, PersonalLibraryRow, buildPersonalLibrary, hasTrackingEvidence } from '../model/PersonalLibrary';
import { RemoteLibraryObservation, RemoteShowObservation, RemotePlayPosition } from '../model/RemoteObservation';
import { FullEpisodeCatalog, scheduleEpisodes, showSections } from '../model/ShowCatalog';
import { CommonEntry } from '../model/ThreeWay';
import { ReadCheckpoint, ReadDecision, EffectiveEpisodes, allowLocalScope, resolveEpisodes } from '../model/EffectiveState';
import { EpisodeStore, EpisodeBackupState, JournalIntent, LocalSeriesState, eligibleCatalog, materializeEffective, fetchFullEpisodeCatalog } from './EpisodeStore';

export interface LibraryProjection {
  evidence: LibraryShowEvidence[];
  missing: number;
  failed: number;
  localAllowed: boolean;
  matches: ReadCheckpoint[];
}
export async function projectLibrary(store: EpisodeStore, records: MediaRecord[],
  cloud: RemoteLibraryObservation | undefined, uuid: string, clientId: string, fill: boolean,
  current: () => boolean, progress: (done: number, total: number) => void): Promise<LibraryProjection> {
  const bound = await store.boundAccount();
  const localAllowed = allowLocalScope(!!cloud, bound, uuid);
  const checkpoints = cloud && localAllowed ? await store.readCheckpoints(uuid) : new Map<number, ReadCheckpoint>();
  const common = cloud && localAllowed ? await store.commonStates(uuid, 'episode') : new Map<string, CommonEntry>();
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
  const members = buildPersonalLibrary(localAllowed ? records : [], cloud?.watchedMovies ?? [], cloud?.watchlist ?? [], remote, local);
  const targets = members.filter((row: PersonalLibraryRow) => row.media.kind === 'show' && (hasTrackingEvidence(row) || row.queued));
  const byId: Map<string, EpisodeBackupState> = new Map<string, EpisodeBackupState>();
  for (const state of states) { byId.set(state.catalog.showId, state); }
  const remoteById: Map<string, RemoteShowObservation> = new Map<string, RemoteShowObservation>();
  for (const show of cloud?.shows ?? []) { remoteById.set(show.id, show); }
  const decisionsByShow: Map<string, ReadDecision[]> = new Map<string, ReadDecision[]>();
  for (const intent of intents) {
    let decisions = decisionsByShow.get(intent.showId);
    if (!decisions) { decisions = []; decisionsByShow.set(intent.showId, decisions); }
    decisions.push({ episodeId: intent.episodeId, watched: intent.watched, seq: intent.seq });
  }
  const result: LibraryShowEvidence[] = [];
  const matches: ReadCheckpoint[] = [];
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
    const effective = full ? resolveEpisodes(full, show, !!cloud, ids,
      decisionsByShow.get(row.media.id) ?? [], checkpoints, common) : undefined;
    if (effective && effective.complete) {
      for (const match of effective.matches) { matches.push(match); }
    }
    const sections = full && effective?.complete ? showSections(full, effective.ids, now) : [];
    result.push({ media: row.media, watchedEpisodes: state ? ids.length : -1,
      sections: sections, merged: !!cloud });
    progress(++done, targets.length);
  }
  return { evidence: result, missing: missing, failed: failed, localAllowed: localAllowed, matches: matches };
}

export interface DetailProjection {
  state?: LocalSeriesState;
  localAllowed: boolean;
  complete: boolean;
}
// The very same resolver as collection. Public schedule is sufficient to
// render aired episodes; never save it into the eligible catalog on read.
export async function projectDetail(store: EpisodeStore, full: FullEpisodeCatalog | undefined,
  showId: string, cloud: RemoteLibraryObservation | undefined, uuid: string): Promise<DetailProjection> {
  const bound = await store.boundAccount();
  const localAllowed = allowLocalScope(!!cloud, bound, uuid);
  const local = localAllowed ? await store.read(showId) : undefined;
  if (!full) {
    return { state: cloud ? undefined : local, localAllowed: localAllowed, complete: !cloud };
  }
  const localIds: number[] = [];
  for (const season of local?.seasons ?? []) {
    for (const episode of season.episodes) { if (episode.watched) { localIds.push(episode.episode.id); } }
  }
  const intents = localAllowed ? await store.journalIntents() : [];
  const decisions = intents.filter((intent: JournalIntent) => intent.showId === showId)
    .map((intent: JournalIntent): ReadDecision => {
      return { episodeId: intent.episodeId, watched: intent.watched, seq: intent.seq };
    });
  const checkpoints = cloud && localAllowed ? await store.readCheckpoints(uuid) : new Map<number, ReadCheckpoint>();
  const common = cloud && localAllowed ? await store.commonStates(uuid, 'episode') : new Map<string, CommonEntry>();
  const remote = cloud?.shows.find((show: RemoteShowObservation) => show.id === showId);
  const effective = resolveEpisodes(full, remote, !!cloud, localIds, decisions, checkpoints, common);
  return { state: effective.complete ? materializeEffective(eligibleCatalog(full, Date.now()), effective.ids) : undefined,
    localAllowed: localAllowed, complete: effective.complete };
}
