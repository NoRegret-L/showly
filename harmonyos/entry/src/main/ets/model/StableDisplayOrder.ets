import { PersonalLibraryRow } from './PersonalLibrary';
// A derived order, never authority. Preserve the stable full-sort source ordinal
// on equal keys. Scope excludes only the dependency explicitly patched by dirty().
export class StableDisplayOrder<T> {
  private scope:string='';
  private basis:string='';
  private sourceIds:string[]=[];
  private from:number=0;
  private until:number=0;
  private source:Map<string,T>=new Map<string,T>();
  private ordinal:Map<string,number>=new Map<string,number>();
  private ordered:T[]=[];
  private changes:Set<string>=new Set<string>();
  private rowOf:(item:T)=>PersonalLibraryRow;
  private comparisons:number=0;
  private patches:number=0;
  constructor(rowOf:(item:T)=>PersonalLibraryRow){this.rowOf=rowOf;}
  clear():void{this.scope='';this.basis='';this.sourceIds=[];this.source.clear();this.ordinal.clear();this.ordered=[];this.changes.clear();}
  comparisonCount():number{return this.comparisons;}
  patchCount():number{return this.patches;}
  validUntil():number{return this.until;}
  seed(scope:string,from:number,until:number,source:T[],sorted:PersonalLibraryRow[],basis:string=scope):void{
    this.clear();
    for(let i=0;i<source.length;i++){
      const id=this.rowOf(source[i]).media.id;
      if(this.source.has(id)){this.clear();return;}
      this.source.set(id,source[i]);this.ordinal.set(id,i);this.sourceIds.push(id);
    }
    const seen=new Set<string>();
    for(const row of sorted){
      const item=this.source.get(row.media.id);
      if(item===undefined||seen.has(row.media.id)){this.clear();return;}
      seen.add(row.media.id);this.ordered.push(item);
    }
    this.scope=scope;this.basis=basis;this.from=from;this.until=until;
  }
  // Snapshot reconciliation: exact candidate equality and unchanged relative
  // order of surviving IDs are the proof that existing sorted rows remain valid.
  reconcile(scope:string,basis:string,now:number,until:number,source:T[],
    equal:(a:T,b:T)=>boolean,eligible:(item:T)=>boolean,compare:(a:T,b:T)=>number):PersonalLibraryRow[]|undefined{
    if(!this.scope||this.basis!==basis||now<this.from||now>=this.until){return undefined;}
    const next=new Map<string,T>(),ids:string[]=[],ord=new Map<string,number>(),dirty=new Set<string>();
    for(const item of source){
      const id=this.rowOf(item).media.id;
      if(next.has(id)){return undefined;}
      const old=this.source.get(id);
      if(old===undefined||!equal(old,item)){dirty.add(id);next.set(id,item);}
      else{next.set(id,old);}
      ord.set(id,ids.length);ids.push(id);
    }
    const oldCommon=this.sourceIds.filter((id:string)=>next.has(id));
    const newCommon=ids.filter((id:string)=>this.source.has(id));
    for(let i=0;i<oldCommon.length;i++){if(oldCommon[i]!==newCommon[i]){return undefined;}}
    for(const id of this.sourceIds){if(!next.has(id)){dirty.add(id);}}
    this.ordered=this.ordered.filter((x:T)=>!dirty.has(this.rowOf(x).media.id));
    this.source=next;this.sourceIds=ids;this.ordinal=ord;
    for(const id of dirty){
      this.patches++;
      const item=next.get(id);if(item===undefined||!eligible(item)){continue;}
      this.insert(item,id,compare);
    }
    this.changes.clear();this.scope=scope;this.from=now;this.until=until;
    return this.ordered.map((x:T)=>this.rowOf(x));
  }
  private insert(item:T,id:string,compare:(a:T,b:T)=>number):void{
    let lo=0,hi=this.ordered.length;
    while(lo<hi){
      const mid=Math.floor((lo+hi)/2),other=this.ordered[mid];this.comparisons++;
      const order=compare(other,item)||(this.ordinal.get(this.rowOf(other).media.id)??0)-(this.ordinal.get(id)??0);
      if(order<=0){lo=mid+1;}else{hi=mid;}
    }
    this.ordered.splice(lo,0,item);
  }
  dirty(id:string):void{if(this.source.has(id)){this.changes.add(id);}}
  update(scope:string,now:number,patch:(item:T)=>T,eligible:(item:T)=>boolean,compare:(a:T,b:T)=>number):PersonalLibraryRow[]|undefined{
    if(!this.scope||this.scope!==scope||now<this.from||now>=this.until){return undefined;}
    for(const id of this.changes){
      const old=this.source.get(id);if(old===undefined){continue;}
      const next=patch(old);this.patches++;
      if(this.rowOf(next).media.id!==id){this.clear();return undefined;}
      this.source.set(id,next);
      const pos=this.ordered.findIndex((x:T)=>this.rowOf(x).media.id===id);
      if(pos>=0){this.ordered.splice(pos,1);}
      if(!eligible(next)){continue;}
      let lo=0,hi=this.ordered.length;
      while(lo<hi){
        const mid=Math.floor((lo+hi)/2),other=this.ordered[mid];
        this.comparisons++;
        const order=compare(other,next)||(this.ordinal.get(this.rowOf(other).media.id)??0)-(this.ordinal.get(id)??0);
        if(order<=0){lo=mid+1;}else{hi=mid;}
      }
      this.ordered.splice(lo,0,next);
    }
    this.changes.clear();
    return this.ordered.map((x:T)=>this.rowOf(x));
  }
}
