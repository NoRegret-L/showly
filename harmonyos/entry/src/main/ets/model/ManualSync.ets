export interface SyncDirection { importEnabled:boolean; exportEnabled:boolean; }
export function syncDirections(importEnabled:boolean,exportEnabled:boolean):SyncDirection|undefined{
  return importEnabled||exportEnabled?{importEnabled:importEnabled,exportEnabled:exportEnabled}:undefined;
}
export function syncDirectionLabel(value:SyncDirection):string {
  return value.importEnabled&&value.exportEnabled?'双向同步':value.importEnabled?'导入':'导出';
}
