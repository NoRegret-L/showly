import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { TraktSession,traktAuth } from './TraktAuth';
import { readActivity,readCollectionRatings,readPartRatings } from './TraktLibrary';
import { readSyncAccount } from './TraktSyncPreview';
import { RatingTarget,RatingRecord,RatingSnapshot,RatingState,RatingReceipt,validRatingTarget,validRatingRows,validRatingValue,ratingKind,ratingState,ratingDecision,receiptSatisfied,ratingBody,ratingDelta } from '../model/RatingRules';
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
  private async persist(scope:string,kind:string,old:RatingSnapshot,next:RatingSnapshot,current:()=>boolean,clearId:number=0):Promise<void>{
    if(!next.known||!validRatingRows(next.rows)){throw new Error('Invalid rating snapshot');}
    const delta=ratingDelta(old.rows,next.rows);this.db.beginTransaction();
    try{
      for(const r of delta.upserts){await this.db.executeSql('INSERT OR REPLACE INTO personal_rating(scope,kind,media_id,payload) VALUES(?,?,?,?)',[scope,kind,r.id,JSON.stringify(r)]);}
      for(const n of delta.removed){await this.db.executeSql('DELETE FROM personal_rating WHERE scope=? AND kind=? AND media_id=?',[scope,kind,n]);}
      await this.db.executeSql('INSERT OR REPLACE INTO rating_snapshot(scope,kind,activity) VALUES(?,?,?)',[scope,kind,next.activity]);
      if(clearId){await this.db.executeSql('DELETE FROM rating_receipt WHERE scope=? AND kind=? AND media_id=?',[scope,kind,clearId]);await this.db.executeSql('DELETE FROM rating_intent WHERE scope=? AND kind=? AND media_id=?',[scope,kind,clearId]);}
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
    await this.verify(scope,session,current);const activity=await readActivity(session);let rows:RatingRecord[]=[];
    if(kind==='show'||kind==='movie'){const values=await readCollectionRatings(session,kind,activity);rows=values.map((r):RatingRecord=>({id:Number(r.id.substring(kind.length+1)),value:r.value,ratedAt:r.ratedAt}));}
    else{rows=await readPartRatings(session,kind==='season'?'seasons':'episodes',activity);}
    await this.verify(scope,session,current);if(await readActivity(session)!==activity||!validRatingRows(rows)){throw new Error('Rating observation changed');}
    return {known:true,activity:activity,rows:rows};
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
      this.guard(scope,t.kind,current);const req=http.createHttp();
      try{await req.request('https://api.trakt.tv/sync/ratings'+(desired===0?'/remove':''),{method:http.RequestMethod.POST,
        header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':session.clientId,'Authorization':'Bearer '+session.token},
        extraData:ratingBody(t,desired,at),expectDataType:http.HttpDataType.STRING});}finally{req.destroy();}
    }catch(error){/* uncertain result: read back only, never resend */}
    const confirmed=await this.remote(scope,t.kind,session,current),state=ratingState(confirmed,t.id,true,true),resolved=receiptSatisfied(receipt,state);
    await this.persist(scope,t.kind,old,confirmed,current,resolved?t.id:0);
    return ratingState(confirmed,t.id,!resolved,true);
  }
  exportIntents(scope:string,kind:string,session:TraktSession,current:()=>boolean):Promise<number>{
    return this.serial(async():Promise<number>=>{
      this.guard(scope,kind,current);await this.verify(scope,session,current);
      const rows=await this.db.querySql('SELECT payload FROM rating_intent WHERE scope=? AND kind=? ORDER BY media_id',[scope,kind]);
      const intents:RatingReceipt[]=[];
      try{while(rows.goToNextRow()){intents.push(JSON.parse(rows.getString(0)) as RatingReceipt);}}finally{rows.close();}
      let blocked=0;
      for(const intent of intents){
        this.guard(scope,kind,current);
        if(!validRatingTarget(intent.target)||intent.target.kind!==kind||!validRatingValue(intent.desired)){throw new Error('Invalid rating intent');}
        try{
          const old=await this.disk(scope,kind),fresh=await this.remote(scope,kind,session,current);
          const pending=await this.receipt(scope,intent.target);
          if(pending){
            const state=ratingState(fresh,intent.target.id,true,true);
            const resolved=receiptSatisfied(pending,state);
            await this.persist(scope,kind,old,fresh,current,resolved?intent.target.id:0);
            if(!resolved){blocked++;}
          }else if((await this.dispatchIntent(scope,intent,session,current,old,fresh)).pending){blocked++;}
        }catch(error){this.guard(scope,kind,current);blocked++;}
      }
      return blocked;
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
