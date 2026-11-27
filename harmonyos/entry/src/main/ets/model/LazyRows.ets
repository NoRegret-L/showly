import { ScrollRows } from './ScrollAnchor';
import { ListDiffInput, ListEdit, planListDiff, sameListOrder } from './ListDiff';
export class LazyRows<T> implements IDataSource, ScrollRows {
  private rows: T[] = [];
  private ids: string[] = [];
  private keys: string[] = [];
  private keyById: Map<string,string> = new Map<string,string>();
  private listeners: DataChangeListener[] = [];
  private revision: number = 0;
  totalCount(): number { return this.rows.length; }
  idAt(index: number): string { return this.ids[index] ?? ''; }
  indexOfId(id: string): number { return this.ids.indexOf(id); }
  getData(index: number): T { return this.rows[index]; }
  keyFor(id: string): string { return id + ':' + (this.keyById.get(id) ?? ''); }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  private input(ids: string[], keys: string[]): ListDiffInput {
    return {oldIds:[...this.ids],oldKeys:[...this.keys],ids:[...ids],keys:[...keys]};
  }
  replace(rows: T[], ids: string[], keys: string[]): void {
    this.revision++;
    this.apply(rows,ids,keys,planListDiff(this.input(ids,keys)));
  }
  async submit(rows: T[], ids: string[], keys: string[], differ: (input: ListDiffInput) => Promise<ListEdit[]>,
    current: () => boolean): Promise<boolean> {
    const revision = ++this.revision;
    const input = this.input(ids,keys);
    // No worker transfer for a content-only delta or empty list transition.
    const structural = input.oldIds.length > 0 && ids.length > 0 && !sameListOrder(input.oldIds,ids);
    const edits = structural ? await differ(input) : planListDiff(input);
    if (revision !== this.revision || !current()) { return false; }
    this.apply(rows,ids,keys,edits);
    return true;
  }
  private apply(rows: T[], ids: string[], keys: string[], edits: ListEdit[]): void {
    if (edits.some((edit: ListEdit) => edit.kind === 'reload')) {
      this.rows = [...rows]; this.ids = [...ids]; this.keys = [...keys];
      this.keyById.clear();
      ids.forEach((id: string,i: number) => { this.keyById.set(id,keys[i]); });
      for (const listener of this.listeners) { listener.onDataReloaded(); }
      return;
    }
    // Source is updated before each native notification. A moved row retains
    // its committed key until the separate content change is applied.
    for (const edit of edits) {
      const i = edit.index;
      if (edit.kind === 'delete') {
        this.keyById.delete(this.ids[i]);
        this.rows.splice(i,1); this.ids.splice(i,1); this.keys.splice(i,1);
        for (const listener of this.listeners) { listener.onDataDelete(i); }
      } else if (edit.kind === 'add') {
        this.rows.splice(i,0,rows[i]); this.ids.splice(i,0,ids[i]); this.keys.splice(i,0,keys[i]);
        this.keyById.set(ids[i],keys[i]);
        for (const listener of this.listeners) { listener.onDataAdd(i); }
      } else if (edit.kind === 'move') {
        const j = edit.to;
        const row = this.rows[i]; this.rows[i] = this.rows[j]; this.rows[j] = row;
        const id = this.ids[i]; this.ids[i] = this.ids[j]; this.ids[j] = id;
        const key = this.keys[i]; this.keys[i] = this.keys[j]; this.keys[j] = key;
        for (const listener of this.listeners) { listener.onDataMove(i,j); }
      } else if (edit.kind === 'change') {
        this.rows[i] = rows[i]; this.keys[i] = keys[i]; this.keyById.set(ids[i],keys[i]);
        for (const listener of this.listeners) { listener.onDataChange(i); }
      }
    }
    // Non-rendered business fields may have changed even with the same key.
    this.rows = [...rows]; this.ids = [...ids]; this.keys = [...keys];
  }
}
