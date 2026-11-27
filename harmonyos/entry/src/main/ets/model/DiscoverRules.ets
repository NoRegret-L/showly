import { Media } from './Media';

export const DISCOVER_CACHE_MS: number = 12 * 60 * 60 * 1000;
export const DISCOVER_LIMIT: number = 280;
export const ANTICIPATED_LIMIT: number = 30;
// Existing HarmonyOS two-column page size; this is a presentation boundary,
// not the number of titles requested from Trakt.
export const DISCOVER_PAGE_SIZE: number = 12;
export const DISCOVER_GENRES: string[] = ['action','adventure','animation','anime','comedy','crime','documentary','drama','fantasy','history','horror','science-fiction','romance','thriller','war','western'];
interface NetworkGroup { name: string; channels: string[]; }
const NETWORKS: NetworkGroup[] = [{"name":"ABC","channels":["ABC","ABC (AU)","ABC (JA)","ABC (US)","ABC Comedy","ABC Family","ABC KIDS","ABC Me","ABC News","ABC News 24","ABC Spark","ABC TV","ABC TV Plus"]},{"name":"AMC","channels":["AMC","AMC+"]},{"name":"APPLE","channels":["Apple","Apple TV+","Apple Music"]},{"name":"AMAZON","channels":["Amazon","Amazon (Japan)","Amazon Freevee","Amazon Kids+","Amazon Prime Video","Amazon Studios","Amazon miniTV"]},{"name":"BBC","channels":["BBC","BBC America","BBC Canada","BBC Choice","BBC Earth","BBC First","BBC Four","BBC HD","BBC Kids","BBC Knowledge","BBC Music","BBC News","BBC One","BBC Prime","BBC Red Button","BBC Scotland","BBC Television","BBC Three","BBC Two","BBC UKTV","BBC Wales","BBC World News","BBC Worldwide","BBC iPlayer"]},{"name":"CBS","channels":["CBS","CBS All Access","CBS News","CBS Reality","CBS Reality (UK)","CBS.com"]},{"name":"CRUNCHYROLL","channels":["Crunchyroll"]},{"name":"CW","channels":["CW","The CW"]},{"name":"DISCOVERY","channels":["Discovery","Discovery (NL)","Discovery (US)","Discovery Asia","Discovery Channel","Discovery Channel (AU)","Discovery Channel (Asia)","Discovery Channel (CA)","Discovery Channel (Canada)","Discovery Channel (PL)","Discovery Channel (SE)","Discovery Channel (UK)","Discovery Communications","Discovery Family","Discovery GO","Discovery HD World","Discovery Health Channel","Discovery History","Discovery JEET","Discovery Kids","Discovery Life","Discovery MAX","Discovery Real Time","Discovery Science","Discovery Shed","Discovery Turbo","Discovery Turbo UK","Discovery UK","Discovery+"]},{"name":"DISNEY","channels":["Disney","Disney Channel","Disney Channel (DE)","Disney Channel (FR)","Disney Channel (IT)","Disney Channel (UK)","Disney Channel (US)","Disney Cinemagic","Disney Junior","Disney Junior (UK)","Disney Television Animation","Disney XD","Disney XD (Latin America)","Disney+","Disney+ Hotstar"]},{"name":"HBO","channels":["HBO Max","HBO Asia","HBO Brasil","HBO Canada","HBO España","HBO Europe","HBO Family","HBO Latin","HBO America","HBO Magyarország","HBO Nordic","HBO","Max","MAX"]},{"name":"FOX","channels":["FOX","FOX (US)","FOX España","FOX Reality","FOX SPORTS","FOX Traveller","FOX Türkiye","FOX Türkiye (TR)","FOX+"]},{"name":"HULU","channels":["Hulu","Hulu Japan"]},{"name":"ITV","channels":["ITV","ITV Encore","ITV Granada","ITV Wales"]},{"name":"NBC","channels":["NBC","NBC News Studios","NBC Universo","NBCSN","NBCUniversal"]},{"name":"NETFLIX","channels":["Netflix"]},{"name":"PARAMOUNT","channels":["Paramount","Paramount (GB)","Paramount Network","Paramount+","Paramount+ (AU)","Paramount+ (MX)"]},{"name":"PEACOCK","channels":["Peacock"]},{"name":"RAKUTEN","channels":["Rakuten TV"]},{"name":"SHOWTIME","channels":["Showtime"]}];
export const DISCOVER_NETWORKS: string[] = NETWORKS.map((x: NetworkGroup) => x.name);
export interface DiscoverOptions { mode: string; genres: string[]; networks: string[]; hideCollection: boolean; }
export interface DiscoverItem { media: Media; posterUrls: string[]; posterUri: string; rating: number; firstAired?: string; }
export interface DiscoverRequest { kind: string; mode: string; genres: string[]; networks: string[]; limit: number; }
export interface DiscoverFeed { fetchedAt: number; items: DiscoverItem[]; }
export interface DiscoverPage { items: DiscoverItem[]; page: number; pages: number; total: number; }
export function defaultDiscover(): DiscoverOptions { return {mode:'trending',genres:[],networks:[],hideCollection:false}; }
export function validDiscoverOptions(value: DiscoverOptions): boolean {
  return !!value && ['trending','popular','anticipated','recent'].includes(value.mode) &&
    typeof value.hideCollection === 'boolean' && Array.isArray(value.genres) && Array.isArray(value.networks) &&
    value.genres.every((x: string) => DISCOVER_GENRES.includes(x)) &&
    value.networks.every((x: string) => DISCOVER_NETWORKS.includes(x));
}
export function discoverRequest(kind: string, options: DiscoverOptions, collectionSize: number): DiscoverRequest {
  if (!['show','movie'].includes(kind) || !validDiscoverOptions(options) || !Number.isSafeInteger(collectionSize) || collectionSize < 0) { throw new Error('Invalid discovery filters'); }
  const mode = options.mode === 'recent' ? 'trending' : options.mode;
  const genres = DISCOVER_GENRES.filter((x: string) => options.genres.includes(x));
  const channels: string[] = [];
  if (kind === 'show') {
    for (const group of NETWORKS) {
      if (options.networks.includes(group.name)) { channels.push(...group.channels); }
    }
  }
  return {kind:kind,mode:mode,genres:genres,networks:channels,
    limit:DISCOVER_LIMIT + (mode === 'trending' && options.hideCollection ? Math.floor(collectionSize/2) : 0)};
}
export function discoverKey(client: string, request: DiscoverRequest): string {
  return JSON.stringify([client,request.kind,request.mode,request.genres,request.networks,request.limit]);
}
export function discoverFresh(feed: DiscoverFeed, now: number): boolean {
  return now >= feed.fetchedAt && now - feed.fetchedAt < DISCOVER_CACHE_MS;
}
export function mixDiscover(trending: DiscoverItem[], anticipated: DiscoverItem[]): DiscoverItem[] {
  const result: DiscoverItem[] = [];
  const ids = new Set<string>();
  const add = (item: DiscoverItem): void => {
    if (!ids.has(item.media.id)) { ids.add(item.media.id); result.push(item); }
  };
  let next = 0;
  for (let i = 0; i < trending.length; i++) {
    add(trending[i]);
    // Preserve upstream's zero-based index and consume even a duplicate.
    if (i !== 0 && i % 6 === 0 && next < anticipated.length) { add(anticipated[next++]); }
  }
  return result;
}
export function validDiscoverFeed(feed: DiscoverFeed, kind: string): boolean {
  if (!feed || !Number.isSafeInteger(feed.fetchedAt) || feed.fetchedAt <= 0 || !Array.isArray(feed.items)) { return false; }
  const seen = new Set<string>();
  for (const item of feed.items) {
    if (!item || !item.media || item.media.kind !== kind || !/^(show|movie):[1-9][0-9]*$/.test(item.media.id) ||
        !item.media.id.startsWith(kind+':') || seen.has(item.media.id) || typeof item.media.title !== 'string' ||
        !Number.isFinite(item.media.year) || item.media.watched !== false || !Number.isFinite(item.rating) ||
        !Array.isArray(item.posterUrls) || !item.posterUrls.every((x: string) => typeof x === 'string') ||
        item.posterUri !== '' || (item.firstAired !== undefined && typeof item.firstAired !== 'string')) { return false; }
    seen.add(item.media.id);
  }
  return true;
}
export function filterDiscover(items: DiscoverItem[], options: DiscoverOptions, hidden: Set<string>, members: Set<string>, now: number): DiscoverItem[] {
  const day = new Date(now).toISOString().substring(0,10);
  const rows = items.filter((item: DiscoverItem) => !hidden.has(item.media.id) && (!options.hideCollection || !members.has(item.media.id)));
  if (options.mode !== 'recent') { return rows; }
  return rows.filter((item: DiscoverItem) => {
    const date = Date.parse(item.firstAired ?? '');
    return Number.isFinite(date) && new Date(date).toISOString().substring(0,10) <= day;
  }).sort((a: DiscoverItem,b: DiscoverItem) => Date.parse(b.firstAired ?? '') - Date.parse(a.firstAired ?? ''));
}
export function discoverPage(items: DiscoverItem[], requested: number): DiscoverPage {
  const pages = Math.max(1,Math.ceil(items.length / DISCOVER_PAGE_SIZE));
  const page = Math.max(1,Math.min(pages,requested));
  return {items:items.slice((page-1)*DISCOVER_PAGE_SIZE,page*DISCOVER_PAGE_SIZE),page:page,pages:pages,total:items.length};
}
