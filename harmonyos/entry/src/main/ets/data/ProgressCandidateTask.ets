import { taskpool } from '@kit.ArkTS';
import { CandidateBatch, CandidateResult, computeCandidates } from '../model/ProgressCandidates';
@Concurrent
export function progressCandidateTask(raw: string): string { return JSON.stringify(computeCandidates(JSON.parse(raw) as CandidateBatch)); }
export async function computeCandidateDisplay(batch: CandidateBatch): Promise<CandidateResult[]> {
  try { return JSON.parse(await taskpool.execute(progressCandidateTask,JSON.stringify(batch)) as string) as CandidateResult[]; }
  catch (error) { return computeCandidates(batch); }
}
