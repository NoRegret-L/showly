import { Media,validReleaseDate } from './Media';
import { PersonRow } from './DetailSections';
export interface PersonIdentity{trakt:number;tmdb?:number;}
export interface PersonProfile{identity:PersonIdentity;name:string;bio:string;birthday:string;death:string;birthplace:string;department:string;headshots:string[];source:string;}
export interface PersonCredit{media:Media;release:string;upcoming:boolean;roles:string[];}
export interface PersonCreditRow{key:string;group:string;credit?:PersonCredit;member:boolean;}
interface PersonWireIds{trakt:number;tmdb?:number;}
interface PersonWireImages{headshot?:string[];}
interface PersonWire{ids:PersonWireIds;name:string;biography?:string;birthday?:string;death?:string;birthplace?:string;known_for?:string;images?:PersonWireImages;}
interface WorkWire{ids:PersonWireIds;title:string;year?:number;released?:string;first_aired?:string;status?:string;}
interface WorkCreditWire{show?:WorkWire;movie?:WorkWire;character?:string;characters?:string[];job?:string;jobs?:string[];}
interface WorkCrewWire{production?:WorkCreditWire[];art?:WorkCreditWire[];crew?:WorkCreditWire[];directing?:WorkCreditWire[];writing?:WorkCreditWire[];sound?:WorkCreditWire[];camera?:WorkCreditWire[];}
interface CreditsWire{cast?:WorkCreditWire[];crew?:WorkCrewWire;}
export function positiveId(id?:number):boolean{return id!==undefined&&Number.isSafeInteger(id)&&id>0;}
export function personKey(person:PersonRow):string{if(!positiveId(person.personId)){throw new Error('Invalid person identity');}return 'trakt:'+person.personId;}
function text(value?:string):string{return typeof value==='string'?value.trim():'';}
function date(value?:string):string{return validReleaseDate(text(value).substring(0,10));}
export function parsePerson(raw:string,person:PersonRow):PersonProfile{
  const p=JSON.parse(raw) as PersonWire;
  if(!p||!p.ids||p.ids.trakt!==person.personId||!text(p.name)||(positiveId(person.tmdb)&&positiveId(p.ids.tmdb)&&p.ids.tmdb!==person.tmdb)){throw new Error('Person identity mismatch');}
  return {identity:{trakt:p.ids.trakt,tmdb:positiveId(p.ids.tmdb)?p.ids.tmdb:person.tmdb},name:p.name,bio:text(p.biography),birthday:date(p.birthday),death:date(p.death),birthplace:text(p.birthplace),department:text(p.known_for)||person.department,headshots:Array.isArray(p.images?.headshot)?p.images?.headshot?.filter((u:string)=>typeof u==='string')??[]:[],source:'trakt'};
}
export function parsePersonCredits(raw:string,kind:string,acting:boolean):PersonCredit[]{
  if(kind!=='movie'&&kind!=='show'){throw new Error('Invalid work type');}
  const p=JSON.parse(raw) as CreditsWire;if(!p||(!Array.isArray(p.cast)&&!p.crew)){throw new Error('Invalid credits');}
  const c=p.crew;const input:WorkCreditWire[]=acting?p.cast??[]:(c?.production??[]).concat(c?.art??[],c?.crew??[],c?.directing??[],c?.writing??[],c?.sound??[],c?.camera??[]);
  const rows=new Map<string,PersonCredit>();
  for(const r of input){
    const w=kind==='movie'?r.movie:r.show;if(!w||!w.ids||!positiveId(w.ids.trakt)||!text(w.title)){throw new Error('Invalid work identity');}
    const id=kind+':'+w.ids.trakt,release=date(kind==='movie'?w.released:w.first_aired),status=text(w.status).toLowerCase();
    const upcoming=['planned','in production','post production','upcoming','rumored','pilot'].includes(status);
    const roles=(acting?r.characters??(r.character?[r.character]:[]):r.jobs??(r.job?[r.job]:[])).filter((v:string)=>!!text(v));
    const old=rows.get(id);if(old){old.roles=Array.from(new Set<string>(old.roles.concat(roles)));continue;}
    rows.set(id,{media:{id:id,kind:kind,title:w.title,year:typeof w.year==='number'?w.year:0,watched:false},release:release,upcoming:upcoming,roles:Array.from(new Set<string>(roles))});
  }
  return Array.from(rows.values());
}
export function projectPersonCredits(rows:PersonCredit[],kind:string,onlyMembers:boolean,members:Set<string>):PersonCreditRow[]{
  const unique=new Map<string,PersonCredit>();for(const r of rows){if(!unique.has(r.media.id)){unique.set(r.media.id,r);}}
  const sorted=Array.from(unique.values()).filter((r:PersonCredit)=>(kind==='all'||r.media.kind===kind)&&(!onlyMembers||members.has(r.media.id))&&(!!r.release||r.upcoming))
    .sort((a:PersonCredit,b:PersonCredit)=>Number(!b.release)-Number(!a.release)||b.release.localeCompare(a.release));
  const result:PersonCreditRow[]=[];let group='';
  for(const r of sorted){const next=r.release?r.release.substring(0,4):'待上映';if(group!==next){group=next;result.push({key:'group:'+group,group:group,member:false});}
    result.push({key:r.media.id,group:group,credit:r,member:members.has(r.media.id)});}
  return result;
}
