import { ReadCancel, ConsumerReadFlight } from './ReadFlight';
import { DiscoverRequest, DiscoverFeed, DiscoverItem, ANTICIPATED_LIMIT, discoverKey, discoverFresh, mixDiscover, validDiscoverFeed } from './DiscoverRules';
export interface DiscoverStorage {
  read(key: string): Promise<string>;
  write(key: string, raw: string): Promise<void>;
}
export interface ChartPage { items: DiscoverItem[]; page: number; pages: number; limit: number; count: number; }
export interface DiscoverTransport {
  read(client: string, request: DiscoverRequest, mode: string, page: number, limit: number, scope?: ReadCancel): Promise<ChartPage>;
}
export class DiscoverRead {
  private storage: DiscoverStorage;
  private transport: DiscoverTransport;
  private flights: ConsumerReadFlight<DiscoverFeed> = new ConsumerReadFlight<DiscoverFeed>();
  constructor(storage: DiscoverStorage, transport: DiscoverTransport) { this.storage=storage; this.transport=transport; }
  async cached(client: string, request: DiscoverRequest): Promise<DiscoverFeed | undefined> {
    try {
      const raw = await this.storage.read(discoverKey(client,request));
      const value = JSON.parse(raw) as DiscoverFeed;
      return validDiscoverFeed(value,request.kind) ? value : undefined;
    } catch (error) { return undefined; }
  }
  async load(client: string, request: DiscoverRequest, force: boolean, publish: (feed: DiscoverFeed, fresh: boolean) => void, consumer?: ReadCancel): Promise<DiscoverFeed> {
    const key = discoverKey(client,request);
    consumer?.check();
    const prior = await this.cached(client,request);
    consumer?.check();
    if (prior) {
      const fresh = discoverFresh(prior,Date.now());
      publish(prior,fresh);
      if (!force && fresh) { return prior; }
    }
    return this.flights.run(key,async (scope: ReadCancel): Promise<DiscoverFeed> => {
      // Recheck after joining async disk reads, avoiding a request after a
      // concurrent refresh already committed.
      if (!force) {
        const latest = await this.cached(client,request);
        scope.check();
        if (latest && discoverFresh(latest,Date.now())) { return latest; }
      }
      let items: DiscoverItem[];
      if (request.mode === 'trending') {
        const lists = await Promise.all([this.chart(client,request,'trending',request.limit,scope),this.chart(client,request,'anticipated',ANTICIPATED_LIMIT,scope)]);
        items = mixDiscover(lists[0],lists[1]);
      } else { items = mixDiscover(await this.chart(client,request,request.mode,request.limit,scope),[]); }
      scope.check();
      const feed: DiscoverFeed = {fetchedAt:Date.now(),items:items};
      if (!validDiscoverFeed(feed,request.kind)) { throw new Error('Invalid discovery feed'); }
      try { await this.storage.write(key,JSON.stringify(feed)); } catch (error) { /* optional public cache */ }
      return feed;
    },consumer);
  }
  private async chart(client: string, request: DiscoverRequest, mode: string, target: number, scope: ReadCancel): Promise<DiscoverItem[]> {
    const rows: DiscoverItem[] = [];
    let page = 1;
    let consumed = 0;
    let effective = 0;
    while (consumed < target) {
      scope.check();
      const part = await this.transport.read(client,request,mode,page,target,scope);
      scope.check();
      if (part.page !== page || !Number.isSafeInteger(part.pages) || part.pages < 0 ||
          !Number.isSafeInteger(part.limit) || part.limit < 1 || !Number.isSafeInteger(part.count) ||
          part.count < 0 || part.count > part.limit || (page > 1 && effective !== part.limit) ||
          (part.pages < page && !(page === 1 && part.pages === 0 && part.count === 0))) {
        throw new Error('Invalid discovery pagination');
      }
      effective = part.limit;
      // Keep original ranks until mixing; duplicates still occupy upstream positions.
      rows.push(...part.items.slice(0,Math.max(0,target-consumed)));
      consumed += part.count;
      if (page >= part.pages || part.count === 0) { break; }
      page++;
    }
    return rows;
  }
}
