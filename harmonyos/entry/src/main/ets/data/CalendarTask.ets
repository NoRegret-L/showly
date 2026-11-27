import { ReadCancel } from '../model/ReadFlight';
import { executeDisplayTask } from './CancelableDisplayTask';
import { taskpool } from '@kit.ArkTS';
import { CalendarJobInput, CalendarJobOutput, calendarJob } from '../model/CalendarRules';
@Concurrent
export function calendarTask(raw: string): string { return JSON.stringify(calendarJob(JSON.parse(raw) as CalendarJobInput)); }
export async function calendarDisplay(input: CalendarJobInput, scope?: ReadCancel): Promise<CalendarJobOutput> {
  scope?.check();
  try { return JSON.parse(await executeDisplayTask(new taskpool.Task(calendarTask,JSON.stringify(input)),scope)) as CalendarJobOutput; }
  catch (error) { scope?.check(); return calendarJob(input); }
}
