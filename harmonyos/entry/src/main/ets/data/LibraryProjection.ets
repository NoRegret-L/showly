import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';
import { replaceProjectionRows, sameProjectionMembers, utf8ProjectionBytes } from '../model/ProjectionRows';
import { taskpool } from '@kit.ArkTS';
import { CalendarSource } from '../model/CalendarRules';
import { summarizeAired } from '../model/BatchEpisodeRead';
import { Media } from '../model/Media';
import { ProjectionInput, ProjectionOutput, computeProjectionBatch, ShowProjectionCache, persistentProjectionScope, diskProjectionAllowed } from '../model/ProjectionCompute';
import { IndexedProjectionRow, indexedProjectionMatches, decodeIndexedProjection, encodeIndexedProjection } from '../model/IndexedProjection';
import { computeProjectionBatchTask } from './ProjectionTask';
import { MediaRecord } from '../model/MediaState';
import { LibraryShowEvidence, PersonalLibraryRow, buildPersonalLibrary, hasTrackingEvidence } from '../model/PersonalLibrary';
import { RemoteLibraryObservation, RemoteShowObservation, RemotePlayPosition } from '../model/RemoteObservation';
import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes } from '../model/ShowCatalog';
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
  calendar: CalendarSource[];
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
  visitedShows:number;
  workerInputBytes:number;
  repairTargets: Media[];
}
interface ProjectionScope {
  ids:Set<string>;
  records:MediaRecord[];
  shows:RemoteShowObservation[];
  watchlist:Media[];
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
  cache: ShowProjectionCache,scope?:ProjectionScope): Promise<LibraryProjection> {
  const readOnly = !fill;
  const revision = store.assertProjectionReadable();
  const bound = await store.boundAccount();
  const localAllowed = allowLocalScope(!!cloud, bound, uuid);
  const checkpoints = cloud && localAllowed ? (readOnly ? await store.projectionCheckpoints(uuid) : await store.readCheckpoints(uuid)) : new Map<number, ReadCheckpoint>();
  const common = cloud && localAllowed ? (readOnly ? await store.projectionCommonStates(uuid) : await store.commonStates(uuid, 'episode')) : new Map<string, CommonEntry>();
  const inputs = localAllowed ? (readOnly ? (scope ? await store.projectionReadInputs(bound,scope.ids) : await store.projectionReadInputs(bound)) : await store.projectionLocalInputs(bound)) : undefined;
  const states: EpisodeBackupState[] = inputs?.states ?? [];
  const intents: JournalIntent[] = inputs?.intents ?? [];
  const local: LibraryShowEvidence[] = states.map((state: EpisodeBackupState): LibraryShowEvidence => {
    const media: Media = { id: state.catalog.showId, kind: 'show', title: state.catalog.title,
      year: state.catalog.year, watched: false };
    return { media: media, watchedEpisodes: state.watchedIds.length };
  });
  const remoteShows=scope ? scope.shows : cloud?.shows ?? [];
  const remote: LibraryShowEvidence[] = remoteShows.map((show: RemoteShowObservation): LibraryShowEvidence => {
    const media: Media = { id: show.id, kind: 'show', title: show.title, year: show.year ?? 0, watched: false };
    return { media: media, watchedEpisodes: show.watchedEpisodes };
  });
  const members = buildPersonalLibrary(localAllowed ? (scope ? scope.records : records) : [], scope ? [] : cloud?.watchedMovies ?? [], scope ? scope.watchlist : cloud?.watchlist ?? [], remote, local);
  const targets = members.filter((row: PersonalLibraryRow) => row.media.kind === 'show' && (hasTrackingEvidence(row) || row.queued));
  const targetIds = new Set<string>(targets.map((row: PersonalLibraryRow) => row.media.id));
  const parseStart = store.projectionScheduleParseCount();
  const schedules = readOnly ? (scope ? await store.projectionReadCatalogs(targetIds,true) : await store.projectionReadCatalogs(targetIds)) : await store.projectionCatalogs(targetIds);
  const scheduleParses = store.projectionScheduleParseCount() - parseStart;
  if (!current() || !store.projectionReadable(revision)) { throw new Error('Projection inputs changed'); }
  const byId: Map<string, EpisodeBackupState> = new Map<string, EpisodeBackupState>();
  for (const state of states) { byId.set(state.catalog.showId, state); }
  const remoteById: Map<string, RemoteShowObservation> = new Map<string, RemoteShowObservation>();
  for (const show of remoteShows) { remoteById.set(show.id, show); }
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
  const calendar: CalendarSource[] = [];
  const latest: Map<string, number> = new Map<string, number>();
  for (const intent of intents) { latest.set(intent.showId, Math.max(latest.get(intent.showId) ?? 0, intent.seq)); }
  let missing = 0;
  let failed = 0;
  let done = 0;
  const now = Date.now();
  cache.begin(JSON.stringify([clientId, uuid, cloud?.generation ?? -1, localAllowed]));
  const retained = new Set<string>();
  const diskScope = persistentProjectionScope(clientId, uuid, !!cloud, localAllowed);
  const diskNeeded=new Set<string>();
  const changedDisk: IndexedProjectionRow[] = [];
  const removedDisk: string[] = [];
  const prepared: PreparedProjection[] = [];
  const pending: ProjectionInput[] = [];
  const pendingRows: PreparedProjection[] = [];
  const repairTargets: Media[] = [];
  let diskHits = 0;
  let diskParses = 0;
  let workerBatches = 0;
  let workerInputBytes=0;
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
    const positions: Set<string> = full ? store.projectionPositions(full) : new Set<string>();
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
      work.key = cache.stateKey(input);
      work.catalogKey = store.projectionCatalogKey(full);
      work.calculated=cache.get(row.media.id,work.key,now,work.catalogKey);
      work.diskReusable=!!work.calculated && cache.diskKnown(row.media.id,work.key,now,work.catalogKey);
      if (!work.diskReusable) { diskNeeded.add(row.media.id); }
    } else { diskNeeded.add(row.media.id); }
    prepared.push(work);
  }
  const disk=await store.readProjectionRows(diskScope,diskNeeded);
  if (!current() || (readOnly && !store.projectionReadable(revision))) { throw new Error('Observation inputs changed'); }
  for (const work of prepared) {
    const input=work.input;
    if (!input) { continue; }
    const id=work.row.media.id;
    const prior=disk.get(id);
    if (!work.diskReusable) {
      const metadataMatch=indexedProjectionMatches(prior,input,work.catalogKey,work.key);
      if (work.calculated) { work.diskReusable=metadataMatch; }
      else if (prior && metadataMatch) {
        diskParses++;
        work.calculated=decodeIndexedProjection(prior,input,work.catalogKey,work.key);
        if (work.calculated) {
          diskHits++; work.diskReusable=true;
          cache.put(id,work.key,now,work.calculated,work.catalogKey);
        }
      }
    }
    if (work.calculated) {
      if (work.diskReusable) { cache.markDiskKnown(id,work.key,work.catalogKey); }
      reusedShows++;
    } else { pending.push(input); pendingRows.push(work); }
  }
  if (pending.length) {
    computedShows = pending.length;
    workerBatches++;
    let outputs: ProjectionOutput[];
    try {
      const payload=JSON.stringify(pending);
      workerInputBytes=utf8ProjectionBytes(payload);
      const serialized = await taskpool.execute(computeProjectionBatchTask, payload) as string;
      outputs = JSON.parse(serialized) as ProjectionOutput[];
      if (outputs.length !== pending.length) { throw new Error('Incomplete projection batch'); }
    } catch (error) {
      outputs = computeProjectionBatch(pending);
    }
    if (!current() || (readOnly && !store.projectionReadable(revision))) { throw new Error('Observation inputs changed'); }
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
    calendar.push({media:row.media,full:full,watchedIds:effective?.complete ? effective.ids : undefined,queued:row.queued});
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
      const summary = calculated?.summary ?? summarizeAired(full,effective.ids,now);
      progressRow = { media: { id: full.media.id, kind: 'show', title: full.media.title,
        year: full.media.year, watched: false }, total: summary.total, completed: summary.completed,
        nextSeason: summary.nextSeason, nextNumber: summary.nextNumber, nextTitle: summary.nextTitle, lastSeq: lastSeq };
    } else if (!cloud && state) { progressRow = projectShow(state,lastSeq); }
    if (progressRow && hasTrackingEvidence(row)) {
      progressRow.sections = sections;
      if (full && effective?.complete) {
        progressRow.source = calculated?.source;
        progressRow.sourceStateKey = work.key;
        progressRow.sourceCatalogKey = work.catalogKey;
      }
      next.push(progressRow);
    }
    result.push({ media: row.media, watchedEpisodes: state ? ids.length : -1,
      sections: sections, merged: !!cloud, effectiveWatched: progressRow?.completed, effectiveTotal: progressRow?.total });
    progress(++done, targets.length);
  }
  if(!scope){cache.retain(retained);}
  if (!current() || (readOnly && !store.projectionReadable(revision))) { throw new Error('Observation inputs changed'); }
  if (changedDisk.length && await store.saveProjectionRows(diskScope,changedDisk)) {
    for (const row of changedDisk) { cache.markDiskKnown(row.id,row.key,row.catalogKey); }
  }
  if (removedDisk.length) { await store.removeProjectionRows(diskScope,removedDisk); }
  if (!current() || (readOnly && !store.projectionReadable(revision))) { throw new Error('Observation inputs changed'); }
  return { evidence: result, missing: missing, failed: failed, localAllowed: localAllowed, matches: matches, next: next, calendar: calendar,
    computedAt: now, validUntil: validUntil, cacheable: cacheable && !missing && !failed, computedShows: computedShows, reusedShows: reusedShows, diskHits: diskHits, scheduleParses: scheduleParses,
    diskParses: diskParses, diskWrites: changedDisk.length, workerBatches: workerBatches, visitedShows:targets.length, workerInputBytes:workerInputBytes, repairTargets: repairTargets };
}

// Separate consumer of committed changes; SQL read indexes may acknowledge
// their own invalidation without losing this view's pending changes.
export class LibraryProjectionSession {
  private prior?:LibraryProjection;
  private store?:EpisodeStore;
  private records?:MediaRecord[];
  private cloud?:RemoteLibraryObservation;
  private scopeKey:string='';
  private epoch:number=0;
  private traceId:number=0;
  private members:Set<string>=new Set<string>();
  private nextMembers:Set<string>=new Set<string>();
  private byRecord:Map<string,MediaRecord[]>=new Map<string,MediaRecord[]>();
  private byRemote:Map<string,RemoteShowObservation>=new Map<string,RemoteShowObservation>();
  private byQueue:Map<string,Media>=new Map<string,Media>();
  clear():void{
    this.epoch++;this.prior=undefined;this.store=undefined;this.records=undefined;this.cloud=undefined;this.scopeKey='';
    this.members.clear();this.nextMembers.clear();this.byRecord.clear();this.byRemote.clear();this.byQueue.clear();
  }
  private seed(store:EpisodeStore,records:MediaRecord[],cloud:RemoteLibraryObservation|undefined,key:string,result:LibraryProjection):void{
    this.clear();this.store=store;this.records=records;this.cloud=cloud;this.scopeKey=key;this.prior=result;
    for(const row of result.evidence){this.members.add(row.media.id);}
    for(const row of result.next){this.nextMembers.add(row.media.id);}
    for(const row of records){let list=this.byRecord.get(row.media.id);if(!list){list=[];this.byRecord.set(row.media.id,list);}list.push(row);}
    for(const row of cloud?.shows??[]){this.byRemote.set(row.id,row);}
    for(const row of cloud?.watchlist??[]){this.byQueue.set(row.id,row);}
  }
  private select(ids:Set<string>):ProjectionScope{
    const records:MediaRecord[]=[],shows:RemoteShowObservation[]=[],watchlist:Media[]=[];
    for(const id of ids){
      for(const row of this.byRecord.get(id)??[]){records.push(row);}
      const remote=this.byRemote.get(id);if(remote){shows.push(remote);}
      const queued=this.byQueue.get(id);if(queued){watchlist.push(queued);}
    }
    return {ids:ids,records:records,shows:shows,watchlist:watchlist};
  }
  async read(store:EpisodeStore,records:MediaRecord[],cloud:RemoteLibraryObservation|undefined,uuid:string,clientId:string,fill:boolean,force:boolean,
    current:()=>boolean,progress:(done:number,total:number)=>void,cache:ShowProjectionCache):Promise<LibraryProjection>{
    const revision=store.assertProjectionReadable(),now=Date.now(),epoch=this.epoch;
    const valid=():boolean=>current()&&this.epoch===epoch;
    const key=JSON.stringify([clientId,uuid,cloud?.generation??-1]);
    const prior=this.prior,trace=++this.traceId;
    let tracing=false;
    try{hiTraceMeter.startTrace('Showly.LibraryProjection',trace);tracing=true;}catch(error){}
    try{
      const ids=new Set<string>(store.libraryChangedIds());
      if(!fill&&!force&&prior&&this.store===store&&this.records===records&&this.cloud===cloud&&this.scopeKey===key&&
        !store.libraryGlobalChanged()&&ids.size>0&&now>=prior.computedAt&&now<prior.validUntil&&
        Array.from(ids).every((id:string)=>this.members.has(id))){
        const scope=this.select(ids);
        const delta=await projectLibrary(store,records,cloud,uuid,clientId,false,valid,progress,cache,scope);
        if(!valid()||!store.projectionReadable(revision)){throw new Error('Projection inputs changed');}
        const expectedNext=new Set<string>();
        for(const id of ids){if(this.nextMembers.has(id)){expectedNext.add(id);}}
        // Keep the exact original target order. A membership transition or a
        // fresh checkpoint requires the full validated path, not a splice guess.
        if(delta.cacheable&&!delta.matches.length&&delta.localAllowed===prior.localAllowed&&
          delta.computedAt>=prior.computedAt&&delta.computedAt<prior.validUntil&&
          sameProjectionMembers(delta.evidence,ids,(row:LibraryShowEvidence)=>row.media.id)&&
          sameProjectionMembers(delta.calendar,ids,(row:CalendarSource)=>row.media.id)&&
          sameProjectionMembers(delta.next,expectedNext,(row:NextShow)=>row.media.id)){
          const result:LibraryProjection={
            evidence:replaceProjectionRows(prior.evidence,delta.evidence,ids,(row:LibraryShowEvidence)=>row.media.id),
            next:replaceProjectionRows(prior.next,delta.next,ids,(row:NextShow)=>row.media.id),
            calendar:replaceProjectionRows(prior.calendar,delta.calendar,ids,(row:CalendarSource)=>row.media.id),
            missing:0,failed:0,localAllowed:delta.localAllowed,matches:[],computedAt:delta.computedAt,
            validUntil:Math.min(prior.validUntil,delta.validUntil),cacheable:true,
            computedShows:delta.computedShows,reusedShows:prior.evidence.length-ids.size+delta.reusedShows,
            diskHits:delta.diskHits,scheduleParses:delta.scheduleParses,diskParses:delta.diskParses,diskWrites:delta.diskWrites,
            workerBatches:delta.workerBatches,visitedShows:delta.visitedShows,workerInputBytes:delta.workerInputBytes,repairTargets:[]
          };
          this.prior=result;store.acknowledgeLibrary(revision);return result;
        }
      }
      const result=await projectLibrary(store,records,cloud,uuid,clientId,fill,valid,progress,cache);
      if(!valid()||(!fill&&!store.projectionReadable(revision))){throw new Error('Projection inputs changed');}
      if(!fill&&result.cacheable&&!result.matches.length&&store.projectionReadable(revision)){
        this.seed(store,records,cloud,key,result);store.acknowledgeLibrary(revision);
      }else{this.clear();}
      return result;
    }finally{if(tracing){try{hiTraceMeter.finishTrace('Showly.LibraryProjection',trace);}catch(error){}}}
  }
}

export interface DetailProjection {
  state?: LocalSeriesState;
  localAllowed: boolean;
  complete: boolean;
}
// The very same resolver as collection. Public schedule is sufficient to
// render aired episodes; never save it into the eligible catalog on read.
export async function projectDetail(store: EpisodeStore, full: FullEpisodeCatalog | undefined,
  showId: string, cloud: RemoteLibraryObservation | undefined, uuid: string, displayOnly: boolean = false): Promise<DetailProjection> {
  const revision=store.assertProjectionReadable();
  const bound = await store.boundAccount();
  const localAllowed = allowLocalScope(!!cloud, bound, uuid);
  const local = localAllowed ? await store.read(showId) : undefined;
  if (!store.projectionReadable(revision)) { throw new Error('Detail inputs changed'); }
  if (!full) {
    return { state: cloud ? undefined : local, localAllowed: localAllowed, complete: !cloud };
  }
  const localIds: number[] = [];
  for (const season of local?.seasons ?? []) {
    for (const episode of season.episodes) { if (episode.watched) { localIds.push(episode.episode.id); } }
  }
  // Scoped reads are only for display; mutation/sync verification retains the global identity check.
  const intents = localAllowed ? (displayOnly ? await store.journalIntents(showId) : await store.journalIntents()) : [];
  const decisions = intents.filter((intent: JournalIntent) => intent.showId === showId)
    .map((intent: JournalIntent): ReadDecision => {
      return { episodeId: intent.episodeId, watched: intent.watched, seq: intent.seq };
    });
  // Validate the whole persisted account payload, materialize only relevant entries.
  const ids=displayOnly ? new Set<number>(scheduleEpisodes(full).map((ep: ScheduledEpisode)=>ep.id)) : undefined;
  const checkpoints = cloud && localAllowed ? (displayOnly ? await store.projectionCheckpoints(uuid,ids) : await store.readCheckpoints(uuid,ids)) : new Map<number, ReadCheckpoint>();
  const common = cloud && localAllowed ? (displayOnly ? await store.projectionCommonStates(uuid,ids) : await store.commonStates(uuid, 'episode',ids)) : new Map<string, CommonEntry>();
  const remote = cloud?.shows.find((show: RemoteShowObservation) => show.id === showId);
  if (!store.projectionReadable(revision)) { throw new Error('Detail inputs changed'); }
  const effective = resolveEpisodes(full, remote, !!cloud, localIds, decisions, checkpoints, common);
  return { state: effective.complete ? materializeEffective(eligibleCatalog(full, Date.now()), effective.ids) : undefined,
    localAllowed: localAllowed, complete: effective.complete };
}
