import { ProgressRow,ProgressPreferences,compareProgressRows,progressSortEligible } from './ProgressRules';
// Reuse the original comparator including group priority, title tie breaker,
// rating and chronological semantics. A changed row is removed/reinserted.
export class ProgressTitleOrder {
  private source?:ProgressRow[];
  private scope:string='';
  private from:number=0;
  private until:number=0;
  private byId:Map<string,ProgressRow>=new Map<string,ProgressRow>();
  private rows:ProgressRow[]=[];
  private changes:Set<string>=new Set<string>();
  private comparisons:number=0;
  comparisonCount():number{return this.comparisons;}
  clear():void{this.source=undefined;this.scope='';this.byId.clear();this.rows=[];this.changes.clear();}
  seed(source:ProgressRow[],scope:string,from:number,until:number,rows:ProgressRow[]):void{
    this.clear();this.source=source;this.scope=scope;this.from=from;this.until=until;
    this.rows=[...rows];for(const row of source){this.byId.set(row.media.id,row);}
  }
  dirty(ids:string[]):void{if(this.source){for(const id of ids){if(this.byId.has(id)){this.changes.add(id);}}}}
  update(source:ProgressRow[],scope:string,now:number,prefs:ProgressPreferences,filter:string,query:string,localize:(row:ProgressRow)=>ProgressRow):ProgressRow[]|undefined{
    if(this.source!==source||scope!==this.scope||now<this.from||now>=this.until){return undefined;}
    const rows=[...this.rows];
    for(const id of this.changes){
      const base=this.byId.get(id);if(!base){continue;}
      const old=rows.findIndex((row:ProgressRow)=>row.media.id===id);if(old>=0){rows.splice(old,1);}
      const row=localize(base);
      if(!progressSortEligible(row,filter,query)){continue;}
      let lo=0,hi=rows.length;
      while(lo<hi){const mid=Math.floor((lo+hi)/2);this.comparisons++;
        if(compareProgressRows(rows[mid],row,prefs)<=0){lo=mid+1;}else{hi=mid;}}
      rows.splice(lo,0,row);
    }
    this.changes.clear();this.rows=rows;return [...rows];
  }
}
