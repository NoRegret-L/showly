import { PageDisplayRows } from './PageDisplayRows';
import { ReadCancel } from './ReadFlight';
import { LatestDisplayJobs } from './DisplayJobs';
import { RevisionMemo } from './ReadModelCache';

export interface PageSummary { key:string; total:number; page:number; pages:number; }
export interface PageTicket { revision:number; consumer:ReadCancel; }
export interface PageWorkSnapshot { revision:number; dependencyVersion:number; starts:number; summaries:number; }
export function samePageSummary(a:PageSummary,b:PageSummary):boolean{
  return a.key===b.key&&a.total===b.total&&a.page===b.page&&a.pages===b.pages;
}
// Derived display state only. The coordinator still validates account, route,
// authoritative commit and synchronization fences before accepting results.
export class PageWork {
  readonly jobs:LatestDisplayJobs=new LatestDisplayJobs();
  private revision:number=0;
  private dependencies:number=0;
  private starts:number=0;
  private summaries:number=0;
  private consumer:ReadCancel=new ReadCancel();
  private commitKey:string='';
  private summary?:PageSummary;
  invalidate():void{this.consumer.cancel();this.consumer=new ReadCancel();this.revision++;}
  begin():PageTicket{this.starts++;return {revision:this.revision,consumer:this.consumer};}
  current(ticket:PageTicket):boolean{return ticket.revision===this.revision&&ticket.consumer===this.consumer&&!ticket.consumer.cancelled();}
  observe(key:string):void{
    if(this.commitKey===key){return;}
    this.commitKey=key;this.dependencies++;this.invalidate();this.jobs.clear();
  }
  reset():void{this.commitKey='';this.summary=undefined;this.invalidate();this.jobs.clear();}
  snapshot():PageWorkSnapshot{return {revision:this.revision,dependencyVersion:this.dependencies,starts:this.starts,summaries:this.summaries};}
  readSummary():PageSummary|undefined{
    const value=this.summary;
    return value?{key:value.key,total:value.total,page:value.page,pages:value.pages}:undefined;
  }
  publishSummary(next:PageSummary,visible:PageSummary):boolean{
    this.summary={key:next.key,total:next.total,page:next.page,pages:next.pages};
    if(samePageSummary(next,visible)){return false;}
    this.summaries++;return true;
  }
}
export class PageStateOwner<T,R> extends PageDisplayRows<T>{
  readonly work:PageWork=new PageWork();
  readonly memo:RevisionMemo<R>=new RevisionMemo<R>();
  readonly allMemo:RevisionMemo<R>=new RevisionMemo<R>();
  constructor(dependenciesOf?:(row:T)=>string[]){super(dependenciesOf);}
}
// Static page dependency routing. A private-library edit can affect search and
// discovery labels for either media kind. Unknown changes invalidate all.
export function pageAffected(page:string,ids:string[],full:boolean):boolean{
  if(full){return true;}
  if(!ids.length){return false;}
  if(page==='show'||page==='calendar'){return ids.some((id:string)=>!id.startsWith('movie:'));}
  if(page==='movie'||page==='movieCalendar'){return ids.some((id:string)=>!id.startsWith('show:'));}
  return true;
}
export class PageWorkSet{
  private owners:Map<string,PageWork>=new Map<string,PageWork>();
  register(page:string,work:PageWork):void{this.owners.set(page,work);}
  get(page:string):PageWork|undefined{return this.owners.get(page);}
  reset():void{for(const work of this.owners.values()){work.reset();}}
  observe(key:string,ids:string[],full:boolean):void{
    for(const page of this.owners.keys()){if(pageAffected(page,ids,full)){this.owners.get(page)?.observe(key);}}
  }
}
export class PageSortJobs{
  private pages:PageWorkSet;
  constructor(pages:PageWorkSet){this.pages=pages;}
  private owner(slot:string):LatestDisplayJobs{
    const page=slot.startsWith('show-')?'show':slot.startsWith('movie-')?'movie':slot==='collection'?'library':slot;
    const work=this.pages.get(page);
    if(!work){throw new Error('Unknown display job owner: '+slot);}
    return work.jobs;
  }
  begin(slot:string,key:string):number{return this.owner(slot).begin(slot,key);}
  current(slot:string,token:number):boolean{return this.owner(slot).current(slot,token);}
  consumer(slot:string,token:number):ReadCancel{return this.owner(slot).consumer(slot,token);}
  pending(slot:string):boolean{return this.owner(slot).pending(slot);}
  matches(slot:string,key:string):boolean{return this.owner(slot).matches(slot,key);}
  finish(slot:string,token:number):boolean{return this.owner(slot).finish(slot,token);}
  clear():void{for(const page of ['show','movie','calendar','library','search','discover','movieCalendar']){this.pages.get(page)?.jobs.clear();}}
}
