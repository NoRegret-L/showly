import { MediaRecord } from './MediaState';
// Exact equality at publication, not repeated serialization at read time.
// Ordering remains significant (as with the previous array comparison).
export class MediaInputVersion {
  private serial: number=0;
  private keys: Map<string,string>=new Map<string,string>();
  private ids: string[]=[];
  private changes: string[]=[];
  private projectionPending:Set<string>=new Set<string>();
  private projectionGlobal:boolean=true;
  projectionChangedIds():string[]{return Array.from(this.projectionPending);}
  projectionOrderChanged():boolean{return this.projectionGlobal;}
  acknowledgeProjection(version:string):void{if(version===this.version()){this.projectionPending.clear();this.projectionGlobal=false;}}
  version(): string { return this.serial.toString(); }
  changedIds(): string[] { return [...this.changes]; }
  replace(records: MediaRecord[]): boolean {
    const next=new Map<string,string>();
    const ids: string[]=[];
    const changed=new Set<string>();
    for (const row of records) {
      const id=row.media.id;
      const key=JSON.stringify(row);
      ids.push(id); next.set(id,key);
      if (this.keys.get(id)!==key) { changed.add(id); }
    }
    for (const id of this.keys.keys()) { if (!next.has(id)) { changed.add(id); } }
    let order=ids.length!==this.ids.length;
    if (!order) { for (let i=0;i<ids.length;i++) { if (ids[i]!==this.ids[i]) { order=true; break; } } }
    this.changes=Array.from(changed);
    if (!order && !changed.size) { return false; }
    const oldCommon=this.ids.filter((id:string)=>next.has(id));
    const newCommon=ids.filter((id:string)=>this.keys.has(id));
    if(oldCommon.length!==newCommon.length||oldCommon.some((id:string,i:number)=>id!==newCommon[i])||next.size!==ids.length){this.projectionGlobal=true;this.projectionPending.clear();}
    if(!this.projectionGlobal){for(const id of changed){this.projectionPending.add(id);}}
    this.ids=ids; this.keys=next; this.serial++;
    return true;
  }
}
