import { fileIo as fs } from '@kit.CoreFileKit';
import { SyncRunRecord, validSyncRun } from '../model/SyncRunState';
// Single diagnostic snapshot. Writers already hold the shared sync lease.
// No credentials, payloads or operation permissions are stored.
export function readSyncRun(directory:string,uuid:string,clientId:string):SyncRunRecord|undefined {
  try {
    const row=JSON.parse(fs.readTextSync(directory+'/sync-run-status')) as SyncRunRecord;
    return validSyncRun(row,uuid,clientId)?row:undefined;
  } catch(error){return undefined;}
}
export function saveSyncRun(directory:string,row:SyncRunRecord):void {
  if(!validSyncRun(row,row.uuid,row.clientId)){throw new Error('Invalid sync status');}
  const temporary=directory+'/sync-run-status.tmp';
  const file=fs.openSync(temporary,fs.OpenMode.WRITE_ONLY|fs.OpenMode.CREATE|fs.OpenMode.TRUNC);
  try{fs.writeSync(file.fd,JSON.stringify(row));fs.fsyncSync(file.fd);}finally{fs.closeSync(file.fd);}
  fs.renameSync(temporary,directory+'/sync-run-status');
}
