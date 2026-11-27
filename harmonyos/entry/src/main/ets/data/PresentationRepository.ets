import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { ReadFlight } from '../model/ReadFlight';
import { TitlePresentation, SeasonPresentation, EpisodePresentation, TranslationText, CollectionMeta, validTitle, validSeason, titleNeedsTranslation, seasonNeedsTranslation, mergeText } from '../model/MediaPresentation';
import { readDetails, cachePoster, cachedPoster, canReadDetails } from './TraktDetails';
import { readChinese, readChineseSeason } from './TraktProgress';
interface TitlePatch { text?: TranslationText; translatedAt?: number; posterUrls?: string[]; posterUri?: string; collection?: CollectionMeta; }
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
  private version: number = 0;
  private loadedSeasons: Set<string> = new Set<string>();
  private dirtyTitles: Map<string, TitlePresentation> = new Map<string, TitlePresentation>();
  private dirtySeasons: Map<string, SeasonPresentation> = new Map<string, SeasonPresentation>();
  private titleWrites: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private artFlights = new ReadFlight<void>();
  private textFlights = new ReadFlight<void>();
  private seasonFlights = new ReadFlight<void>();
  constructor(db: relationalStore.RdbStore, dir: string, oldDir: string) {
    this.db = db; this.dir = dir; this.oldDir = oldDir;
  }
  static async open(context: common.UIAbilityContext): Promise<PresentationRepository> {
    const db = await relationalStore.getRdbStore(context, { name: 'showly_presentation.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_title (id TEXT PRIMARY KEY,payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS presentation_season (show_id TEXT NOT NULL,season INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(show_id,season))');
    const repo = new PresentationRepository(db, context.filesDir, context.cacheDir);
    const titles = await db.querySql('SELECT id,payload FROM presentation_title');
    try {
      while (titles.goToNextRow()) {
        try {
          const value = JSON.parse(titles.getString(1)) as TitlePresentation;
          if (!validTitle(value) || value.id !== titles.getString(0)) { continue; }
          // Validate files only when their card is requested, not at startup.
          value.posterUri = '';
          repo.titles.set(value.id, value);
          repo.dirtyTitles.set(value.id,value);
          repo.version++;
        } catch (error) {}
      }
    } finally { titles.close(); }
    // Season payloads are read by exact show/season only when requested.
    return repo;
  }
  revision(): number { return this.version; }
  takeChanges(): PresentationChanges {
    const result: PresentationChanges = { titles: Array.from(this.dirtyTitles.values()), seasons: Array.from(this.dirtySeasons.values()) };
    this.dirtyTitles.clear(); this.dirtySeasons.clear();
    return result;
  }
  retryArtwork(): void { this.artAttempted.clear(); this.artChecked.clear(); }
  private emptyTitle(id: string): TitlePresentation {
    return { id: id, text: { title: '', overview: '' }, translatedAt: 0, posterUrls: [], posterUri: '' };
  }
  async artwork(item: Media, clientId: string, artwork: boolean, hints: string[], collection: boolean): Promise<void> {
    if (!canReadDetails(item)) { return; }
    await this.artFlights.run(JSON.stringify([clientId,item.id,artwork,hints,collection]),
      () => this.loadArtwork(item,clientId,artwork,hints,collection));
  }
  private async loadArtwork(item: Media, clientId: string, artwork: boolean, hints: string[], collection: boolean): Promise<void> {
    const prior = this.titles.get(item.id) ?? this.emptyTitle(item.id);
    let urls = prior.posterUrls.length ? prior.posterUrls : hints;
    let uri = prior.posterUri;
    let meta = prior.collection;
    let failed = false;
    if (collection && clientId && !meta) {
      const detail = await readDetails(item,clientId);
      meta = detail.collection;
      if (!urls.length) { urls = detail.posterUrls; }
      await this.saveTitlePatch(item.id,{ collection: meta, posterUrls: urls });
    }
    if (artwork) {
      if (!this.artChecked.has(item.id)) {
        this.artChecked.add(item.id);
        uri = cachedPoster(this.dir,item,urls) || cachedPoster(this.oldDir,item,urls);
      }
      if (!uri && clientId && !this.artAttempted.has(item.id)) {
        this.artAttempted.add(item.id);
        try {
          if (!urls.length) { urls = (await readDetails(item,clientId)).posterUrls; }
          for (const url of urls) {
            const result = await cachePoster(this.dir,item,[url]);
            if (result.uri) { uri = result.uri; break; }
          }
        } catch (error) { failed = !(error as Error).message.includes('HTTP 404'); }
      }
      await this.saveTitlePatch(item.id,{ posterUrls: urls, posterUri: uri, collection: meta });
    } else if (urls.length && !prior.posterUrls.length) {
      await this.saveTitlePatch(item.id,{ posterUrls: urls });
    }
    if (failed) { throw new Error('Artwork request failed'); }
  }
  async translation(item: Media, clientId: string, language: string): Promise<void> {
    if (language !== 'zh' || !clientId || !canReadDetails(item)) { return; }
    await this.textFlights.run(JSON.stringify([clientId,item.id,language]), async (): Promise<void> => {
      const old = this.titles.get(item.id);
      if (!titleNeedsTranslation(old,Date.now())) { return; }
      const text = await readChinese(item,clientId);
      await this.saveTitlePatch(item.id,{ text: { title: text.title, overview: text.overview }, translatedAt: Date.now() });
    });
  }
  // Serialize only persistence of the same title. Merge field patches against
  // the latest committed value; independent requests cannot erase each other.
  private async saveTitlePatch(id: string, patch: TitlePatch): Promise<void> {
    const previous = this.titleWrites.get(id) ?? Promise.resolve();
    const task = previous.catch((): void => {}).then(async (): Promise<void> => {
      const old = this.titles.get(id) ?? this.emptyTitle(id);
      const row: TitlePresentation = { id: id, text: patch.text ? mergeText(old.text,patch.text) : old.text,
        translatedAt: patch.translatedAt ?? old.translatedAt,
        posterUrls: patch.posterUrls?.length ? patch.posterUrls : old.posterUrls,
        posterUri: patch.posterUri ?? old.posterUri, collection: patch.collection ?? old.collection };
      if (!validTitle(row)) { throw new Error('Invalid title presentation'); }
      const raw = JSON.stringify(row);
      if (raw === JSON.stringify(old)) { return; }
      await this.db.executeSql('INSERT OR REPLACE INTO presentation_title(id,payload) VALUES(?,?)',[id,raw]);
      this.titles.set(id,row); this.dirtyTitles.set(id,row); this.version++;
    });
    this.titleWrites.set(id,task);
    try { await task; }
    finally { if (this.titleWrites.get(id) === task) { this.titleWrites.delete(id); } }
  }
  async hydrateSeason(item: Media, season: number): Promise<void> {
    if (item.kind === 'show' && season > 0 && canReadDetails(item)) { await this.readSeason(item,season); }
  }
  private async readSeason(item: Media, season: number): Promise<void> {
    const key = item.id + ':' + season;
    if (this.loadedSeasons.has(key)) { return; }
    const rows = await this.db.querySql('SELECT payload FROM presentation_season WHERE show_id=? AND season=?',[item.id,season]);
    try {
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
  async season(item: Media, season: number, clientId: string, language: string): Promise<void> {
    if (language !== 'zh' || item.kind !== 'show' || season <= 0 || !canReadDetails(item)) { return; }
    const key = item.id + ':' + season;
    await this.seasonFlights.run(key, () => this.loadSeason(item,season,clientId));
  }
  private async loadSeason(item: Media, season: number, clientId: string): Promise<void> {
    const key = item.id + ':' + season;
    await this.readSeason(item,season);
    if (!clientId) { return; }
    const old = this.seasons.get(key);
    if (!seasonNeedsTranslation(old, Date.now())) { return; }
    const next = await readChineseSeason(item, season, clientId);
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
    this.seasons.set(key, next);
    this.dirtySeasons.set(key,next);
    this.version++;
  }
}
