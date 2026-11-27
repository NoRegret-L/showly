import { PersonalLibraryRow,LibraryOrder } from './PersonalLibrary';
export interface StableOrderChange<T>{id:string;item?:T;ordinal?:LibraryOrder;}
export interface StableOrderPatch{id:string;kind:string;index:number;oldIndex:number;row?:PersonalLibraryRow;}
export interface StableOrderResult{rows:PersonalLibraryRow[];patches:StableOrderPatch[];structural:boolean;}
function compareOrdinal(a:LibraryOrder,b:LibraryOrder):number{return a.segment-b.segment||a.position-b.position;}
export class StableDisplayOrder<T>{
  private scope:string='';private basis:string='';private sourceIds:string[]=[];
  private from:number=0;private until:number=0;
  private source:Map<string,T>=new Map<string,T>();private ordinal:Map<string,LibraryOrder>=new Map<string,LibraryOrder>();
  private ordered:T[]=[];private rows:PersonalLibraryRow[]=[];private positions:Map<string,number>=new Map<string,number>();
  private changes:Set<string>=new Set<string>();private rowOf:(item:T)=>PersonalLibraryRow;
  private comparisons:number=0;private patches:number=0;private activeCompare:(a:T,b:T)=>number=(a:T,b:T)=>0;
  constructor(rowOf:(item:T)=>PersonalLibraryRow){this.rowOf=rowOf;}
  clear():void{
    this.scope='';this.basis='';this.sourceIds=[];this.source.clear();this.ordinal.clear();
    this.ordered=[];this.rows=[];this.positions.clear();this.changes.clear();
  }
  comparisonCount():number{return this.comparisons;}
  patchCount():number{return this.patches;}
  validUntil():number{return this.until;}
  rowsView():PersonalLibraryRow[]{return this.rows;}
  positionOf(id:string):number{return this.positions.get(id)??-1;}
  sourceItem(id:string):T|undefined{return this.source.get(id);}
  hasDirty():boolean{return this.changes.size>0;}
  private compareItems(a:T,b:T,compare:(a:T,b:T)=>number):number{
    const primary=compare(a,b);if(primary){return primary;}
    const ao=this.ordinal.get(this.rowOf(a).media.id),bo=this.ordinal.get(this.rowOf(b).media.id);
    return ao&&bo?compareOrdinal(ao,bo):0;
  }
  private reindex(from:number):void{for(let i=from;i<this.ordered.length;i++){this.positions.set(this.rowOf(this.ordered[i]).media.id,i);}}
  private removeOrdered(index:number):void{
    const id=this.rowOf(this.ordered[index]).media.id;
    this.ordered.splice(index,1);this.rows.splice(index,1);this.positions.delete(id);this.reindex(index);
  }
  private insertOrdered(item:T):number{
    let lo=0,hi=this.ordered.length;
    while(lo<hi){const mid=Math.floor((lo+hi)/2);this.comparisons++;
      if(this.compareItems(this.ordered[mid],item,this.activeCompare)<=0){lo=mid+1;}else{hi=mid;}}
    this.ordered.splice(lo,0,item);this.rows.splice(lo,0,this.rowOf(item));this.reindex(lo);return lo;
  }
  private insertSourceId(id:string,ordinal:LibraryOrder):void{
    let lo=0,hi=this.sourceIds.length;
    while(lo<hi){const mid=Math.floor((lo+hi)/2),other=this.ordinal.get(this.sourceIds[mid]);
      if(other&&compareOrdinal(other,ordinal)<=0){lo=mid+1;}else{hi=mid;}}
    this.sourceIds.splice(lo,0,id);
  }
  private removeSourceId(id:string):void{const pos=this.sourceIds.indexOf(id);if(pos>=0){this.sourceIds.splice(pos,1);}}
  seed(scope:string,from:number,until:number,source:T[],sorted:PersonalLibraryRow[],basis:string=scope,
    ordinalOf?:(id:string)=>LibraryOrder|undefined):void{
    this.clear();
    for(let i=0;i<source.length;i++){
      const id=this.rowOf(source[i]).media.id;if(this.source.has(id)){this.clear();return;}
      const ordinal=ordinalOf?.(id)??{segment:0,position:i};
      this.source.set(id,source[i]);this.ordinal.set(id,ordinal);this.sourceIds.push(id);
    }
    const seen=new Set<string>();
    for(const row of sorted){const item=this.source.get(row.media.id);if(item===undefined||seen.has(row.media.id)){this.clear();return;}
      seen.add(row.media.id);this.ordered.push(item);this.rows.push(row);}
    for(let i=0;i<this.ordered.length;i++){this.positions.set(this.rowOf(this.ordered[i]).media.id,i);}
    this.scope=scope;this.basis=basis;this.from=from;this.until=until;
  }
  reconcile(scope:string,basis:string,now:number,until:number,source:T[],equal:(a:T,b:T)=>boolean,
    eligible:(item:T)=>boolean,compare:(a:T,b:T)=>number,ordinalOf?:(id:string)=>LibraryOrder|undefined):PersonalLibraryRow[]|undefined{
    if(!this.scope||this.basis!==basis||now<this.from||now>=this.until){return undefined;}
    const next=new Map<string,T>(),ids:string[]=[],ord=new Map<string,LibraryOrder>(),dirty=new Set<string>();
    for(const item of source){
      const id=this.rowOf(item).media.id;if(next.has(id)){return undefined;}
      const old=this.source.get(id);
      if(old!==undefined&&equal(old,item)){next.set(id,old);}else{next.set(id,item);dirty.add(id);}
      ord.set(id,ordinalOf?.(id)??{segment:0,position:ids.length});ids.push(id);
    }
    const oldCommon=this.sourceIds.filter((id:string)=>next.has(id)),newCommon=ids.filter((id:string)=>this.source.has(id));
    if(oldCommon.length!==newCommon.length){return undefined;}
    for(let i=0;i<oldCommon.length;i++){if(oldCommon[i]!==newCommon[i]){return undefined;}}
    for(const id of this.sourceIds){if(!next.has(id)){dirty.add(id);}}
    const retained:T[]=[],retainedRows:PersonalLibraryRow[]=[];
    for(let i=0;i<this.ordered.length;i++){
      const id=this.rowOf(this.ordered[i]).media.id;
      if(!dirty.has(id)){retained.push(this.ordered[i]);retainedRows.push(this.rows[i]);}
    }
    this.ordered=retained;this.rows=retainedRows;this.positions.clear();
    for(let i=0;i<this.ordered.length;i++){this.positions.set(this.rowOf(this.ordered[i]).media.id,i);}
    this.source=next;this.sourceIds=ids;this.ordinal=ord;this.activeCompare=compare;
    for(const id of dirty){this.patches++;const item=next.get(id);if(item!==undefined&&eligible(item)){this.insertOrdered(item);}}
    this.changes.clear();this.scope=scope;this.basis=basis;this.from=now;this.until=until;return this.rows;
  }
  dirty(id:string):void{if(this.source.has(id)){this.changes.add(id);}}
  update(scope:string,now:number,patch:(item:T)=>T,eligible:(item:T)=>boolean,compare:(a:T,b:T)=>number):PersonalLibraryRow[]|undefined{
    if(!this.scope||this.scope!==scope||now<this.from||now>=this.until){return undefined;}
    this.activeCompare=compare;
    for(const id of this.changes){
      const old=this.source.get(id);if(old===undefined){continue;}
      const next=patch(old);if(this.rowOf(next).media.id!==id){this.clear();return undefined;}
      this.source.set(id,next);this.patches++;
      const pos=this.positions.get(id);if(pos!==undefined){this.removeOrdered(pos);}
      if(eligible(next)){this.insertOrdered(next);}
    }
    this.changes.clear();return this.rows;
  }
  applyChanges(scopeBefore:string,scopeAfter:string,basis:string,now:number,until:number,changes:StableOrderChange<T>[],
    eligible:(item:T)=>boolean,compare:(a:T,b:T)=>number):StableOrderResult|undefined{
    if(!this.scope||this.scope!==scopeBefore||this.basis!==basis||now<this.from||now>=this.until){return undefined;}
    for(const change of changes){
      if(change.item!==undefined&&(this.rowOf(change.item).media.id!==change.id||(!this.source.has(change.id)&&!change.ordinal))){return undefined;}
    }
    this.activeCompare=compare;const patches:StableOrderPatch[]=[];let structural=false;
    for(const change of changes){
      const oldSource=this.source.get(change.id),oldIndex=this.positions.get(change.id);
      if(change.item===undefined){
        if(oldSource===undefined){continue;}
        this.source.delete(change.id);this.ordinal.delete(change.id);this.removeSourceId(change.id);
        if(oldIndex!==undefined){this.removeOrdered(oldIndex);patches.push({id:change.id,kind:'remove',index:-1,oldIndex:oldIndex});structural=true;}
        continue;
      }
      const item=change.item,oldOrdinal=this.ordinal.get(change.id);
      if(oldSource===undefined){
        const ordinal=change.ordinal as LibraryOrder;this.source.set(change.id,item);this.ordinal.set(change.id,ordinal);this.insertSourceId(change.id,ordinal);
      }else{
        if(change.ordinal){this.ordinal.set(change.id,change.ordinal);}
        if(change.ordinal&&oldOrdinal&&compareOrdinal(oldOrdinal,change.ordinal)!==0){
          this.removeSourceId(change.id);this.insertSourceId(change.id,change.ordinal);
        }
        this.source.set(change.id,item);
      }
      if(!eligible(item)){
        if(oldIndex!==undefined){this.removeOrdered(oldIndex);patches.push({id:change.id,kind:'remove',index:-1,oldIndex:oldIndex});structural=true;}
        continue;
      }
      if(oldIndex!==undefined){
        const previous=oldIndex>0?this.ordered[oldIndex-1]:undefined,following=oldIndex+1<this.ordered.length?this.ordered[oldIndex+1]:undefined;
        if((!previous||this.compareItems(previous,item,compare)<=0)&&(!following||this.compareItems(item,following,compare)<=0)){
          this.ordered[oldIndex]=item;this.rows[oldIndex]=this.rowOf(item);this.patches++;
          patches.push({id:change.id,kind:'update',index:oldIndex,oldIndex:oldIndex,row:this.rows[oldIndex]});continue;
        }
        this.removeOrdered(oldIndex);
      }
      const index=this.insertOrdered(item);patches.push({id:change.id,kind:oldIndex===undefined?'insert':'move',
        index:index,oldIndex:oldIndex??-1,row:this.rows[index]});structural=true;
    }
    this.scope=scopeAfter;this.from=now;this.until=until;return {rows:this.rows,patches:patches,structural:structural};
  }
}
