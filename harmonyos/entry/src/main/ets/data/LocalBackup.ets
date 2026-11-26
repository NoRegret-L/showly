import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Media } from '../model/Media';
import { MediaRecord, inLocalWatchlist, validateMediaRecords } from '../model/MediaState';
import { EpisodeStore, EpisodeBackupState, EpisodeCatalog, LocalEpisode, validateCatalog } from './EpisodeStore';
import { MediaStore } from './MediaStore';

interface BackupTitle { media: Media; watchlist: boolean; following?: boolean; }
export interface BackupData {
  schema: number;
  createdAt: string;
  titles: BackupTitle[];
  shows: EpisodeBackupState[];
}
interface BackupEnvelope { format: string; sha256: string; payload: string; }
export interface RestorePlan {
  titles: MediaRecord[];
  shows: EpisodeBackupState[];
  skippedTitles: number;
  skippedShows: number;
  watchedEpisodes: number;
}
export interface RestoreSummary { titles: number; shows: number; }

const FORMAT: string = 'showly-harmony-local-v1';
// Explicit input resource limit, not a synchronization threshold.
const MAX_FILE_BYTES: number = 32 * 1024 * 1024;

function cleanMedia(media: Media): Media {
  if (!media || typeof media.id !== 'string' || !media.id ||
      typeof media.title !== 'string' || typeof media.kind !== 'string' ||
      typeof media.year !== 'number' || !Number.isFinite(media.year) ||
      typeof media.watched !== 'boolean') { throw new Error('Invalid backup title'); }
  return { id: media.id, title: media.title, kind: media.kind, year: media.year, watched: media.watched };
}

function cleanShow(state: EpisodeBackupState): EpisodeBackupState {
  if (!state || !state.catalog || !Array.isArray(state.watchedIds)) { throw new Error('Invalid backup show'); }
  const source = state.catalog;
  validateCatalog(source, source.showId);
  if (!Number.isSafeInteger(Number(source.showId.substring(5))) || !Number.isFinite(source.year)) {
    throw new Error('Invalid backup show identity');
  }
  const episodes: LocalEpisode[] = source.episodes.map((ep: LocalEpisode): LocalEpisode => {
    return { id: ep.id, season: ep.season, number: ep.number, title: ep.title };
  });
  const allowed: Set<number> = new Set<number>(episodes.map((ep: LocalEpisode) => ep.id));
  if (state.watchedIds.some((id: number) => !allowed.has(id)) ||
      new Set<number>(state.watchedIds).size !== state.watchedIds.length) {
    throw new Error('Invalid watched episode IDs');
  }
  const catalog: EpisodeCatalog = { showId: source.showId, title: source.title, year: source.year, episodes: episodes };
  return { catalog: catalog, watchedIds: [...state.watchedIds] };
}

// Reconstruct only allowlisted display fields. An external backup is never
// authority for account identity, upload intent, or deletion provenance.
export function validateBackup(data: BackupData): BackupData {
  if (!data || data.schema !== 1 || typeof data.createdAt !== 'string' ||
      !Number.isFinite(Date.parse(data.createdAt)) || !Array.isArray(data.titles) || !Array.isArray(data.shows)) {
    throw new Error('Unsupported backup schema');
  }
  const titles: BackupTitle[] = [];
  const ids: Set<string> = new Set<string>();
  for (const title of data.titles) {
    if (!title || typeof title.watchlist !== 'boolean') { throw new Error('Invalid backup title state'); }
    const media = cleanMedia(title.media);
    if (ids.has(media.id)) { throw new Error('Duplicate backup title'); }
    ids.add(media.id);
    if (title.following !== undefined && (typeof title.following !== 'boolean' || media.kind !== 'show' ||
        (title.following && title.watchlist))) { throw new Error('Invalid followed state'); }
    titles.push({ media: media, watchlist: title.watchlist, following: title.following });
  }
  const shows: EpisodeBackupState[] = [];
  const showIds: Set<string> = new Set<string>();
  const epIds: Set<number> = new Set<number>();
  for (const entry of data.shows) {
    const show = cleanShow(entry);
    if (showIds.has(show.catalog.showId)) { throw new Error('Duplicate backup show'); }
    showIds.add(show.catalog.showId);
    for (const ep of show.catalog.episodes) {
      if (epIds.has(ep.id)) { throw new Error('Duplicate cross-show episode ID'); }
      epIds.add(ep.id);
    }
    shows.push(show);
  }
  return { schema: 1, createdAt: data.createdAt, titles: titles, shows: shows };
}

async function sha256(value: string): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: new Uint8Array(buffer.from(value, 'utf-8').buffer) });
  const digest = await md.digest();
  let hex = '';
  for (const byte of digest.data) { hex += byte.toString(16).padStart(2, '0'); }
  return hex;
}

export async function createBackup(mediaStore: MediaStore, episodeStore: EpisodeStore): Promise<BackupData> {
  const records = await mediaStore.load();
  const titles: BackupTitle[] = records.map((record: MediaRecord): BackupTitle => {
    return { media: cleanMedia(record.media), watchlist: inLocalWatchlist(record),
      following: record.followState === undefined ? undefined : record.followState === 'yes' };
  });
  const data: BackupData = { schema: 1, createdAt: new Date().toISOString(), titles: titles,
    shows: await episodeStore.backupStates() };
  return validateBackup(data);
}

async function encodeBackup(data: BackupData): Promise<string> {
  const payload = JSON.stringify(validateBackup(data));
  const envelope: BackupEnvelope = { format: FORMAT, sha256: await sha256(payload), payload: payload };
  const raw = JSON.stringify(envelope);
  if (buffer.from(raw, 'utf-8').length > MAX_FILE_BYTES) { throw new Error('Backup exceeds 32 MiB'); }
  return raw;
}

async function decodeBackup(raw: string): Promise<BackupData> {
  const envelope = JSON.parse(raw) as BackupEnvelope;
  if (!envelope || envelope.format !== FORMAT || typeof envelope.payload !== 'string' ||
      typeof envelope.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(envelope.sha256)) {
    throw new Error('Unsupported backup file');
  }
  if (await sha256(envelope.payload) !== envelope.sha256) { throw new Error('Backup checksum mismatch'); }
  return validateBackup(JSON.parse(envelope.payload) as BackupData);
}

async function readFile(uri: string): Promise<string> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size <= 0 || stat.size > MAX_FILE_BYTES) {
      throw new Error('Invalid backup size (maximum 32 MiB)');
    }
    const bytes = new ArrayBuffer(stat.size);
    const count = await fileIo.read(file.fd, bytes);
    if (count !== stat.size || fileIo.statSync(file.fd).size !== stat.size) { throw new Error('Incomplete backup read'); }
    return buffer.from(bytes).toString('utf-8');
  } finally { fileIo.closeSync(file); }
}

export async function exportBackup(context: common.UIAbilityContext, data: BackupData): Promise<boolean> {
  const raw = await encodeBackup(data);
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = ['Showly-Harmony-' + data.createdAt.replace(/[:.]/g, '-') + '.json'];
  const view = new picker.DocumentViewPicker(context);
  const uris = await view.save(options);
  if (!uris.length) { return false; }
  if (uris.length !== 1) { throw new Error('Unexpected save selection'); }
  const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    const expected = buffer.from(raw, 'utf-8').length;
    const count = await fileIo.write(file.fd, raw);
    if (count !== expected || fileIo.statSync(file.fd).size !== expected) { throw new Error('Incomplete backup write'); }
    fileIo.fsyncSync(file.fd);
  } finally { fileIo.closeSync(file); }
  const readback = await readFile(uris[0]);
  if (readback !== raw) { throw new Error('Backup file readback mismatch'); }
  await decodeBackup(readback);
  return true;
}

export async function selectBackup(context: common.UIAbilityContext): Promise<BackupData | undefined> {
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  const view = new picker.DocumentViewPicker(context);
  const uris = await view.select(options);
  if (!uris.length) { return undefined; }
  if (uris.length !== 1) { throw new Error('Select exactly one backup file'); }
  return await decodeBackup(await readFile(uris[0]));
}

export async function planRestore(data: BackupData, mediaStore: MediaStore,
  episodeStore: EpisodeStore): Promise<RestorePlan> {
  const clean = validateBackup(data);
  const current = await mediaStore.load();
  const existing: Set<string> = new Set<string>(current.map((record: MediaRecord) => record.media.id));
  const titles: MediaRecord[] = [];
  for (const title of clean.titles) {
    if (!existing.has(title.media.id)) {
      titles.push({ media: title.media, movieState: 'unknown', watchlistState: 'unknown',
        restoredWatchlist: title.watchlist,
        followState: title.following === undefined ? undefined : title.following ? 'yes' : 'no' });
    }
  }
  validateMediaRecords([...current, ...titles]);
  const shows = await episodeStore.missingBackupShows(clean.shows);
  let watchedEpisodes = 0;
  for (const show of shows) { watchedEpisodes += show.watchedIds.length; }
  return { titles: titles, shows: shows, skippedTitles: clean.titles.length - titles.length,
    skippedShows: clean.shows.length - shows.length, watchedEpisodes: watchedEpisodes };
}

export async function restoreBackup(data: BackupData, reviewed: RestorePlan,
  mediaStore: MediaStore, episodeStore: EpisodeStore): Promise<RestoreSummary> {
  const fresh = await planRestore(data, mediaStore, episodeStore);
  if (JSON.stringify(fresh) !== JSON.stringify(reviewed)) { throw new Error('Restore preview changed'); }
  // Two databases, two atomic commits. No replacement/deletion; if interrupted,
  // reselecting the same file skips committed rows and resumes missing data.
  const shows = await episodeStore.restoreMissingShows(fresh.shows);
  const current = await mediaStore.load();
  if (fresh.titles.length) { await mediaStore.save([...current, ...fresh.titles]); }
  return { titles: fresh.titles.length, shows: shows };
}
