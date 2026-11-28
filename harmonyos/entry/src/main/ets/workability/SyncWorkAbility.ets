import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { runBackgroundObservation } from '../data/BackgroundObservation';
import { SYNC_WORK_ID, recordScheduleWake } from '../data/SyncSchedule';
export default class SyncWorkAbility extends WorkSchedulerExtensionAbility {
  private run: number = 0;
  onWorkStart(work: workScheduler.WorkInfo): void {
    if (work.workId !== SYNC_WORK_ID) { return; }
    const ticket = ++this.run;
    try { recordScheduleWake(this.context.filesDir); } catch (error) {}
    runBackgroundObservation(this.context.filesDir,()=>ticket===this.run).catch(()=>{});
  }
  onWorkStop(work: workScheduler.WorkInfo): void { if (work.workId === SYNC_WORK_ID) { this.run++; } }
}
