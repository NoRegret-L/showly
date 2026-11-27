import { taskpool } from '@kit.ArkTS';
import { ReadCancel, ReadCancelled } from '../model/ReadFlight';
// Native cancellation is best effort for a running task; its consumer
// detaches immediately and never invokes a synchronous fallback on cancel.
async function runNative(task: taskpool.Task): Promise<string> { return await taskpool.execute(task) as string; }
export async function executeDisplayTask(task: taskpool.Task, scope?: ReadCancel): Promise<string> {
  scope?.check();
  let stop: ()=>void=()=>{};
  const cancelled=new Promise<string>((resolve,reject)=>{
    stop=(): void=>{
      try { taskpool.cancel(task); } catch (error) {}
      reject(new ReadCancelled());
    };
  });
  scope?.subscribe(stop);
  try {
    const running=runNative(task);
    const result=await Promise.race([running,cancelled]);
    scope?.check();
    return result;
  } finally { scope?.unsubscribe(stop); }
}
