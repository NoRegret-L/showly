import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
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
export async function diffDisplay(input: ListDiffInput, scope?: ReadCancel): Promise<ListEdit[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(diffDisplayTask,JSON.stringify(input)),scope)) as ListEdit[]; }
  catch (error) { scope?.check(); return planListDiff(input); }
}
export async function showDisplay(input: ProgressSortInput, scope?: ReadCancel): Promise<ProgressRow[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(showDisplayTask,JSON.stringify(input)),scope)) as ProgressRow[]; }
  catch (error) { scope?.check(); return sortShowDisplay(input); }
}
export async function movieDisplay(input: MovieSortInput, scope?: ReadCancel): Promise<PersonalLibraryRow[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(movieDisplayTask,JSON.stringify(input)),scope)) as PersonalLibraryRow[]; }
  catch (error) { scope?.check(); return sortMovieDisplay(input); }
}
export async function collectionDisplay(input: CollectionSortInput, scope?: ReadCancel): Promise<PersonalLibraryRow[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(collectionDisplayTask,JSON.stringify(input)),scope)) as PersonalLibraryRow[]; }
  catch (error) { scope?.check(); return sortCollectionDisplay(input); }
}
