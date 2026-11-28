import { fileIo as fs } from '@kit.CoreFileKit';
// Same stable inode in foreground and WorkScheduler processes; never unlink.
export function trySyncLease(directory:string):fs.File|undefined{
  let file:fs.File|undefined;
  try{if(!directory){return undefined;}file=fs.openSync(directory+'/trakt-sync-operation.lock',fs.OpenMode.READ_WRITE|fs.OpenMode.CREATE);file.tryLock(true);return file;}
  catch(error){if(file){try{fs.closeSync(file);}catch(failure){}}return undefined;}
}
export function releaseSyncLease(file:fs.File):void{try{file.unlock();}finally{fs.closeSync(file);}}
