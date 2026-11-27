import { ProjectionInput, computeProjectionBatch } from '../model/ProjectionCompute';
@Concurrent
export function computeProjectionBatchTask(serialized: string): string {
  const inputs = JSON.parse(serialized) as ProjectionInput[];
  return JSON.stringify(computeProjectionBatch(inputs));
}
