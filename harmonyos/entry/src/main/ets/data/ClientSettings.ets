import { validCollectionRecentAmount, CollectionSpoilers, defaultCollectionSpoilers } from '../model/CollectionViewOwner';
import { preferences } from '@kit.ArkData';
import { DiscoverOptions, defaultDiscover, validDiscoverOptions } from '../model/DiscoverRules';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { ProgressPreferences, ProgressFlag, defaultProgress, validProgress, validFlags } from '../model/ProgressRules';

import { MovieProgressOptions, defaultMovieProgress, validMovieProgress } from '../model/MovieProgressRules';

import { CollectionOptions, CollectionState, defaultCollection, emptyCollectionState, validCollection, validCollectionState } from '../model/CollectionRules';

export class ClientSettings {
  private storage: preferences.Preferences;
  constructor(context: common.UIAbilityContext) {
    this.storage = preferences.getPreferencesSync(context, { name: 'showly_trakt_settings' });
  }
  load(): string {
    const value = this.storage.getSync('client_id', '');
    return typeof value === 'string' ? value : '';
  }
  loadLanguage(): string { return this.storage.getSync('presentation_language', 'zh') === 'original' ? 'original' : 'zh'; }
  async saveLanguage(language: string): Promise<void> {
    if (language !== 'zh' && language !== 'original') { throw new Error('Invalid language'); }
    await this.storage.put('presentation_language', language);
    await this.storage.flush();
  }
  loadMode(): string {
    return this.storage.getSync('media_mode', 'show') === 'movie' ? 'movie' : 'show';
  }
  async saveMode(mode: string): Promise<void> {
    if (mode !== 'movie' && mode !== 'show') { throw new Error('Invalid media mode'); }
    await this.storage.put('media_mode', mode);
    await this.storage.flush();
  }
  loadDiscoverOptions(kind: string): DiscoverOptions {
    const raw = this.storage.getSync('discover_options:' + kind,'');
    try {
      const value = JSON.parse(typeof raw === 'string' ? raw : '') as DiscoverOptions;
      return validDiscoverOptions(value) ? value : defaultDiscover();
    } catch (error) { return defaultDiscover(); }
  }
  async saveDiscoverOptions(kind: string, value: DiscoverOptions): Promise<void> {
    if (!['show','movie'].includes(kind) || !validDiscoverOptions(value)) { throw new Error('Invalid discovery settings'); }
    await this.storage.put('discover_options:'+kind,JSON.stringify(value));
    await this.storage.flush();
  }
  loadCollectionSpoilers(kind:string,section:string):CollectionSpoilers{
    const raw=this.storage.getSync('collection_spoilers:'+kind+':'+section,'');
    try{
      const value=JSON.parse(typeof raw==='string'?raw:'') as CollectionSpoilers;
      if(typeof value.description==='boolean'&&typeof value.rating==='boolean'&&typeof value.reveal==='boolean'){return value;}
    }catch(error){}
    return defaultCollectionSpoilers();
  }
  async saveCollectionSpoilers(kind:string,section:string,value:CollectionSpoilers):Promise<void>{
    if(!['show','movie'].includes(kind)||!['mine','queue','hidden'].includes(section)){throw new Error('Invalid spoiler scope');}
    await this.storage.put('collection_spoilers:'+kind+':'+section,JSON.stringify(value));await this.storage.flush();
  }
  loadCollectionRecentAmount():number {
    const value=this.storage.getSync('collection_recent_amount',4);
    return typeof value==='number'&&validCollectionRecentAmount(value)?value:4;
  }
  async saveCollectionRecentAmount(value:number):Promise<void>{
    if(!validCollectionRecentAmount(value)){throw new Error('Invalid collection recent amount');}
    await this.storage.put('collection_recent_amount',value);await this.storage.flush();
  }
  loadCollectionOptions(kind: string, section: string): CollectionOptions {
    const raw = this.storage.getSync('collection_options:' + kind + ':' + section, '');
    try {
      const value = JSON.parse(typeof raw === 'string' ? raw : '') as CollectionOptions;
      return validCollection(value) ? value : defaultCollection();
    } catch (error) { return defaultCollection(); }
  }
  async saveCollectionOptions(kind: string, section: string, value: CollectionOptions): Promise<void> {
    if (!validCollection(value) || !['show','movie'].includes(kind) || !['mine','queue','hidden'].includes(section)) { throw new Error('Invalid collection settings'); }
    await this.storage.put('collection_options:' + kind + ':' + section, JSON.stringify(value));
    await this.storage.flush();
  }
  loadCollectionState(scope: string): CollectionState {
    if (!scope) { return emptyCollectionState(); }
    const raw = this.storage.getSync('collection_state:' + scope, '');
    if (typeof raw !== 'string' || !raw) { return emptyCollectionState(); }
    const value = JSON.parse(raw) as CollectionState;
    if (!validCollectionState(value)) { throw new Error('Invalid collection state'); }
    return value;
  }
  async saveCollectionState(scope: string, value: CollectionState): Promise<void> {
    if (!scope || !validCollectionState(value)) { throw new Error('Invalid collection state'); }
    await this.storage.put('collection_state:' + scope, JSON.stringify(value));
    await this.storage.flush();
  }
  loadMovieProgress(): MovieProgressOptions {
    const raw = this.storage.getSync('movie_progress_options', '');
    if (typeof raw !== 'string' || !raw) { return defaultMovieProgress(); }
    try {
      const value = JSON.parse(raw) as MovieProgressOptions;
      return validMovieProgress(value) ? value : defaultMovieProgress();
    } catch (error) { return defaultMovieProgress(); }
  }
  async saveMovieProgress(value: MovieProgressOptions): Promise<void> {
    if (!validMovieProgress(value)) { throw new Error('Invalid movie progress options'); }
    await this.storage.put('movie_progress_options', JSON.stringify(value));
    await this.storage.flush();
  }
  loadProgress(): ProgressPreferences {
    const raw = this.storage.getSync('show_progress_options', '');
    if (typeof raw !== 'string' || !raw) { return defaultProgress(); }
    try {
      const value = JSON.parse(raw) as ProgressPreferences;
      return validProgress(value) ? value : defaultProgress();
    } catch (error) { return defaultProgress(); }
  }
  async saveProgress(value: ProgressPreferences): Promise<void> {
    if (!validProgress(value)) { throw new Error('Invalid progress settings'); }
    await this.storage.put('show_progress_options', JSON.stringify(value));
    await this.storage.flush();
  }
  loadProgressFlags(scope: string): ProgressFlag[] {
    if (!scope) { return []; }
    const raw = this.storage.getSync('show_progress_flags:' + scope, '');
    if (typeof raw !== 'string' || !raw) { return []; }
    const flags = JSON.parse(raw) as ProgressFlag[];
    if (!validFlags(flags)) { throw new Error('Invalid progress flags'); }
    return flags;
  }
  async saveProgressFlags(scope: string, flags: ProgressFlag[]): Promise<void> {
    if (!scope || !validFlags(flags)) { throw new Error('Invalid progress flag scope'); }
    await this.storage.put('show_progress_flags:' + scope, JSON.stringify(flags));
    await this.storage.flush();
  }
  async save(value: string): Promise<void> {
    await this.storage.put('client_id', value);
    await this.storage.flush();
  }
}

export async function validateClientId(clientId: string): Promise<number> {
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/movies/trending?limit=1', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    return response.responseCode;
  } finally {
    request.destroy();
  }
}
