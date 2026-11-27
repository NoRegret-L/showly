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
  replace(records:MediaRecord[]):boolean{
    const next=new Map<string,string>(),nextRecords=new Map<string,MediaRecord>(),ids:string[]=[],changed=new Set<string>();
    for(const row of records){
      const id=row.media.id,key=JSON.stringify(row);
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
      if(!this.projectionGlobal){for(const id of changed){this.projectionPending.add(id);}}
      if(!this.libraryGlobal){for(const id of changed){this.libraryPending.add(id);}}
    }
    this.ids=ids;this.keys=next;this.records=nextRecords;this.serial++;
    return true;
  }
}
