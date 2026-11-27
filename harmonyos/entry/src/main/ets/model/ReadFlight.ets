// In-flight deduplication only. No TTL, retry, authorization or completed-response cache.
export class ReadFlight<T> {
  private pending: Map<string, Promise<T>> = new Map<string, Promise<T>>();
  private starts: number = 0;
  private joins: number = 0;
  started(): number { return this.starts; }
  joined(): number { return this.joins; }
  async run(key: string, work: () => Promise<T>): Promise<T> {
    const existing = this.pending.get(key);
    if (existing) { this.joins++; return existing; }
    this.starts++;
    // Defer execution so the pending identity is registered before work runs.
    const task = Promise.resolve().then(work);
    this.pending.set(key,task);
    try { return await task; }
    finally { if (this.pending.get(key) === task) { this.pending.delete(key); } }
  }
}
