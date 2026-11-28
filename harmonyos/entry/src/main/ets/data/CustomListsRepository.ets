import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { CustomList, ListDocument, ListCommand, ListMember, emptyListDocument, applyListCommand, replaceRemoteLists } from '../model/CustomLists';
import { ListPreference, defaultListPreference, validListPreference, ListDelta, listDelta, validStorageDocument, mergeListBackup } from '../model/ListPersistence';
import { TraktSession,traktAuth } from './TraktAuth';
import { ReadCancel } from '../model/ReadFlight';
import { readCustomLists } from './TraktCustomLists';
import { readActivity } from './TraktLibrary';
import { readSyncAccount } from './TraktSyncPreview';
import { createPrivateList,appendListMembers } from './TraktListExport';
import { missingMemberIds,membersSatisfied } from '../model/ExportEvidence';
import { mergeMappedLists,SyncListLink } from '../model/ListSyncMerge';
interface ListExportLink {remoteId:number;pending:string;}
interface ListExportObservation {activity:string;rows:CustomList[];}
export interface ListExportResult {created:number;added:number;blocked:number;}
function validScope(scope:string):boolean{return scope==='device'||(scope.startsWith('account:')&&scope.length>8&&scope.trim()===scope);}
export class CustomListsRepository{
  private db:relationalStore.RdbStore;
  // One connection, one queue including reads and migrations. Per-scope
  // queues would allow another scope to enter an open connection transaction.
  private tail:Promise<void>=Promise.resolve();
  private docs:Map<string,ListDocument>=new Map<string,ListDocument>();
  constructor(db:relationalStore.RdbStore){this.db=db;}
  private serial<T>(body:()=>Promise<T>):Promise<T>{
    const task=this.tail.catch(()=>{}).then(body);this.tail=task.then(()=>{},()=>{});return task;
  }
  private check(scope:string,current:()=>boolean):void{if(!validScope(scope)||!current()){throw new Error('List scope changed');}}
  private async apply(scope:string,delta:ListDelta,mark:boolean,current:()=>boolean,links:SyncListLink[]=[]):Promise<void>{
    this.db.beginTransaction();
    try{
      for(const id of delta.removedLists){await this.db.executeSql('DELETE FROM list_member_v2 WHERE scope=? AND list_id=?',[scope,id]);await this.db.executeSql('DELETE FROM list_header_v2 WHERE scope=? AND list_id=?',[scope,id]);await this.db.executeSql('DELETE FROM list_preference_v2 WHERE scope=? AND list_id=?',[scope,id]);}
      for(const item of delta.lists){await this.db.executeSql('INSERT OR REPLACE INTO list_header_v2(scope,list_id,remote,position,payload) VALUES(?,?,?,?,?)',[scope,item.row.id,item.row.remote?1:0,item.position,JSON.stringify(item.row)]);}
      for(const item of delta.removedMembers){await this.db.executeSql('DELETE FROM list_member_v2 WHERE scope=? AND list_id=? AND media_id=?',[scope,item.listId,item.mediaId]);}
      for(const item of delta.members){await this.db.executeSql('INSERT OR REPLACE INTO list_member_v2(scope,list_id,media_id,position,payload) VALUES(?,?,?,?,?)',[scope,item.listId,item.member.media.id,item.position,JSON.stringify(item.member)]);}
      for(const link of links){await this.db.executeSql('INSERT INTO list_export_link(scope,local_id,remote_id,pending) VALUES(?,?,?,?)',[scope,link.localId,link.remoteId,link.pending]);}
      // Marker commits only alongside all migrated rows. Legacy stays untouched.
      if(mark){await this.db.executeSql('INSERT OR REPLACE INTO list_scope_v2(scope,next_id) VALUES(?,?)',[scope,delta.nextId]);}
      this.check(scope,current);this.db.commit();
    }catch(error){this.db.rollBack();throw new Error('List transaction failed; previous snapshot retained');}
  }
  private async readBody(scope:string,current:()=>boolean):Promise<ListDocument>{
    this.check(scope,current);const cached=this.docs.get(scope);if(cached){return cached;}
    const marker=await this.db.querySql('SELECT next_id FROM list_scope_v2 WHERE scope=?',[scope]);let nextId=0,initialized=false;
    try{if(marker.goToFirstRow()){initialized=true;nextId=marker.getLong(0);}}finally{marker.close();}
    if(!initialized){
      const legacy=await this.db.querySql('SELECT payload FROM list_document WHERE scope=?',[scope]);let doc=emptyListDocument();
      try{if(legacy.goToFirstRow()){doc=JSON.parse(legacy.getString(0)) as ListDocument;}}finally{legacy.close();}
      if(!validStorageDocument(doc)){throw new Error('Invalid legacy list document; retained');}
      await this.apply(scope,listDelta(emptyListDocument(),doc),true,current);this.docs.set(scope,doc);return doc;
    }
    const doc:ListDocument={nextId:nextId,local:[],remote:[]},byId=new Map<string,CustomList>();
    const headers=await this.db.querySql('SELECT list_id,payload FROM list_header_v2 WHERE scope=? ORDER BY remote,position,list_id',[scope]);
    try{while(headers.goToNextRow()){const key=headers.getString(0),row=JSON.parse(headers.getString(1)) as CustomList;if(row.id!==key||row.members.length||byId.has(key)){throw new Error('Invalid list header');}byId.set(key,row);if(row.remote){doc.remote.push(row);}else{doc.local.push(row);}}}finally{headers.close();}
    const members=await this.db.querySql('SELECT list_id,media_id,payload FROM list_member_v2 WHERE scope=? ORDER BY list_id,position,media_id',[scope]);
    try{while(members.goToNextRow()){const row=byId.get(members.getString(0)),member=JSON.parse(members.getString(2)) as ListMember;if(!row||member.media.id!==members.getString(1)){throw new Error('Invalid list member row');}row.members.push(member);}}finally{members.close();}
    this.check(scope,current);if(!validStorageDocument(doc)){throw new Error('Invalid row storage; no stale legacy fallback');}this.docs.set(scope,doc);return doc;
  }
  read(scope:string,current:()=>boolean):Promise<ListDocument>{return this.serial(()=>this.readBody(scope,current));}
  private write(scope:string,current:()=>boolean,mutate:(doc:ListDocument)=>ListDocument):Promise<ListDocument>{
    return this.serial(async():Promise<ListDocument>=>{
      const old=await this.readBody(scope,current),next=mutate(old);this.check(scope,current);
      if(!validStorageDocument(next)){throw new Error('Invalid list commit');}
      if(next!==old){await this.apply(scope,listDelta(old,next),old.nextId!==next.nextId,current);this.docs.set(scope,next);}
      this.check(scope,current);return next;
    });
  }
  edit(scope:string,command:ListCommand,current:()=>boolean):Promise<ListDocument>{return this.write(scope,current,(doc:ListDocument)=>applyListCommand(doc,command,Date.now()));}
  importRemote(scope:string,rows:CustomList[],current:()=>boolean):Promise<ListDocument>{
    if(!scope.startsWith('account:')){return Promise.reject(new Error('Verified account required'));}
    return this.write(scope,current,(doc:ListDocument)=>replaceRemoteLists(doc,rows));
  }
  importMapped(scope:string,rows:CustomList[],current:()=>boolean):Promise<ListDocument>{
    return this.serial(async():Promise<ListDocument>=>{
      this.check(scope,current);if(!scope.startsWith('account:')){throw new Error('Verified account required');}
      const old=await this.readBody(scope,current),data=await this.db.querySql('SELECT local_id,remote_id,pending FROM list_export_link WHERE scope=?',[scope]);
      const links:SyncListLink[]=[];
      try{while(data.goToNextRow()){links.push({localId:data.getString(0),remoteId:data.getLong(1),pending:data.getString(2)});}}finally{data.close();}
      const next=mergeMappedLists(old,rows,links);
      if(!validStorageDocument(next.doc)){throw new Error('Invalid merged list');}
      await this.apply(scope,listDelta(old,next.doc),old.nextId!==next.doc.nextId,current,next.links);
      this.docs.set(scope,next.doc);return next.doc;
    });
  }
  restoreLocal(scope:string,backup:ListDocument,expected:ListDocument,current:()=>boolean):Promise<ListDocument>{
    return this.write(scope,current,(doc:ListDocument)=>{if(doc!==expected){throw new Error('Restore preview changed');}return mergeListBackup(doc,backup);});
  }
  preference(scope:string,id:string,current:()=>boolean):Promise<ListPreference>{return this.serial(async():Promise<ListPreference>=>{
    this.check(scope,current);const rows=await this.db.querySql('SELECT payload FROM list_preference_v2 WHERE scope=? AND list_id=?',[scope,id]);
    try{this.check(scope,current);if(rows.goToFirstRow()){const p=JSON.parse(rows.getString(0)) as ListPreference;if(validListPreference(p)){return p;}}return defaultListPreference();}finally{rows.close();}
  });}
  savePreference(scope:string,id:string,p:ListPreference,current:()=>boolean):Promise<void>{return this.serial(async():Promise<void>=>{
    this.check(scope,current);if(!validListPreference(p)){throw new Error('Invalid list preference');}
    const doc=await this.readBody(scope,current);if(!doc.local.concat(doc.remote).some((r:CustomList)=>r.id===id)){throw new Error('List missing');}
    this.check(scope,current);await this.db.executeSql('INSERT OR REPLACE INTO list_preference_v2(scope,list_id,payload) VALUES(?,?,?)',[scope,id,JSON.stringify(p)]);
  });}
  private async link(scope:string,id:string):Promise<ListExportLink|undefined>{
    const rows=await this.db.querySql('SELECT remote_id,pending FROM list_export_link WHERE scope=? AND local_id=?',[scope,id]);
    try{if(!rows.goToFirstRow()){return undefined;}return {remoteId:rows.getLong(0),pending:rows.getString(1)};}finally{rows.close();}
  }
  private async observeExport(scope:string,session:TraktSession,signal:ReadCancel,current:()=>boolean):Promise<ListExportObservation>{
    this.check(scope,current);const activity=await readActivity(session);
    const rows=await readCustomLists(session,scope.substring(8),signal);
    this.check(scope,current);if(await readActivity(session)!==activity){throw new Error('List observation changed');}
    return {activity:activity,rows:rows};
  }
  exportAdditive(scope:string,session:TraktSession,signal:ReadCancel,current:()=>boolean):Promise<ListExportResult>{
    return this.serial(async():Promise<ListExportResult>=>{
      this.check(scope,current);
      if(!scope.startsWith('account:')||(await readSyncAccount(session)).uuid!==scope.substring(8)||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('List account mismatch');}
      const doc=await this.readBody(scope,current),uuid=scope.substring(8);
      const result:ListExportResult={created:0,added:0,blocked:0};
      if(!doc.local.length){return result;}
      let observed=await this.observeExport(scope,session,signal,current);
      for(const local of doc.local){
        this.check(scope,current);
        let link=await this.link(scope,local.id);
        if(!link){
          // Never guess a mapping by name. A collision requires manual review.
          if(observed.rows.some((row:CustomList)=>row.name===local.name)){result.blocked++;continue;}
          await this.db.executeSql('INSERT INTO list_export_link(scope,local_id,remote_id,pending) VALUES(?,?,?,?)',[scope,local.id,0,'create']);
          try{
            const id=await createPrivateList(session,uuid,observed.activity,local.name,local.description,current);
            this.check(scope,current);
            await this.db.executeSql('UPDATE list_export_link SET remote_id=? WHERE scope=? AND local_id=? AND remote_id=0 AND pending=?',[id,scope,local.id,'create']);
            link={remoteId:id,pending:'create'};
          }catch(error){result.blocked++;break;}
          observed=await this.observeExport(scope,session,signal,current);
        }
        if(!link||!Number.isSafeInteger(link.remoteId)||link.remoteId<=0){result.blocked++;continue;}
        let remote=observed.rows.find((row:CustomList)=>row.id==='trakt:'+link?.remoteId);
        if(!remote){result.blocked++;continue;}
        if(link.pending==='create'){
          if(remote.name!==local.name||remote.description!==local.description){result.blocked++;continue;}
          await this.db.executeSql('UPDATE list_export_link SET pending=? WHERE scope=? AND local_id=?',['',scope,local.id]);
          result.created++;link.pending='';
        }else if(link.pending){
          const expected=JSON.parse(link.pending) as string[];
          if(!Array.isArray(expected)||!expected.length||!membersSatisfied(expected,remote.members.map((m:ListMember)=>m.media.id))){result.blocked++;continue;}
          await this.db.executeSql('UPDATE list_export_link SET pending=? WHERE scope=? AND local_id=?',['',scope,local.id]);
          link.pending='';
        }
        const missing=missingMemberIds(local.members.map((m:ListMember)=>m.media.id),remote.members.map((m:ListMember)=>m.media.id));
        if(!missing.length){continue;}
        // One durable receipt for the exact additive delta; no removal or rename.
        this.check(scope,current);
        await this.db.executeSql('UPDATE list_export_link SET pending=? WHERE scope=? AND local_id=?',[JSON.stringify(missing),scope,local.id]);
        try{await appendListMembers(session,uuid,observed.activity,link.remoteId,missing,current);}catch(error){}
        observed=await this.observeExport(scope,session,signal,current);
        remote=observed.rows.find((row:CustomList)=>row.id==='trakt:'+link?.remoteId);
        if(!remote||!membersSatisfied(missing,remote.members.map((m:ListMember)=>m.media.id))){result.blocked++;continue;}
        this.check(scope,current);
        await this.db.executeSql('UPDATE list_export_link SET pending=? WHERE scope=? AND local_id=?',['',scope,local.id]);
        result.added+=missing.length;
      }
      return result;
    });
  }
  release():void{this.docs.clear();}
}
let opening:Promise<CustomListsRepository>|undefined;
export function openCustomLists(context:common.UIAbilityContext):Promise<CustomListsRepository>{
  if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_custom_lists.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<CustomListsRepository>=>{
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_document (scope TEXT PRIMARY KEY,payload TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_scope_v2(scope TEXT PRIMARY KEY,next_id INTEGER NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_header_v2(scope TEXT NOT NULL,list_id TEXT NOT NULL,remote INTEGER NOT NULL,position INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,list_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_member_v2(scope TEXT NOT NULL,list_id TEXT NOT NULL,media_id TEXT NOT NULL,position INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,list_id,media_id))');
    await db.executeSql('CREATE INDEX IF NOT EXISTS list_member_reverse_v2 ON list_member_v2(scope,media_id,list_id)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_preference_v2(scope TEXT NOT NULL,list_id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,list_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_export_link(scope TEXT NOT NULL,local_id TEXT NOT NULL,remote_id INTEGER NOT NULL,pending TEXT NOT NULL,PRIMARY KEY(scope,local_id))');
    return new CustomListsRepository(db);
  }).catch((error:Error):CustomListsRepository=>{opening=undefined;throw error;});}
  return opening;
}
