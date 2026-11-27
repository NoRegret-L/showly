import { ProjectionInput, computeProjection } from '../model/ProjectionCompute';

@Concurrent
export function computeProjectionTask(serialized: string): string {
  const input = JSON.parse(serialized) as ProjectionInput;
  return JSON.stringify(computeProjection(input));
}
