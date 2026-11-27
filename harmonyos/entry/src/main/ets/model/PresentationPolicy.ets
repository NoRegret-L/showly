import { ReadCancelled } from './ReadFlight';
import { PresentationTask } from './MediaPresentation';

// Only response status and protocol-defined retry information control a
// service barrier. No guessed timeout, retry interval or concurrency factor.
export class PresentationFailure extends Error {
  category: string;
  status: number;
  retryAt: number;
  constructor(category: string,status: number,retryAt: number=0) {
    super('Presentation '+category+' HTTP '+status);
    this.category=category; this.status=status; this.retryAt=retryAt;
  }
}
export function retryAfter(value: string,now: number): number {
  const raw=value.trim();
  if (/^[0-9]+$/.test(raw)) {
    const at=now+Number(raw)*1000;
    return Number.isSafeInteger(at) ? at : Number.MAX_SAFE_INTEGER;
  }
  if (!raw) { return Number.MAX_SAFE_INTEGER; }
  const at=Date.parse(raw);
  return Number.isFinite(at) ? Math.max(now,at) : Number.MAX_SAFE_INTEGER;
}
export function httpPresentationFailure(status: number,header: string,now: number): PresentationFailure {
  if (status===404 || status===410) { return new PresentationFailure('missing',status); }
  if (status===401 || status===403) { return new PresentationFailure('authorization',status); }
  if (status===429 || (status===503 && !!header.trim())) { return new PresentationFailure('limited',status,retryAfter(header,now)); }
  return new PresentationFailure('temporary',status);
}
export function presentationFailure(error: Error): PresentationFailure {
  return error instanceof PresentationFailure ? error : new PresentationFailure('temporary',0);
}
export class PresentationGate {
  private barriers: Map<string,PresentationFailure>=new Map<string,PresentationFailure>();
  check(service: string,now: number): void {
    const error=this.barriers.get(service);
    if (!error) { return; }
    if (error.category==='limited' && now>=error.retryAt) { this.barriers.delete(service); return; }
    throw error;
  }
  record(service: string,error: PresentationFailure,auth: boolean): void {
    if (error.category!=='limited' && !(auth && error.category==='authorization')) { return; }
    const old=this.barriers.get(service);
    if (old?.category==='limited' && (error.category!=='limited' || old.retryAt>error.retryAt)) { return; }
    this.barriers.set(service,error);
  }
  // Explicit retry can probe a missing Retry-After or changed authorization.
  // A known server deadline is never shortened by refresh or navigation.
  manualProbe(): void {
    for (const key of this.barriers.keys()) {
      const error=this.barriers.get(key);
      if (error && (error.category==='authorization' || error.retryAt===Number.MAX_SAFE_INTEGER)) { this.barriers.delete(key); }
    }
  }
}
export class PresentationAttempts {
  private failures: Map<string,PresentationFailure>=new Map<string,PresentationFailure>();
  private epoch: number=0;
  generation(): number { return this.epoch; }
  allowed(key: string,now: number): boolean {
    const error=this.failures.get(key);
    if (!error) { return true; }
    if (error.category==='limited' && now>=error.retryAt) { this.failures.delete(key); return true; }
    return false;
  }
  fail(key: string,error: PresentationFailure,generation: number): void {
    if (generation===this.epoch) { this.failures.set(key,error); }
  }
  // A network recovery or explicit retry does not change the transport gate.
  retry(): void { this.epoch++; this.failures.clear(); }
}
export function presentationTaskKey(task: PresentationTask,lane: string): string {
  return lane==='season' || lane==='local' ? task.media.id+':'+task.season : task.media.id;
}
// The actual native visible set is the only priority signal. A task required
// for nonvisible metadata remains behind all visible tasks.
export function prioritizePresentation(tasks: PresentationTask[]): PresentationTask[] {
  const visible: PresentationTask[]=[];
  const other: PresentationTask[]=[];
  for (const task of tasks) { (task.artwork ? visible : other).push(task); }
  return visible.concat(other);
}
export async function runPresentationPass(tasks: PresentationTask[],lane: string,attempts: PresentationAttempts,
  scope: string,current: () => boolean,eligible: (task: PresentationTask) => boolean,
  work: (task: PresentationTask) => Promise<void>,publish: () => void,report: (error: PresentationFailure) => void): Promise<void> {
  const seen=new Set<string>();
  for (const task of prioritizePresentation(tasks)) {
    if (!current()) { return; }
    if (!eligible(task)) { continue; }
    const key=JSON.stringify([scope,lane,presentationTaskKey(task,lane)]);
    if (seen.has(key) || !attempts.allowed(key,Date.now())) { continue; }
    seen.add(key);
    const generation=attempts.generation();
    try { await work(task); }
    catch (error) {
      if (error instanceof ReadCancelled) { continue; }
      const failure=presentationFailure(error as Error);
      // A scroll or route change suppresses publication, not the failure of
      // the resource in its captured scope. An explicit retry wins a race.
      attempts.fail(key,failure,generation);
      if (current()) { report(failure); }
    }
    if (current()) { publish(); }
  }
}
