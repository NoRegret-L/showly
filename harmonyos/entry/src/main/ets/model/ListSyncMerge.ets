import { CustomList,ListDocument,ListMember,validateList } from './CustomLists';
export interface SyncListLink {localId:string;remoteId:number;pending:string;}
export interface ListMergeResult {doc:ListDocument;links:SyncListLink[];}
function appendMembers(local:ListMember[],remote:ListMember[]):ListMember[]{
  const seen=new Set<string>(local.map((m:ListMember)=>m.media.id));
  let rank=local.reduce((n:number,m:ListMember)=>Math.max(n,m.rank),0);
  const added:ListMember[]=[];
  for(const m of remote){
    if(!seen.has(m.media.id)){
      if(!Number.isSafeInteger(rank+1)){throw new Error('Rank exhausted');}
      rank++;seen.add(m.media.id);added.push({media:m.media,rank:rank,listedAt:m.listedAt,rating:m.rating,date:m.date,localized:m.localized});
    }
  }
  return added.length?local.concat(added):local;
}
// Only persistent numeric identity establishes a match. Unknown creates are never matched by name.
export function mergeMappedLists(doc:ListDocument,remote:CustomList[],links:SyncListLink[]):ListMergeResult{
  const byRemote=new Map<number,SyncListLink>(),byLocal=new Map<string,CustomList>();
  let uncertainCreate=false;
  for(const row of doc.local){byLocal.set(row.id,row);}
  for(const link of links){
    if(link.remoteId===0){uncertainCreate=true;continue;}
    if(!Number.isSafeInteger(link.remoteId)||link.remoteId<0||byRemote.has(link.remoteId)){throw new Error('Invalid or duplicate mapping');}
    byRemote.set(link.remoteId,link);
  }
  const newLinks:SyncListLink[]=[],unmapped:CustomList[]=[],seen=new Set<number>();
  let next=doc.nextId;
  for(const row of remote){
    if(!validateList(row,true)){throw new Error('Invalid remote snapshot');}
    const id=Number(row.id.substring(6));
    if(!Number.isSafeInteger(id)||seen.has(id)){throw new Error('Duplicate remote identity');}seen.add(id);
    const link=byRemote.get(id);
    if(link){
      const old=byLocal.get(link.localId);
      // Deleted local lists, unresolved receipts and unsupported media remain read-only.
      if(!old||link.pending||row.unsupported){unmapped.push(row);continue;}
      const members=appendMembers(old.members,row.members);
      const newer=row.updatedAt>0&&row.updatedAt>old.updatedAt;
      if(members!==old.members||newer){
        byLocal.set(old.id,{id:old.id,name:newer?row.name:old.name,description:newer?row.description:old.description,
          createdAt:old.createdAt,updatedAt:Math.max(old.updatedAt,row.updatedAt),remote:false,members:members,unsupported:0});
      }
    }else if(uncertainCreate||row.unsupported){
      unmapped.push(row);
    }else{
      if(!Number.isSafeInteger(next+1)){throw new Error('List identity exhausted');}
      const localId='local:'+next;next++;
      byLocal.set(localId,{id:localId,name:row.name,description:row.description,createdAt:row.createdAt,updatedAt:row.updatedAt,
        remote:false,members:appendMembers([],row.members),unsupported:0});
      newLinks.push({localId:localId,remoteId:id,pending:''});
    }
  }
  return {doc:{nextId:next,local:Array.from(byLocal.values()),remote:unmapped},links:newLinks};
}
