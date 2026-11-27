import { MediaRecord } from './MediaState';
// Each consumer acknowledges its own versioned change set. No consumer clears another's work.
export class MediaInputVersion {
  private serial:number=0;
  private keys:Map<string,string>=new Map<string,string>();
  private ids:string[]=[];
  private records:Map<string,MediaRecord>=new Map<string,MediaRecord>();
  private changes:string[]=[];
  private projectionPending:Set<string>=new Set<string>();
  private projectionGlobal:boolean=true;
  private libraryPending:Set<string>=new Set<string>();
  private libraryGlobal:boolean=true;
  private incrementalOrder:boolean=false;
  private snapshot?:MediaRecord[];
  private serialized:number=0;
  serializedRecords():number{return this.serialized;}
  matchesSnapshot(records:MediaRecord[]):boolean{return this.snapshot===records;}
  projectionChangedIds():string[]{return Array.from(this.projectionPending);}
  projectionOrderChanged():boolean{return this.projectionGlobal;}
  acknowledgeProjection(version:string):void{if(version===this.version()){this.projectionPending.clear();this.projectionGlobal=false;}}
  libraryChangedIds():string[]{return Array.from(this.libraryPending);}
  libraryOrderChanged():boolean{return this.libraryGlobal;}
  acknowledgeLibrary(version:string):void{if(version===this.version()){this.libraryPending.clear();this.libraryGlobal=false;}}
  canApplyIncremental():boolean{return this.incrementalOrder;}
  recordsById():Map<string,MediaRecord>{return this.records;}
  indexOf(id:string):number{return this.ids.indexOf(id);}
  version():string{return this.serial.toString();}
  changedIds():string[]{return [...this.changes];}
  // Only called after MediaStore.save/saveTitleEdit has verified the entire
  // submitted payload and the caller still owns the same base version.
  // Reference checks prove that all non-target records were carried unchanged.
  replaceVerifiedEdit(expected:string,submitted:MediaRecord[],verified:MediaRecord[],ids:string[]):boolean{
    if(expected!==this.version()||!this.snapshot||!ids.length||submitted.length!==verified.length||submitted.length<this.ids.length){return this.replace(verified);}
    const allowed=new Set<string>(ids),seen=new Set<string>(),changed=new Set<string>();
    const updates=new Map<string,string>();
    this.serialized=0;
    for(let i=0;i<submitted.length;i++){
      const input=submitted[i],row=verified[i],id=input.media.id;
      if(row.media.id!==id||seen.has(id)|| (i<this.ids.length&&this.ids[i]!==id)||
        (i>=this.ids.length&&!allowed.has(id))||(!allowed.has(id)&&this.records.get(id)!==input)){return this.replace(verified);}
      seen.add(id);
      if(allowed.has(id)){
        const key=JSON.stringify(row);this.serialized++;
        if(this.keys.get(id)!==key){changed.add(id);updates.set(id,key);}
      }
    }
    this.changes=Array.from(changed);
    if(!changed.size){return false;}
    for(const id of changed){
      if(!this.keys.has(id)){
        this.ids.push(id);
        if(this.projectionPending.has(id)){this.projectionGlobal=true;this.projectionPending.clear();}
        if(this.libraryPending.has(id)){this.libraryGlobal=true;this.libraryPending.clear();}
      }
      const key=updates.get(id);if(key!==undefined){this.keys.set(id,key);}
      if(!this.projectionGlobal){this.projectionPending.add(id);}
      if(!this.libraryGlobal){this.libraryPending.add(id);}
    }
    for(const row of verified){this.records.set(row.media.id,row);}
    this.snapshot=verified;this.incrementalOrder=true;this.serial++;return true;
  }
  replace(records:MediaRecord[]):boolean{
    this.serialized=0;
    const next=new Map<string,string>(),nextRecords=new Map<string,MediaRecord>(),ids:string[]=[],changed=new Set<string>();
    for(const row of records){
      const id=row.media.id,key=JSON.stringify(row);this.serialized++;
      ids.push(id);next.set(id,key);nextRecords.set(id,row);
      if(this.keys.get(id)!==key){changed.add(id);}
    }
    for(const id of this.keys.keys()){if(!next.has(id)){changed.add(id);}}
    let order=ids.length!==this.ids.length;
    if(!order){for(let i=0;i<ids.length;i++){if(ids[i]!==this.ids[i]){order=true;break;}}}
    this.changes=Array.from(changed);
    if(!order&&!changed.size){return false;}
    const oldCommon=this.ids.filter((id:string)=>next.has(id));
    const newCommon=ids.filter((id:string)=>this.keys.has(id));
    let sameRelative=oldCommon.length===newCommon.length;
    if(sameRelative){for(let i=0;i<oldCommon.length;i++){if(oldCommon[i]!==newCommon[i]){sameRelative=false;break;}}}
    let lastRetained=-1;
    for(let i=0;i<ids.length;i++){if(this.keys.has(ids[i])){lastRetained=i;}}
    let appendOnly=sameRelative&&next.size===ids.length;
    if(appendOnly){for(let i=0;i<ids.length;i++){if(!this.keys.has(ids[i])&&i<lastRetained){appendOnly=false;break;}}}
    this.incrementalOrder=appendOnly;
    if(!appendOnly){
      this.projectionGlobal=true;this.projectionPending.clear();
      this.libraryGlobal=true;this.libraryPending.clear();
    }else{
      // A deletion followed by re-addition changes source precedence even
      // when the final member ID is identical. Unconsumed consumers rebuild.
      for(const id of changed){
        if(!this.keys.has(id)&&next.has(id)){
          if(this.projectionPending.has(id)){this.projectionGlobal=true;this.projectionPending.clear();}
          if(this.libraryPending.has(id)){this.libraryGlobal=true;this.libraryPending.clear();}
        }
        if(!this.projectionGlobal){this.projectionPending.add(id);}
        if(!this.libraryGlobal){this.libraryPending.add(id);}
      }
    }
    this.ids=ids;this.keys=next;this.records=nextRecords;this.snapshot=records;this.serial++;
    return true;
  }
}
