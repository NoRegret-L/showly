// Diagnostic state only: never an authorization, journal, or retry source.
export interface SyncRunRecord { uuid:string; clientId:string; phase:string; startedAt:number; updatedAt:number; lastImportAt:number; }
const phases:string[]=['import-library','import-archive','import-lists','import-ratings','recover','export-episodes','export-media','export-archive','export-lists','export-ratings','import-verified','export-reviewed','interrupted'];
export function validSyncRun(row:SyncRunRecord,uuid:string,clientId:string):boolean {
  return !!row && !!uuid && !!clientId && row.uuid===uuid && row.clientId===clientId && phases.includes(row.phase) &&
    Number.isSafeInteger(row.startedAt) && row.startedAt>0 && Number.isSafeInteger(row.updatedAt) && row.updatedAt>=row.startedAt &&
    Number.isSafeInteger(row.lastImportAt) && row.lastImportAt>=0 && row.lastImportAt<=row.updatedAt;
}
export function runPhaseLabel(phase:string):string {
  if(phase==='import-verified'){return '导入已核对';}
  if(phase==='export-reviewed'){return '导出核对结束（可能仍有待确认项）';}
  return '上次同步未完整结束；保留凭证，请先核对';
}
export class ManualRunOwner {
  private value?:SyncRunRecord;
  begin(uuid:string,clientId:string,previous:SyncRunRecord|undefined,phase:string,now:number):SyncRunRecord {
    if(this.value||!uuid||!clientId||!phases.includes(phase)){throw new Error('Invalid manual run');}
    this.value={uuid:uuid,clientId:clientId,phase:phase,startedAt:now,updatedAt:now,lastImportAt:previous&&validSyncRun(previous,uuid,clientId)?previous.lastImportAt:0};
    return this.value;
  }
  transition(phase:string,now:number):SyncRunRecord {
    const row=this.value;
    if(!row||!phases.includes(phase)){throw new Error('Manual run unavailable');}
    const updatedAt=Math.max(now,row.updatedAt);
    this.value={uuid:row.uuid,clientId:row.clientId,phase:phase,startedAt:row.startedAt,updatedAt:updatedAt,lastImportAt:phase==='import-verified'?updatedAt:row.lastImportAt};
    return this.value;
  }
  active():boolean {return this.value!==undefined;}
  end():void {this.value=undefined;}
}
