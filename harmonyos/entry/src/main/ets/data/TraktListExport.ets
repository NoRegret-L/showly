import { http } from '@kit.NetworkKit';
import { TraktSession,traktAuth } from './TraktAuth';
import { readSyncAccount } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
interface ListCreateBody {name:string;description:string;privacy:string;}
interface ListIds {trakt:number;}
interface ListResponse {ids:ListIds;}
interface MemberItem {ids:ListIds;}
interface MembersBody {shows:MemberItem[];movies:MemberItem[];}
async function post(session:TraktSession,uuid:string,activity:string,path:string,body:string,current:()=>boolean,method:http.RequestMethod=http.RequestMethod.POST):Promise<string>{
  const account=await readSyncAccount(session);
  if(account.uuid!==uuid||await readActivity(session)!==activity||!current()||!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('List fence changed');}
  const req=http.createHttp();
  try{
    if(!current()){throw new Error('List scope changed');}
    const res=await req.request('https://api.trakt.tv/'+path,{method:method,
      header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':session.clientId,'Authorization':'Bearer '+session.token},
      extraData:body,expectDataType:http.HttpDataType.STRING});
    if((res.responseCode!==200&&res.responseCode!==201)||typeof res.result!=='string'){throw new Error('List response unconfirmed');}
    return res.result;
  }finally{req.destroy();}
}
// Caller must persist a receipt before either call. No retry in transport.
export async function createPrivateList(session:TraktSession,uuid:string,activity:string,name:string,description:string,current:()=>boolean):Promise<number>{
  const body:ListCreateBody={name:name,description:description,privacy:'private'};
  const result=JSON.parse(await post(session,uuid,activity,'users/me/lists',JSON.stringify(body),current)) as ListResponse;
  if(!result.ids||!Number.isSafeInteger(result.ids.trakt)||result.ids.trakt<=0){throw new Error('List identity not confirmed');}
  return result.ids.trakt;
}
export async function appendListMembers(session:TraktSession,uuid:string,activity:string,remoteId:number,ids:string[],current:()=>boolean):Promise<void>{
  if(!Number.isSafeInteger(remoteId)||remoteId<=0||!ids.length){throw new Error('Invalid list mutation');}
  const body:MembersBody={shows:[],movies:[]};
  for(const key of ids){
    const id=Number(key.substring(key.indexOf(':')+1));
    if(!Number.isSafeInteger(id)||id<=0||! /^(show|movie):[1-9][0-9]*$/.test(key)){throw new Error('Invalid member');}
    const row:MemberItem={ids:{trakt:id}};
    if(key.startsWith('show:')){body.shows.push(row);}else{body.movies.push(row);}
  }
  await post(session,uuid,activity,'users/me/lists/'+remoteId+'/items',JSON.stringify(body),current);
}

interface ListMetadataBody {name:string;description:string;}
// Same partial metadata body as Android AuthorizedTraktApi.postUpdateList; no privacy/sort changes requested.
export async function updateListMetadata(session:TraktSession,uuid:string,activity:string,id:number,name:string,description:string,current:()=>boolean):Promise<void>{
  if(!Number.isSafeInteger(id)||id<=0||!name.trim()){throw new Error('Invalid metadata');}
  const body:ListMetadataBody={name:name,description:description};
  await post(session,uuid,activity,'users/me/lists/'+id,JSON.stringify(body),current,http.RequestMethod.PUT);
}
