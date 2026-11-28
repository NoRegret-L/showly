import { PageDisplayRows } from './PageDisplayRows';
import { ReadCancel } from './ReadFlight';
import { LatestDisplayJobs } from './DisplayJobs';
import { RevisionMemo } from './ReadModelCache';

export interface PageSummary { key:string; total:number; page:number; pages:number; }
export interface PageTicket { revision:number; consumer:ReadCancel; }
export interface PageWorkSnapshot { revision:number; dependencyVersion:number; starts:number; summaries:number; }
export interface PageReadSnapshot { revision:number; key:string; loading:boolean; error:string; starts:number; joins:number; publications:number; }
// One consumer lane per kind of page work; the repository remains the
// transport owner. Returned snapshots contain scalar copies only.
export class PageReadLane {
  private signal:ReadCancel=new ReadCancel();
  private serial:number=0;
  private key:string='';
  private loading:boolean=false;
  private error:string='';
  private starts:number=0;
  private joins:number=0;
  private publications:number=0;
  version():number{return this.serial;}
  consumer():ReadCancel{return this.signal;}
  current(consumer:ReadCancel):boolean{return consumer===this.signal&&!consumer.cancelled();}
  snapshot():PageReadSnapshot{return {revision:this.serial,key:this.key,loading:this.loading,error:this.error,
    starts:this.starts,joins:this.joins,publications:this.publications};}
  cancel():number{
    this.signal.cancel();this.signal=new ReadCancel();this.serial++;
    if(this.loading||this.key||this.error){this.publications++;}
    this.loading=false;this.key='';this.error='';return this.serial;
  }
  begin(key:string,force:boolean=false):ReadCancel|undefined{
    if(!force&&this.loading&&this.key===key&&!this.signal.cancelled()){this.joins++;return undefined;}
    this.cancel();this.key=key;this.loading=true;this.starts++;this.publications++;return this.signal;
  }
  start(consumer:ReadCancel,key:string):void{
    if(!this.current(consumer)){return;}
    if(!this.loading||this.key!==key||this.error){this.key=key;this.loading=true;this.error='';this.starts++;this.publications++;}
  }
  finish(consumer:ReadCancel,error:string=''):boolean{
    if(!this.current(consumer)){return false;}
    if(this.loading||this.error!==error){this.loading=false;this.error=error;this.publications++;}
    return true;
  }
}
export function samePageSummary(a:PageSummary,b:PageSummary):boolean{
  return a.key===b.key&&a.total===b.total&&a.page===b.page&&a.pages===b.pages;
}
// Derived display state only. The coordinator still validates account, route,
// authoritative commit and synchronization fences before accepting results.
export class PageWork {
  readonly jobs:LatestDisplayJobs=new LatestDisplayJobs();
  readonly remote:PageReadLane=new PageReadLane();
  readonly local:PageReadLane=new PageReadLane();
  readonly hydrate:PageReadLane=new PageReadLane();
  private presentationKey:string='';
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
  deactivate():void{this.invalidate();this.jobs.clear();this.remote.cancel();this.local.cancel();this.hydrate.cancel();}
  changePresentation(key:string):void{
    if(this.presentationKey===key){return;}
    this.presentationKey=key;this.invalidate();this.jobs.clear();
  }
  reset():void{this.commitKey='';this.presentationKey='';this.summary=undefined;this.deactivate();}
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
  private account:string='';private route:string='';private active:string='';private initialized:boolean=false;
  // Account/hide boundaries revoke every consumer. Ordinary navigation only
  // revokes the outgoing page, including a different route in the same page.
  transition(page:string,route:string,account:string):void{
    if(!this.initialized||this.account!==account||!route){
      if(!this.initialized||this.account!==account||this.route!==route){this.reset();}
    }else if(this.route!==route||this.active!==page){this.owners.get(this.active)?.deactivate();}
    this.initialized=true;this.account=account;this.route=route;this.active=page;
  }
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
