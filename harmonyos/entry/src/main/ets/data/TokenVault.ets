import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export interface RefreshRecord {
  clientId: string;
  refreshToken: string;
  uuid?: string;
}

function bytes(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function alias(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, bytes('showly_trakt_refresh_v1'));
  return query;
}

export function removeRefresh(): void {
  try {
    asset.removeSync(alias());
  } catch (error) {
    if ((error as BusinessError).code !== 24000002) {
      throw new Error('Cannot clear secure token');
    }
  }
}

export function saveRefresh(clientId: string, refreshToken: string, uuid: string = ''): void {
  const record: RefreshRecord = { clientId: clientId, refreshToken: refreshToken, uuid: uuid };
  const secret = bytes(JSON.stringify(record));
  if (secret.length > 1024) {
    // Asset Store's documented maximum; never fall back to plaintext.
    removeRefresh();
    throw new Error('Token too large for secure store');
  }
  const attrs = alias();
  attrs.set(asset.Tag.SECRET, secret);
  attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  asset.addSync(attrs);
}

export function loadRefreshRecord(clientId: string): RefreshRecord | undefined {
  const query = alias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const records = asset.querySync(query);
    if (records.length !== 1) {
      return undefined;
    }
    const raw = records[0].get(asset.Tag.SECRET) as Uint8Array;
    const record = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(raw)) as RefreshRecord;
    if (!record || record.clientId !== clientId || typeof record.refreshToken !== 'string' || !record.refreshToken) { return undefined; }
    return {clientId:clientId,refreshToken:record.refreshToken,uuid:typeof record.uuid==='string' && record.uuid.trim()===record.uuid ? record.uuid : ''};
  } catch (error) {
    if ((error as BusinessError).code === 24000002) {
      return undefined;
    }
    throw new Error('Cannot read secure token');
  }
}

export function loadRefresh(clientId: string): string { return loadRefreshRecord(clientId)?.refreshToken ?? ''; }

// One stable inode for all token-mutating operations, never unlink or rotate.
// The kernel releases the advisory lock when the owning process exits.
let vaultDirectory: string = '';
export function configureVaultLock(directory: string): void { vaultDirectory = directory; }
export function tryVaultLock(): fs.File | undefined {
  if (!vaultDirectory) { return undefined; }
  let file: fs.File | undefined;
  try {
    file = fs.openSync(vaultDirectory + '/trakt-oauth.lock', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    file.tryLock(true);
    return file;
  } catch (error) {
    if (file) { try { fs.closeSync(file); } catch (failure) {} }
    return undefined;
  }
}
export function releaseVaultLock(file: fs.File): void {
  try { file.unlock(); } finally { fs.closeSync(file); }
}

// Explicit, account-scoped background READ grant. Access token only; the
// refresh token never leaves the existing foreground OAuth path.
export interface BackgroundGrant {
  uuid: string;
  clientId: string;
  token: string;
  expiresAt: number;
  id: string;
}
function backgroundAlias(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, bytes('showly_trakt_background_read_v1'));
  return query;
}
export function newBackgroundGrantId(): string {
  return new util.Base64Helper().encodeToStringSync(cryptoFramework.createRandom().generateRandomSync(24).data, util.Type.BASIC_URL_SAFE);
}
export function clearBackgroundGrant(): void {
  try { asset.removeSync(backgroundAlias()); }
  catch (error) {
    if ((error as BusinessError).code !== 24000002) { throw new Error('Cannot revoke background grant'); }
  }
}
export function readBackgroundGrant(): BackgroundGrant | undefined {
  const query = backgroundAlias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const records = asset.querySync(query);
    if (records.length !== 1) { return undefined; }
    const value = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(records[0].get(asset.Tag.SECRET) as Uint8Array)) as BackgroundGrant;
    if (!value || typeof value.uuid !== 'string' || !value.uuid || typeof value.clientId !== 'string' || !value.clientId ||
        typeof value.token !== 'string' || !value.token || typeof value.id !== 'string' || !value.id ||
        !Number.isSafeInteger(value.expiresAt) || value.expiresAt <= 0) { return undefined; }
    return value;
  } catch (error) {
    if ((error as BusinessError).code === 24000002) { return undefined; }
    throw new Error('Cannot read background grant');
  }
}
export function writeBackgroundGrant(value: BackgroundGrant): void {
  const secret = bytes(JSON.stringify(value));
  if (secret.length > 1024) { throw new Error('Background credential too large'); }
  const attrs = backgroundAlias();
  attrs.set(asset.Tag.SECRET, secret);
  attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  asset.addSync(attrs);
}
