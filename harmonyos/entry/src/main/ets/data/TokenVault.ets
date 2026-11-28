import { fileIo as fs } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

interface RefreshRecord {
  clientId: string;
  refreshToken: string;
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

export function saveRefresh(clientId: string, refreshToken: string): void {
  const record: RefreshRecord = { clientId: clientId, refreshToken: refreshToken };
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

export function loadRefresh(clientId: string): string {
  const query = alias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const records = asset.querySync(query);
    if (records.length !== 1) {
      return '';
    }
    const raw = records[0].get(asset.Tag.SECRET) as Uint8Array;
    const record = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(raw)) as RefreshRecord;
    return record.clientId === clientId && typeof record.refreshToken === 'string' ? record.refreshToken : '';
  } catch (error) {
    if ((error as BusinessError).code === 24000002) {
      return '';
    }
    throw new Error('Cannot read secure token');
  }
}

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
