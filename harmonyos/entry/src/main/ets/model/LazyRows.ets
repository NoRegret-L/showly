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
    const sameOrder = this.ids.length === ids.length && this.ids.every((id: string, i: number) => id === ids[i]);
    const previous = this.keys;
    this.rows = rows;
    this.ids = ids;
    this.keys = keys;
    if (!sameOrder) {
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
