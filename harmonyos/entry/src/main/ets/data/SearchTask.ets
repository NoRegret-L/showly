import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';
import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
import { taskpool } from '@kit.ArkTS';
import { Media } from '../model/Media';
import { SearchInput, SearchWire, packSearch, unpackSearch, searchRows } from '../model/SearchRules';
let searchTrace:number=0;
@Concurrent
export function searchTask(raw: string): string { return JSON.stringify(searchRows(unpackSearch(JSON.parse(raw) as SearchWire))); }
export async function searchDisplay(input: SearchInput, scope?: ReadCancel): Promise<Media[]> {
  scope?.check();
  const payload=JSON.stringify(packSearch(input)),trace=++searchTrace;
  let tracing=false;
  try{hiTraceMeter.startTrace('Showly.SearchTaskPool',trace);tracing=true;}catch(error){}
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(searchTask,payload),scope)) as Media[]; }
  catch (error) { scope?.check(); return searchRows(input); }
  finally{if(tracing){try{hiTraceMeter.finishTrace('Showly.SearchTaskPool',trace);}catch(error){}}}
}
