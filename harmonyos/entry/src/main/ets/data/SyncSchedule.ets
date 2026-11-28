import { workScheduler } from '@kit.BackgroundTasksKit';
import { fileIo as fs } from '@kit.CoreFileKit';

// System-scheduled durable wake evidence only. Never contains an account,
// token, consent, or mutation; foreground must independently verify them.
export const SYNC_WORK_ID: number = 94;
export const SYNC_PERIODS: number[] = [0,1,3,6,24,72,168];
function workInfo(hours: number): workScheduler.WorkInfo {
  return { workId: SYNC_WORK_ID, bundleName: 'com.noregret.showly.harmony',
    abilityName: 'SyncWorkAbility', networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isRepeat: true, repeatCycleTime: hours * 60 * 60 * 1000, isPersisted: true };
}
export async function scheduledHours(): Promise<number> {
  const works = await workScheduler.obtainAllWorks();
  for (const work of works) {
    if (work.workId === SYNC_WORK_ID && work.abilityName === 'SyncWorkAbility') {
      const hours = (work.repeatCycleTime ?? 0) / 3600000;
      return SYNC_PERIODS.includes(hours) ? hours : 0;
    }
  }
  return 0;
}
export async function setScheduledHours(hours: number): Promise<void> {
  if (!SYNC_PERIODS.includes(hours)) { throw new Error('Invalid schedule'); }
  const works = await workScheduler.obtainAllWorks();
  for (const work of works) {
    if (work.workId === SYNC_WORK_ID && work.abilityName === 'SyncWorkAbility') {
      workScheduler.stopWork(work, true);
    }
  }
  if (hours > 0) { workScheduler.startWork(workInfo(hours)); }
}
export function recordScheduleWake(directory: string): void {
  const file = fs.openSync(directory + '/sync-scheduled-wake', fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, Date.now().toString()); fs.fsyncSync(file.fd); }
  finally { fs.closeSync(file); }
}
export function lastScheduleWake(directory: string): number {
  try {
    const value = Number(fs.readTextSync(directory + '/sync-scheduled-wake'));
    return Number.isSafeInteger(value) && value > 0 ? value : 0;
  } catch (error) { return 0; }
}
