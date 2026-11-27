import { taskpool } from '@kit.ArkTS';
import { CalendarJobInput, CalendarJobOutput, calendarJob } from '../model/CalendarRules';
@Concurrent
export function calendarTask(raw: string): string { return JSON.stringify(calendarJob(JSON.parse(raw) as CalendarJobInput)); }
export async function calendarDisplay(input: CalendarJobInput): Promise<CalendarJobOutput> {
  try { return JSON.parse(await taskpool.execute(calendarTask,JSON.stringify(input)) as string) as CalendarJobOutput; }
  catch (error) { return calendarJob(input); }
}
