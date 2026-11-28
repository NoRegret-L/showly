import { Media } from './Media';
import { ProgressSource } from './ProgressRules';
import { CollectionMeta } from './MediaPresentation';
export interface StatisticsRuntime { id:number; minutes:number; }
export interface StatisticsInput { media:Media; mine:boolean; source?:ProgressSource; sourceKey:string; observed:number; meta?:CollectionMeta; runtimes:StatisticsRuntime[]; }
export interface StatisticsRow { media:Media; minutes:number; episodes:number; seasons:number; missing:number; mine:boolean; genres:string[]; unknownGenres:boolean; }
export interface StatisticsGenre { name:string; count:number; }
export interface StatisticsRating { id:string; value:number; ratedAt?:number; }
export interface StatisticsRatingRow { media:Media; value:number; ratedAt?:number; }
export interface StatisticsSnapshot { revision:number; titles:number; minutes:number; episodes:number; watchedShows:number; missing:number; unknownGenres:number; ranking:StatisticsRow[]; genres:StatisticsGenre[]; }
interface StatisticsEntry { input:StatisticsInput; signature:string; row:StatisticsRow; }
export function emptyStatistics():StatisticsSnapshot{return {revision:0,titles:0,minutes:0,episodes:0,watchedShows:0,missing:0,unknownGenres:0,ranking:[],genres:[]};}
function known(n?:number):boolean{return n!==undefined&&Number.isSafeInteger(n)&&n>0;}
function contribution(x:StatisticsInput):StatisticsRow{
  const genres=Array.from(new Set<string>((x.meta?.genres??[]).filter((g:string)=>!!g.trim())));
  const row:StatisticsRow={media:x.media,minutes:0,episodes:0,seasons:0,missing:0,mine:x.mine,genres:genres,unknownGenres:!x.meta};
  if(x.media.kind==='movie'){if(known(x.meta?.runtime)){row.minutes=x.meta?.runtime??0;}else{row.missing=1;}return row;}
  const runtimes=new Map<number,number>();for(const value of x.runtimes){if(known(value.minutes)){runtimes.set(value.id,value.minutes);}}
  const ids=new Set<number>(),seasons=new Set<number>();
  if(x.source?.media.id===x.media.id){for(const ep of x.source.episodes){if(!ep.watched||ids.has(ep.episode.id)){continue;}ids.add(ep.episode.id);seasons.add(ep.episode.season);const runtime=runtimes.get(ep.episode.id);if(runtime!==undefined){row.minutes+=runtime;}else{row.missing++;}}}
  row.episodes=ids.size;row.seasons=seasons.size;
  // Aggregate cloud counts cannot create fake episode identities or runtimes.
  if(x.observed>row.episodes){row.missing+=x.observed-row.episodes;}
  return row;
}
function signature(x:StatisticsInput):string{return JSON.stringify([x.media,x.mine,x.sourceKey,x.observed,x.meta?.genres,x.meta?.runtime,x.runtimes]);}
export class StatisticsOwner{
  private scope:string='';private entries:Map<string,StatisticsEntry>=new Map<string,StatisticsEntry>();private counts:Map<string,number>=new Map<string,number>();
  private minutes:number=0;private episodes:number=0;private watchedShows:number=0;private missing:number=0;private unknownGenres:number=0;private scans:number=0;
  private view:StatisticsSnapshot=emptyStatistics();
  clear():void{this.scope='';this.entries.clear();this.counts.clear();this.minutes=0;this.episodes=0;this.watchedShows=0;this.missing=0;this.unknownGenres=0;this.scans=0;this.view=emptyStatistics();}
  computations():number{return this.scans;}
  snapshot():StatisticsSnapshot{return this.view;}
  private apply(row:StatisticsRow,sign:number):void{this.minutes+=sign*row.minutes;this.episodes+=sign*row.episodes;this.watchedShows+=sign*(row.episodes>0?1:0);this.missing+=sign*row.missing;this.unknownGenres+=sign*(row.unknownGenres?1:0);
    for(const genre of row.genres){const n=(this.counts.get(genre)??0)+sign;if(n===0){this.counts.delete(genre);}else{this.counts.set(genre,n);}}}
  update(scope:string,inputs:StatisticsInput[]):StatisticsSnapshot{
    if(!scope){this.clear();return this.view;}
    if(scope!==this.scope){this.clear();this.scope=scope;}
    let changed=false;const seen=new Set<string>();
    for(const x of inputs){if(seen.has(x.media.id)){continue;}seen.add(x.media.id);const key=signature(x),prior=this.entries.get(x.media.id);
      if(prior&&prior.signature===key&&(prior.input.source===x.source||!!x.sourceKey)){continue;}
      if(prior){this.apply(prior.row,-1);}const row=contribution(x);this.apply(row,1);this.entries.set(x.media.id,{input:x,signature:key,row:row});this.scans++;changed=true;}
    for(const id of this.entries.keys()){if(!seen.has(id)){const prior=this.entries.get(id);if(prior){this.apply(prior.row,-1);}this.entries.delete(id);changed=true;}}
    if(!changed){return this.view;}
    const ranking:StatisticsRow[]=[],genres:StatisticsGenre[]=[];const first=new Set<string>();
    // Equal counts follow first encounter in the original deduplicated member sequence.
    for(const x of inputs){const row=this.entries.get(x.media.id)?.row;if(!row||first.has(x.media.id)){continue;}first.add(x.media.id);if(row.media.kind==='show'){ranking.push(row);}for(const name of row.genres){if(!genres.some((g:StatisticsGenre)=>g.name===name)){genres.push({name:name,count:this.counts.get(name)??0});}}}
    ranking.sort((a:StatisticsRow,b:StatisticsRow)=>b.minutes-a.minutes);genres.sort((a:StatisticsGenre,b:StatisticsGenre)=>b.count-a.count);
    this.view={revision:this.view.revision+1,titles:this.entries.size,minutes:this.minutes,episodes:this.episodes,watchedShows:this.watchedShows,missing:this.missing,unknownGenres:this.unknownGenres,ranking:ranking,genres:genres};return this.view;
  }
  ratings(rows:StatisticsRating[]):StatisticsRatingRow[]{const result:StatisticsRatingRow[]=[];for(const rating of rows){const row=this.entries.get(rating.id)?.row;if(!row?.mine||!Number.isInteger(rating.value)||rating.value<1||rating.value>10){continue;}result.push({media:row.media,value:rating.value,ratedAt:rating.ratedAt});if(result.length===25){break;}}
    return result.sort((a:StatisticsRatingRow,b:StatisticsRatingRow)=>(b.ratedAt??0)-(a.ratedAt??0));}
}
export function completeStatistics(scope:string,inputs:StatisticsInput[]):StatisticsSnapshot{return new StatisticsOwner().update(scope,inputs);}
