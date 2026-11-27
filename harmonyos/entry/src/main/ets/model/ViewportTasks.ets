import { Media } from './Media';
import { PresentationTask } from './MediaPresentation';
// Stable visibility identity and O(1) task aggregation. Visibility is supplied
// by the native component, never inferred from a fixed prefetch distance.
export class ViewportTasks {
  private active: Map<string, PresentationTask> = new Map<string, PresentationTask>();
  private counts: Map<string,number> = new Map<string,number>();
  static key(item: Media, season: number): string { return item.id + ':' + season; }
  clear(): void { this.active.clear(); this.counts.clear(); }
  update(item: Media, season: number, urls: string[], visible: boolean, slot: string = ''): boolean {
    const key = ViewportTasks.key(item,season);
    const id = key + ':' + slot;
    if (!visible) {
      if (!this.active.delete(id)) { return false; }
      const count = (this.counts.get(key) ?? 1) - 1;
      if (count > 0) { this.counts.set(key,count); } else { this.counts.delete(key); }
      return true;
    }
    if (this.active.has(id)) { return false; }
    this.active.set(id,{media:item,season:season,posterUrls:urls,artwork:true});
    this.counts.set(key,(this.counts.get(key) ?? 0)+1);
    return true;
  }
  has(item: Media, season: number): boolean { return this.counts.has(ViewportTasks.key(item,season)); }
  rows(): PresentationTask[] { return Array.from(this.active.values()); }
}
export function addPresentationTask(tasks: Map<string,PresentationTask>, item: Media, artwork: boolean,
  season: number, urls: string[]): void {
  const key = ViewportTasks.key(item,season);
  const found = tasks.get(key);
  if (found) {
    found.artwork = found.artwork || artwork;
    if (!found.posterUrls.length && urls.length) { found.posterUrls = urls; }
    return;
  }
  tasks.set(key,{media:item,season:season,posterUrls:urls,artwork:artwork});
}

// The input is the native visible index plus explicitly required business
// metadata. There is no dependency on the backing list length.
export function mergeViewportTasks(viewport: ViewportTasks, business: Map<string,PresentationTask>): PresentationTask[] {
  const tasks=new Map<string,PresentationTask>();
  for (const task of viewport.rows()) { addPresentationTask(tasks,task.media,true,task.season,task.posterUrls); }
  for (const task of business.values()) { addPresentationTask(tasks,task.media,false,task.season,task.posterUrls); }
  return Array.from(tasks.values());
}
