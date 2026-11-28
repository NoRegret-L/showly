import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { TraktSession,traktAuth } from './TraktAuth';
import { readSyncAccount } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
import { readArchiveObservation } from './TraktCustomLists';
import { ReadCancel } from '../model/ReadFlight';
import { CollectionState,HiddenEntry,mergeHiddenArchive } from '../model/CollectionRules';
import { ARCHIVE_SECTIONS,ArchiveItem,ArchiveLedger,ArchiveMutation,ArchiveObservation,archiveIndex,archiveImportRows,archivePlan } from '../model/ArchiveSyncRules';
interface ArchiveWire {ids:ArchiveIds;hidden_at?:string;}
interface ArchiveIds {trakt:number;}
interface ArchiveBody {shows:ArchiveWire[];movies:ArchiveWire[];}
export interface ArchiveResult {confirmed:number;blocked:number;}
export class ArchiveRepository {
  private db:relationalStore.RdbStore;
  private tail:Promise<void>=Promise.resolve();
  constructor(db:relationalStore.RdbStore){this.db=db;}
  private serial<T>(body:()=>Promise<T>):Promise<T>{const task=this.tail.catch(()=>{}).then(body);this.tail=task.then(()=>{},()=>{});return task;}
  private guard(scope:string,current:()=>boolean):void{if(!scope.startsWith('account:')||scope.length<=8||scope.trim()!==scope||!current()){throw new Error('Archive scope changed');}}
  private async rows(scope:string):Promise<Map<string,ArchiveLedger>>{
    const data=await this.db.querySql('SELECT payload FROM archive_sync WHERE scope=?',[scope]),result=new Map<string,ArchiveLedger>();
    try{while(data.goToNextRow()){const row=JSON.parse(data.getString(0)) as ArchiveLedger;if(!row||!Array.isArray(row.base)||typeof row.remove!=='boolean'||! /^(show|movie):[1-9][0-9]*$/.test(row.id)){throw new Error('Invalid archive ledger');}archiveIndex(row.base);result.set(row.id,row);}}finally{data.close();}return result;
  }
  private async save(scope:string,row:ArchiveLedger):Promise<void>{
    await this.db.executeSql('INSERT OR REPLACE INTO archive_sync(scope,media_id,payload) VALUES(?,?,?)',[scope,row.id,JSON.stringify(row)]);
  }
  // Stage before changing local preference. A crash before the local change blocks remote removal.
  stageLocal(scope:string,id:string,hidden:boolean,current:()=>boolean):Promise<void>{
    return this.serial(async():Promise<void>=>{
      this.guard(scope,current);const all=await this.rows(scope),old=all.get(id);
      if(old?.pending){throw new Error('Unconfirmed archive receipt');}
      this.guard(scope,current);
      await this.save(scope,{id:id,base:old?.base??[],remove:!hidden});
    });
  }
  importObserved(scope:string,state:CollectionState,observation:ArchiveObservation,current:()=>boolean):Promise<CollectionState>{
    return this.serial(async():Promise<CollectionState>=>{
      this.guard(scope,current);const rows=await this.rows(scope),index=archiveIndex(observation.items);
      const next=mergeHiddenArchive(state,archiveImportRows(observation.items,Array.from(rows.values()),state));
      await this.remember(scope,rows,index,current);return next;
    });
  }
  private async remember(scope:string,rows:Map<string,ArchiveLedger>,index:Map<string,ArchiveItem[]>,current:()=>boolean):Promise<void>{
    this.db.beginTransaction();
    try{
      for(const id of new Set<string>(Array.from(rows.keys()).concat(Array.from(index.keys())))){
        const old=rows.get(id);if(old?.remove||old?.pending){continue;}
        const base=index.get(id)??[];
        if(!base.length){await this.db.executeSql('DELETE FROM archive_sync WHERE scope=? AND media_id=?',[scope,id]);rows.delete(id);}
        else{const row:ArchiveLedger={id:id,base:base,remove:false};await this.save(scope,row);rows.set(id,row);}
      }
      this.guard(scope,current);this.db.commit();
    }catch(error){this.db.rollBack();throw new Error('Archive observation persistence failed');}
  }
  private async reconcile(scope:string,rows:Map<string,ArchiveLedger>,index:Map<string,ArchiveItem[]>,local:Map<string,HiddenEntry>,current:()=>boolean):Promise<number>{
    let confirmed=0;
    this.db.beginTransaction();
    try{
      for(const row of rows.values()){
        const observed=index.get(row.id)??[];
        if(row.pending&&archivePlan(row,local.get(row.id),observed).settled){
          row.pending=undefined;confirmed++;
          if(!row.remove){row.base=observed;}
          await this.save(scope,row);
        }
        if(row.remove&&!row.pending&&!local.has(row.id)&&!observed.length){row.remove=false;row.base=[];await this.save(scope,row);}
      }
      this.guard(scope,current);this.db.commit();return confirmed;
    }catch(error){this.db.rollBack();throw new Error('Archive receipt reconciliation failed');}
  }
  private async send(session:TraktSession,uuid:string,activity:string,section:string,remove:boolean,items:ArchiveMutation[],current:()=>boolean):Promise<void>{
    if((await readSyncAccount(session)).uuid!==uuid||await readActivity(session)!==activity||!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Archive fence changed');}
    const body:ArchiveBody={shows:[],movies:[]};
    for(const item of items){
      const media=item.entry.media,id=Number(media.id.substring(media.id.indexOf(':')+1));
      if(!Number.isSafeInteger(id)||id<=0||item.section!==section||item.remove!==remove){throw new Error('Invalid archive mutation');}
      const wire:ArchiveWire=remove?{ids:{trakt:id}}:{ids:{trakt:id},hidden_at:new Date(item.entry.at).toISOString()};
      if(media.kind==='show'){body.shows.push(wire);}else{body.movies.push(wire);}
    }
    const req=http.createHttp();try{
      if(!current()){throw new Error('Archive cancelled');}
      await req.request('https://api.trakt.tv/users/hidden/'+section+(remove?'/remove':''),{method:http.RequestMethod.POST,header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':session.clientId,'Authorization':'Bearer '+session.token},extraData:JSON.stringify(body),expectDataType:http.HttpDataType.STRING});
    }finally{req.destroy();}
  }
  export(scope:string,state:CollectionState,session:TraktSession,signal:ReadCancel,current:()=>boolean):Promise<ArchiveResult>{
    return this.serial(async():Promise<ArchiveResult>=>{
      this.guard(scope,current);const uuid=scope.substring(8),rows=await this.rows(scope),local=new Map<string,HiddenEntry>();
      for(const row of state.hidden){local.set(row.media.id,row);}
      let observation=await readArchiveObservation(session,uuid,signal),index=archiveIndex(observation.items);
      let confirmed=await this.reconcile(scope,rows,index,local,current);
      const ids=Array.from(new Set<string>(Array.from(rows.keys()).concat(Array.from(local.keys()))));
      // Original Android runner uses batches of 500. Each section is rechecked after every write.
      for(const section of ARCHIVE_SECTIONS){
        for(const remove of [false,true]){
          const candidates=ids.filter((id:string)=>{const plan=archivePlan(rows.get(id),local.get(id),index.get(id)??[]);return plan.send?.section===section&&plan.send?.remove===remove;});
          for(let start=0;start<candidates.length;start+=500){
            this.guard(scope,current);const batch:ArchiveMutation[]=[];
            for(const id of candidates.slice(start,start+500)){
              const plan=archivePlan(rows.get(id),local.get(id),index.get(id)??[]);
              if(plan.send&&plan.send.section===section&&plan.send.remove===remove){batch.push(plan.send);}
            }
            if(!batch.length){continue;}
            // Reserve the exact targets together before the one outbound POST.
            this.db.beginTransaction();
            try{for(const op of batch){
              const id=op.entry.media.id,old=rows.get(id);
              if(old?.pending){throw new Error('Existing receipt');}
              const row:ArchiveLedger={id:id,base:old?.base??[],remove:old?.remove??false,pending:op};await this.save(scope,row);rows.set(id,row);
            }this.guard(scope,current);this.db.commit();}catch(error){this.db.rollBack();throw new Error('Archive reservation failed');}
            try{await this.send(session,uuid,observation.activity,section,remove,batch,current);}catch(error){/* uncertain: read back only */}
            observation=await readArchiveObservation(session,uuid,signal);index=archiveIndex(observation.items);
            confirmed+=await this.reconcile(scope,rows,index,local,current);
          }
        }
      }
      await this.remember(scope,rows,index,current);
      let blocked=0;for(const id of ids){const row=rows.get(id),plan=archivePlan(row,local.get(id),index.get(id)??[]);if(plan.blocked||plan.send||row?.pending){blocked++;}}
      return {confirmed:confirmed,blocked:blocked};
    });
  }
}
let opening:Promise<ArchiveRepository>|undefined;
export function openArchive(context:common.UIAbilityContext):Promise<ArchiveRepository>{
  if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_archive_sync.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<ArchiveRepository>=>{
    await db.executeSql('CREATE TABLE IF NOT EXISTS archive_sync(scope TEXT NOT NULL,media_id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,media_id))');return new ArchiveRepository(db);
  }).catch((error:Error):ArchiveRepository=>{opening=undefined;throw error;});}return opening;
}
