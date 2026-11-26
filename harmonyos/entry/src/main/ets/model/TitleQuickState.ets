import { Media } from './Media';
import { MediaRecord, setMediaIntent, followShow } from './MediaState';
import { CommonEntry, classifyThreeWay } from './ThreeWay';

export interface TitleChange {
  id: string;
  domain: string;
  value: string;
}
export interface TitleEdit {
  records: MediaRecord[];
  changes: TitleChange[];
}
export interface TitleConsent {
  uuid: string;
  clientId: string;
  epoch: number;
}
export interface TitleIntent {
  seq: number;
  id: string;
  domain: string;
  value: string;
  epoch: number;
  operationSeq: number;
  watchedAt: string;
  state: string;
}
export function titleValue(record: MediaRecord, domain: string): string {
  return domain === 'movie' ? record.movieState : record.watchlistState;
}
export function titleEdit(records: MediaRecord[], item: Media, domain: string, value: string): TitleEdit {
  let next = domain === 'follow' ? followShow(records, item) : setMediaIntent(records, item, domain, value);
  const changes: TitleChange[] = [{ id: item.id, domain: domain === 'follow' ? 'watchlist' : domain,
    value: domain === 'follow' ? 'no' : value }];
  // Upstream MyMoviesRepository.insert removes the movie from watchlist.
  if (domain === 'movie' && value === 'yes') {
    next = setMediaIntent(next, item, 'watchlist', 'no');
    changes.push({ id: item.id, domain: 'watchlist', value: 'no' });
  }
  return { records: next, changes: changes };
}
export function autoEligible(domain: string, value: string): boolean {
  return domain === 'watchlist' || (domain === 'movie' && value === 'yes');
}
export function quickDisposition(intent: TitleIntent, local: string, remote: boolean, operation: string,
  priorSeq: number, priorState: string, priorAction: string, epoch: number): string {
  if (intent.state !== 'open' || intent.epoch <= 0 || intent.epoch !== epoch || local !== intent.value ||
      !autoEligible(intent.domain, intent.value)) { return 'review'; }
  if (priorState === 'pending') { return 'readback'; }
  const action = intent.value === 'yes' ? 'add' : 'remove';
  if (priorSeq !== intent.operationSeq) {
    return priorSeq > intent.operationSeq && priorState === 'verified' && priorAction === action ? 'settled' : 'review';
  }
  if (remote === (intent.value === 'yes')) { return 'matched'; }
  return operation === action ? 'send' : 'review';
}
export function canAdoptTitle(local: string, remote: boolean, base: CommonEntry | undefined,
  intent: TitleIntent | undefined, pending: boolean): boolean {
  return !pending && (!intent || intent.state === 'settled') && classifyThreeWay(local, remote, base) === 'remote';
}
