import { Media } from './Media';
import { FullEpisodeCatalog } from './ShowCatalog';
import { matchesText } from './MediaPresentation';
export interface CalendarSource { media: Media; full?: FullEpisodeCatalog; watchedIds?: number[]; queued: boolean; }
export interface CalendarInput { source: CalendarSource; release: string; }
export interface CalendarAtom { key: string; media: Media; episodeId: number; season: number; number: number; title: string; order: number; state: string; queued: boolean; synthetic: boolean; }
export interface CalendarEntry { key: string; media: Media; episodeId: number; season: number; number: number; episodeTitle: string; order: number; day: string; time: string; state: string; queued: boolean; synthetic: boolean; group: string; header: string; }
export interface CalendarText { key: string; title: string; }
export interface CalendarBuilt { id: string; atoms: CalendarAtom[]; }
export interface CalendarPlan { pending: CalendarInput[]; retained: CalendarAtom[]; }
export interface CalendarJobInput { plan: CalendarPlan; now: number; mode: string; premieres: boolean; query: string; hidden: string[]; members: string[]; titles: CalendarText[]; episodes: CalendarText[]; }
export interface CalendarJobOutput { built: CalendarBuilt[]; entries: CalendarEntry[]; }
export function calendarDay(date: Date): string {
  return date.getFullYear().toString().padStart(4,'0')+'-'+(date.getMonth()+1).toString().padStart(2,'0')+'-'+date.getDate().toString().padStart(2,'0');
}
function start(date: Date): Date { return new Date(date.getFullYear(),date.getMonth(),date.getDate()); }
function days(date: Date,n: number): Date { return new Date(date.getFullYear(),date.getMonth(),date.getDate()+n); }
export function calendarMonthBefore(date: Date,n: number): Date {
  const first = new Date(date.getFullYear(),date.getMonth()-n,1);
  return new Date(first.getFullYear(),first.getMonth(),Math.min(date.getDate(),new Date(first.getFullYear(),first.getMonth()+1,0).getDate()));
}
export function calendarClockKey(now: number): string { const d=new Date(now); return calendarDay(d)+':'+d.getTimezoneOffset(); }
export function calendarExpiry(now: number): number { return days(start(new Date(now)),1).getTime(); }
export function calendarAtoms(input: CalendarInput): CalendarAtom[] {
  const s=input.source;
  const result: CalendarAtom[]=[];
  const watched=s.watchedIds === undefined ? undefined : new Set<number>(s.watchedIds);
  let premiere=false;
  let first='';
  for (const season of s.full?.seasons ?? []) {
    if (season.number <= 0) { continue; }
    if (season.number === 1) { first=season.firstAired; }
    for (const ep of season.episodes) {
      const order=Date.parse(ep.firstAired);
      if (ep.season <= 0 || ep.number <= 0 || !Number.isFinite(order)) { continue; }
      if (ep.season === 1 && ep.number === 1) { premiere=true; }
      result.push({key:'episode:'+ep.id,media:s.media,episodeId:ep.id,season:ep.season,number:ep.number,title:ep.title,order:order,
        state:watched === undefined ? 'unknown' : watched.has(ep.id) ? 'watched' : 'unwatched',queued:s.queued,synthetic:false});
    }
  }
  // Never synthesize a positive episode ID or a duplicate known premiere.
  if (s.queued && !premiere) {
    const release=Date.parse(input.release);
    const order=Number.isFinite(release) ? release : Date.parse(first);
    if (Number.isFinite(order)) { result.push({key:'premiere:'+s.media.id,media:s.media,episodeId:0,season:1,number:1,title:'',order:order,state:'unknown',queued:true,synthetic:true}); }
  }
  return result;
}
interface CachedAtoms { input: CalendarInput; atoms: CalendarAtom[]; }
export class CalendarIndex {
  private scope: string='';
  private entries: Map<string,CachedAtoms>=new Map<string,CachedAtoms>();
  begin(scope: string): void { if (scope!==this.scope) { this.clear(); this.scope=scope; } }
  clear(): void { this.scope=''; this.entries.clear(); }
  plan(inputs: CalendarInput[]): CalendarPlan {
    const pending: CalendarInput[]=[];
    const retained: CalendarAtom[]=[];
    for (const input of inputs) {
      const s=input.source, old=this.entries.get(s.media.id);
      if (old && old.input.source.full===s.full && old.input.source.watchedIds===s.watchedIds &&
          old.input.source.queued===s.queued && old.input.release===input.release &&
          old.input.source.media.title===s.media.title && old.input.source.media.year===s.media.year) {
        for (const atom of old.atoms) { retained.push(atom); }
      } else { pending.push(input); }
    }
    return {pending:pending,retained:retained};
  }
  commit(inputs: CalendarInput[],built: CalendarBuilt[]): void {
    const byId=new Map<string,CalendarAtom[]>();
    for (const row of built) { byId.set(row.id,row.atoms); }
    const keep=new Set<string>();
    for (const input of inputs) {
      const id=input.source.media.id; keep.add(id);
      const atoms=byId.get(id);
      if (atoms!==undefined) { this.entries.set(id,{input:input,atoms:atoms}); }
    }
    for (const id of this.entries.keys()) { if (!keep.has(id)) { this.entries.delete(id); } }
  }
}
export function calendarGroup(date: Date,today: Date,mode: string): string {
  const d=start(date).getTime(), t=start(today);
  if (mode==='recent') {
    if (d===days(t,-1).getTime()) { return '昨天'; }
    if (d>days(t,-8).getTime()) { return '最近7天'; }
    if (d>days(t,-31).getTime()) { return '最近30天'; }
    if (d>days(t,-91).getTime()) { return '最近90天'; }
    return '更早（3个月内）';
  }
  if (d===t.getTime()) { return '今天'; }
  if (d===days(t,1).getTime()) { return '明天'; }
  const monday=days(t,(8-t.getDay())%7 || 7);
  if (d<monday.getTime()) { return '本周'; }
  if (d<days(monday,7).getTime()) { return '下周'; }
  if (date.getFullYear()===t.getFullYear() && date.getMonth()===t.getMonth()) { return '本月'; }
  const next=new Date(t.getFullYear(),t.getMonth()+1,1);
  if (date.getFullYear()===next.getFullYear() && date.getMonth()===next.getMonth()) { return '下月'; }
  return date.getFullYear()===t.getFullYear() ? '今年' : '以后';
}
export function calendarJob(input: CalendarJobInput): CalendarJobOutput {
  const built=input.plan.pending.map((x: CalendarInput): CalendarBuilt=>({id:x.source.media.id,atoms:calendarAtoms(x)}));
  const all: CalendarAtom[]=[...input.plan.retained];
  for (const row of built) { for (const atom of row.atoms) { all.push(atom); } }
  const hidden=new Set<string>(input.hidden), members=new Set<string>(input.members);
  const titles=new Map<string,string>(), episodes=new Map<string,string>();
  for (const x of input.titles) { titles.set(x.key,x.title); }
  for (const x of input.episodes) { episodes.set(x.key,x.title); }
  const today=start(new Date(input.now)), lower=calendarMonthBefore(today,3).getTime(), recent=input.mode==='recent';
  const filtered=all.filter((x: CalendarAtom)=>{
    if (hidden.has(x.media.id) || !members.has(x.media.id) || (input.premieres && x.number!==1)) { return false; }
    const d=start(new Date(x.order)).getTime();
    return recent ? d<today.getTime() && d>lower : d>=today.getTime();
  });
  filtered.sort((a: CalendarAtom,b: CalendarAtom)=>(recent?b.order-a.order:a.order-b.order)||
    Number(b.media.id.substring(5))-Number(a.media.id.substring(5))||(recent?b.number-a.number:a.number-b.number)||a.key.localeCompare(b.key));
  const entries: CalendarEntry[]=[];
  for (const x of filtered) {
    const date=new Date(x.order), day=calendarDay(date);
    const time=date.getHours().toString().padStart(2,'0')+':'+date.getMinutes().toString().padStart(2,'0');
    if (!matchesText(input.query,x.media.title,titles.get(x.media.id)??'') &&
        !matchesText(input.query,x.title,episodes.get(x.media.id+':'+x.season+':'+x.episodeId)??'') &&
        !matchesText(input.query,day+' '+time,'')) { continue; }
    const group=calendarGroup(date,today,input.mode);
    const header=!entries.length || entries[entries.length-1].group!==group ? group : '';
    entries.push({key:x.key,media:x.media,episodeId:x.episodeId,season:x.season,number:x.number,episodeTitle:x.title,order:x.order,
      day:day,time:time,state:x.state,queued:x.queued,synthetic:x.synthetic,group:group,header:header});
  }
  return {built:built,entries:entries};
}
export function calendarPageRows(rows: CalendarEntry[],page: number,size: number): CalendarEntry[] {
  const from=(Math.max(1,Math.min(page,Math.max(1,Math.ceil(rows.length/size))))-1)*size;
  const result=rows.slice(from,from+size);
  if (result.length && !result[0].header) {
    const r=result[0];
    result[0]={key:r.key,media:r.media,episodeId:r.episodeId,season:r.season,number:r.number,episodeTitle:r.episodeTitle,order:r.order,
      day:r.day,time:r.time,state:r.state,queued:r.queued,synthetic:r.synthetic,group:r.group,header:r.group};
  }
  return result;
}
export function calendarTitleHidden(row: CalendarEntry,protect: boolean): boolean { return protect && row.state!=='watched' && !row.synthetic; }
