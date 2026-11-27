import { taskpool } from '@kit.ArkTS';
import { Media } from '../model/Media';
import { ProjectionInput, ProjectionOutput, computeProjection, ShowProjectionCache, showProjectionKey } from '../model/ProjectionCompute';
import { computeProjectionTask } from './ProjectionTask';
import { MediaRecord } from '../model/MediaState';
import { LibraryShowEvidence, PersonalLibraryRow, buildPersonalLibrary, hasTrackingEvidence } from '../model/PersonalLibrary';
import { RemoteLibraryObservation, RemoteShowObservation, RemotePlayPosition } from '../model/RemoteObservation';
import { FullEpisodeCatalog, scheduleEpisodes } from '../model/ShowCatalog';
import { CommonEntry } from '../model/ThreeWay';
import { NextShow, projectShow } from './NextShows';
import { TimedDecision } from '../model/ProgressRules';
import { ReadCheckpoint, ReadDecision, EffectiveEpisodes, allowLocalScope, resolveEpisodes } from '../model/EffectiveState';
import { EpisodeStore, EpisodeBackupState, JournalIntent, LocalSeriesState, eligibleCatalog, materializeEffective, fetchFullEpisodeCatalog } from './EpisodeStore';

export interface LibraryProjection {
  evidence: LibraryShowEvidence[];
  missing: number;
  failed: number;
  localAllowed: boolean;
  matches: ReadCheckpoint[];
  next: NextShow[];
  computedAt: number;
  validUntil: number;
  cacheable: boolean;
  computedShows: number;
  reusedShows: number;
}
export async function projectLibrary(store: EpisodeStore, records: MediaRecord[],
  cloud: RemoteLibraryObservation | undefined, uuid: string, clientId: string, fill: boolean,
  current: () => boolean, progress: (done: number, total: number) => void,
  cache: ShowProjectionCache): Promise<LibraryProjection> {
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
  const timedByShow: Map<string, TimedDecision[]> = new Map<string, TimedDecision[]>();
  for (const intent of intents) {
    let decisions = decisionsByShow.get(intent.showId);
    if (!decisions) { decisions = []; decisionsByShow.set(intent.showId, decisions); }
    decisions.push({ episodeId: intent.episodeId, watched: intent.watched, seq: intent.seq });
    let timed = timedByShow.get(intent.showId);
    if (!timed) { timed = []; timedByShow.set(intent.showId, timed); }
    timed.push({ episodeId: intent.episodeId, watched: intent.watched, seq: intent.seq, changedAt: intent.changedAt });
  }
  const result: LibraryShowEvidence[] = [];
  const matches: ReadCheckpoint[] = [];
  const next: NextShow[] = [];
  const latest: Map<string, number> = new Map<string, number>();
  for (const intent of intents) { latest.set(intent.showId, Math.max(latest.get(intent.showId) ?? 0, intent.seq)); }
  let missing = 0;
  let failed = 0;
  let done = 0;
  const now = Date.now();
  cache.begin(JSON.stringify([clientId, uuid, cloud?.generation ?? -1, localAllowed]));
  const retained = new Set<string>();
  let cacheable = true;
  let computedShows = 0;
  let reusedShows = 0;
  let validUntil = Number.MAX_SAFE_INTEGER;
  for (const row of targets) {
    if (!current()) { throw new Error('Observation session changed'); }
    retained.add(row.media.id);
    const show = remoteById.get(row.media.id);
    let full = await store.fullCatalog(row.media.id);
    const stale = !!show?.updatedAt && !!full && Date.parse(show.updatedAt) > full.fetchedAt;
    // Existing missing positions also force repair, even when activity is unchanged.
    const positions: Set<string> = new Set<string>();
    if (full) {
      for (const episode of scheduleEpisodes(full)) { positions.add(episode.season + ':' + episode.number); }
    }
    const unmatched = (show?.positions ?? []).some((pos: RemotePlayPosition) => pos.season > 0 && !positions.has(pos.season + ':' + pos.number));
    const needsRepair = !full || stale || unmatched || !full.status;
    if (needsRepair && (!fill || !clientId)) { cacheable = false; }
    if (fill && clientId && needsRepair) {
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
    let calculated: ProjectionOutput | undefined;
    if (full) {
      const decisions = decisionsByShow.get(row.media.id) ?? [];
      const timed = timedByShow.get(row.media.id) ?? [];
      // Only the checkpoint and baseline entries used by this show cross threads.
      const cp: ReadCheckpoint[] = [];
      const baseline: CommonEntry[] = [];
      for (const decision of decisions) {
        const checkpoint = checkpoints.get(decision.episodeId);
        const entry = common.get(decision.episodeId.toString());
        if (checkpoint) { cp.push(checkpoint); }
        if (entry) { baseline.push(entry); }
      }
      const input: ProjectionInput = { full: full, remote: show, cloudActive: !!cloud, localIds: ids,
        decisions: decisions, timed: timed, checkpoints: cp, common: baseline, now: now };
      const key = showProjectionKey(input);
      calculated = cache.get(row.media.id, key, now);
      if (calculated) { reusedShows++; }
      else {
        computedShows++;
        try {
          const serialized = await taskpool.execute(computeProjectionTask, JSON.stringify(input)) as string;
          calculated = JSON.parse(serialized) as ProjectionOutput;
        } catch (error) {
          // Same pure resolver; fallback never changes authorization or writes.
          calculated = computeProjection(input);
        }
        if (current()) { cache.put(row.media.id, key, now, calculated); }
      }
      if (!current()) { throw new Error('Observation session changed'); }
      validUntil = Math.min(validUntil, calculated.validUntil);
    }
    const effective = calculated?.effective;
    if (!effective?.complete || !full?.status) { cacheable = false; }
    if (effective && effective.complete) {
      for (const match of effective.matches) {
        const prior = checkpoints.get(match.id);
        if (!prior || match.seq > prior.seq || (match.seq === prior.seq && prior.watched !== match.watched)) { matches.push(match); }
      }
    }
    const sections = calculated?.sections ?? [];
    const progressState: EpisodeBackupState | undefined = full && effective?.complete ?
      { catalog: eligibleCatalog(full, now), watchedIds: effective.ids } : !cloud ? state : undefined;
    const progressRow = progressState ? projectShow(progressState, latest.get(row.media.id) ?? 0) : undefined;
    if (progressRow && hasTrackingEvidence(row)) {
      progressRow.sections = sections;
      if (full && effective?.complete) {
        progressRow.source = calculated?.source;
      }
      next.push(progressRow);
    }
    result.push({ media: row.media, watchedEpisodes: state ? ids.length : -1,
      sections: sections, merged: !!cloud, effectiveWatched: progressRow?.completed, effectiveTotal: progressRow?.total });
    progress(++done, targets.length);
  }
  cache.retain(retained);
  return { evidence: result, missing: missing, failed: failed, localAllowed: localAllowed, matches: matches, next: next,
    computedAt: now, validUntil: validUntil, cacheable: cacheable && !missing && !failed, computedShows: computedShows, reusedShows: reusedShows };
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
