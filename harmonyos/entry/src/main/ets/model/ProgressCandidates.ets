import { ProgressSource, ProgressPreferences, ProgressFlag, ProgressRow, selectProgress } from './ProgressRules';
import { progressExpiry } from './ReadModelCache';
export interface CandidateInput {
  source: ProgressSource; stateKey?: string; catalogKey?: string; flag?: ProgressFlag;
}
export interface CandidateResult { id: string; row?: ProgressRow; until: number; }
export interface CandidatePlan { inputs: CandidateInput[]; pending: CandidateInput[]; reused: CandidateResult[]; prefs: ProgressPreferences; now: number; }
export interface CandidateBatch { inputs: CandidateInput[]; prefs: ProgressPreferences; now: number; }
interface CandidateEntry { input: CandidateInput; prefsKey: string; from: number; result: CandidateResult; }
export interface CandidateOutput { rows: ProgressRow[]; expiry: number; }
function prefsKey(prefs: ProgressPreferences): string { return JSON.stringify([prefs.strategy,prefs.count,prefs.days,prefs.newAtTop]); }
function sameInput(a: CandidateInput,b: CandidateInput): boolean {
  const keys=a.stateKey!==undefined && b.stateKey!==undefined && a.catalogKey!==undefined && b.catalogKey!==undefined;
  return (keys ? a.stateKey===b.stateKey && a.catalogKey===b.catalogKey : a.source===b.source) &&
    a.source.media.id===b.source.media.id && a.source.randomOrder===b.source.randomOrder &&
    (a.flag?.pinned ?? false)===(b.flag?.pinned ?? false) && (a.flag?.held ?? false)===(b.flag?.held ?? false);
}
export function computeCandidates(batch: CandidateBatch): CandidateResult[] {
  return batch.inputs.map((input: CandidateInput): CandidateResult=>({
    id:input.source.media.id,row:selectProgress(input.source,batch.prefs,input.flag ? [input.flag] : [],batch.now),
    until:progressExpiry([input.source],batch.prefs,batch.now)
  }));
}
// Only proven effective source keys are reusable. No time-to-live heuristic.
// A negative (no next episode) result is cached with the same time fence.
export class ProgressCandidateIndex {
  private scope: string='';
  private entries: Map<string,CandidateEntry>=new Map<string,CandidateEntry>();
  begin(scope: string): void { if (scope!==this.scope) { this.clear(); this.scope=scope; } }
  clear(): void { this.scope=''; this.entries.clear(); }
  remove(id: string): void { this.entries.delete(id); }
  retain(ids: Set<string>): void { for (const id of this.entries.keys()) { if (!ids.has(id)) { this.entries.delete(id); } } }
  plan(inputs: CandidateInput[],prefs: ProgressPreferences,now: number): CandidatePlan {
    const pending: CandidateInput[]=[];
    const reused: CandidateResult[]=[];
    const key=prefsKey(prefs);
    for (const input of inputs) {
      const entry=this.entries.get(input.source.media.id);
      if (entry && entry.prefsKey===key && now>=entry.from && now<entry.result.until && sameInput(entry.input,input)) { reused.push(entry.result); }
      else { pending.push(input); }
    }
    return {inputs:inputs,pending:pending,reused:reused,prefs:prefs,now:now};
  }
  commit(plan: CandidatePlan,built: CandidateResult[]): CandidateOutput {
    if (built.length!==plan.pending.length) { throw new Error('Incomplete progress candidate batch'); }
    const byId=new Map<string,CandidateResult>();
    for (const result of plan.reused) { byId.set(result.id,result); }
    for (let i=0;i<built.length;i++) {
      const result=built[i];
      const input=plan.pending[i];
      if (result.id!==input.source.media.id || !Number.isSafeInteger(result.until) || result.until<=plan.now) { throw new Error('Invalid progress candidate'); }
      byId.set(result.id,result);
    }
    const key=prefsKey(plan.prefs);
    for (let i=0;i<built.length;i++) { this.entries.set(built[i].id,{input:plan.pending[i],prefsKey:key,from:plan.now,result:built[i]}); }
    const rows: ProgressRow[]=[];
    let expiry=Number.MAX_SAFE_INTEGER;
    for (const input of plan.inputs) {
      const result=byId.get(input.source.media.id);
      if (!result) { throw new Error('Missing progress candidate'); }
      expiry=Math.min(expiry,result.until);
      if (result.row) { rows.push(result.row); }
    }
    return {rows:rows,expiry:expiry};
  }
}
