import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { CustomList, ListMember, validateList } from '../model/CustomLists';
import { TraktSession, traktAuth } from './TraktAuth';
import { readSyncAccount } from './TraktSyncPreview';
import { readActivity } from './TraktLibrary';
import { ReadCancel } from '../model/ReadFlight';
import { HiddenEntry } from '../model/CollectionRules';
import { ArchiveItem,ArchiveObservation } from '../model/ArchiveSyncRules';
interface ListIds{trakt:number;}
interface ListWire{ids:ListIds;name:string;description?:string;created_at?:string;updated_at?:string;item_count:number;}
interface TitleWire{ids:ListIds;title:string;year?:number;rating?:number;released?:string;first_aired?:string;}
interface MemberWire{type:string;rank:number;listed_at?:string;show?:TitleWire;movie?:TitleWire;}
interface ListPage{raw:string;page:number;pages:number;total:number;hasPagination:boolean;}
function instant(value?:string):number{const n=Date.parse(value??'');return Number.isFinite(n)&&n>=0?n:0;}
function ensure(session:TraktSession,signal:ReadCancel):void{signal.check();if(!traktAuth.isCurrent(session.clientId,session.generation)){throw new Error('Account session changed');}}
async function page(session:TraktSession,path:string,index:number,signal:ReadCancel):Promise<ListPage>{
  ensure(session,signal);const req=http.createHttp();let closed=false;
  const close=():void=>{if(!closed){closed=true;req.destroy();}};signal.subscribe(close);
  try{
    const res=await req.request('https://api.trakt.tv/'+path+(path.includes('?')?'&':'?')+'page='+index+'&limit=250',{method:http.RequestMethod.GET,header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':session.clientId,'Authorization':'Bearer '+session.token},expectDataType:http.HttpDataType.STRING});
    ensure(session,signal);if(res.responseCode!==200||typeof res.result!=='string'){throw new Error('List HTTP '+res.responseCode);}
    const h=JSON.parse(JSON.stringify(res.header).toLowerCase()) as Record<string,string>;
    const has=h['x-pagination-page']!==undefined||h['x-pagination-page-count']!==undefined||h['x-pagination-item-count']!==undefined;
    const current=Number(h['x-pagination-page']),pages=Number(h['x-pagination-page-count']),total=Number(h['x-pagination-item-count']);
    if(has&&(!Number.isSafeInteger(current)||current!==index||!Number.isSafeInteger(pages)||pages<0||!Number.isSafeInteger(total)||total<0||pages<index&&!(index===1&&pages===0&&total===0))){throw new Error('Invalid list pagination');}
    return {raw:res.result,page:current,pages:pages,total:total,hasPagination:has};
  }finally{signal.unsubscribe(close);close();}
}
async function manifest(session:TraktSession,signal:ReadCancel):Promise<ListWire[]>{
  const first=await page(session,'users/me/lists',1,signal),rows=JSON.parse(first.raw) as ListWire[];
  if(!Array.isArray(rows)){throw new Error('Invalid list manifest');}
  if(first.hasPagination){for(let i=2;i<=first.pages;i++){const next=await page(session,'users/me/lists',i,signal);const values=JSON.parse(next.raw) as ListWire[];if(!next.hasPagination||next.pages!==first.pages||next.total!==first.total||!Array.isArray(values)||!values.length){throw new Error('List manifest changed');}rows.push(...values);}if(rows.length!==first.total){throw new Error('Incomplete list manifest');}}
  const seen=new Set<number>();
  for(const row of rows){if(!row||!row.ids||!Number.isSafeInteger(row.ids.trakt)||row.ids.trakt<=0||seen.has(row.ids.trakt)||typeof row.name!=='string'||!row.name.trim()||!Number.isSafeInteger(row.item_count)||row.item_count<0){throw new Error('Invalid list identity');}seen.add(row.ids.trakt);}
  return rows.sort((a:ListWire,b:ListWire)=>a.ids.trakt-b.ids.trakt);
}
async function members(session:TraktSession,row:ListWire,signal:ReadCancel):Promise<CustomList>{
  const path='users/me/lists/'+row.ids.trakt+'/items?extended=full',first=await page(session,path,1,signal);
  const items=JSON.parse(first.raw) as MemberWire[];
  if(!Array.isArray(items)||!first.hasPagination||first.total!==row.item_count){throw new Error('Incomplete list item evidence');}
  for(let i=2;i<=first.pages;i++){const next=await page(session,path,i,signal),values=JSON.parse(next.raw) as MemberWire[];if(!next.hasPagination||next.total!==first.total||next.pages!==first.pages||!Array.isArray(values)||!values.length){throw new Error('List items changed');}items.push(...values);}
  if(items.length!==row.item_count){throw new Error('Incomplete list items');}
  const rows:ListMember[]=[],seen=new Set<string>();let unsupported=0;
  for(const m of items){
    if(m.type!=='show'&&m.type!=='movie'){unsupported++;continue;}
    const t=m.type==='show'?m.show:m.movie;
    if(!t||!t.ids||!Number.isSafeInteger(t.ids.trakt)||t.ids.trakt<=0||typeof t.title!=='string'||!t.title.trim()||!Number.isSafeInteger(m.rank)||m.rank<0){throw new Error('Invalid list member');}
    const media:Media={id:m.type+':'+t.ids.trakt,kind:m.type,title:t.title,year:typeof t.year==='number'?t.year:0,watched:false};
    if(seen.has(media.id)){throw new Error('Duplicate list media');}seen.add(media.id);
    rows.push({media:media,rank:m.rank,listedAt:instant(m.listed_at),rating:typeof t.rating==='number'&&t.rating>0&&t.rating<=10?t.rating:undefined,date:m.type==='show'?t.first_aired:t.released});
  }
  const result:CustomList={id:'trakt:'+row.ids.trakt,name:row.name,description:typeof row.description==='string'?row.description:'',createdAt:instant(row.created_at),updatedAt:instant(row.updated_at),remote:true,members:rows,unsupported:unsupported};
  if(!validateList(result,true)){throw new Error('Invalid remote list');}return result;
}
// Read only; verify stable account identity and both activity/manifest fences.
export async function readCustomLists(session:TraktSession,uuid:string,signal:ReadCancel):Promise<CustomList[]>{
  ensure(session,signal);const before=await readSyncAccount(session);if(before.uuid!==uuid){throw new Error('Wrong account');}
  const activity=await readActivity(session),initial=await manifest(session,signal),rows:CustomList[]=[];
  for(const row of initial){rows.push(await members(session,row,signal));}
  const after=await manifest(session,signal),confirmed=await readSyncAccount(session);
  if(confirmed.uuid!==uuid||await readActivity(session)!==activity||JSON.stringify(initial)!==JSON.stringify(after)){throw new Error('Lists changed during read');}
  ensure(session,signal);return rows;
}

interface HiddenWire{type?:string;hidden_at:string;show?:TitleWire;movie?:TitleWire;}
async function hiddenSection(session:TraktSession,section:string,kind:string,signal:ReadCancel):Promise<HiddenEntry[]>{
  const path='users/hidden/'+section+'?type='+kind+'&extended=full';
  const first=await page(session,path,1,signal),rows=JSON.parse(first.raw) as HiddenWire[];
  if(!Array.isArray(rows)||!first.hasPagination){throw new Error('Incomplete hidden observation');}
  for(let i=2;i<=first.pages;i++){
    const next=await page(session,path,i,signal),items=JSON.parse(next.raw) as HiddenWire[];
    if(!next.hasPagination||next.pages!==first.pages||next.total!==first.total||!Array.isArray(items)||!items.length){throw new Error('Hidden pagination changed');}rows.push(...items);
  }
  if(rows.length!==first.total){throw new Error('Incomplete hidden observation');}
  const result:HiddenEntry[]=[];const seen=new Set<string>();
  for(const row of rows){
    const title=kind==='show'?row.show:row.movie,at=instant(row.hidden_at);
    if((row.type!==undefined&&row.type!==kind)||!title||!title.ids||!Number.isSafeInteger(title.ids.trakt)||title.ids.trakt<=0||!title.title.trim()||!at){throw new Error('Invalid hidden item');}
    const id=kind+':'+title.ids.trakt;if(seen.has(id)){throw new Error('Duplicate hidden identity');}seen.add(id);
    result.push({media:{id:id,kind:kind,title:title.title,year:title.year??0,watched:false},at:at});
  }
  return result;
}
export async function readArchiveObservation(session:TraktSession,uuid:string,signal:ReadCancel):Promise<ArchiveObservation>{
  ensure(session,signal);if((await readSyncAccount(session)).uuid!==uuid){throw new Error('Wrong account');}
  const activity=await readActivity(session),sections=['progress_watched','dropped','calendar'];
  const groups=await Promise.all([hiddenSection(session,sections[0],'show',signal),hiddenSection(session,sections[1],'show',signal),hiddenSection(session,sections[2],'movie',signal)]);
  if((await readSyncAccount(session)).uuid!==uuid||await readActivity(session)!==activity){throw new Error('Hidden observation changed');}
  ensure(session,signal);const items:ArchiveItem[]=[];
  for(let i=0;i<groups.length;i++){for(const entry of groups[i]){items.push({section:sections[i],entry:entry});}}
  return {activity:activity,items:items};
}
export async function readHiddenArchive(session:TraktSession,uuid:string,signal:ReadCancel):Promise<HiddenEntry[]>{
  const snapshot=await readArchiveObservation(session,uuid,signal);
  const byId=new Map<string,HiddenEntry>();for(const item of snapshot.items){const row=item.entry,old=byId.get(row.media.id);if(!old||row.at>old.at){byId.set(row.media.id,row);}}
  return Array.from(byId.values());
}
