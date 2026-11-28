import { Media } from './Media';
import { stableProgressRandom } from './ProgressRules';
export interface ListMember {media:Media;rank:number;listedAt:number;rating?:number;userRating?:number;date?:string;localized?:string;}
export interface CustomList {id:string;name:string;description:string;createdAt:number;updatedAt:number;remote:boolean;members:ListMember[];unsupported:number;}
export interface ListDocument {nextId:number;local:CustomList[];remote:CustomList[];}
export interface ListCommand {kind:string;id?:string;name?:string;description?:string;media?:Media;mediaId?:string;direction?:number;}
export interface ListSnapshot {revision:number;rows:CustomList[];busy:boolean;status:string;loaded:boolean;}
export function emptyListDocument():ListDocument{return {nextId:1,local:[],remote:[]};}
export function emptyListSnapshot():ListSnapshot{return {revision:0,rows:[],busy:false,status:'',loaded:false};}
export function listMediaValid(item:Media):boolean{return !!item&&['show','movie'].includes(item.kind)&&new RegExp('^'+item.kind+':[1-9][0-9]*$').test(item.id)&&typeof item.title==='string'&&!!item.title.trim()&&Number.isSafeInteger(item.year)&&item.year>=0;}
function validTime(value:number):boolean{return Number.isSafeInteger(value)&&value>=0;}
function validRating(value?:number):boolean{return value===undefined||(Number.isFinite(value)&&value>=0&&value<=10);}
export function validateList(row:CustomList,remote:boolean):boolean{
  if(!row||row.remote!==remote||!(remote?/^trakt:[1-9][0-9]*$/:/^local:[1-9][0-9]*$/).test(row.id)||typeof row.name!=='string'||!row.name.trim()||typeof row.description!=='string'||!validTime(row.createdAt)||!validTime(row.updatedAt)||!Number.isSafeInteger(row.unsupported)||row.unsupported<0||!Array.isArray(row.members)){return false;}
  const ids=new Set<string>();
  for(const m of row.members){if(!m||!listMediaValid(m.media)||ids.has(m.media.id)||!Number.isSafeInteger(m.rank)||m.rank<0||!validTime(m.listedAt)||!validRating(m.rating)||!validRating(m.userRating)){return false;}ids.add(m.media.id);}
  return true;
}
export function validateListDocument(doc:ListDocument):boolean{
  if(!doc||!Number.isSafeInteger(doc.nextId)||doc.nextId<=0||!Array.isArray(doc.local)||!Array.isArray(doc.remote)){return false;}
  const ids=new Set<string>();for(const row of doc.local.concat(doc.remote)){if(!validateList(row,row.remote)||ids.has(row.id)){return false;}ids.add(row.id);}
  return doc.local.every((r:CustomList)=>!r.remote&&Number(r.id.substring(6))<doc.nextId)&&doc.remote.every((r:CustomList)=>r.remote);
}
export function publicListMedia(item:Media):Media{return {id:item.id,kind:item.kind,title:item.title,year:item.year,watched:false};}
function normalizeRanks(rows:ListMember[]):ListMember[]{return rows.map((m:ListMember,i:number):ListMember=>({media:m.media,rank:i+1,listedAt:m.listedAt,rating:m.rating,userRating:m.userRating,date:m.date,localized:m.localized}));}
export function applyListCommand(doc:ListDocument,command:ListCommand,now:number):ListDocument{
  if(!validTime(now)){throw new Error('Invalid timestamp');}
  if(command.kind==='create'){
    const name=command.name?.trim()??'';if(!name||!Number.isSafeInteger(doc.nextId+1)){throw new Error('Invalid list name or identity');}
    const row:CustomList={id:'local:'+doc.nextId,name:name,description:command.description?.trim()??'',createdAt:now,updatedAt:now,remote:false,members:[],unsupported:0};
    return {nextId:doc.nextId+1,local:doc.local.concat([row]),remote:doc.remote};
  }
  const at=doc.local.findIndex((r:CustomList)=>r.id===command.id);
  if(at<0){throw new Error('Local list not found or read only');}
  const old=doc.local[at];
  if(command.kind==='delete'){return {nextId:doc.nextId,local:doc.local.filter((r:CustomList)=>r.id!==old.id),remote:doc.remote};}
  let name=old.name,description=old.description,members=old.members;
  if(command.kind==='edit'){
    name=command.name?.trim()??'';description=command.description?.trim()??'';if(!name){throw new Error('List name required');}
    if(name===old.name&&description===old.description){return doc;}
  }else if(command.kind==='add'){
    const item=command.media;if(!item||!listMediaValid(item)){throw new Error('Invalid member');}
    if(members.some((m:ListMember)=>m.media.id===item.id)){return doc;}
    const rank=members.reduce((n:number,m:ListMember)=>Math.max(n,m.rank),0)+1;
    members=members.concat([{media:publicListMedia(item),rank:rank,listedAt:now}]);
  }else if(command.kind==='remove'){
    members=members.filter((m:ListMember)=>m.media.id!==command.mediaId);if(members.length===old.members.length){return doc;}
  }else if(command.kind==='move'){
    members=[...members].sort((a:ListMember,b:ListMember)=>a.rank-b.rank);
    const i=members.findIndex((m:ListMember)=>m.media.id===command.mediaId),d=command.direction??0,j=i+d;
    if(i<0||(d!==1&&d!==-1)||j<0||j>=members.length){return doc;}
    const temp=members[i];members[i]=members[j];members[j]=temp;members=normalizeRanks(members);
  }else{throw new Error('Unknown local list command');}
  const local=[...doc.local];local[at]={id:old.id,name:name,description:description,createdAt:old.createdAt,updatedAt:Math.max(now,old.updatedAt),remote:false,members:members,unsupported:0};
  return {nextId:doc.nextId,local:local,remote:doc.remote};
}
export function replaceRemoteLists(doc:ListDocument,rows:CustomList[]):ListDocument{
  const seen=new Set<string>();
  for(const row of rows){if(!validateList(row,true)||seen.has(row.id)){throw new Error('Invalid remote list snapshot');}seen.add(row.id);}
  return {nextId:doc.nextId,local:doc.local,remote:rows};
}
export class ListMembershipIndex{
  private lists:Map<string,CustomList>=new Map<string,CustomList>();
  private reverse:Map<string,Set<string>>=new Map<string,Set<string>>();
  private members:Map<string,Set<string>>=new Map<string,Set<string>>();
  private changes:number=0;
  clear():void{this.lists.clear();this.reverse.clear();this.members.clear();}
  private unlink(list:string,id:string):void{const ids=this.reverse.get(id);if(ids){ids.delete(list);if(!ids.size){this.reverse.delete(id);}}}
  private link(list:string,id:string):void{let ids=this.reverse.get(id);if(!ids){ids=new Set<string>();this.reverse.set(id,ids);}ids.add(list);}
  update(rows:CustomList[]):void{
    const seen=new Set<string>();
    for(const row of rows){
      if(seen.has(row.id)){this.clear();throw new Error('Duplicate list identity');}seen.add(row.id);
      const prior=this.lists.get(row.id);if(prior===row){continue;}
      const old=this.members.get(row.id)??new Set<string>(),next=new Set<string>(row.members.map((m:ListMember)=>m.media.id));
      for(const id of old){if(!next.has(id)){this.unlink(row.id,id);this.changes++;}}
      for(const id of next){if(!old.has(id)){this.link(row.id,id);this.changes++;}}
      this.lists.set(row.id,row);this.members.set(row.id,next);
    }
    for(const id of Array.from(this.lists.keys())){if(!seen.has(id)){for(const media of this.members.get(id)??new Set<string>()){this.unlink(id,media);this.changes++;}this.members.delete(id);this.lists.delete(id);}}
  }
  contains(list:string,media:string):boolean{return this.members.get(list)?.has(media)??false;}
  listsFor(media:string):string[]{return Array.from(this.reverse.get(media)??new Set<string>()).sort();}
  count(list:string):number{return this.members.get(list)?.size??0;}
  updates():number{return this.changes;}
}
export class ListsOwner{
  readonly index:ListMembershipIndex=new ListMembershipIndex();
  private value:ListSnapshot=emptyListSnapshot();
  private ticket:number=0;
  begin():number{return ++this.ticket;}
  current(token:number):boolean{return token===this.ticket;}
  clear():void{this.ticket++;this.index.clear();this.value=emptyListSnapshot();}
  snapshot():ListSnapshot{return this.value;}
  publish(token:number,rows:CustomList[],busy:boolean,status:string,loaded:boolean):void{
    if(!this.current(token)){return;}const old=this.value;
    if(rows===old.rows&&busy===old.busy&&status===old.status&&loaded===old.loaded){return;}
    if(rows!==old.rows){this.index.update(rows);}
    this.value={revision:old.revision+1,rows:rows,busy:busy,status:status,loaded:loaded};
  }
}
function cmp(a:string,b:string):number{return a<b?-1:a>b?1:0;}
function title(m:ListMember):string{return m.localized||m.media.title.replace(/^the /i,'').toUpperCase();}
export function sortLists(rows:CustomList[],query:string,sort:string,descending:boolean):CustomList[]{
  const q=query.trim().toLowerCase(),dir=descending?-1:1;
  return rows.filter((r:CustomList)=>!q||r.name.toLowerCase().includes(q)||r.description.toLowerCase().includes(q)).sort((a:CustomList,b:CustomList)=>dir*(sort==='created'?a.createdAt-b.createdAt:sort==='updated'?a.updatedAt-b.updatedAt:cmp(a.name,b.name)));
}
export function sortListMembers(rows:ListMember[],filter:string,sort:string,descending:boolean,seed:string=''):ListMember[]{
  const dir=descending?-1:1;
  return rows.filter((m:ListMember)=>filter==='all'||m.media.kind===filter).sort((a:ListMember,b:ListMember)=>{
    if(sort==='userRating'){return Number(b.userRating!==undefined)-Number(a.userRating!==undefined)||dir*((a.userRating??0)-(b.userRating??0))||cmp(title(a),title(b));}
    if(sort==='rating'){return Number(b.rating!==undefined)-Number(a.rating!==undefined)||dir*((a.rating??0)-(b.rating??0));}
    if(sort==='name'){return dir*cmp(title(a),title(b));}
    if(sort==='year'){return dir*(a.media.year-b.media.year||cmp(a.date??'',b.date??''));}
    if(sort==='added'){return dir*(a.listedAt-b.listedAt);}
    if(sort==='random'){return stableProgressRandom(seed+':'+a.media.id)-stableProgressRandom(seed+':'+b.media.id)||cmp(a.media.id,b.media.id);}
    return dir*(a.rank-b.rank);
  });
}
