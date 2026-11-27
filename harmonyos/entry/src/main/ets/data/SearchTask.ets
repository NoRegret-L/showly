import { taskpool } from '@kit.ArkTS';
import { Media } from '../model/Media';
import { SearchInput, searchRows } from '../model/SearchRules';
@Concurrent
export function searchTask(raw: string): string { return JSON.stringify(searchRows(JSON.parse(raw) as SearchInput)); }
export async function searchDisplay(input: SearchInput): Promise<Media[]> {
  try { return JSON.parse(await taskpool.execute(searchTask,JSON.stringify(input)) as string) as Media[]; }
  catch (error) { return searchRows(input); }
}
