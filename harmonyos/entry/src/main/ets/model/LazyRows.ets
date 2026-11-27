export class LazyRows<T> implements IDataSource {
  private rows: T[] = [];
  private ids: string[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): T { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  replace(rows: T[], ids: string[], keys: string[]): void {
    // Identity remains separate from content. For an isolated insertion or
    // deletion issue the native delta; complex reorder uses safe reload.
    const sameOrder = this.ids.length === ids.length && this.ids.every((id: string,i: number) => id === ids[i]);
    const previous = this.keys;
    const oldIds = this.ids;
    this.rows = rows;
    this.ids = ids;
    this.keys = keys;
    if (!sameOrder) {
      const added = ids.length === oldIds.length + 1;
      const removed = oldIds.length === ids.length + 1;
      if (added || removed) {
        const longer = added ? ids : oldIds;
        const shorter = added ? oldIds : ids;
        let index = 0;
        while (index < shorter.length && longer[index] === shorter[index]) { index++; }
        if (shorter.slice(index).every((id: string,i: number) => id === longer[index+i+1])) {
          for (const listener of this.listeners) {
            if (added) { listener.onDataAdd(index); } else { listener.onDataDelete(index); }
          }
          for (let i = 0; i < ids.length; i++) {
            if (added && i === index) { continue; }
            const old = added ? (i < index ? i : i-1) : (i < index ? i : i+1);
            if (previous[old] !== keys[i]) { for (const listener of this.listeners) { listener.onDataChange(i); } }
          }
          return;
        }
      }
      for (const listener of this.listeners) { listener.onDataReloaded(); }
      return;
    }
    for (let i = 0; i < keys.length; i++) {
      if (previous[i] !== keys[i]) {
        for (const listener of this.listeners) { listener.onDataChange(i); }
      }
    }
  }
}
