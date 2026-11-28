import { ArtworkRecovery } from '../model/ArtworkRules';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { ReadFlight, ReadCancel, ConsumerReadFlight } from '../model/ReadFlight';
import { PresentationFailure, presentationFailure } from '../model/PresentationPolicy';
import { TitlePresentation, SeasonPresentation, EpisodePresentation, TranslationText, CollectionMeta, validTitle, validSeason, titleNeedsTranslation, seasonNeedsTranslation, mergeText, PresentationTask, TITLE_RETRY, SEASON_RETRY } from '../model/MediaPresentation';
import { MediaDetail, readDetails, cachePoster, cachedPoster, canReadDetails, rejectPosterUri } from './TraktDetails';
import { readChinese, readChineseSeason } from './TraktProgress';
interface PublicDetailRow { id:string; summary:MediaDetail; }
interface TitlePatch { expectedPosterUri?: string; text?: TranslationText; translatedAt?: number; posterUrls?: string[]; posterUri?: string; collection?: CollectionMeta; }
export interface PresentationChanges { titles: TitlePresentation[]; seasons: SeasonPresentation[]; }
// Public metadata cache only: no personal library or sync writes.
export class PresentationRepository {
  private db: relationalStore.RdbStore;
  private dir: string;
  private oldDir: string;
  private titles: Map<string, TitlePresentation> = new Map<string, TitlePresentation>();
  private seasons: Map<string, SeasonPresentation> = new Map<string, SeasonPresentation>();
  private artAttempted: Set<string> = new Set<string>();
  private artChecked: Set<string> = new Set<string>();
  private repair: ArtworkRecovery=new ArtworkRecovery();
  private summaryMissing: Set<string> = new Set<string>();
  private version: number = 0;
  private residency: number = 0;
  private loadedSeasons: Set<string> = new Set<string>();
  private dirtyTitles: Map<string, TitlePresentation> = new Map<string, TitlePresentation>();
  private dirtySeasons: Map<string, SeasonPresentation> = new Map<string, SeasonPresentation>();
  private titleWrites: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private artFlights = new ConsumerReadFlight<void>();
  private textFlights = new ConsumerReadFlight<void>();
  private seasonFlights = new ConsumerReadFlight<void>();
  private hydrateFlights = new ConsumerReadFlight<void>();
  constructor(db: relationalStore.RdbStore, dir: string, oldDir: string) {
    this.db = db; this.dir = dir; this.oldDir = oldDir;
  }
  static async open(context: common.UIAbilityContext): Promise<PresentationRepository> {
    const db = await relationalStore.getRdbStore(context, { name: 'showly_presentation.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_title (id TEXT PRIMARY KEY,payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_season (show_id TEXT NOT NULL,season INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(show_id,season))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_detail (id TEXT PRIMARY KEY,payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_section (id TEXT NOT NULL,section TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(id,section))');
    const repo = new PresentationRepository(db, context.filesDir, context.cacheDir);
    const titles = await db.querySql('SELECT id,payload FROM presentation_title');
    try {
      while (titles.goToNextRow()) {
        try {
          const value = JSON.parse(titles.getString(1)) as TitlePresentation;
          if (!validTitle(value) || value.id !== titles.getString(0)) { continue; }
          // Validate files only when their card is requested, not at startup.
          value.posterUri = '';
          repo.dirtyTitles.set(value.id,repo.lightTitle(value));
          repo.version++;
        } catch (error) {}
      }
    } finally { titles.close(); }
    // Season payloads are read by exact show/season only when requested.
    return repo;
  }
  // Keep only title/sort metadata in the page-wide index; full summaries
  // hydrate by exact ID, including offline detail entry.
  private lightTitle(row: TitlePresentation): TitlePresentation {
    return {id:row.id,text:{title:row.text.title,overview:''},translatedAt:row.translatedAt,
      posterUrls:[],posterUri:row.posterUri,collection:row.collection};
  }
  async readDetailSection(item:Media,section:string,consumer:ReadCancel):Promise<string>{
    if(!canReadDetails(item)||!['people-trakt','related-trakt','seasons-trakt'].includes(section)){return '';}
    consumer.check();const rows=await this.db.querySql('SELECT payload FROM presentation_section WHERE id=? AND section=?',[item.id,section]);
    try{consumer.check();return rows.goToFirstRow()?rows.getString(0):'';}finally{rows.close();}
  }
  async saveDetailSection(item:Media,section:string,payload:string,consumer:ReadCancel):Promise<void>{
    if(!canReadDetails(item)||!['people-trakt','related-trakt','seasons-trakt'].includes(section)){return;}
    consumer.check();await this.db.executeSql('INSERT OR REPLACE INTO presentation_section(id,section,payload) VALUES(?,?,?)',[item.id,section,payload]);
  }
  async readCachedDetail(item:Media,consumer:ReadCancel):Promise<MediaDetail|undefined>{
    if(!canReadDetails(item)){return undefined;}
    consumer.check();
    const rows=await this.db.querySql('SELECT payload FROM presentation_detail WHERE id=?',[item.id]);
    try{
      consumer.check();
      if(!rows.goToFirstRow()){return undefined;}
      const row=JSON.parse(rows.getString(0)) as PublicDetailRow;
      const d=row.summary;
      if(row.id!==item.id||!d||typeof d.title!=='string'||typeof d.overview!=='string'||
        typeof d.year!=='number'||typeof d.rating!=='number'||typeof d.runtime!=='number'||typeof d.status!=='string'||
        typeof d.genres!=='string'||typeof d.airedEpisodes!=='number'||!Array.isArray(d.posterUrls)||
        !d.posterUrls.every((url:string)=>typeof url==='string')){return undefined;}
      return d;
    }catch(error){return undefined;}finally{rows.close();}
  }
  async saveCachedDetail(item:Media,summary:MediaDetail,consumer:ReadCancel):Promise<void>{
    if(!canReadDetails(item)){return;}
    consumer.check();
    const row:PublicDetailRow={id:item.id,summary:summary};
    await this.db.executeSql('INSERT OR REPLACE INTO presentation_detail(id,payload) VALUES(?,?)',[item.id,JSON.stringify(row)]);
  }
  overview(id: string): string { return this.titles.get(id)?.text.overview ?? ''; }
  releaseTransient(): void {
    this.residency++;
    this.titles.clear(); this.seasons.clear(); this.loadedSeasons.clear(); this.dirtySeasons.clear();
    this.artChecked.clear(); this.artAttempted.clear(); this.summaryMissing.clear();
    this.repair.clear();
  }
  private async readTitle(id: string,version: number): Promise<TitlePresentation> {
    const cached=this.titles.get(id);
    if (cached) { return cached; }
    let row=this.emptyTitle(id);
    const result=await this.db.querySql('SELECT payload FROM presentation_title WHERE id=?',[id]);
    try {
      if (result.goToFirstRow()) {
        try { const parsed=JSON.parse(result.getString(0)) as TitlePresentation;
          if (validTitle(parsed) && parsed.id===id) { parsed.posterUri=''; row=parsed; }
        } catch (error) {}
      }
    } finally { result.close(); }
    // A concurrently committed patch wins over a disk read.
    if (version===this.residency) {
      const current=this.titles.get(id);
      if (current) { return current; }
      this.titles.set(id,row); this.dirtyTitles.set(id,this.lightTitle(row)); this.version++;
    }
    return row;
  }
  taskValidUntil(task: PresentationTask,lane: string,now: number): number {
    if (lane==='title') {
      const row=this.titles.get(task.media.id);
      if (row && (!row.text.title || !row.text.overview) && row.translatedAt>0) { return Math.max(now,row.translatedAt+TITLE_RETRY); }
    } else if (lane==='season') {
      const row=this.seasons.get(task.media.id+':'+task.season);
      if (row) { return Math.max(now,row.fetchedAt+SEASON_RETRY); }
    }
    return Number.MAX_SAFE_INTEGER;
  }
  revision(): number { return this.version; }
  takeChanges(): PresentationChanges {
    const result: PresentationChanges = { titles: Array.from(this.dirtyTitles.values()), seasons: Array.from(this.dirtySeasons.values()) };
    this.dirtyTitles.clear(); this.dirtySeasons.clear();
    return result;
  }
  retryArtwork(): void { this.artAttempted.clear(); this.artChecked.clear(); this.summaryMissing.clear(); this.repair.clear(); }
  // A native decoder error is not proof of corrupt bytes; quarantine this URI
  // and permit a single recovery transition, then require explicit retry.
  async repairArtwork(item: Media,uri: string): Promise<boolean> {
    const version=this.residency;
    const old=await this.readTitle(item.id,version);
    if (version!==this.residency || old.posterUri!==uri || !uri) { return false; }
    rejectPosterUri(uri);
    const first=this.repair.reject(item.id,uri);
    this.artChecked.delete(item.id);
    for (const attempt of this.artAttempted) {
      if (attempt.includes(','+JSON.stringify(item.id)+',')) { this.artAttempted.delete(attempt); }
    }
    await this.saveTitlePatch(item.id,{posterUri:'',expectedPosterUri:uri},version);
    return first && version===this.residency;
  }
  private emptyTitle(id: string): TitlePresentation {
    return { id: id, text: { title: '', overview: '' }, translatedAt: 0, posterUrls: [], posterUri: '' };
  }
  async artwork(item: Media, clientId: string, artwork: boolean, hints: string[], collection: boolean, consumer?: ReadCancel): Promise<void> {
    if (!canReadDetails(item)) { return; }
    await this.artFlights.run(JSON.stringify([clientId,item.id,artwork,hints,collection]),
      (scope: ReadCancel) => this.loadArtwork(item,clientId,artwork,hints,collection,scope),consumer);
  }
  private async loadArtwork(item: Media, clientId: string, artwork: boolean, hints: string[], collection: boolean, scope: ReadCancel): Promise<void> {
    const version=this.residency;
    const prior = await this.readTitle(item.id,version);
    if (version!==this.residency) { return; }
    scope.check();
    let urls = prior.posterUrls.length ? prior.posterUrls : hints;
    let uri = prior.posterUri;
    let meta = prior.collection;
    // Local file reuse is independent of a failed/limited metadata request.
    if (artwork && !this.artChecked.has(item.id) && this.repair.allowed(item.id)) {
      uri = await cachedPoster(this.dir,item,urls,scope) || await cachedPoster(this.oldDir,item,urls,scope);
      scope.check();
      if (version!==this.residency) { return; }
      this.artChecked.add(item.id);
    }
    if (artwork || (urls.length && !prior.posterUrls.length)) {
      await this.saveTitlePatch(item.id,{posterUrls:urls,posterUri:uri},version);
    }
    if (!clientId || version!==this.residency) { return; }
    const attempt=JSON.stringify([clientId,item.id,urls]);
    const summaryKey=JSON.stringify([clientId,item.id]);
    let missingSummary=this.summaryMissing.has(summaryKey);
    if (collection && !meta && !missingSummary) {
      try {
        const detail=await readDetails(item,clientId,false,scope);
        meta=detail.collection;
        if (!urls.length) { urls=detail.posterUrls; }
        if (version!==this.residency) { return; }
        await this.saveTitlePatch(item.id,{collection:meta,posterUrls:urls},version);
      } catch (error) {
        scope.check();
        const failure: PresentationFailure = presentationFailure(error as Error);
        if (failure.category!=='missing') { throw failure; }
        missingSummary=true;
        if (version===this.residency) { this.summaryMissing.add(summaryKey); }
      }
    }
    if (version!==this.residency || !artwork || uri || !this.repair.allowed(item.id) || this.artAttempted.has(attempt)) { return; }
    if (!urls.length && !missingSummary) {
      try { urls=(await readDetails(item,clientId,false,scope)).posterUrls; }
      catch (error) {
        scope.check();
        const failure: PresentationFailure = presentationFailure(error as Error);
        if (failure.category!=='missing') { throw failure; }
        if (version===this.residency) { this.summaryMissing.add(summaryKey); }
      }
    }
    let failed: PresentationFailure | undefined;
    for (const url of urls) {
      scope.check();
      if (version!==this.residency) { return; }
      const result=await cachePoster(this.dir,item,[url],scope);
      if (result.uri) { uri=result.uri; break; }
      if (result.failure && result.failure.category!=='missing') {
        if (result.failure.category==='limited') { throw result.failure; }
        failed=result.failure;
      }
    }
    scope.check();
    if (version!==this.residency) { return; }
    await this.saveTitlePatch(item.id,{posterUrls:urls,posterUri:uri,collection:meta},version);
    if (version!==this.residency) { return; }
    if (!uri && failed) { throw failed; }
    // Only a completed result or verified absence is a completed attempt.
    this.artAttempted.add(JSON.stringify([clientId,item.id,urls]));
    this.artAttempted.add(attempt);
  }
  async translation(item: Media, clientId: string, language: string, consumer?: ReadCancel): Promise<void> {
    if (language !== 'zh' || !clientId || !canReadDetails(item)) { return; }
    await this.textFlights.run(JSON.stringify([clientId,item.id,language]), async (scope: ReadCancel): Promise<void> => {
      const version=this.residency;
      const old = await this.readTitle(item.id,version);
      if (version!==this.residency || !titleNeedsTranslation(old,Date.now())) { return; }
      scope.check();
      const text = await readChinese(item,clientId,scope);
      scope.check();
      if (version!==this.residency) { return; }
      await this.saveTitlePatch(item.id,{ text: { title: text.title, overview: text.overview }, translatedAt: Date.now() },version);
    },consumer);
  }
  // Serialize only persistence of the same title. Merge field patches against
  // the latest committed value; independent requests cannot erase each other.
  private async saveTitlePatch(id: string, patch: TitlePatch, version: number): Promise<void> {
    const previous = this.titleWrites.get(id) ?? Promise.resolve();
    const task = previous.catch((): void => {}).then(async (): Promise<void> => {
      if (version!==this.residency) { return; }
      const old = await this.readTitle(id,version);
      if (version!==this.residency || (patch.expectedPosterUri!==undefined && old.posterUri!==patch.expectedPosterUri)) { return; }
      const row: TitlePresentation = { id: id, text: patch.text ? mergeText(old.text,patch.text) : old.text,
        translatedAt: patch.translatedAt ?? old.translatedAt,
        posterUrls: patch.posterUrls?.length ? patch.posterUrls : old.posterUrls,
        posterUri: patch.posterUri ?? old.posterUri, collection: patch.collection ?? old.collection };
      if (!validTitle(row)) { throw new Error('Invalid title presentation'); }
      const raw = JSON.stringify(row);
      if (raw === JSON.stringify(old)) { return; }
      await this.db.executeSql('INSERT OR REPLACE INTO presentation_title(id,payload) VALUES(?,?)',[id,raw]);
      // Durable public metadata may complete after eviction; never refill the full cache.
      if (version===this.residency) { this.titles.set(id,row); }
      else { this.titles.delete(id); }
      this.dirtyTitles.set(id,this.lightTitle(row)); this.version++;
    });
    this.titleWrites.set(id,task);
    try { await task; }
    finally { if (this.titleWrites.get(id) === task) { this.titleWrites.delete(id); } }
  }
  async hydrateSeason(item: Media, season: number, consumer?: ReadCancel): Promise<void> {
    if (item.kind === 'show' && season > 0 && canReadDetails(item)) {
      const version=this.residency;
      await this.hydrateFlights.run(JSON.stringify([item.id,season,version]),(scope: ReadCancel) => this.readSeason(item,season,version,scope),consumer);
    }
  }
  private async readSeason(item: Media, season: number, version: number, scope: ReadCancel): Promise<void> {
    const key = item.id + ':' + season;
    scope.check();
    if (this.loadedSeasons.has(key)) { return; }
    const rows = await this.db.querySql('SELECT payload FROM presentation_season WHERE show_id=? AND season=?',[item.id,season]);
    try {
      scope.check();
      if (version!==this.residency) { return; }
      if (rows.goToFirstRow()) {
        try {
          const row = JSON.parse(rows.getString(0)) as SeasonPresentation;
          if (validSeason(row) && row.showId === item.id && row.season === season) {
            this.seasons.set(key,row); this.dirtySeasons.set(key,row); this.version++;
          }
        } catch (error) { /* invalid optional cache is a miss */ }
      }
      this.loadedSeasons.add(key);
    } finally { rows.close(); }
  }
  async season(item: Media, season: number, clientId: string, language: string, consumer?: ReadCancel): Promise<void> {
    if (language !== 'zh' || item.kind !== 'show' || season <= 0 || !canReadDetails(item)) { return; }
    const key = item.id + ':' + season;
    const version=this.residency;
    await this.seasonFlights.run(JSON.stringify([clientId,key,language]), (scope: ReadCancel) => this.loadSeason(item,season,clientId,scope),consumer);
    consumer?.check();
    if (version===this.residency && !this.loadedSeasons.has(key)) { await this.hydrateSeason(item,season,consumer); }
  }
  private async loadSeason(item: Media, season: number, clientId: string, scope: ReadCancel): Promise<void> {
    const key = item.id + ':' + season;
    const version=this.residency;
    await this.hydrateSeason(item,season,scope);
    if (version!==this.residency || !clientId) { return; }
    const old = this.seasons.get(key);
    if (!seasonNeedsTranslation(old, Date.now())) { return; }
    scope.check();
    const next = await readChineseSeason(item, season, clientId, scope);
    scope.check();
    if (version!==this.residency) { return; }
    const merged: EpisodePresentation[] = [];
    for (const episode of next.episodes) {
      const previous = old?.episodes.find((value: EpisodePresentation) => value.id === episode.id && value.number === episode.number);
      merged.push({ id: episode.id, number: episode.number, text: previous ? mergeText(previous.text, episode.text) : episode.text });
    }
    for (const episode of old?.episodes ?? []) {
      if (!merged.some((value: EpisodePresentation) => value.id === episode.id || value.number === episode.number)) { merged.push(episode); }
    }
    next.episodes = merged;
    if (!validSeason(next)) { throw new Error('Invalid merged season'); }
    await this.db.executeSql('INSERT OR REPLACE INTO presentation_season(show_id,season,payload) VALUES(?,?,?)',
      [next.showId, next.season, JSON.stringify(next)]);
    if (version!==this.residency) { return; }
    this.seasons.set(key, next);
    this.dirtySeasons.set(key,next);
    this.version++;
  }
}
