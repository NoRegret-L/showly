import { BusinessError } from '@kit.BasicServicesKit';

// Never expose raw HTTP/SDK error objects, headers, tokens or server bodies.
export function safeSyncError(error: Error): string {
  const code = (error as BusinessError).code;
  if (typeof code === 'number' && Number.isSafeInteger(code)) { return 'SDK 错误码 ' + code; }
  const message = error.message;
  if (typeof message === 'string' &&
      /^(?:(?:Account verification|History verification|Watched episode|Trakt activity|Trakt library) HTTP [0-9]{3}|(?:Account mismatch|Account changed|Account changed after POST|Account session changed|Session changed|Snapshot or account changed|Cloud changed|Cloud changed before batch|Cloud changed during readback|Cloud changed during media preview|Preflight changed|Missing activity revision|Missing or invalid pagination headers|Incomplete library pagination|Library changed while reading; retry|Invalid response evidence|Invalid watched pagination|Incomplete watched list|Watched list changed while reading|Incomplete history response|Invalid history identity|Invalid or duplicate watched episode|Queue changed|Offline or sign-in required|Auto disabled|Foreground ended|Account not bound))$/.test(message)) {
    return message;
  }
  return '未分类异常（未输出原始异常，以保护账户信息）';
}
