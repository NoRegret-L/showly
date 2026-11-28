import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { TraktSession,traktAuth } from './TraktAuth';
import { readSyncAccount,SyncAccount } from './TraktSyncPreview';
import { ConsumerReadFlight,ReadCancel } from '../model/ReadFlight';
import { checkPresentationService,presentationHttpError,traktPresentationService } from './PresentationHttp';
import { CommentTarget,CommentRow,CommentPage,CommentReceipt,targetKey,commentPath,commentLimit,parseComments,parseComment,postBody,nextCommentPage,ownComment,canDeleteComment,positiveCommentId } from '../model/CommentRules';
interface CachedPage{raw:string;headers:string;}
interface CommentHeaders{'Content-Type':string;'trakt-api-version':string;'trakt-api-key':string;Authorization?:string;}
interface CommentResponse{code:number;raw:string;headers:string;}
export class CommentsRepository{
 private db:relationalStore.RdbStore;private flights:ConsumerReadFlight<CachedPage>=new ConsumerReadFlight<CachedPage>();private tail:Promise<void>=Promise.resolve();
 constructor(db:relationalStore.RdbStore){this.db=db;}
 private serial<T>(body:()=>Promise<T>):Promise<T>{const task=this.tail.catch(()=>{}).then(body);this.tail=task.then(()=>{},()=>{});return task;}
 private async transport(path:string,client:string,method:http.RequestMethod,session?:TraktSession,body?:string,signal?:ReadCancel):Promise<CommentResponse>{
  signal?.check();if(!client){throw new Error('Client required');}const service=traktPresentationService(client);if(method===http.RequestMethod.GET&&!session){checkPresentationService(service);}
  const req=http.createHttp();let closed=false;const close=():void=>{if(!closed){closed=true;req.destroy();}};signal?.subscribe(close);
  try{const headers:CommentHeaders={'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':client};if(session){headers.Authorization='Bearer '+session.token;}
   const res=await req.request('https://api.trakt.tv/'+path,{method:method,header:headers,extraData:body,expectDataType:http.HttpDataType.STRING});signal?.check();
   if(method===http.RequestMethod.GET&&res.responseCode!==200&&!session){throw presentationHttpError(service,res.responseCode,JSON.stringify(res.header),true);}
   return {code:res.responseCode,raw:typeof res.result==='string'?res.result:'',headers:JSON.stringify(res.header)};
  }finally{signal?.unsubscribe(close);close();}
 }
 async account(scope:string,session:TraktSession,current:()=>boolean):Promise<SyncAccount>{
  if(!scope.startsWith('account:')||!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Comment account changed');}
  const a=await readSyncAccount(session);if(a.uuid!==scope.substring(8)||!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Comment account mismatch');}return a;
 }
 async page(t:CommentTarget,parent:number,page:number,client:string,signal:ReadCancel):Promise<CommentPage>{
  if(!Number.isSafeInteger(page)||page<1||!Number.isSafeInteger(parent)||parent<0){throw new Error('Invalid comment page');}
  const key=JSON.stringify([targetKey(t),parent,page]),path=(parent?'comments/'+parent+'/replies':commentPath(t))+'?extended=full&limit='+commentLimit(t)+'&page='+page;
  try{
   const result=await this.flights.run(JSON.stringify([client,key]),async(scope:ReadCancel):Promise<CachedPage>=>{const r=await this.transport(path,client,http.RequestMethod.GET,undefined,undefined,scope);parseComments(r.raw,parent);nextCommentPage(page,r.headers);scope.check();await this.db.executeSql('INSERT OR REPLACE INTO comment_page(cache_key,payload,headers) VALUES(?,?,?)',[key,r.raw,r.headers]);return {raw:r.raw,headers:r.headers};},signal);
   signal.check();return {rows:parseComments(result.raw,parent),next:nextCommentPage(page,result.headers),cached:false};
  }catch(error){signal.check();const rows=await this.db.querySql('SELECT payload,headers FROM comment_page WHERE cache_key=?',[key]);try{signal.check();if(rows.goToFirstRow()){return {rows:parseComments(rows.getString(0),parent),next:nextCommentPage(page,rows.getString(1)),cached:true};}}finally{rows.close();}throw new Error('Comments unavailable');}
 }
 async pending(scope:string):Promise<boolean>{const r=await this.db.querySql('SELECT scope FROM comment_receipt WHERE scope=?',[scope]);try{return r.goToFirstRow();}finally{r.close();}}
 private async reserve(scope:string,r:CommentReceipt):Promise<void>{await this.db.executeSql('INSERT INTO comment_receipt(scope,payload) VALUES(?,?)',[scope,JSON.stringify(r)]);}
 private async confirmed(scope:string,t:CommentTarget):Promise<void>{
  // Invalidate all cached pages after a confirmed mutation, atomically with receipt retirement.
  this.db.beginTransaction();try{await this.db.executeSql('DELETE FROM comment_page');await this.db.executeSql('DELETE FROM comment_receipt WHERE scope=?',[scope]);this.db.commit();}catch(error){this.db.rollBack();throw new Error('Comment confirmation storage failed');}
 }
 post(scope:string,t:CommentTarget,parent:number,text:string,spoiler:boolean,session:TraktSession,current:()=>boolean):Promise<CommentRow>{
  return this.serial(async():Promise<CommentRow>=>{
   const body=postBody(t,parent,text,spoiler),a=await this.account(scope,session,current);if(await this.pending(scope)){throw new Error('Unresolved comment write');}
   if(parent){const p=await this.transport('comments/'+parent,session.clientId,http.RequestMethod.GET,session);if(p.code!==200||parseComment(p.raw).id!==parent||parseComment(p.raw).parent!==0){throw new Error('Reply parent unavailable');}}
   await this.account(scope,session,current);await this.reserve(scope,{action:'post',target:targetKey(t),parent:parent,id:0,created:Date.now()});
   // No retries; a lost POST response cannot be proven by text matching.
   await this.account(scope,session,current);const res=await this.transport(parent?'comments/'+parent+'/replies':'comments',session.clientId,http.RequestMethod.POST,session,body);
   if(res.code!==201){throw new Error('Comment result unconfirmed');}const row=parseComment(res.raw);
   if(row.parent!==parent||!ownComment(row,a.uuid,a.username)||row.text!==text.trim()){throw new Error('Comment response mismatch');}
   await this.account(scope,session,current);await this.confirmed(scope,t);return row;
  });
 }
 remove(scope:string,t:CommentTarget,expected:CommentRow,session:TraktSession,current:()=>boolean):Promise<void>{
  return this.serial(async():Promise<void>=>{
   const a=await this.account(scope,session,current);if(!positiveCommentId(expected.id)||await this.pending(scope)){throw new Error('Deletion blocked');}
   const res=await this.transport('comments/'+expected.id,session.clientId,http.RequestMethod.GET,session);if(res.code!==200){throw new Error('Comment unavailable');}
   const row=parseComment(res.raw);
   if(row.id!==expected.id||row.parent!==expected.parent||row.text!==expected.text||row.updated!==expected.updated||!canDeleteComment(row,a.uuid,a.username,Date.now())){throw new Error('Comment conflict or deletion not allowed');}
   await this.account(scope,session,current);await this.reserve(scope,{action:'delete',target:targetKey(t),parent:row.parent,id:row.id,created:Date.now()});
   await this.account(scope,session,current);const deleted=await this.transport('comments/'+row.id,session.clientId,http.RequestMethod.DELETE,session);
   if(deleted.code!==204){throw new Error('Delete result unconfirmed');}
   await this.account(scope,session,current);await this.confirmed(scope,t);
  });
 }
}
let opening:Promise<CommentsRepository>|undefined;
export function openComments(context:common.UIAbilityContext):Promise<CommentsRepository>{
 if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_comments.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<CommentsRepository>=>{
  await db.executeSql('CREATE TABLE IF NOT EXISTS comment_page(cache_key TEXT PRIMARY KEY,payload TEXT NOT NULL,headers TEXT NOT NULL)');
  await db.executeSql('CREATE TABLE IF NOT EXISTS comment_receipt(scope TEXT PRIMARY KEY,payload TEXT NOT NULL)');return new CommentsRepository(db);
 }).catch((e:Error):CommentsRepository=>{opening=undefined;throw e;});}return opening;
}
