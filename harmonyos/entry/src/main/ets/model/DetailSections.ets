import { Media } from './Media';
import { ReadCancel } from './ReadFlight';
export interface CreditPerson { id:number; tmdb?:number; name:string; }
export interface CreditRow { person:CreditPerson; character?:string; characters?:string[]; job?:string; jobs?:string[]; }
export interface CreditCrew { directing?:CreditRow[]; writing?:CreditRow[]; sound?:CreditRow[]; }
export interface CreditResponse { cast?:CreditRow[]; crew?:CreditCrew; }
export interface PersonRow { key:string; personId:number; tmdb?:number; name:string; department:string; roles:string[]; }
export interface RelatedRow { media:Media; votes:number; rating?:number; posters:string[]; }
interface RelatedIds { trakt:number; }
interface RelatedImages { poster?:string[]; }
export interface RelatedWire { ids:RelatedIds; title:string; year?:number; votes?:number; rating?:number; images?:RelatedImages; }
function distinct(values:string[]):string[]{return Array.from(new Set<string>(values.filter((v:string)=>typeof v==='string'&&!!v.trim())));}
function credits(rows:CreditRow[],department:string):PersonRow[]{
  const result:Map<number,PersonRow>=new Map<number,PersonRow>();
  for(const row of rows){
    const p=row.person;
    if(!p||!Number.isSafeInteger(p.id)||p.id<=0||typeof p.name!=='string'||!p.name.trim()){continue;}
    const roles=distinct(department==='Acting'?(row.characters??(row.character?[row.character]:[])):(row.jobs??(row.job?[row.job]:[])));
    const allowed=department==='Acting'?roles:roles.filter((x:string)=>['Director','Writer','Story','Screenplay','Music','Original Music Composer'].includes(x));
    if(department!=='Acting'&&!allowed.length){continue;}
    const old=result.get(p.id);
    if(old){old.roles=distinct(old.roles.concat(allowed));continue;}
    result.set(p.id,{key:department+':'+p.id,personId:p.id,tmdb:p.tmdb,name:p.name,department:department,roles:allowed});
  }
  // Original repository limits, not new tuning parameters.
  return Array.from(result.values()).slice(0,department==='Acting'?30:20);
}
export function projectPeople(data:CreditResponse):PersonRow[]{
  return credits(data.cast??[],'Acting').concat(credits(data.crew?.directing??[],'Directing'),credits(data.crew?.writing??[],'Writing'),credits(data.crew?.sound??[],'Sound'));
}
export function parseRelated(rows:RelatedWire[],kind:string):RelatedRow[]{
  const result:RelatedRow[]=[];const seen:Set<string>=new Set<string>();
  for(const row of rows){
    if(!row.ids||!Number.isSafeInteger(row.ids.trakt)||row.ids.trakt<=0||typeof row.title!=='string'){throw new Error('Invalid related identity');}
    const id=kind+':'+row.ids.trakt;if(seen.has(id)){continue;}seen.add(id);
    result.push({media:{id:id,kind:kind,title:row.title,year:typeof row.year==='number'?row.year:0,watched:false},
      votes:typeof row.votes==='number'&&Number.isFinite(row.votes)&&row.votes>=0?row.votes:0,
      rating:typeof row.rating==='number'&&Number.isFinite(row.rating)&&row.rating>=0&&row.rating<=10?row.rating:undefined,
      posters:Array.isArray(row.images?.poster)?row.images?.poster?.filter((url:string)=>typeof url==='string')??[]:[]});
  }
  return result;
}
export function projectRelated(rows:RelatedRow[],parent:string,hidden:Set<string>):RelatedRow[]{
  // Kotlin stable ascending compare(votes,rating), then reversed, including exact ties.
  return rows.filter((r:RelatedRow)=>r.media.id!==parent&&(r.media.kind!=='show'||!hidden.has(r.media.id)))
    .sort((a:RelatedRow,b:RelatedRow)=>a.votes-b.votes||(a.rating??0)-(b.rating??0)).reverse();
}
export interface SectionSnapshot<T>{revision:number;rows:T[];busy:boolean;status:string;loaded:boolean;}
export function emptySection<T>():SectionSnapshot<T>{return {revision:0,rows:[],busy:false,status:'',loaded:false};}
export class SectionOwner<T>{
  private value:SectionSnapshot<T>=emptySection<T>();private signal:ReadCancel=new ReadCancel();private generation:number=0;
  snapshot():SectionSnapshot<T>{return this.value;}
  begin():number{this.signal.cancel();this.signal=new ReadCancel();this.generation++;return this.generation;}
  consumer():ReadCancel{return this.signal;}
  current(token:number):boolean{return token===this.generation&&!this.signal.cancelled();}
  clear():void{this.begin();this.value=emptySection<T>();}
  publish(token:number,rows:T[],busy:boolean,status:string,loaded:boolean):boolean{
    if(!this.current(token)){return false;}
    const v=this.value;if(v.rows===rows&&v.busy===busy&&v.status===status&&v.loaded===loaded){return false;}
    this.value={revision:v.revision+1,rows:rows,busy:busy,status:status,loaded:loaded};return true;
  }
}
