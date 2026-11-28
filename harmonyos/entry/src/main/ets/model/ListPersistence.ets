import { CustomList, ListDocument, ListMember, validateListDocument, validateList, publicListMedia } from './CustomLists';
export interface ListPreference{sort:string;kind:string;descending:boolean;}
export function defaultListPreference():ListPreference{return {sort:'rank',kind:'all',descending:false};}
export function validListPreference(p:ListPreference):boolean{return !!p&&['rank','name','year','rating','userRating','added','random'].includes(p.sort)&&['all','show','movie'].includes(p.kind)&&typeof p.descending==='boolean';}
export interface MemberWrite{listId:string;position:number;member:ListMember;}
export interface MemberDelete{listId:string;mediaId:string;}
export interface ListWrite{position:number;row:CustomList;}
export interface ListDelta{lists:ListWrite[];removedLists:string[];members:MemberWrite[];removedMembers:MemberDelete[];nextId:number;}
export function listHeader(row:CustomList):CustomList{return {id:row.id,name:row.name,description:row.description,createdAt:row.createdAt,updatedAt:row.updatedAt,remote:row.remote,members:[],unsupported:row.unsupported};}
function position(row:CustomList,index:number):number{return row.remote?index:Number(row.id.substring(6));}
function memberPosition(row:CustomList,index:number):number{return row.remote?index:row.members[index].rank;}
export function listDelta(old:ListDocument,next:ListDocument):ListDelta{
  const delta:ListDelta={lists:[],removedLists:[],members:[],removedMembers:[],nextId:next.nextId};
  const before=new Map<string,ListWrite>();
  for(const rows of [old.local,old.remote]){rows.forEach((r:CustomList,i:number)=>{before.set(r.id,{position:position(r,i),row:r});});}
  for(const rows of [next.local,next.remote]){
    rows.forEach((row:CustomList,i:number)=>{
      const pos=position(row,i),prior=before.get(row.id);before.delete(row.id);
      if(prior?.row===row&&prior.position===pos){return;}
      if(!prior||prior.position!==pos||JSON.stringify(listHeader(prior.row))!==JSON.stringify(listHeader(row))){delta.lists.push({position:pos,row:listHeader(row)});}
      const members=new Map<string,MemberWrite>();
      if(prior){prior.row.members.forEach((m:ListMember,j:number)=>{members.set(m.media.id,{listId:row.id,position:memberPosition(prior.row,j),member:m});});}
      row.members.forEach((m:ListMember,j:number)=>{
        const p=memberPosition(row,j),o=members.get(m.media.id);members.delete(m.media.id);
        if(!o||o.position!==p||(o.member!==m&&JSON.stringify(o.member)!==JSON.stringify(m))){delta.members.push({listId:row.id,position:p,member:m});}
      });
      for(const key of members.keys()){delta.removedMembers.push({listId:row.id,mediaId:key});}
    });
  }
  for(const key of before.keys()){delta.removedLists.push(key);}
  return delta;
}
// Local legacy operations always produce ascending distinct ranks. Refuse
// invalid ordering rather than silently changing a legacy document.
export function validStorageDocument(doc:ListDocument):boolean{
  if(!validateListDocument(doc)){return false;}
  let id=0;for(const row of doc.local){const n=Number(row.id.substring(6));if(!Number.isSafeInteger(n)||n<=id){return false;}id=n;
    let rank=0;for(const member of row.members){if(member.rank<=rank){return false;}rank=member.rank;}}
  return true;
}
export function localListBackup(doc:ListDocument):ListDocument{
  const local:CustomList[]=doc.local.map((row:CustomList):CustomList=>({id:row.id,name:row.name,description:row.description,createdAt:row.createdAt,updatedAt:row.updatedAt,remote:false,unsupported:0,
    members:row.members.map((m:ListMember):ListMember=>({media:publicListMedia(m.media),rank:m.rank,listedAt:m.listedAt,rating:m.rating,date:m.date,localized:m.localized}))}));
  return {nextId:doc.nextId,local:local,remote:[]};
}
function backupIdentity(row:CustomList):string{return JSON.stringify([row.name,row.description,row.createdAt,row.updatedAt,row.members]);}
export function mergeListBackup(doc:ListDocument,backup:ListDocument):ListDocument{
  if(!validStorageDocument(backup)||backup.remote.length){throw new Error('Invalid local list backup');}
  const seen=new Set<string>(localListBackup(doc).local.map((r:CustomList)=>backupIdentity(r))),local=[...doc.local];let next=doc.nextId;
  for(const row of localListBackup(backup).local){const key=backupIdentity(row);if(seen.has(key)){continue;}if(!Number.isSafeInteger(next+1)){throw new Error('List identity exhausted');}
    local.push({id:'local:'+next,name:row.name,description:row.description,createdAt:row.createdAt,updatedAt:row.updatedAt,remote:false,members:row.members,unsupported:0});next++;seen.add(key);}
  return local.length===doc.local.length?doc:{nextId:next,local:local,remote:doc.remote};
}
