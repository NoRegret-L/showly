import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
import { taskpool } from '@kit.ArkTS';
import { Media } from '../model/Media';
import { SearchInput, searchRows } from '../model/SearchRules';
@Concurrent
export function searchTask(raw: string): string { return JSON.stringify(searchRows(JSON.parse(raw) as SearchInput)); }
export async function searchDisplay(input: SearchInput, scope?: ReadCancel): Promise<Media[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(searchTask,JSON.stringify(input)),scope)) as Media[]; }
  catch (error) { scope?.check(); return searchRows(input); }
}
