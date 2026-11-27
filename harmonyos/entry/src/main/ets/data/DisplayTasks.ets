import { taskpool } from '@kit.ArkTS';
import { ListDiffInput, ListEdit, planListDiff } from '../model/ListDiff';
import { ProgressSortInput, MovieSortInput, CollectionSortInput, sortShowDisplay, sortMovieDisplay, sortCollectionDisplay } from '../model/DisplaySort';
import { ProgressRow } from '../model/ProgressRules';
import { PersonalLibraryRow } from '../model/PersonalLibrary';
@Concurrent
export function diffDisplayTask(raw: string): string {
  return JSON.stringify(planListDiff(JSON.parse(raw) as ListDiffInput));
}
@Concurrent
export function showDisplayTask(raw: string): string {
  return JSON.stringify(sortShowDisplay(JSON.parse(raw) as ProgressSortInput));
}
@Concurrent
export function movieDisplayTask(raw: string): string {
  return JSON.stringify(sortMovieDisplay(JSON.parse(raw) as MovieSortInput));
}
@Concurrent
export function collectionDisplayTask(raw: string): string {
  return JSON.stringify(sortCollectionDisplay(JSON.parse(raw) as CollectionSortInput));
}
export async function diffDisplay(input: ListDiffInput): Promise<ListEdit[]> {
  try { return JSON.parse(await taskpool.execute(diffDisplayTask,JSON.stringify(input)) as string) as ListEdit[]; }
  catch (error) { return planListDiff(input); }
}
export async function showDisplay(input: ProgressSortInput): Promise<ProgressRow[]> {
  try { return JSON.parse(await taskpool.execute(showDisplayTask,JSON.stringify(input)) as string) as ProgressRow[]; }
  catch (error) { return sortShowDisplay(input); }
}
export async function movieDisplay(input: MovieSortInput): Promise<PersonalLibraryRow[]> {
  try { return JSON.parse(await taskpool.execute(movieDisplayTask,JSON.stringify(input)) as string) as PersonalLibraryRow[]; }
  catch (error) { return sortMovieDisplay(input); }
}
export async function collectionDisplay(input: CollectionSortInput): Promise<PersonalLibraryRow[]> {
  try { return JSON.parse(await taskpool.execute(collectionDisplayTask,JSON.stringify(input)) as string) as PersonalLibraryRow[]; }
  catch (error) { return sortCollectionDisplay(input); }
}
