import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
  posterUrls: string[];
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
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId, 'User-Agent': 'Showly-HarmonyOS-Personal/0.6.1' },
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
      posterUrls: Array.isArray(poster) ? poster.filter((value: string) => typeof value === 'string' && value.length > 0) : []
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

export interface PosterResult {
  uri: string;
  status: string;
}

function normalizePoster(raw: string): string {
  const url = raw.startsWith('https://') ? raw : 'https://' + raw;
  // Constrain to Trakt-owned HTTPS hosts and the documented artwork namespace.
  // Do not hardcode CDN host names or artwork sizes: Trakt can migrate them.
  if (!/^https:\/\/[a-z0-9-]+\.trakt\.tv\/images\/(movies|shows)\/[0-9]+(?:\/[0-9]+)*\/posters\/[a-zA-Z0-9_-]+\/[a-zA-Z0-9._-]+\.webp$/.test(url)) {
    return '';
  }
  return url;
}

function networkError(code: number): string {
  if (code === 2300006) {
    return 'DNS 解析失败';
  }
  if (code === 2300007) {
    return '无法连接图片服务器';
  }
  if (code === 2300028) {
    return '图片请求超时';
  }
  return '图片网络请求失败';
}

// Only Trakt-owned HTTPS artwork hosts are accepted. Never attach API credentials.
// Download into local cache first; no hotlinking, proxy, or TLS verification bypass.
export async function cachePoster(cacheDir: string, item: Media, candidates: string[]): Promise<PosterResult> {
  if (!canReadDetails(item) || candidates.length === 0) {
    return { uri: '', status: 'Trakt API 未返回海报地址（images.poster 为空）' };
  }
  let url = '';
  for (const candidate of candidates) {
    const normalized = normalizePoster(candidate);
    if (normalized) {
      url = normalized;
      break;
    }
  }
  if (!url) {
    return { uri: '', status: 'Trakt 返回了海报地址，但不符合受信任的 HTTPS 图片路径规则' };
  }
  const host = url.substring(8, url.indexOf('/', 8));
  const filename = url.substring(url.lastIndexOf('/') + 1);
  const path = cacheDir + '/showly_poster_' + item.kind + '_' +
    item.id.substring(item.kind.length + 1) + '_' + filename;
  try {
    if (fileIo.accessSync(path) && fileIo.statSync(path).size > 0) {
      return { uri: fileUri.getUriFromPath(path), status: '海报来自本地缓存 · ' + host };
    }
  } catch (error) {
    // Cache miss; download below.
  }
  const request = http.createHttp();
  const temp = path + '.part';
  let response: http.HttpResponse;
  try {
    response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'Showly-HarmonyOS-Personal/0.6.1', 'Accept': 'image/webp' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
  } catch (error) {
    const code = (error as BusinessError).code;
    return { uri: '', status: networkError(code) + '（' + host + '，错误码 ' + code + '）' };
  } finally {
    request.destroy();
  }
  if (response.responseCode !== 200) {
    return { uri: '', status: '海报 CDN HTTP ' + response.responseCode + ' · ' + host };
  }
  if (!(response.result instanceof ArrayBuffer)) {
    return { uri: '', status: '海报 CDN 返回 HTTP 200，但响应不是二进制图片 · ' + host };
  }
  const bytes = response.result;
  const signature = new Uint8Array(bytes);
  if (signature.length < 12 || signature[0] !== 82 || signature[1] !== 73 ||
      signature[2] !== 70 || signature[3] !== 70 || signature[8] !== 87 ||
      signature[9] !== 69 || signature[10] !== 66 || signature[11] !== 80) {
    return { uri: '', status: '海报 CDN 返回 HTTP 200，但内容不是有效 WebP 文件头 · ' + host };
  }
  try {
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
    return { uri: fileUri.getUriFromPath(path), status: '海报已下载并缓存 · ' + host };
  } catch (error) {
    return { uri: '', status: '海报下载成功，但本地缓存写入失败（错误码 ' + (error as BusinessError).code + '）' };
  } finally {
    try {
      if (fileIo.accessSync(temp)) {
        fileIo.unlinkSync(temp);
      }
    } catch (error) {
      // A temporary cache file is not a library record.
    }
  }
}
