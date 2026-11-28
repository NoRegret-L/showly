import { HiddenEntry,CollectionState,validCollectionState } from './CollectionRules';
export const ARCHIVE_SECTIONS:string[]=['progress_watched','dropped','calendar'];
export interface ArchiveItem {section:string;entry:HiddenEntry;}
export interface ArchiveObservation {activity:string;items:ArchiveItem[];}
export interface ArchiveMutation {section:string;entry:HiddenEntry;remove:boolean;}
export interface ArchiveLedger {id:string;base:ArchiveItem[];remove:boolean;pending?:ArchiveMutation;}
export interface ArchivePlan {send?:ArchiveMutation;blocked:boolean;settled:boolean;}
export function validArchiveItem(item:ArchiveItem):boolean{
  return !!item&&!!item.entry&&validCollectionState({hidden:[item.entry],mine:[],queue:[]})&&
    (item.entry.media.kind==='show'?item.section==='progress_watched'||item.section==='dropped':item.section==='calendar');
}
export function archivePlan(ledger:ArchiveLedger|undefined,local:HiddenEntry|undefined,remote:ArchiveItem[]):ArchivePlan{
  if(ledger?.pending){
    const pending=ledger.pending,found=remote.some((r:ArchiveItem)=>r.section===pending.section);
    return {blocked:pending.remove?found:!found,settled:pending.remove?!found:found};
  }
  if(ledger?.remove){
    if(local){return {blocked:true,settled:false};}
    if(!remote.length){return {blocked:false,settled:true};}
    // Explicit removal may only affect unchanged sections in the observed baseline.
    if(remote.some((r:ArchiveItem)=>!ledger.base.some((b:ArchiveItem)=>b.section===r.section&&b.entry.at===r.entry.at))){return {blocked:true,settled:false};}
    return {send:{section:remote[0].section,entry:remote[0].entry,remove:true},blocked:false,settled:false};
  }
  if(!local||remote.length){return {blocked:false,settled:true};}
  if(!Number.isSafeInteger(local.at)||local.at<=0||local.at>Date.now()){return {blocked:true,settled:false};}
  return {send:{section:local.media.kind==='show'?'progress_watched':'calendar',entry:local,remove:false},blocked:false,settled:false};
}
export function archiveIndex(items:ArchiveItem[]):Map<string,ArchiveItem[]>{
  const result=new Map<string,ArchiveItem[]>();
  for(const item of items){
    if(!validArchiveItem(item)){throw new Error('Invalid archive item');}
    const id=item.entry.media.id,rows=result.get(id)??[];
    if(rows.some((r:ArchiveItem)=>r.section===item.section)){throw new Error('Duplicate archive section');}
    rows.push(item);result.set(id,rows);
  }return result;
}
export function archiveImportRows(items:ArchiveItem[],ledgers:ArchiveLedger[],state:CollectionState):HiddenEntry[]{
  const blocked=new Set<string>(),local=new Set<string>(state.hidden.map((r:HiddenEntry)=>r.media.id));
  for(const row of ledgers){if(row.remove&&!local.has(row.id)){blocked.add(row.id);}}
  const result:HiddenEntry[]=[];
  for(const [id,rows] of archiveIndex(items)){if(!blocked.has(id)){let newest=rows[0].entry;for(const r of rows){if(r.entry.at>newest.at){newest=r.entry;}}result.push(newest);}}
  return result;
}
