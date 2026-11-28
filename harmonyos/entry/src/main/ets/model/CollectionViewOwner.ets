import { PersonalLibraryRow } from './PersonalLibrary';
import { CollectionMeta } from './MediaPresentation';
import { CollectionOptions } from './CollectionRules';
// Derived, account-scoped view state only; no authority or sync writes.
export interface CollectionViewSnapshot { section:string; query:string; status:string; grid:boolean; searchOpen:boolean; revision:number; }
export class CollectionViewOwner {
  private value:CollectionViewSnapshot={section:'mine',query:'',status:'all',grid:true,searchOpen:false,revision:0};
  snapshot():CollectionViewSnapshot{
    const v=this.value;
    return {section:v.section,query:v.query,status:v.status,grid:v.grid,searchOpen:v.searchOpen,revision:v.revision};
  }
  update(section:string,query:string,status:string,grid:boolean,searchOpen:boolean):boolean{
    const v=this.value;
    if(v.section===section&&v.query===query&&v.status===status&&v.grid===grid&&v.searchOpen===searchOpen){return false;}
    this.value={section:section,query:query,status:status,grid:grid,searchOpen:searchOpen,revision:v.revision+1};return true;
  }
  clear():void{this.update('mine','','all',true,false);}
}
export interface CollectionNetworkGroup { name:string; channels:string[]; }
// Exact channel groups ported from Android Network.kt at e08cb90b.
export const COLLECTION_NETWORK_GROUPS:CollectionNetworkGroup[]=[
  {name:"ABC",channels:["ABC","ABC (AU)","ABC (JA)","ABC (US)","ABC Comedy","ABC Family","ABC KIDS","ABC Me","ABC News","ABC News 24","ABC Spark","ABC TV","ABC TV Plus"]},
  {name:"AMC",channels:["AMC","AMC+"]},
  {name:"APPLE",channels:["Apple","Apple TV+","Apple Music"]},
  {name:"AMAZON",channels:["Amazon","Amazon (Japan)","Amazon Freevee","Amazon Kids+","Amazon Prime Video","Amazon Studios","Amazon miniTV"]},
  {name:"BBC",channels:["BBC","BBC America","BBC Canada","BBC Choice","BBC Earth","BBC First","BBC Four","BBC HD","BBC Kids","BBC Knowledge","BBC Music","BBC News","BBC One","BBC Prime","BBC Red Button","BBC Scotland","BBC Television","BBC Three","BBC Two","BBC UKTV","BBC Wales","BBC World News","BBC Worldwide","BBC iPlayer"]},
  {name:"CBS",channels:["CBS","CBS All Access","CBS News","CBS Reality","CBS Reality (UK)","CBS.com"]},
  {name:"CRUNCHYROLL",channels:["Crunchyroll"]},
  {name:"CW",channels:["CW","The CW"]},
  {name:"DISCOVERY",channels:["Discovery","Discovery (NL)","Discovery (US)","Discovery Asia","Discovery Channel","Discovery Channel (AU)","Discovery Channel (Asia)","Discovery Channel (CA)","Discovery Channel (Canada)","Discovery Channel (PL)","Discovery Channel (SE)","Discovery Channel (UK)","Discovery Communications","Discovery Family","Discovery GO","Discovery HD World","Discovery Health Channel","Discovery History","Discovery JEET","Discovery Kids","Discovery Life","Discovery MAX","Discovery Real Time","Discovery Science","Discovery Shed","Discovery Turbo","Discovery Turbo UK","Discovery UK","Discovery+"]},
  {name:"DISNEY",channels:["Disney","Disney Channel","Disney Channel (DE)","Disney Channel (FR)","Disney Channel (IT)","Disney Channel (UK)","Disney Channel (US)","Disney Cinemagic","Disney Junior","Disney Junior (UK)","Disney Television Animation","Disney XD","Disney XD (Latin America)","Disney+","Disney+ Hotstar"]},
  {name:"HBO",channels:["HBO Max","HBO Asia","HBO Brasil","HBO Canada","HBO España","HBO Europe","HBO Family","HBO Latin","HBO America","HBO Magyarország","HBO Nordic","HBO","Max","MAX"]},
  {name:"FOX",channels:["FOX","FOX (US)","FOX España","FOX Reality","FOX SPORTS","FOX Traveller","FOX Türkiye","FOX Türkiye (TR)","FOX+"]},
  {name:"HULU",channels:["Hulu","Hulu Japan"]},
  {name:"ITV",channels:["ITV","ITV Encore","ITV Granada","ITV Wales"]},
  {name:"NBC",channels:["NBC","NBC News Studios","NBC Universo","NBCSN","NBCUniversal"]},
  {name:"NETFLIX",channels:["Netflix"]},
  {name:"PARAMOUNT",channels:["Paramount","Paramount (GB)","Paramount Network","Paramount+","Paramount+ (AU)","Paramount+ (MX)"]},
  {name:"PEACOCK",channels:["Peacock"]},
  {name:"RAKUTEN",channels:["Rakuten TV"]},
  {name:"SHOWTIME",channels:["Showtime"]},
];
export interface CollectionGenreOption { slug:string; label:string; }
export const COLLECTION_GENRES:CollectionGenreOption[]=[
  {slug:"action",label:"动作"},
  {slug:"adventure",label:"冒险"},
  {slug:"animation",label:"动画"},
  {slug:"anime",label:"动漫"},
  {slug:"comedy",label:"喜剧"},
  {slug:"crime",label:"犯罪"},
  {slug:"documentary",label:"纪录片"},
  {slug:"drama",label:"剧情"},
  {slug:"fantasy",label:"奇幻"},
  {slug:"history",label:"历史"},
  {slug:"horror",label:"恐怖"},
  {slug:"science-fiction",label:"科幻"},
  {slug:"romance",label:"爱情"},
  {slug:"thriller",label:"惊悚"},
  {slug:"war",label:"战争"},
  {slug:"western",label:"西部"},
];
export function toggleCollectionSelection(current:string[],values:string[]):string[]{
  const remove=values.every((v:string)=>current.includes(v));
  if(remove){return current.filter((v:string)=>!values.includes(v));}
  return Array.from(new Set<string>([...current,...values]));
}

// Config.MY_SHOWS_RECENTS_OPTIONS and Settings.createInitial at e08cb90b.
export const COLLECTION_RECENT_AMOUNTS:number[]=[0,2,4,6,8];
export function validCollectionRecentAmount(value:number):boolean{return COLLECTION_RECENT_AMOUNTS.includes(value);}
export class CollectionDependencyVersions {
  private showBusiness:number=0;
  private movieBusiness:number=0;
  private showSource:number=0;
  private movieSource:number=0;
  observe(ids:string[],unknown:boolean):void{
    let show=unknown,movie=unknown;
    for(const id of ids){
      if(id.startsWith('show:')){show=true;}else if(id.startsWith('movie:')){movie=true;}else{show=true;movie=true;}
    }
    if(show){this.showBusiness++;}if(movie){this.movieBusiness++;}
  }
  sourceChanged(kind:string):void{
    if(kind!=='movie'){this.showSource++;}if(kind!=='show'){this.movieSource++;}
  }
  business(kind:string):number{return kind==='movie'?this.movieBusiness:this.showBusiness;}
  source(kind:string):number{return kind==='movie'?this.movieSource:this.showSource;}
  reset():void{this.observe([],true);this.sourceChanged('');}
}
class CollectionFieldVersions {
  genres:number=0;network:number=0;release:number=0;rating:number=0;runtime:number=0;
  change(before:CollectionMeta|undefined,after:CollectionMeta|undefined):void{
    // Absence is distinct from a verified empty field.
    if(JSON.stringify(before?.genres??null)!==JSON.stringify(after?.genres??null)){this.genres++;}
    if(before?.network!==after?.network){this.network++;}
    if(before?.release!==after?.release){this.release++;}
    if(before?.rating!==after?.rating){this.rating++;}
    if(before?.runtime!==after?.runtime){this.runtime++;}
  }
  key(options:CollectionOptions,section:string,kind:string):string{
    return JSON.stringify([options.genres.length?this.genres:0,
      kind==='show'&&options.networks.length?this.network:0,
      options.sort==='newest'||(section==='queue'&&options.upcoming!=='all')?this.release:0,
      options.sort==='rating'?this.rating:0,options.sort==='runtime'?this.runtime:0]);
  }
}
export class CollectionMetadataVersions {
  private show:CollectionFieldVersions=new CollectionFieldVersions();
  private movie:CollectionFieldVersions=new CollectionFieldVersions();
  changed(id:string,before:CollectionMeta|undefined,after:CollectionMeta|undefined):void{
    if(id.startsWith('movie:')){this.movie.change(before,after);}else if(id.startsWith('show:')){this.show.change(before,after);}
    else{this.show.change(before,after);this.movie.change(before,after);}
  }
  key(kind:string,options:CollectionOptions,section:string):string{
    return (kind==='movie'?this.movie:this.show).key(options,section,kind);
  }
}
// The transport is shared by progress and collection; request ownership is
// per kind. A reset revokes the right to publish, not another consumer's I/O.
export class CollectionRatingRequest {
  private serial:number=0;private active:number=0;private key:string='';
  begin(key:string):number{
    if(this.active!==0&&this.key===key){return 0;}
    this.key=key;this.active=++this.serial;return this.active;
  }
  current(token:number):boolean{return token!==0&&token===this.active;}
  finish(token:number):boolean{
    if(!this.current(token)){return false;}
    this.active=0;return true;
  }
  reset():void{this.active=0;this.key='';}
}
export function collectionEmptyText(filtered:boolean,section:string):string{
  if(filtered){return '没有符合筛选条件的影视';}
  if(section==='queue'){return '待看清单为空';}
  if(section==='hidden'){return '没有隐藏的影视';}
  return '此分类暂无影视';
}

// Derived runtime state is independently owned per media kind. Retry tickets
// revoke publication rights across account/route changes, not sync writes.
export interface CollectionRecoverySnapshot {
  revision:number;scope:string;failureKey:string;error:string;fullRetry:boolean;retrying:boolean;headerKey:string;
}
export class CollectionRecoveryOwner {
  private revision:number=0;
  private scope:string='';
  private failureKey:string='';
  private error:string='';
  private fullRetry:boolean=false;
  private retrying:boolean=false;
  private headerKey:string='';
  private serial:number=0;
  private ticket:number=0;
  activate(scope:string):void{
    if(this.scope===scope){return;}
    this.clear();this.scope=scope;
  }
  clear():void{
    this.scope='';this.failureKey='';this.error='';this.fullRetry=false;this.retrying=false;
    this.headerKey='';this.ticket=0;this.revision++;
  }
  snapshot():CollectionRecoverySnapshot{
    return {revision:this.revision,scope:this.scope,failureKey:this.failureKey,error:this.error,
      fullRetry:this.fullRetry,retrying:this.retrying,headerKey:this.headerKey};
  }
  blocked(key:string):boolean{return !!this.failureKey&&this.failureKey===key;}
  needsFull():boolean{return this.fullRetry;}
  headerCurrent(key:string):boolean{return key===this.headerKey;}
  publishHeader(key:string):void{if(this.headerKey!==key){this.headerKey=key;this.revision++;}}
  fail(key:string,message:string):void{
    if(this.failureKey===key&&this.error===message&&!this.fullRetry){return;}
    this.failureKey=key;this.error=message;this.fullRetry=false;this.revision++;
  }
  beginRetry(scope:string):number{
    if(this.scope!==scope||this.retrying){return 0;}
    this.retrying=true;this.ticket=++this.serial;this.revision++;return this.ticket;
  }
  current(scope:string,ticket:number):boolean{return this.scope===scope&&ticket!==0&&this.ticket===ticket&&this.retrying;}
  requestFull(scope:string,ticket:number):boolean{
    if(!this.current(scope,ticket)){return false;}
    this.failureKey='';this.error='';this.headerKey='';this.fullRetry=true;this.revision++;return true;
  }
  finishRetry(scope:string,ticket:number):boolean{
    if(!this.current(scope,ticket)){return false;}
    this.retrying=false;this.ticket=0;this.revision++;return true;
  }
  refresh():void{this.failureKey='';this.error='';this.headerKey='';this.fullRetry=false;this.revision++;}
  published():void{
    if(this.error||this.failureKey||this.fullRetry){this.error='';this.failureKey='';this.fullRetry=false;this.revision++;}
  }
}

// One immutable-by-publication UI value; avoid independent header/error state writes.
export interface CollectionUiSnapshot { recent:PersonalLibraryRow[]; other:boolean; error:string; retrying:boolean; revision:number; }
export function emptyCollectionUi():CollectionUiSnapshot{return {recent:[],other:false,error:'',retrying:false,revision:0};}
export function collectionUiNext(old:CollectionUiSnapshot,recent:PersonalLibraryRow[],other:boolean,error:string,retrying:boolean):CollectionUiSnapshot{
  if(old.recent===recent&&old.other===other&&old.error===error&&old.retrying===retrying){return old;}
  return {recent:recent,other:other,error:error,retrying:retrying,revision:old.revision+1};
}
export interface CollectionSpoilers { description:boolean; rating:boolean; reveal:boolean; }
export function defaultCollectionSpoilers():CollectionSpoilers{return {description:false,rating:false,reveal:false};}
export function collectionSpoilerText(value:string,hidden:boolean,revealed:boolean,rating:boolean=false):string{
  if(!hidden||revealed||!value){return value;}
  return rating?'•.•':value.replace(/\S/g,'•');
}
// Same visibility policy as the progress row; reuse the collection spoiler mask.
export function progressRatingSpoilerText(sort:string,fresh:boolean,upcoming:boolean,rating:number|undefined,userRating:number|undefined,hidden:boolean,revealed:boolean):string{
  if(fresh||upcoming){return '';}
  if(sort==='userRating'){return userRating===undefined?'':userRating.toString();}
  if(sort!=='rating'||rating===undefined||!Number.isFinite(rating)){return '';}
  return collectionSpoilerText(rating.toFixed(1),hidden,revealed,true);
}
