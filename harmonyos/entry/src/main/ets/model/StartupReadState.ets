// A locally verified display identity is never an online write session.
export function cacheReadable(uuid: string, credentialUuid: string, verifiedAt: number): boolean {
  return !!uuid && uuid===credentialUuid && uuid.trim()===uuid &&
    Number.isSafeInteger(verifiedAt) && verifiedAt>0;
}
export function startupNotice(hasSnapshot: boolean, busy: boolean): string {
  if (hasSnapshot) { return busy?'显示上次已核对记录 · 正在更新':'显示上次已核对记录 · 尚未在线确认'; }
  return busy?'正在核对账户；暂未取得可读记录':'账户或个人库尚未核对，请重试。';
}
