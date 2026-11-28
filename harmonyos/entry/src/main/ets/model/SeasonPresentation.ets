import { airDate } from './ShowCatalog';
export interface PartIds {trakt:number;}
export interface PartImages {poster?:string[];screenshot?:string[];}
export interface EpisodeWire {ids:PartIds;number:number;season?:number;title?:string;first_aired?:string;rating?:number;runtime?:number;overview?:string;images?:PartImages;}
export interface SeasonWire {ids:PartIds;number:number;title?:string;rating?:number;images?:PartImages;episodes?:EpisodeWire[];}
export interface EpisodeInfo {id:number;season:number;number:number;title:string;firstAired:string;rating?:number;runtime?:number;overview:string;images:string[];}
export interface SeasonInfo {id:number;number:number;title:string;rating?:number;images:string[];episodes:EpisodeInfo[];}
function id(n:number):boolean{return Number.isSafeInteger(n)&&n>0;}
function rating(n?:number):number|undefined{return typeof n==='number'&&Number.isFinite(n)&&n>0&&n<=10?n:undefined;}
function urls(rows?:string[]):string[]{return Array.isArray(rows)?Array.from(new Set<string>(rows.filter((v:string)=>typeof v==='string'&&!!v))):[];}
export function parseSeasonPresentation(raw:string):SeasonInfo[]{
  const input=JSON.parse(raw) as SeasonWire[];
  if(!Array.isArray(input)){throw new Error('Invalid public seasons');}
  const seasons:SeasonInfo[]=[],numbers=new Set<number>(),episodeIds=new Set<number>();
  for(const row of input){
    if(!row||!row.ids||!id(row.ids.trakt)||!Number.isSafeInteger(row.number)||row.number<0||numbers.has(row.number)||!Array.isArray(row.episodes)){throw new Error('Invalid public season identity');}
    numbers.add(row.number);const episodes:EpisodeInfo[]=[],positions=new Set<number>();
    for(const e of row.episodes){
      if(!e||!e.ids||!id(e.ids.trakt)||!id(e.number)||(e.season!==undefined&&e.season!==row.number)||episodeIds.has(e.ids.trakt)||positions.has(e.number)){throw new Error('Invalid public episode identity');}
      episodeIds.add(e.ids.trakt);positions.add(e.number);
      episodes.push({id:e.ids.trakt,season:row.number,number:e.number,title:typeof e.title==='string'?e.title:'',firstAired:airDate(e.first_aired),rating:rating(e.rating),runtime:typeof e.runtime==='number'&&Number.isSafeInteger(e.runtime)&&e.runtime>0?e.runtime:undefined,overview:typeof e.overview==='string'?e.overview:'',images:urls(e.images?.screenshot)});
    }
    if(episodes.length){seasons.push({id:row.ids.trakt,number:row.number,title:typeof row.title==='string'?row.title:'',rating:rating(row.rating),images:urls(row.images?.poster),episodes:episodes.sort((a:EpisodeInfo,b:EpisodeInfo)=>a.number-b.number)});}
  }
  return seasons.sort((a:SeasonInfo,b:SeasonInfo)=>b.number-a.number);
}
export interface PartRating {id:number;value:number;}
export class SeasonPresentationOwner{
  private scope:string='';private seasons:Map<number,SeasonInfo>=new Map<number,SeasonInfo>();private episodes:Map<number,EpisodeInfo>=new Map<number,EpisodeInfo>();
  private seasonRatings:Map<number,number>=new Map<number,number>();private episodeRatings:Map<number,number>=new Map<number,number>();
  private ratingScope:string='';
  clear():void{this.scope='';this.seasons.clear();this.episodes.clear();this.clearRatings();}
  clearRatings():void{this.ratingScope='';this.seasonRatings.clear();this.episodeRatings.clear();}
  replace(scope:string,rows:SeasonInfo[]):void{
    if(scope!==this.scope){this.clear();this.scope=scope;}
    this.seasons.clear();this.episodes.clear();
    for(const season of rows){this.seasons.set(season.number,season);for(const episode of season.episodes){this.episodes.set(episode.id,episode);}}
  }
  setRatings(scope:string,activityScope:string,seasons:PartRating[],episodes:PartRating[]):boolean{
    if(scope!==this.scope){return false;}
    this.ratingScope=activityScope;this.seasonRatings.clear();this.episodeRatings.clear();
    for(const row of seasons){this.seasonRatings.set(row.id,row.value);}for(const row of episodes){this.episodeRatings.set(row.id,row.value);}return true;
  }
  season(number:number):SeasonInfo|undefined{return this.seasons.get(number);}
  episode(id:number):EpisodeInfo|undefined{return this.episodes.get(id);}
  seasonRating(number:number,scope:string):number|undefined{const row=this.season(number);return scope===this.ratingScope&&row?this.seasonRatings.get(row.id):undefined;}
  episodeRating(id:number,scope:string):number|undefined{return scope===this.ratingScope?this.episodeRatings.get(id):undefined;}
}
