import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { TitlePresentation, SeasonPresentation, EpisodePresentation, validTitle, validSeason, titleNeedsTranslation, seasonNeedsTranslation, mergeText } from '../model/MediaPresentation';
import { readDetails, cachePoster, cachedPoster, canReadDetails } from './TraktDetails';
import { readChinese, readChineseSeason } from './TraktProgress';
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
        } catch (error) {}
      }
    } finally { titles.close(); }
    const seasons = await db.querySql('SELECT show_id,season,payload FROM presentation_season');
    try {
      while (seasons.goToNextRow()) {
        try {
          const value = JSON.parse(seasons.getString(2)) as SeasonPresentation;
          if (validSeason(value) && value.showId === seasons.getString(0) && value.season === seasons.getLong(1)) {
            repo.seasons.set(value.showId + ':' + value.season, value);
          }
        } catch (error) {}
      }
    } finally { seasons.close(); }
    return repo;
  }
  revision(): number { return this.version; }
  titleRows(): TitlePresentation[] { return Array.from(this.titles.values()); }
  seasonRows(): SeasonPresentation[] { return Array.from(this.seasons.values()); }
  retryArtwork(): void { this.artAttempted.clear(); this.artChecked.clear(); }
  async title(item: Media, clientId: string, language: string, artwork: boolean, hints: string[]): Promise<void> {
    if (!canReadDetails(item)) { return; }
    const prior = this.titles.get(item.id);
    const row: TitlePresentation = prior ? { id: prior.id, text: prior.text, translatedAt: prior.translatedAt,
      posterUrls: prior.posterUrls, posterUri: prior.posterUri } :
      { id: item.id, text: { title: '', overview: '' }, translatedAt: 0, posterUrls: [], posterUri: '' };
    if (hints.length && !row.posterUrls.length) { row.posterUrls = hints; }
    let failed = false;
    // Independent failures cannot erase successful metadata.
    if (artwork) {
      if (!this.artChecked.has(item.id)) {
        this.artChecked.add(item.id);
        row.posterUri = cachedPoster(this.dir, item, row.posterUrls) || cachedPoster(this.oldDir, item, row.posterUrls);
      }
      if (!row.posterUri && clientId && !this.artAttempted.has(item.id)) {
        this.artAttempted.add(item.id);
        try {
          if (!row.posterUrls.length) { row.posterUrls = (await readDetails(item, clientId)).posterUrls; }
          for (const url of row.posterUrls) {
            const result = await cachePoster(this.dir, item, [url]);
            if (result.uri) { row.posterUri = result.uri; break; }
          }
        } catch (error) {
          failed = !(error as Error).message.includes('HTTP 404');
        }
      }
      if (!prior || row.posterUri !== prior.posterUri || row.posterUrls !== prior.posterUrls) { await this.saveTitle(row); }
    }
    if (language === 'zh' && clientId && titleNeedsTranslation(row, Date.now())) {
      const text = await readChinese(item, clientId);
      row.text = mergeText(row.text, { title: text.title, overview: text.overview });
      row.translatedAt = Date.now();
      await this.saveTitle(row);
    }
    if (failed) { throw new Error('Artwork request failed'); }
  }
  private async saveTitle(row: TitlePresentation): Promise<void> {
    if (!validTitle(row)) { throw new Error('Invalid title presentation'); }
    const saved: TitlePresentation = { id: row.id, text: row.text, translatedAt: row.translatedAt,
      posterUrls: row.posterUrls, posterUri: row.posterUri };
    await this.db.executeSql('INSERT OR REPLACE INTO presentation_title(id,payload) VALUES(?,?)', [saved.id, JSON.stringify(saved)]);
    this.titles.set(saved.id, saved);
    this.version++;
  }
  async season(item: Media, season: number, clientId: string, language: string): Promise<void> {
    if (language !== 'zh' || !clientId || item.kind !== 'show' || season <= 0 || !canReadDetails(item)) { return; }
    const key = item.id + ':' + season;
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
    this.version++;
  }
}
