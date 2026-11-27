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

export class ReadCancelled extends Error { constructor() { super('Read cancelled'); } }

/** A cancel signal belongs to one consumer, not to an account or shared flight. */
export class ReadCancel {
  private stopped: boolean=false;
  private listeners: Set<()=>void>=new Set<()=>void>();
  cancelled(): boolean { return this.stopped; }
  check(): void { if (this.stopped) { throw new ReadCancelled(); } }
  subscribe(listener: ()=>void): void { if (this.stopped) { listener(); } else { this.listeners.add(listener); } }
  unsubscribe(listener: ()=>void): void { this.listeners.delete(listener); }
  cancel(): void {
    if (this.stopped) { return; }
    this.stopped=true;
    const listeners=Array.from(this.listeners); this.listeners.clear();
    for (const listener of listeners) { try { listener(); } catch (error) {} }
  }
}
class SharedRead<T> {
  readonly scope: ReadCancel=new ReadCancel();
  consumers: number=0;
  task: Promise<T>;
  constructor(work: (scope: ReadCancel)=>Promise<T>) {
    this.task=Promise.resolve().then(()=>{ this.scope.check(); return work(this.scope); });
  }
}
/** Reference-counted transport. Never use for durable writes or observations. */
export class ConsumerReadFlight<T> {
  private pending: Map<string,SharedRead<T>>=new Map<string,SharedRead<T>>();
  async run(key: string,work: (scope: ReadCancel)=>Promise<T>,consumer?: ReadCancel): Promise<T> {
    consumer?.check();
    let existing=this.pending.get(key);
    if (!existing) { existing=new SharedRead<T>(work); this.pending.set(key,existing); }
    const flight=existing;
    flight.consumers++;
    let released=false;
    const release=(): void=>{
      if (released) { return; }
      released=true; flight.consumers--;
      if (!flight.consumers && this.pending.get(key)===flight) {
        this.pending.delete(key); flight.scope.cancel();
      }
    };
    return new Promise<T>((resolve,reject)=>{
      const stop=(): void=>{ release(); reject(new ReadCancelled()); };
      consumer?.subscribe(stop);
      flight.task.then((value: T)=>{
        consumer?.unsubscribe(stop); release();
        if (consumer?.cancelled()) { reject(new ReadCancelled()); } else { resolve(value); }
      }).catch((error: Error)=>{
        consumer?.unsubscribe(stop); release(); reject(error);
      });
    });
  }
}
