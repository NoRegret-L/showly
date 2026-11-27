import { ReadCancel } from './ReadFlight';
// A single active detail owns one public catalog snapshot. It never survives
// an account/route change or native memory pressure, and is not a write permit.
export class DetailSession<T> {
  private scope: string='';
  private id: string='';
  private revision: number=-1;
  private value?: T;
  private signal: ReadCancel=new ReadCancel();
  private serial: number=0;
  begin(scope: string,id: string): number {
    this.clear(); this.scope=scope; this.id=id; return this.serial;
  }
  token(): number { return this.serial; }
  current(token: number,scope: string,id: string): boolean {
    return this.serial===token && this.scope===scope && this.id===id && !this.signal.cancelled();
  }
  consumer(): ReadCancel { return this.signal; }
  remember(token: number,scope: string,id: string,revision: number,value: T): boolean {
    if (!this.current(token,scope,id)) { return false; }
    this.revision=revision; this.value=value; return true;
  }
  read(scope: string,id: string,revision: number): T | undefined {
    return !this.signal.cancelled() && this.scope===scope && this.id===id && this.revision===revision ? this.value : undefined;
  }
  clear(): void {
    this.signal.cancel(); this.signal=new ReadCancel(); this.serial++;
    this.scope=''; this.id=''; this.revision=-1; this.value=undefined;
  }
}
export interface SeasonSummary { number: number; completed: number; count: number; }
export interface SeasonSlice<T> { number: number; completed: number; episodes: T[]; }
export function summarizeSeasons<T>(seasons: SeasonSlice<T>[]): SeasonSummary[] {
  return seasons.map((season: SeasonSlice<T>): SeasonSummary=>({number:season.number,completed:season.completed,count:season.episodes.length}));
}
