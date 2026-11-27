// Page/module residency is determined by actual navigation and OS pressure,
// not by a guessed cache capacity, TTL or periodic eviction.
export class CacheLifecycle {
  private route: string='';
  private scope: string='';
  private serial: number=0;
  transition(route: string,scope: string): boolean {
    if (route===this.route && scope===this.scope) { return false; }
    this.route=route; this.scope=scope; this.serial++; return true;
  }
  invalidate(): void { this.serial++; }
  generation(): number { return this.serial; }
  current(token: number): boolean { return token===this.serial; }
}
export interface CacheResidency { search: boolean; progress: boolean; calendar: boolean; movieProgress: boolean; movieCalendar: boolean; collection: boolean; discover: boolean; }
export function cacheResidency(visible: boolean,tab: string,mode: string,progress: string,detail: boolean): CacheResidency {
  return {search:visible && tab==='search' && !detail,progress:visible && tab==='progress' && progress==='next' && mode==='show' && !detail,
    calendar:visible && tab==='progress' && progress==='calendar' && mode==='show' && !detail,
    movieProgress:visible && tab==='progress' && progress==='next' && mode==='movie' && !detail,
    movieCalendar:visible && tab==='progress' && progress==='calendar' && mode==='movie' && !detail,
    collection:visible && tab==='library' && !detail,discover:visible && tab==='discover' && !detail};
}
export class MemoryEvents {
  private listeners: Set<()=>void>=new Set<()=>void>();
  subscribe(listener: ()=>void): void { this.listeners.add(listener); }
  unsubscribe(listener: ()=>void): void { this.listeners.delete(listener); }
  notify(): void {
    for (const listener of this.listeners) { listener(); }
  }
}
export const memoryEvents: MemoryEvents=new MemoryEvents();
