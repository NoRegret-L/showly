import { Media } from './Media';
export const STREAMING_AGE:number=3*24*60*60*1000;
export const SERIES_AGE:number=7*24*60*60*1000;
export const WATCH_REGIONS:string[]=['ar','au','at','be','br','bg','ca','cl','co','cz','dk','ec','ee','fi','fr','de','gr','hk','hu','in','id','ie','it','jp','lv','lt','my','mx','nl','nz','no','pe','ph','pl','pt','ro','ru','sg','za','kr','es','se','ch','th','tw','tr','ua','uk','us','ve'];
export interface WatchOptions{enabled:boolean;region:string;}
export function validWatchOptions(o:WatchOptions):boolean{return !!o&&typeof o.enabled==='boolean'&&WATCH_REGIONS.includes(o.region);}
export function providerRegion(region:string):string{if(!WATCH_REGIONS.includes(region)){throw new Error('Unknown region');}return region==='uk'?'GB':region.toUpperCase();}
export function fresh(at:number,now:number,age:number):boolean{return Number.isFinite(at)&&at>0&&now>=at&&now-at<age;}
export function numericId(id:number):boolean{return Number.isSafeInteger(id)&&id>0;}
export function mediaNumber(m:Media):number{if(!['show','movie'].includes(m.kind)||!new RegExp('^'+m.kind+':[1-9][0-9]*$').test(m.id)){throw new Error('Invalid media identity');}const n=Number(m.id.substring(m.kind.length+1));if(!numericId(n)){throw new Error('Invalid ID');}return n;}
export interface Provider{key:string;name:string;logo:string;options:string[];link:string;}
interface WireProvider{provider_id:number;provider_name:string;logo_path?:string;}
interface ProviderCountry{link?:string;flatrate?:WireProvider[];free?:WireProvider[];buy?:WireProvider[];rent?:WireProvider[];ads?:WireProvider[];}
interface ProviderResponse{id:number;results:Record<string,ProviderCountry>;}
export function safeProviderLink(value?:string):string{return typeof value==='string'&&/^https:\/\/www\.themoviedb\.org\/(movie|tv)\/[A-Za-z0-9_-]+\/watch(?:\?[A-Za-z0-9_=&%-]+)?$/.test(value)?value:'';}
export function parseProviders(raw:string,tmdb:number,region:string):Provider[]{
 const data=JSON.parse(raw) as ProviderResponse;if(!data||data.id!==tmdb||!data.results||Array.isArray(data.results)||typeof data.results!=='object'){throw new Error('Invalid provider identity');}
 const country=data.results[providerRegion(region)];if(!country){return [];}const out=new Map<string,Provider>();
 const groups:WireProvider[][]=[country.flatrate??[],country.free??[],country.buy??[],country.rent??[],country.ads??[]],types=['订阅','免费','购买','租赁','广告'];
 groups.forEach((rows:WireProvider[],i:number)=>{if(!Array.isArray(rows)){throw new Error('Invalid provider group');}for(const row of rows){if(!numericId(row.provider_id)||typeof row.provider_name!=='string'||!row.provider_name.trim()){throw new Error('Invalid provider');}
 const old=out.get(row.provider_name);if(old){if(!old.options.includes(types[i])){old.options.push(types[i]);}continue;}
 out.set(row.provider_name,{key:row.provider_name,name:row.provider_name,logo:typeof row.logo_path==='string'&&/^\/[A-Za-z0-9_-]+\.(png|jpg|jpeg|webp)$/.test(row.logo_path)?'https://image.tmdb.org/t/p/w92'+row.logo_path:'',options:[types[i]],link:safeProviderLink(country.link)});}});
 return Array.from(out.values());
}
interface WireIds{trakt:number;tmdb?:number;}
interface WireSeries{ids:WireIds;name:string;description:string;privacy:string;item_count:number;}
interface WireMovie{ids:WireIds;title:string;year?:number;}
interface WireItem{rank:number;movie:WireMovie;}
interface WireIdentity{ids:WireIds;}
export interface Series{ id:number;name:string;description:string;count:number; }
export interface SeriesMovie{rank:number;media:Media;}
export function parseTmdbIdentity(raw:string,media:Media):number{const row=JSON.parse(raw) as WireIdentity;if(!row?.ids||row.ids.trakt!==mediaNumber(media)||!numericId(row.ids.tmdb??0)){throw new Error('TMDB identity unavailable');}return row.ids.tmdb??0;}
export function parseSeries(raw:string):Series[]{const rows=JSON.parse(raw) as WireSeries[];if(!Array.isArray(rows)){throw new Error('Invalid series');}const out=new Map<number,Series>();for(const r of rows){if(r.privacy!=='public'){continue;}if(!r.ids||!numericId(r.ids.trakt)||typeof r.name!=='string'||!r.name.trim()||!Number.isSafeInteger(r.item_count)||r.item_count<0){throw new Error('Invalid series row');}if(!out.has(r.ids.trakt)){out.set(r.ids.trakt,{id:r.ids.trakt,name:r.name,description:typeof r.description==='string'?r.description:'',count:r.item_count});}}return Array.from(out.values());}
export function parseSeriesMovies(raw:string):SeriesMovie[]{const rows=JSON.parse(raw) as WireItem[];if(!Array.isArray(rows)){throw new Error('Invalid series members');}const seen=new Set<number>(),result:SeriesMovie[]=[];for(const r of rows){const m=r.movie;if(!m?.ids||!numericId(m.ids.trakt)||typeof m.title!=='string'||!m.title.trim()||!Number.isSafeInteger(r.rank)||r.rank<0||seen.has(m.ids.trakt)){throw new Error('Invalid member identity/rank');}seen.add(m.ids.trakt);result.push({rank:r.rank,media:{id:'movie:'+m.ids.trakt,title:m.title,kind:'movie',year:m.year??0,watched:false}});}return result.sort((a:SeriesMovie,b:SeriesMovie)=>a.rank-b.rank);}
export function verifySeriesMembers(series:Series,rows:SeriesMovie[],parent:string):void{if(rows.length!==series.count||!rows.some((r:SeriesMovie)=>r.media.id===parent)){throw new Error('Series membership incomplete or changed');}}
