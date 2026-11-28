import { fileIo as fs } from '@kit.CoreFileKit';
import { trySyncLease,releaseSyncLease } from './SyncLease';
import { configureVaultLock, tryVaultLock, releaseVaultLock, readBackgroundGrant, BackgroundGrant } from './TokenVault';
import { TraktSession } from './TraktAuth';
import { readCloudLibraryIncremental, CloudLibrary } from './TraktLibrary';
import { readSyncAccount } from './TraktSyncPreview';
import { validateObservation } from '../model/RemoteObservation';

interface BackgroundSnapshot {
  id: string;
  uuid: string;
  clientId: string;
  snapshot: CloudLibrary;
}
export interface BackgroundReadInfo { enabled: boolean; expiresAt: number; verifiedAt: number; }
function readSnapshot(directory: string, grant: BackgroundGrant): CloudLibrary | undefined {
  try {
    const row = JSON.parse(fs.readTextSync(directory + '/sync-background-observation')) as BackgroundSnapshot;
    if (!row || row.id !== grant.id || row.uuid !== grant.uuid || row.clientId !== grant.clientId) { return undefined; }
    validateObservation(row.snapshot);
    return row.snapshot;
  } catch (error) { return undefined; }
}
function saveSnapshot(directory: string, grant: BackgroundGrant, snapshot: CloudLibrary): void {
  const row: BackgroundSnapshot = {id:grant.id,uuid:grant.uuid,clientId:grant.clientId,snapshot:snapshot};
  const temporary = directory + '/sync-background-observation.tmp';
  const file = fs.openSync(temporary,fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd,JSON.stringify(row)); fs.fsyncSync(file.fd); }
  finally { fs.closeSync(file); }
  fs.renameSync(temporary,directory + '/sync-background-observation');
}
export function backgroundReadInfo(directory: string, uuid: string, clientId: string): BackgroundReadInfo {
  try {
    const grant = readBackgroundGrant();
    if (!grant || grant.uuid !== uuid || grant.clientId !== clientId) { return {enabled:false,expiresAt:0,verifiedAt:0}; }
    return {enabled:true,expiresAt:grant.expiresAt,verifiedAt:readSnapshot(directory,grant)?.verifiedAt ?? 0};
  } catch (error) { return {enabled:false,expiresAt:0,verifiedAt:0}; }
}
export function readPreparedObservation(directory: string, uuid: string, clientId: string, generation: number): CloudLibrary | undefined {
  try {
    const grant = readBackgroundGrant();
    if (!grant || grant.uuid !== uuid || grant.clientId !== clientId || grant.expiresAt <= Date.now()) { return undefined; }
    const snapshot = readSnapshot(directory,grant);
    if (snapshot) { snapshot.generation = generation; }
    return snapshot;
  } catch (error) { return undefined; }
}
// Worker never opens the authoritative database, refreshes tokens or uploads.
// Exclusive OAuth lease spans the full read. Stop cancels new requests and
// publication; in-flight HTTP may drain before the lease is released.
export async function runBackgroundObservation(directory: string, active: () => boolean): Promise<void> {
  const operation=trySyncLease(directory);if(!operation){return;}
  try {
  configureVaultLock(directory);
  const lease = tryVaultLock();
  if (!lease) { return; }
  try {
    const grant = readBackgroundGrant();
    if (!grant || !active() || grant.expiresAt <= Date.now()) { return; }
    const permit = (): boolean => active() && grant.expiresAt > Date.now();
    const session: TraktSession = {clientId:grant.clientId,token:grant.token,generation:1};
    const before = await readSyncAccount(session,permit);
    if (!permit() || before.uuid !== grant.uuid) { return; }
    const prior = readSnapshot(directory,grant);
    const snapshot = await readCloudLibraryIncremental(session,prior,permit);
    const after = await readSyncAccount(session,permit);
    if (!permit() || after.uuid !== grant.uuid) { return; }
    snapshot.verifiedAt = Date.now();
    validateObservation(snapshot);
    saveSnapshot(directory,grant,snapshot);
  } finally { releaseVaultLock(lease); }
  }finally{releaseSyncLease(operation);}
}
