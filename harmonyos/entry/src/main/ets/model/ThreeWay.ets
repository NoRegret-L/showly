// Boolean membership, not history counts or timestamps. No wall-clock winner.
export interface CommonEntry {
  id: string;
  value: boolean;
  activity: string;
}
export interface CommonUpdate {
  id: string;
  value: boolean;
}
export function commonId(domain: string, id: string): boolean {
  if (domain === 'episode') {
    return /^[1-9][0-9]*$/.test(id) && Number.isSafeInteger(Number(id));
  }
  if (domain !== 'movie' && domain !== 'watchlist') { return false; }
  return /^(movie|show):[1-9][0-9]*$/.test(id) &&
    (domain !== 'movie' || id.startsWith('movie:')) &&
    Number.isSafeInteger(Number(id.substring(id.indexOf(':') + 1)));
}
export function validDomain(domain: string): boolean {
  return domain === 'episode' || domain === 'movie' || domain === 'watchlist';
}
export function classifyThreeWay(local: string, remote: boolean, base?: CommonEntry): string {
  if (local !== 'yes' && local !== 'no') { return 'unknown'; }
  if (!base) { return 'unbased'; }
  const current = local === 'yes';
  const localChanged = current !== base.value;
  const remoteChanged = remote !== base.value;
  if (!localChanged && !remoteChanged) { return 'same'; }
  if (localChanged && !remoteChanged) { return 'local'; }
  if (!localChanged && remoteChanged) { return 'remote'; }
  return current === remote ? 'converged' : 'divergent';
}
export function threeWayLabel(kind: string, baseline: string): string {
  const base = baseline === 'yes' ? '存在' : baseline === 'no' ? '不存在' : '未建立';
  const label = kind === 'same' ? '双方未变化' : kind === 'converged' ? '双方已收敛' :
    kind === 'local' ? '仅本机变化' : kind === 'remote' ? '仅云端变化 · 暂停反向写入' :
    kind === 'divergent' ? '双端冲突' : kind === 'unknown' ? '本机意图未知' : '缺少共同基线';
  return '基线：' + base + ' · ' + label;
}
