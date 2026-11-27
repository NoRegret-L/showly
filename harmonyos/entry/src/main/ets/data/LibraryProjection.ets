import { taskpool } from '@kit.ArkTS';
import { summarizeAired } from '../model/BatchEpisodeRead';
import { Media } from '../model/Media';
import { ProjectionInput, ProjectionOutput, computeProjectionBatch, ShowProjectionCache, showProjectionStateKey, persistentProjectionScope, diskProjectionAllowed } from '../model/ProjectionCompute';
import { IndexedProjectionRow, indexedProjectionMatches, decodeIndexedProjection, encodeIndexedProjection } from '../model/IndexedProjection';
import { computeProjectionBatchTask } from './ProjectionTask';
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
  diskHits: number;
  scheduleParses: number;
  diskParses: number;
  diskWrites: number;
  workerBatches: number;
  repairTargets: Media[];
}
interface PreparedProjection {
  row: PersonalLibraryRow;
  full?: FullEpisodeCatalog;
  state?: EpisodeBackupState;
  ids: number[];
  input?: ProjectionInput;
  key: string;
  catalogKey: string;
  calculated?: ProjectionOutput;
  diskReusable: boolean;
}
export async function projectLibrary(store: EpisodeStore, records: MediaRecord[],
  cloud: RemoteLibraryObservation | undefined, uuid: string, clientId: string, fill: boolean,
  current: () => boolean, progress: (done: number, total: number) => void,
  cache: ShowProjectionCache): Promise<LibraryProjection> {
  const readOnly = !fill;
  const revision = store.readModelRevision();
  const bound = await store.boundAccount();
  const localAllowed = allowLocalScope(!!cloud, bound, uuid);
  const checkpoints = cloud && localAllowed ? await store.readCheckpoints(uuid) : new Map<number, ReadCheckpoint>();
  const common = cloud && localAllowed ? await store.commonStates(uuid, 'episode') : new Map<string, CommonEntry>();
  const inputs = localAllowed ? await store.projectionLocalInputs(bound) : undefined;
  const states: EpisodeBackupState[] = inputs?.states ?? [];
  const intents: JournalIntent[] = inputs?.intents ?? [];
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
  const targetIds = new Set<string>(targets.map((row: PersonalLibraryRow) => row.media.id));
  const parseStart = store.projectionScheduleParseCount();
  const schedules = await store.projectionCatalogs(targetIds);
  const scheduleParses = store.projectionScheduleParseCount() - parseStart;
  if (!current() || store.readModelRevision() !== revision) { throw new Error('Projection inputs changed'); }
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
  const diskScope = persistentProjectionScope(clientId, uuid, !!cloud, localAllowed);
  const disk = await store.readProjectionRows(diskScope,targetIds);
  const changedDisk: IndexedProjectionRow[] = [];
  const removedDisk: string[] = [];
  const prepared: PreparedProjection[] = [];
  const pending: ProjectionInput[] = [];
  const pendingRows: PreparedProjection[] = [];
  const repairTargets: Media[] = [];
  let diskHits = 0;
  let diskParses = 0;
  let workerBatches = 0;
  let cacheable = true;
  let computedShows = 0;
  let reusedShows = 0;
  let validUntil = Number.MAX_SAFE_INTEGER;
  for (const row of targets) {
    if (!current()) { throw new Error('Observation session changed'); }
    retained.add(row.media.id);
    const show = remoteById.get(row.media.id);
    let full = schedules.get(row.media.id);
    const stale = !!show?.updatedAt && !!full && Date.parse(show.updatedAt) > full.fetchedAt;
    // Existing missing positions also force repair, even when activity is unchanged.
    const positions: Set<string> = new Set<string>();
    if (full) {
      for (const episode of scheduleEpisodes(full)) { positions.add(episode.season + ':' + episode.number); }
    }
    const unmatched = (show?.positions ?? []).some((pos: RemotePlayPosition) => pos.season > 0 && !positions.has(pos.season + ':' + pos.number));
    const needsRepair = !full || stale || unmatched || !full.status;
    if (needsRepair) { repairTargets.push(row.media); }
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
    const work: PreparedProjection = { row: row, full: full, state: state, ids: ids,
      key: '', catalogKey: '', diskReusable: false };
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
      work.input = input;
      work.key = showProjectionStateKey(input);
      work.catalogKey = store.projectionCatalogKey(full);
      let calculated = cache.get(row.media.id,work.key,now,work.catalogKey);
      const prior = disk.get(row.media.id);
      const metadataMatch = indexedProjectionMatches(prior,input,work.catalogKey,work.key);
      if (calculated) {
        work.diskReusable = metadataMatch;
      } else if (prior && metadataMatch) {
        diskParses++;
        calculated = decodeIndexedProjection(prior,input,work.catalogKey,work.key);
        if (calculated) {
          diskHits++;
          work.diskReusable = true;
          cache.put(row.media.id,work.key,now,calculated,work.catalogKey);
        }
      }
      if (calculated) {
        work.calculated = calculated;
        reusedShows++;
      } else {
        pending.push(input);
        pendingRows.push(work);
      }
    }
    prepared.push(work);
  }
  if (!current() || (readOnly && store.readModelRevision() !== revision)) { throw new Error('Observation inputs changed'); }
  if (pending.length) {
    computedShows = pending.length;
    workerBatches++;
    let outputs: ProjectionOutput[];
    try {
      const serialized = await taskpool.execute(computeProjectionBatchTask, JSON.stringify(pending)) as string;
      outputs = JSON.parse(serialized) as ProjectionOutput[];
      if (outputs.length !== pending.length) { throw new Error('Incomplete projection batch'); }
    } catch (error) {
      outputs = computeProjectionBatch(pending);
    }
    if (!current() || (readOnly && store.readModelRevision() !== revision)) { throw new Error('Observation inputs changed'); }
    for (let i = 0; i < pendingRows.length; i++) {
      const work = pendingRows[i];
      work.calculated = outputs[i];
      cache.put(work.row.media.id,work.key,now,outputs[i],work.catalogKey);
    }
  }
  for (const work of prepared) {
    if (!current()) { throw new Error('Observation session changed'); }
    const row = work.row;
    const full = work.full;
    const state = work.state;
    const ids = work.ids;
    const calculated = work.calculated;
    const input = work.input;
    if (calculated) { validUntil = Math.min(validUntil,calculated.validUntil); }
    if (calculated && input && calculated.effective.complete && diskProjectionAllowed(input)) {
      if (!work.diskReusable) { changedDisk.push(encodeIndexedProjection(input,work.catalogKey,work.key,calculated)); }
    } else if (disk.has(row.media.id)) { removedDisk.push(row.media.id); }
    const effective = calculated?.effective;
    if (!effective?.complete || !full?.status) { cacheable = false; }
    if (effective && effective.complete) {
      for (const match of effective.matches) {
        const prior = checkpoints.get(match.id);
        if (!prior || match.seq > prior.seq || (match.seq === prior.seq && prior.watched !== match.watched)) { matches.push(match); }
      }
    }
    const sections = calculated?.sections ?? [];
    let progressRow: NextShow | undefined;
    const lastSeq = latest.get(row.media.id) ?? 0;
    if (full && effective?.complete) {
      const summary = summarizeAired(full,effective.ids,now);
      progressRow = { media: { id: full.media.id, kind: 'show', title: full.media.title,
        year: full.media.year, watched: false }, total: summary.total, completed: summary.completed,
        nextSeason: summary.nextSeason, nextNumber: summary.nextNumber, nextTitle: summary.nextTitle, lastSeq: lastSeq };
    } else if (!cloud && state) { progressRow = projectShow(state,lastSeq); }
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
  if (!current() || (readOnly && store.readModelRevision() !== revision)) { throw new Error('Observation inputs changed'); }
  if (changedDisk.length) { await store.saveProjectionRows(diskScope,changedDisk); }
  if (removedDisk.length) { await store.removeProjectionRows(diskScope,removedDisk); }
  if (!current() || (readOnly && store.readModelRevision() !== revision)) { throw new Error('Observation inputs changed'); }
  return { evidence: result, missing: missing, failed: failed, localAllowed: localAllowed, matches: matches, next: next,
    computedAt: now, validUntil: validUntil, cacheable: cacheable && !missing && !failed, computedShows: computedShows, reusedShows: reusedShows, diskHits: diskHits, scheduleParses: scheduleParses,
    diskParses: diskParses, diskWrites: changedDisk.length, workerBatches: workerBatches, repairTargets: repairTargets };
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
