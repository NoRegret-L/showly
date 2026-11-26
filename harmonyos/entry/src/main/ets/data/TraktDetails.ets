import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { Media } from '../model/Media';

interface TraktIds {
  trakt: number;
}
interface Images {
  poster?: string[];
}
interface Summary {
  title: string;
  ids: TraktIds;
  year?: number;
  overview?: string;
  runtime?: number;
  rating?: number;
  status?: string;
  genres?: string[];
  aired_episodes?: number;
  images?: Images;
}
export interface MediaDetail {
  title: string;
  year: number;
  overview: string;
  runtime: number;
  rating: number;
  status: string;
  genres: string;
  airedEpisodes: number;
  posterUrl: string;
}
const summaries: Map<string, MediaDetail> = new Map<string, MediaDetail>();

export function canReadDetails(item: Media): boolean {
  return (item.kind === 'show' || item.kind === 'movie') &&
    new RegExp('^' + item.kind + ':[1-9][0-9]*$').test(item.id);
}

export async function readDetails(item: Media, clientId: string, reload: boolean = false): Promise<MediaDetail> {
  if (!canReadDetails(item) || !clientId) {
    throw new Error('Missing Trakt media identity');
  }
  const key = clientId + ':' + item.id;
  const cached = summaries.get(key);
  if (cached && !reload) {
    return cached;
  }
  const id = item.id.substring(item.kind.length + 1);
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/' +
      (item.kind === 'show' ? 'shows/' : 'movies/') + id + '?extended=full', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Trakt summary HTTP ' + response.responseCode);
    }
    const data = JSON.parse(response.result) as Summary;
    if (typeof data.title !== 'string' || !data.ids || data.ids.trakt !== Number(id)) {
      throw new Error('Invalid summary identity');
    }
    const poster = data.images?.poster;
    const result: MediaDetail = {
      title: data.title,
      year: typeof data.year === 'number' ? data.year : item.year,
      overview: typeof data.overview === 'string' ? data.overview : '',
      runtime: typeof data.runtime === 'number' ? data.runtime : 0,
      rating: typeof data.rating === 'number' ? data.rating : 0,
      status: typeof data.status === 'string' ? data.status : '',
      genres: Array.isArray(data.genres) ? data.genres.join(' / ') : '',
      airedEpisodes: typeof data.aired_episodes === 'number' ? data.aired_episodes : 0,
      posterUrl: Array.isArray(poster) && typeof poster[0] === 'string' ? poster[0] : ''
    };
    summaries.set(key, result);
    return result;
  } finally {
    request.destroy();
  }
}

export function clearDetailMemory(): void {
  summaries.clear();
}

// Only Trakt-owned HTTPS artwork hosts are accepted. No auth headers on CDN requests.
// Trakt requires downloaded artwork to be cached locally, not hotlinked by Image().
export async function cachePoster(cacheDir: string, item: Media, raw: string): Promise<string> {
  if (!raw || !canReadDetails(item)) {
    return '';
  }
  const url = raw.startsWith('https://') ? raw : 'https://' + raw;
  if (!/^https:\/\/[a-z0-9-]+\.trakt\.tv\/images\/(movies|shows)\/[0-9/]+\/posters\/(thumb|medium|full)\/[a-zA-Z0-9._-]+\.webp$/.test(url)) {
    return '';
  }
  const filename = url.substring(url.lastIndexOf('/') + 1);
  const path = cacheDir + '/showly_poster_' + item.kind + '_' +
    item.id.substring(item.kind.length + 1) + '_' + filename;
  try {
    if (fileIo.accessSync(path) && fileIo.statSync(path).size > 0) {
      return fileUri.getUriFromPath(path);
    }
  } catch (error) {
    // Cache miss; download below.
  }
  const request = http.createHttp();
  const temp = path + '.part';
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
      return '';
    }
    const bytes = response.result;
    const signature = new Uint8Array(bytes);
    // Only cache WebP containers, as documented by Trakt.
    if (signature.length < 12 || signature[0] !== 82 || signature[1] !== 73 ||
        signature[2] !== 70 || signature[3] !== 70 || signature[8] !== 87 ||
        signature[9] !== 69 || signature[10] !== 66 || signature[11] !== 80) {
      return '';
    }
    const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const written = await fileIo.write(file.fd, bytes);
      if (written !== bytes.byteLength) {
        throw new Error('Incomplete poster cache write');
      }
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temp, path);
    return fileUri.getUriFromPath(path);
  } finally {
    request.destroy();
    try {
      if (fileIo.accessSync(temp)) {
        fileIo.unlinkSync(temp);
      }
    } catch (error) {
      // A temporary cache file is not a library record.
    }
  }
}
