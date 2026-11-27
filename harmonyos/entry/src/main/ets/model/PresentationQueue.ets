import { PresentationTask } from './MediaPresentation';
import { presentationTaskKey } from './PresentationPolicy';
interface DoneTask { signature:string; until:number; }
export interface QueuedPresentation { key:string; signature:string; task:PresentationTask; generation:number; }
// One owner per lane. Visible priority is a separate map, never a full union.
export class PresentationQueue {
  private generation:number=0;
  private businessRef?: Map<string,PresentationTask>;
  private business:Map<string,QueuedPresentation>=new Map<string,QueuedPresentation>();
  private visible:Map<string,QueuedPresentation>=new Map<string,QueuedPresentation>();
  private pendingBusiness:Map<string,QueuedPresentation>=new Map<string,QueuedPresentation>();
  private pendingVisible:Map<string,QueuedPresentation>=new Map<string,QueuedPresentation>();
  private done:Map<string,DoneTask>=new Map<string,DoneTask>();
  private expiry:number=Number.MAX_SAFE_INTEGER;
  private active?:QueuedPresentation;
  private lane:string;
  private businessVisits:number=0;
  private visibleVisits:number=0;
  constructor(lane:string){this.lane=lane;}
  businessCount():number{return this.businessVisits;}
  visibleCount():number{return this.visibleVisits;}
  clear():void {
    this.generation++;this.businessRef=undefined;this.business.clear();this.visible.clear();
    this.pendingBusiness.clear();this.pendingVisible.clear();this.done.clear();this.active=undefined;this.expiry=Number.MAX_SAFE_INTEGER;
  }
  private entry(task:PresentationTask):QueuedPresentation {
    const key=presentationTaskKey(task,this.lane)+(this.lane==='artwork'?(task.artwork?':image':':metadata'):'');
    const signature=this.lane==='artwork'?JSON.stringify([key,task.posterUrls]):key;
    return {key:key,signature:signature,task:task,generation:this.generation};
  }
  private needed(row:QueuedPresentation,now:number):boolean {
    const prior=this.done.get(row.key);
    return (!prior||prior.signature!==row.signature||now>=prior.until) &&
      !(this.active?.key===row.key&&this.active.signature===row.signature);
  }
  update(visible:PresentationTask[],business:Map<string,PresentationTask>,eligible:(task:PresentationTask)=>boolean,now:number):void {
    if(now>=this.expiry){
      this.expiry=Number.MAX_SAFE_INTEGER;
      for(const key of this.done.keys()){
        const row=this.done.get(key);
        if(row&&now>=row.until){this.done.delete(key);}
        else if(row){this.expiry=Math.min(this.expiry,row.until);}
      }
      this.businessRef=undefined;
    }
    if(this.businessRef!==business){
      this.businessRef=business;this.business.clear();this.pendingBusiness.clear();
      for(const task of business.values()){
        this.businessVisits++;
        if(!eligible(task)){continue;}
        const row=this.entry(task);this.business.set(row.key,row);
        if(this.needed(row,now)){this.pendingBusiness.set(row.key,row);}
      }
    }
    this.visible.clear();this.pendingVisible.clear();
    for(const task of visible){
      this.visibleVisits++;
      if(!eligible(task)){continue;}
      const row=this.entry(task);this.visible.set(row.key,row);
      if(this.needed(row,now)){this.pendingVisible.set(row.key,row);}
    }
  }
  hasPending():boolean { return this.pendingVisible.size>0 || this.pendingBusiness.size>0; }
  next():QueuedPresentation|undefined {
    for(const row of this.pendingVisible.values()){this.pendingVisible.delete(row.key);this.pendingBusiness.delete(row.key);this.active=row;return row;}
    for(const row of this.pendingBusiness.values()){this.pendingBusiness.delete(row.key);this.active=row;return row;}
    return undefined;
  }
  relevant(row:QueuedPresentation):boolean {
    if(row.generation!==this.generation){return false;}
    return this.visible.get(row.key)?.signature===row.signature||this.business.get(row.key)?.signature===row.signature;
  }
  finish(row:QueuedPresentation,success:boolean,until:number):void {
    if(row.generation!==this.generation){return;}
    if(this.active===row){this.active=undefined;}
    if(success){
      this.done.set(row.key,{signature:row.signature,until:until});this.expiry=Math.min(this.expiry,until);
      if(this.pendingVisible.get(row.key)?.signature===row.signature){this.pendingVisible.delete(row.key);}
      if(this.pendingBusiness.get(row.key)?.signature===row.signature){this.pendingBusiness.delete(row.key);}
    } else {
      const v=this.visible.get(row.key),b=this.business.get(row.key);
      if(v){this.pendingVisible.set(v.key,v);} if(b){this.pendingBusiness.set(b.key,b);}
    }
  }
  invalidateMedia(id:string):void {
    // Explicit decoder recovery is scoped to this media; no scan of all done tasks.
    const key=id+':image';this.done.delete(key);
    const row=this.visible.get(key);if(row){this.pendingVisible.set(key,row);}
  }
}
export class PresentationQueues {
  private queues:Map<string,PresentationQueue>=new Map<string,PresentationQueue>();
  lane(name:string):PresentationQueue {
    let q=this.queues.get(name);if(!q){q=new PresentationQueue(name);this.queues.set(name,q);}return q;
  }
  clear():void{for(const q of this.queues.values()){q.clear();}}
}
// A one-shot frame gate. Reset invalidates pending callbacks on account/page change.
export class FramePublication {
  private epoch:number=0;
  private pending:boolean=false;
  request():number {if(this.pending){return -1;}this.pending=true;return ++this.epoch;}
  consume(token:number):boolean{if(!this.pending||token!==this.epoch){return false;}this.pending=false;return true;}
  clear():void{this.pending=false;this.epoch++;}
}
