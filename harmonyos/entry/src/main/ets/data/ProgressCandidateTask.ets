import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
import { taskpool } from '@kit.ArkTS';
import { CandidateBatch, CandidateResult, computeCandidates } from '../model/ProgressCandidates';
@Concurrent
export function progressCandidateTask(raw: string): string { return JSON.stringify(computeCandidates(JSON.parse(raw) as CandidateBatch)); }
export async function computeCandidateDisplay(batch: CandidateBatch, scope?: ReadCancel): Promise<CandidateResult[]> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(progressCandidateTask,JSON.stringify(batch)),scope)) as CandidateResult[]; }
  catch (error) { scope?.check(); return computeCandidates(batch); }
}
