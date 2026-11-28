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
