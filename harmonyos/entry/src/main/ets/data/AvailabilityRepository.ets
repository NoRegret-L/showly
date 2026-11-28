import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { Provider,Series,SeriesMovie,STREAMING_AGE,SERIES_AGE,fresh,mediaNumber,parseTmdbIdentity,parseProviders,parseSeries,parseSeriesMovies,verifySeriesMembers } from '../model/AvailabilityRules';
import { ReadCancel,ConsumerReadFlight } from '../model/ReadFlight';
import { checkPresentationService,presentationHttpError,traktPresentationService } from './PresentationHttp';
// Session-only; never persisted or included in cache keys.
let tmdbToken:string='';let credentialVersion:number=0;
export function configureTmdb(value:string):number{const token=value.trim();if(token&&!/^[A-Za-z0-9._~-]+$/.test(token)){throw new Error('Invalid token format');}tmdbToken=token;credentialVersion++;return credentialVersion;}
export function tmdbConfigured():boolean{return !!tmdbToken;}
export function tmdbCredentialVersion():number{return credentialVersion;}
interface CacheRow{raw:string;at:number;}
interface TraktHeaders{'Content-Type':string;'trakt-api-version':string;'trakt-api-key':string;}
interface TmdbHeaders{Authorization:string;Accept:string;}
export interface PublicRead<T>{rows:T[];cached:boolean;stale:boolean;}
export class AvailabilityRepository{
 private db:relationalStore.RdbStore;
 private flights:ConsumerReadFlight<string>=new ConsumerReadFlight<string>();
 constructor(db:relationalStore.RdbStore){this.db=db;}
 private async disk(key:string,signal:ReadCancel):Promise<CacheRow|undefined>{signal.check();const r=await this.db.querySql('SELECT payload,observed_at FROM availability_cache WHERE cache_key=?',[key]);try{signal.check();return r.goToFirstRow()?{raw:r.getString(0),at:r.getLong(1)}:undefined;}finally{r.close();}}
 private async fetch(path:string,client:string,tmdb:boolean,version:number,signal:ReadCancel):Promise<string>{
  signal.check();if(tmdb?(!tmdbToken||version!==credentialVersion):!client){throw new Error('Credentials unavailable');}
  const service=tmdb?'tmdb:public:'+version:traktPresentationService(client);checkPresentationService(service);
  const req=http.createHttp();let closed=false;const close=():void=>{if(!closed){closed=true;req.destroy();}};signal.subscribe(close);
  try{
   const th:TraktHeaders={'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':client};const mh:TmdbHeaders={Authorization:'Bearer '+tmdbToken,Accept:'application/json'};
   const response=await req.request((tmdb?'https://api.themoviedb.org/3/':'https://api.trakt.tv/')+path,{method:http.RequestMethod.GET,header:tmdb?mh:th,expectDataType:http.HttpDataType.STRING});
   signal.check();if(tmdb&&version!==credentialVersion){throw new Error('Credential changed');}
   if(response.responseCode!==200||typeof response.result!=='string'){throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);}
   return response.result;
  }finally{signal.unsubscribe(close);close();}
 }
 private async cached<T>(key:string,flightKey:string,age:number,refresh:boolean,signal:ReadCancel,parse:(raw:string)=>T[],fetcher:(scope:ReadCancel)=>Promise<string>):Promise<PublicRead<T>>{
  const old=await this.disk(key,signal);let previous:T[]|undefined;
  if(old){try{previous=parse(old.raw);}catch(error){}}
  if(previous&&old&&!refresh&&fresh(old.at,Date.now(),age)){return {rows:previous,cached:true,stale:false};}
  try{
   const raw=await this.flights.run(flightKey,async(scope:ReadCancel):Promise<string>=>{const data=await fetcher(scope);parse(data);scope.check();await this.db.executeSql('INSERT OR REPLACE INTO availability_cache(cache_key,payload,observed_at) VALUES(?,?,?)',[key,data,Date.now()]);return data;},signal);
   signal.check();return {rows:parse(raw),cached:false,stale:false};
  }catch(error){signal.check();if(previous){return {rows:previous,cached:true,stale:true};}throw new Error('Public detail unavailable');}
 }
 async galleryIdentity(item:Media,client:string,signal:ReadCancel):Promise<number>{
  const n=mediaNumber(item),kind=item.kind==='show'?'shows':'movies',key='identity:'+item.id;
  const value=await this.cached<number>(key,JSON.stringify([client,key]),SERIES_AGE,false,signal,(raw:string)=>[parseTmdbIdentity(raw,item)],(scope:ReadCancel)=>this.fetch(kind+'/'+n+'?extended=full',client,false,0,scope));return value.rows[0];
 }
 async galleryImages(kind:string,tmdb:number,version:number,signal:ReadCancel):Promise<string>{
  if(!['movie','tv','person'].includes(kind)||!Number.isSafeInteger(tmdb)||tmdb<=0){throw new Error('Invalid TMDB gallery identity');}
  return this.fetch(kind+'/'+tmdb+'/images','',true,version,signal);
 }
 async providers(item:Media,client:string,region:string,refresh:boolean,signal:ReadCancel):Promise<PublicRead<Provider>>{
  const n=mediaNumber(item),kind=item.kind==='show'?'shows':'movies',version=credentialVersion;
  const identityKey='identity:'+item.id;const identity=await this.cached<number>(identityKey,JSON.stringify([client,identityKey]),SERIES_AGE,false,signal,(raw:string)=>[parseTmdbIdentity(raw,item)],(scope:ReadCancel)=>this.fetch(kind+'/'+n+'?extended=full',client,false,version,scope));
  const tmdb=identity.rows[0],key='provider:'+item.id+':'+tmdb+':'+region;
  const result=await this.cached<Provider>(key,JSON.stringify([key,version]),STREAMING_AGE,refresh,signal,(raw:string)=>parseProviders(raw,tmdb,region),(scope:ReadCancel)=>this.fetch((item.kind==='show'?'tv/':'movie/')+tmdb+'/watch/providers','',true,version,scope));
  if(version!==credentialVersion){throw new Error('Credential changed');}return result;
 }
 series(item:Media,client:string,refresh:boolean,signal:ReadCancel):Promise<PublicRead<Series>>{
  if(item.kind!=='movie'){return Promise.reject(new Error('Movie required'));}const n=mediaNumber(item),key='series:movie:'+n;
  return this.cached<Series>(key,JSON.stringify([client,key]),SERIES_AGE,refresh,signal,parseSeries,(scope:ReadCancel)=>this.fetch('movies/'+n+'/lists/official/popular',client,false,0,scope));
 }
 movies(series:Series,parent:string,client:string,refresh:boolean,signal:ReadCancel):Promise<PublicRead<SeriesMovie>>{
  const key='series:items:'+series.id;
  return this.cached<SeriesMovie>(key,JSON.stringify([client,key,series.count,parent]),SERIES_AGE,refresh,signal,(raw:string)=>{const rows=parseSeriesMovies(raw);verifySeriesMembers(series,rows,parent);return rows;},(scope:ReadCancel)=>this.fetch('lists/'+series.id+'/items/movie?extended=full',client,false,0,scope));
 }
}
let opening:Promise<AvailabilityRepository>|undefined;
export function openAvailability(context:common.UIAbilityContext):Promise<AvailabilityRepository>{
 if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_availability.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<AvailabilityRepository>=>{await db.executeSql('CREATE TABLE IF NOT EXISTS availability_cache(cache_key TEXT PRIMARY KEY,payload TEXT NOT NULL,observed_at INTEGER NOT NULL)');return new AvailabilityRepository(db);}).catch((e:Error):AvailabilityRepository=>{opening=undefined;throw e;});}return opening;
}
