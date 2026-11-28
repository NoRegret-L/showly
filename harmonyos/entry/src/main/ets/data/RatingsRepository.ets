import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { TraktSession,traktAuth } from './TraktAuth';
import { readActivity,readCollectionRatings,readPartRatings } from './TraktLibrary';
import { readSyncAccount } from './TraktSyncPreview';
import { RatingTarget,RatingRecord,RatingSnapshot,RatingState,RatingReceipt,validRatingTarget,validRatingRows,validRatingValue,ratingKind,ratingState,ratingDecision,receiptSatisfied,ratingBody,ratingDelta,ratingBatchBody,ratingIntentDecision } from '../model/RatingRules';
export class RatingsRepository{
  private db:relationalStore.RdbStore;
  private tail:Promise<void>=Promise.resolve();
  private resident:string='';private cache:Map<string,RatingSnapshot>=new Map<string,RatingSnapshot>();
  constructor(db:relationalStore.RdbStore){this.db=db;}
  private serial<T>(body:()=>Promise<T>):Promise<T>{const task=this.tail.catch(()=>{}).then(body);this.tail=task.then(()=>{},()=>{});return task;}
  private guard(scope:string,kind:string,current:()=>boolean):void{
    if(!ratingKind(kind)||!(scope==='device'||scope.startsWith('account:')&&scope.length>8&&scope.trim()===scope)||!current()){throw new Error('Rating scope changed');}
    if(this.resident!==scope){this.cache.clear();this.resident=scope;}
  }
  private async disk(scope:string,kind:string):Promise<RatingSnapshot>{
    const cached=this.cache.get(kind);if(cached){return cached;}
    const mark=await this.db.querySql('SELECT activity FROM rating_snapshot WHERE scope=? AND kind=?',[scope,kind]);let known=scope==='device',activity='';
    try{if(mark.goToFirstRow()){known=true;activity=mark.getString(0);}}finally{mark.close();}
    const rows:RatingRecord[]=[];const data=await this.db.querySql('SELECT payload FROM personal_rating WHERE scope=? AND kind=? ORDER BY media_id',[scope,kind]);
    try{while(data.goToNextRow()){rows.push(JSON.parse(data.getString(0)) as RatingRecord);}}finally{data.close();}
    if(!validRatingRows(rows)||(!known&&rows.length)){throw new Error('Invalid rating storage');}
    const snapshot:RatingSnapshot={known:known,activity:activity,rows:rows};this.cache.set(kind,snapshot);return snapshot;
  }
  private async persist(scope:string,kind:string,old:RatingSnapshot,next:RatingSnapshot,current:()=>boolean,clearId:number=0,clearIds:number[]=[]):Promise<void>{
    if(!next.known||!validRatingRows(next.rows)){throw new Error('Invalid rating snapshot');}
    const delta=ratingDelta(old.rows,next.rows);this.db.beginTransaction();
    try{
      for(const r of delta.upserts){await this.db.executeSql('INSERT OR REPLACE INTO personal_rating(scope,kind,media_id,payload) VALUES(?,?,?,?)',[scope,kind,r.id,JSON.stringify(r)]);}
      for(const n of delta.removed){await this.db.executeSql('DELETE FROM personal_rating WHERE scope=? AND kind=? AND media_id=?',[scope,kind,n]);}
      await this.db.executeSql('INSERT OR REPLACE INTO rating_snapshot(scope,kind,activity) VALUES(?,?,?)',[scope,kind,next.activity]);
      for(const id of clearId?clearIds.concat([clearId]):clearIds){await this.db.executeSql('DELETE FROM rating_receipt WHERE scope=? AND kind=? AND media_id=?',[scope,kind,id]);await this.db.executeSql('DELETE FROM rating_intent WHERE scope=? AND kind=? AND media_id=?',[scope,kind,id]);}
      this.guard(scope,kind,current);this.db.commit();this.cache.set(kind,next);
    }catch(error){this.db.rollBack();throw new Error('Rating transaction failed');}
  }
  private async receipt(scope:string,t:RatingTarget):Promise<RatingReceipt|undefined>{
    const rows=await this.db.querySql('SELECT payload FROM rating_receipt WHERE scope=? AND kind=? AND media_id=?',[scope,t.kind,t.id]);
    try{if(!rows.goToFirstRow()){return undefined;}const r=JSON.parse(rows.getString(0)) as RatingReceipt;
      if(!validRatingTarget(r.target)||r.target.kind!==t.kind||r.target.id!==t.id||!validRatingValue(r.desired)){throw new Error('Invalid rating receipt');}return r;
    }finally{rows.close();}
  }
  private async verify(scope:string,session:TraktSession,current:()=>boolean):Promise<void>{
    if(!current()||!traktAuth.isCurrent(session.clientId,session.generation)||!scope.startsWith('account:')){throw new Error('Rating session changed');}
    const account=await readSyncAccount(session);if(account.uuid!==scope.substring(8)||!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Rating account mismatch');}
  }
  private async remote(scope:string,kind:string,session:TraktSession,current:()=>boolean):Promise<RatingSnapshot>{
    await this.verify(scope,session,current);const activity=await readActivity(session);
    const next=await this.readKind(kind,session,activity);
    await this.verify(scope,session,current);if(await readActivity(session)!==activity){throw new Error('Rating observation changed');}
    return next;
  }
  private async readKind(kind:string,session:TraktSession,activity:string):Promise<RatingSnapshot>{
    let rows:RatingRecord[]=[];
    if(kind==='show'||kind==='movie'){const values=await readCollectionRatings(session,kind,activity);rows=values.map((r):RatingRecord=>({id:Number(r.id.substring(kind.length+1)),value:r.value,ratedAt:r.ratedAt}));}
    else{rows=await readPartRatings(session,kind==='season'?'seasons':'episodes',activity);}
    if(!validRatingRows(rows)){throw new Error('Rating observation invalid');}
    return {known:true,activity:activity,rows:rows};
  }
  refreshAllVerified(scope:string,session:TraktSession,current:()=>boolean):Promise<void>{
    return this.serial(async():Promise<void>=>{
      const kinds=['show','movie','season','episode'];this.guard(scope,kinds[0],current);
      await this.verify(scope,session,current);const activity=await readActivity(session);
      const snapshots=await Promise.all(kinds.map((kind:string)=>this.readKind(kind,session,activity)));
      await this.verify(scope,session,current);if(await readActivity(session)!==activity){throw new Error('Rating observation changed');}
      for(let i=0;i<kinds.length;i++){this.guard(scope,kinds[i],current);await this.persist(scope,kinds[i],await this.disk(scope,kinds[i]),snapshots[i],current);}
    });
  }
  // Explicit sync never mistakes a retained stale cache for a fresh import.
  refreshVerified(scope:string,kind:string,session:TraktSession,current:()=>boolean):Promise<RatingSnapshot>{
    return this.serial(async():Promise<RatingSnapshot>=>{
      this.guard(scope,kind,current);const old=await this.disk(scope,kind);
      const next=await this.remote(scope,kind,session,current);
      await this.persist(scope,kind,old,next,current);return next;
    });
  }
  list(scope:string,kind:string,session:TraktSession|undefined,activity:string,current:()=>boolean):Promise<RatingSnapshot>{
    return this.serial(async():Promise<RatingSnapshot>=>{
      this.guard(scope,kind,current);const old=await this.disk(scope,kind);
      if(scope==='device'||!session||!activity||old.known&&old.activity===activity){this.guard(scope,kind,current);return old;}
      try{const next=await this.remote(scope,kind,session,current);await this.persist(scope,kind,old,next,current);return next;}
      catch(error){this.guard(scope,kind,current);if(old.known){return old;}throw new Error('Rating snapshot unavailable');}
    });
  }
  inspect(scope:string,t:RatingTarget,session:TraktSession|undefined,current:()=>boolean):Promise<RatingState>{
    return this.serial(async():Promise<RatingState>=>{
      this.guard(scope,t.kind,current);if(!validRatingTarget(t)){throw new Error('Invalid rating target');}
      const old=await this.disk(scope,t.kind),pending=await this.receipt(scope,t);
      if(scope==='device'){return ratingState(old,t.id,!!pending,true);}
      if(!session){return ratingState(old,t.id,!!pending,false);}
      try{const next=await this.remote(scope,t.kind,session,current),state=ratingState(next,t.id,!!pending,true);
        const resolved=!!pending&&receiptSatisfied(pending,state);await this.persist(scope,t.kind,old,next,current,resolved?t.id:0);
        return ratingState(next,t.id,!!pending&&!resolved,true);
      }catch(error){this.guard(scope,t.kind,current);return ratingState(old,t.id,!!pending,false);}
    });
  }
  change(scope:string,t:RatingTarget,expected:RatingState,desired:number,session:TraktSession|undefined,current:()=>boolean):Promise<RatingState>{
    return this.serial(async():Promise<RatingState>=>{
      this.guard(scope,t.kind,current);if(!validRatingTarget(t)||!validRatingValue(desired)){throw new Error('Invalid rating change');}
      const old=await this.disk(scope,t.kind),pending=await this.receipt(scope,t);
      if(pending){throw new Error('Previous rating result unresolved; read only');}
      const fresh=scope==='device'?old:session?await this.remote(scope,t.kind,session,current):undefined;
      if(!fresh){throw new Error('Verified account required');}
      const actual=ratingState(fresh,t.id,false,true),decision=ratingDecision(expected,actual,desired);
      if(decision==='conflict'||decision==='blocked'){throw new Error('Rating changed; reopen and review');}
      if(decision==='match'){if(scope!=='device'){await this.persist(scope,t.kind,old,fresh,current,t.id);}return actual;}
      const at=Date.now();
      if(scope==='device'){
        const rows=fresh.rows.filter((r:RatingRecord)=>r.id!==t.id);if(desired){rows.push({id:t.id,value:desired,ratedAt:at});}
        const next:RatingSnapshot={known:true,activity:'',rows:rows};await this.persist(scope,t.kind,old,next,current);return ratingState(next,t.id,false,true);
      }
      if(!session){throw new Error('Verified account required');}
      const intent:RatingReceipt={target:t,desired:desired,before:actual.value,beforeAt:actual.ratedAt,createdAt:at};
      // No pending receipt exists: a new explicitly reviewed choice supersedes an unsent intent.
      // Explicit intent is separate from cached remote ratings and survives interruption.
      this.guard(scope,t.kind,current);
      await this.db.executeSql('INSERT OR REPLACE INTO rating_intent(scope,kind,media_id,payload) VALUES(?,?,?,?)',[scope,t.kind,t.id,JSON.stringify(intent)]);
      return this.dispatchIntent(scope,intent,session,current,old,fresh);

    });
  }
  private async dispatchIntent(scope:string,receipt:RatingReceipt,session:TraktSession,current:()=>boolean,old:RatingSnapshot,fresh:RatingSnapshot):Promise<RatingState>{
    const t=receipt.target,desired=receipt.desired,at=receipt.createdAt;
    if(!validRatingTarget(t)||!validRatingValue(desired)||!Number.isFinite(at)||at<=0||at>Date.now()){throw new Error('Invalid rating intent');}
    const actual=ratingState(fresh,t.id,false,true);
    if(actual.value===desired){await this.persist(scope,t.kind,old,fresh,current,t.id);return actual;}
    if(actual.value!==receipt.before||actual.ratedAt!==receipt.beforeAt){throw new Error('Rating conflict; review required');}
    await this.verify(scope,session,current);if(await readActivity(session)!==fresh.activity){throw new Error('Rating activity changed');}
    this.guard(scope,t.kind,current);
    // Durable reservation BEFORE dispatch. A pending receipt is read-only forever until satisfied.
    await this.db.executeSql('INSERT INTO rating_receipt(scope,kind,media_id,payload) VALUES(?,?,?,?)',[scope,t.kind,t.id,JSON.stringify(receipt)]);
    try{
      await this.verify(scope,session,current);if(await readActivity(session)!==fresh.activity){throw new Error('Rating activity changed before dispatch');}
      this.guard(scope,t.kind,current);
      await this.sendRatings(session,ratingBody(t,desired,at),desired===0,current);
    }catch(error){/* uncertain result: read back only, never resend */}
    const confirmed=await this.remote(scope,t.kind,session,current),state=ratingState(confirmed,t.id,true,true),resolved=receiptSatisfied(receipt,state);
    await this.persist(scope,t.kind,old,confirmed,current,resolved?t.id:0);
    return ratingState(confirmed,t.id,!resolved,true);
  }
  private async sendRatings(session:TraktSession,body:string,remove:boolean,current:()=>boolean):Promise<void>{
    const req=http.createHttp();
    try{
      if(!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Rating session changed');}
      await req.request('https://api.trakt.tv/sync/ratings'+(remove?'/remove':''),{method:http.RequestMethod.POST,
        header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':session.clientId,'Authorization':'Bearer '+session.token},
        extraData:body,expectDataType:http.HttpDataType.STRING});
    }finally{req.destroy();}
  }
  exportIntents(scope:string,kind:string,session:TraktSession,current:()=>boolean):Promise<number>{
    return this.serial(async():Promise<number>=>{
      this.guard(scope,kind,current);await this.verify(scope,session,current);
      const rows=await this.db.querySql('SELECT payload FROM rating_intent WHERE scope=? AND kind=? ORDER BY media_id',[scope,kind]);
      const intents:RatingReceipt[]=[];
      try{while(rows.goToNextRow()){intents.push(JSON.parse(rows.getString(0)) as RatingReceipt);}}finally{rows.close();}
      // Include pre-Build98 receipts, even when no separate intent exists. Never dispatch them.
      const pendingRows=await this.db.querySql('SELECT payload FROM rating_receipt WHERE scope=? AND kind=? ORDER BY media_id',[scope,kind]);
      const pending=new Map<number,RatingReceipt>();
      try{while(pendingRows.goToNextRow()){
        const i=JSON.parse(pendingRows.getString(0)) as RatingReceipt;
        if(!validRatingTarget(i.target)||i.target.kind!==kind||!validRatingValue(i.desired)){throw new Error('Invalid rating receipt');}
        pending.set(i.target.id,i);
      }}finally{pendingRows.close();}
      const byId=new Map<number,RatingReceipt>();
      for(const i of intents){
        if(!validRatingTarget(i.target)||i.target.kind!==kind||!validRatingValue(i.desired)){throw new Error('Invalid rating intent');}
        byId.set(i.target.id,i);
      }
      for(const i of pending.values()){byId.set(i.target.id,i);}
      if(!byId.size){return 0;}
      let old=await this.disk(scope,kind),fresh=await this.remote(scope,kind,session,current);
      const blocked=new Set<number>(),resolved:number[]=[];
      const adds:RatingReceipt[]=[],removes:RatingReceipt[]=[];
      const index=new Map<number,RatingRecord>();for(const row of fresh.rows){index.set(row.id,row);}
      for(const i of byId.values()){
        const row=index.get(i.target.id);
        const state:RatingState={known:fresh.known,value:row?.value??0,ratedAt:row?.ratedAt,pending:pending.has(i.target.id),fresh:true};
        const decision=ratingIntentDecision(i,state,pending.has(i.target.id));
        if(decision==='satisfied'){resolved.push(i.target.id);}
        else if(decision==='blocked'){blocked.add(i.target.id);}
        else if(i.desired===0){removes.push(i);}else{adds.push(i);}
      }
      await this.persist(scope,kind,old,fresh,current,0,resolved);old=fresh;
      // Android TraktExportRatingsRunner uses 200 items per type per request.
      for(const group of [adds,removes]){
        for(let start=0;start<group.length;start+=200){
          this.guard(scope,kind,current);
          const indexNow=new Map<number,RatingRecord>();for(const row of fresh.rows){indexNow.set(row.id,row);}
          const chunk:RatingReceipt[]=[],already:number[]=[];
          for(const i of group.slice(start,start+200)){
            const row=indexNow.get(i.target.id);
            const state:RatingState={known:fresh.known,value:row?.value??0,ratedAt:row?.ratedAt,pending:false,fresh:true};
            const decision=ratingIntentDecision(i,state,false);
            if(decision==='satisfied'){already.push(i.target.id);}else if(decision==='send'){chunk.push(i);}else{blocked.add(i.target.id);}
          }
          if(already.length){await this.persist(scope,kind,old,fresh,current,0,already);old=fresh;}
          if(!chunk.length){continue;}
          const body=ratingBatchBody(kind,chunk,chunk[0].desired===0);
          await this.verify(scope,session,current);if(await readActivity(session)!==fresh.activity){throw new Error('Rating activity changed');}
          // All reservations are committed together BEFORE the single network call.
          this.db.beginTransaction();
          try{
            for(const i of chunk){await this.db.executeSql('INSERT INTO rating_receipt(scope,kind,media_id,payload) VALUES(?,?,?,?)',[scope,kind,i.target.id,JSON.stringify(i)]);}
            this.guard(scope,kind,current);this.db.commit();
          }catch(error){this.db.rollBack();throw new Error('Rating reservation failed');}
          try{
            await this.verify(scope,session,current);if(await readActivity(session)!==fresh.activity){throw new Error('Rating activity changed before dispatch');}
            await this.sendRatings(session,body,chunk[0].desired===0,current);
          }catch(error){/* unknown result: only read back; never resend this chunk */}
          fresh=await this.remote(scope,kind,session,current);
          const readback=new Map<number,RatingRecord>();for(const row of fresh.rows){readback.set(row.id,row);}
          const confirmed:number[]=[];
          for(const i of chunk){
            const row=readback.get(i.target.id);
            if((row?.value??0)===i.desired){confirmed.push(i.target.id);}else{blocked.add(i.target.id);}
          }
          await this.persist(scope,kind,old,fresh,current,0,confirmed);old=fresh;
        }
      }
      return blocked.size;
    });
  }
  release():void{this.cache.clear();this.resident='';}
}
let opening:Promise<RatingsRepository>|undefined;
export function openRatings(context:common.UIAbilityContext):Promise<RatingsRepository>{
  if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_ratings.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<RatingsRepository>=>{
    await db.executeSql('CREATE TABLE IF NOT EXISTS personal_rating(scope TEXT NOT NULL,kind TEXT NOT NULL,media_id INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,kind,media_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS rating_snapshot(scope TEXT NOT NULL,kind TEXT NOT NULL,activity TEXT NOT NULL,PRIMARY KEY(scope,kind))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS rating_receipt(scope TEXT NOT NULL,kind TEXT NOT NULL,media_id INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,kind,media_id))');
    await db.executeSql('CREATE TABLE IF NOT EXISTS rating_intent(scope TEXT NOT NULL,kind TEXT NOT NULL,media_id INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(scope,kind,media_id))');
    return new RatingsRepository(db);
  }).catch((error:Error):RatingsRepository=>{opening=undefined;throw error;});}return opening;
}
