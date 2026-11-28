import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { GalleryTarget,GalleryImage,galleryKey,galleryRows,parseGallery,PEOPLE_GALLERY_AGE,galleryTraktUrl,tmdbArtworkUrl } from '../model/GalleryRules';
import { ReadCancel,ConsumerReadFlight } from '../model/ReadFlight';
import { openAvailability,tmdbCredentialVersion } from './AvailabilityRepository';
import { cachedPoster,posterPath,readDetails } from './TraktDetails';
export interface GalleryRead{rows:GalleryImage[];status:string;}
interface GalleryCache{raw:string;at:number;}
export class GalleryRepository{
 private db:relationalStore.RdbStore;private flights:ConsumerReadFlight<string>=new ConsumerReadFlight<string>();
 constructor(db:relationalStore.RdbStore){this.db=db;}
 private async disk(key:string,signal:ReadCancel):Promise<GalleryCache|undefined>{
  signal.check();const r=await this.db.querySql('SELECT payload,observed_at FROM gallery_candidates WHERE identity=?',[key]);try{signal.check();return r.goToFirstRow()?{raw:r.getString(0),at:r.getLong(1)}:undefined;}finally{r.close();}
 }
 async load(context:common.UIAbilityContext,t:GalleryTarget,client:string,refresh:boolean,signal:ReadCancel):Promise<GalleryRead>{
  const key=galleryKey(t);let hints=t.hints.slice(),remote:GalleryImage[]=[],status='';const version=tmdbCredentialVersion();
  if(t.item.kind!=='person'&&!hints.length){try{const d=await readDetails(t.item,client,false,signal);hints=t.type==='poster'?d.posterUrls:d.fanartUrls??[];}catch(error){signal.check();}}
  const fallback:GalleryImage[]=hints.map((url:string):GalleryImage=>({url:galleryTraktUrl(url),source:'trakt'})).filter((r:GalleryImage)=>!!r.url);
  let tmdb=t.tmdb??0;
  try{
   const repo=await openAvailability(context);
   if(t.item.kind!=='person'){tmdb=await repo.galleryIdentity(t.item,client,signal);}
   if(!Number.isSafeInteger(tmdb)||tmdb<=0){throw new Error('No TMDB ID');}
   const lane=JSON.stringify([key,tmdb,'tmdb']),old=await this.disk(lane,signal);
   let previous:GalleryImage[]|undefined;if(old){try{previous=parseGallery(old.raw,tmdb,t.type);}catch(error){}}
   if(t.item.kind==='person'&&previous&&old&&!refresh&&Date.now()>=old.at&&Date.now()-old.at<PEOPLE_GALLERY_AGE){remote=previous;status='TMDB 本地图库';}
   else{
    try{const kind=t.item.kind==='show'?'tv':t.item.kind;
     const raw=await this.flights.run(JSON.stringify([lane,version]),async(s:ReadCancel):Promise<string>=>{
      const data=await repo.galleryImages(kind,tmdb,version,s);parseGallery(data,tmdb,t.type);s.check();if(version!==tmdbCredentialVersion()){throw new Error('Credential changed');}
      await this.db.executeSql('INSERT OR REPLACE INTO gallery_candidates(identity,payload,observed_at) VALUES(?,?,?)',[lane,data,Date.now()]);return data;
     },signal);remote=parseGallery(raw,tmdb,t.type);status='TMDB 图库';
    }catch(error){signal.check();if(previous){remote=previous;status='TMDB 离线图库 · 可能不是最新';}else{status='TMDB 不可用 · Trakt 降级';}}
   }
  }catch(error){signal.check();status='TMDB 不可用 · Trakt 降级';}
  signal.check();if(version!==tmdbCredentialVersion()){throw new Error('Credential changed');}
  const type=t.type==='poster'?'poster':'fanart',dir=context.cacheDir;
  let initial:GalleryImage|undefined;
  const candidates=galleryRows(t,undefined,remote,fallback);
  if(t.initialUri){
   for(const row of candidates){
    const path=await posterPath(dir,t.item,row.url,type);
    if(fileUri.getUriFromPath(path)===t.initialUri){initial=row;break;}
    const oldPath=await posterPath(context.filesDir,t.item,row.url,type);
    if(fileUri.getUriFromPath(oldPath)===t.initialUri){initial=row;break;}
   }
   if(!initial&&t.initialUri.startsWith('file://')){initial={source:'local',url:t.initialUri};}
  }else{
   const cached=await cachedPoster(dir,t.item,fallback.map((r:GalleryImage)=>r.url),signal,type);
   if(cached){for(const r of fallback){if(fileUri.getUriFromPath(await posterPath(dir,t.item,r.url,type))===cached){initial=r;break;}}}
  }
  signal.check();return {rows:galleryRows(t,initial,remote,fallback),status:status};
 }
}
let opening:Promise<GalleryRepository>|undefined;
export function openGallery(context:common.UIAbilityContext):Promise<GalleryRepository>{
 if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_gallery.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<GalleryRepository>=>{
  await db.executeSql('CREATE TABLE IF NOT EXISTS gallery_candidates(identity TEXT PRIMARY KEY,payload TEXT NOT NULL,observed_at INTEGER NOT NULL)');return new GalleryRepository(db);
 }).catch((e:Error):GalleryRepository=>{opening=undefined;throw e;});}return opening;
}
