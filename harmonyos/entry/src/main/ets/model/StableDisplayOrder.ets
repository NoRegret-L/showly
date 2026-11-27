import { PersonalLibraryRow } from './PersonalLibrary';
// A derived order, never authority. Preserve the stable full-sort source ordinal
// on equal keys. Scope excludes only the dependency explicitly patched by dirty().
export class StableDisplayOrder<T> {
  private scope:string='';
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
  clear():void{this.scope='';this.source.clear();this.ordinal.clear();this.ordered=[];this.changes.clear();}
  comparisonCount():number{return this.comparisons;}
  patchCount():number{return this.patches;}
  validUntil():number{return this.until;}
  seed(scope:string,from:number,until:number,source:T[],sorted:PersonalLibraryRow[]):void{
    this.clear();
    for(let i=0;i<source.length;i++){
      const id=this.rowOf(source[i]).media.id;
      if(this.source.has(id)){this.clear();return;}
      this.source.set(id,source[i]);this.ordinal.set(id,i);
    }
    const seen=new Set<string>();
    for(const row of sorted){
      const item=this.source.get(row.media.id);
      if(item===undefined||seen.has(row.media.id)){this.clear();return;}
      seen.add(row.media.id);this.ordered.push(item);
    }
    this.scope=scope;this.from=from;this.until=until;
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
