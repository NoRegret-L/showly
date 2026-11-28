import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { SYNC_WORK_ID, recordScheduleWake } from '../data/SyncSchedule';
export default class SyncWorkAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    if (work.workId !== SYNC_WORK_ID) { return; }
    // No credential access, network mutation, or authoritative store access.
    try { recordScheduleWake(this.context.filesDir); } catch (error) {}
  }
  onWorkStop(work: workScheduler.WorkInfo): void {}
}
