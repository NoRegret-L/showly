import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
import { taskpool } from '@kit.ArkTS';
import { Media } from '../model/Media';
import { SearchInput, SearchWire, packSearch, unpackSearch, searchRows } from '../model/SearchRules';
@Concurrent
export function searchTask(raw: string): string { return JSON.stringify(searchRows(unpackSearch(JSON.parse(raw) as SearchWire))); }
export async function searchDisplay(input: SearchInput, scope?: ReadCancel): Promise<Media[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(searchTask,JSON.stringify(packSearch(input))),scope)) as Media[]; }
  catch (error) { scope?.check(); return searchRows(input); }
}
