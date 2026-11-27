import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Media } from '../model/Media';
import { imageFormat } from '../model/MediaPresentation';

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
let posterWriteSequence: number = 0;
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
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId, 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.0' },
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

// The API examples and CDN hosts change over time. Validate the authority and
// traversal-safe path, not the provider's internal ID/size directory layout.
function normalizePoster(raw: string): string {
  const value = raw.trim();
  if (!value || /[\s\\#\x00-\x1f\x7f]/.test(value)) {
    return '';
  }
  const url = /^https:\/\//i.test(value) ? 'https://' + value.substring(8) :
    value.startsWith('//') ? 'https:' + value : 'https://' + value;
  const slash = url.indexOf('/', 8);
  if (slash < 0) {
    return '';
  }
  const host = url.substring(8, slash).toLowerCase();
  if (!/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+trakt\.tv$/i.test(host)) {
    return '';
  }
  const q = url.indexOf('?', slash);
  const path = q < 0 ? url.substring(slash) : url.substring(slash, q);
  if (!/^\/[A-Za-z0-9._~/-]+$/.test(path) || path.endsWith('/') ||
      path.split('/').some((segment: string) => segment === '.' || segment === '..')) {
    return '';
  }
  if (!path.startsWith('/images/') &&
      !(/^(?:media|walter(?:-[a-z0-9-]+)?)\.trakt\.tv$/i.test(host) && /\.(?:webp|jpg|jpeg|png)$/i.test(path))) {
    return '';
  }
  return 'https://' + host + url.substring(slash);
}

// Show only an authority and a sanitized path. Never copy query strings,
// fragments, embedded user information, or credentials into diagnostics.
function rejectedPosterHint(raw: string): string {
  const value = raw.trim();
  const address = value.replace(/^https?:\/\//i, '').replace(/^\/\//, '');
  const clean = address.split('?')[0].split('#')[0];
  if (!/^[A-Za-z0-9._~/-]+$/.test(clean)) {
    return '地址含未支持字符';
  }
  return clean;
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
export function cachedPoster(cacheDir: string, item: Media, candidates: string[]): string {
  if (!canReadDetails(item)) { return ''; }
  for (const candidate of candidates) {
    const url = normalizePoster(candidate);
    if (!url) { continue; }
    const imagePath = url.split('?')[0];
    const filename = imagePath.substring(imagePath.lastIndexOf('/') + 1);
    const path = cacheDir + '/showly_poster_' + item.kind + '_' + item.id.substring(item.kind.length + 1) + '_' + filename;
    try { if (fileIo.accessSync(path) && fileIo.statSync(path).size > 0) { return fileUri.getUriFromPath(path); } } catch (error) {}
  }
  return '';
}
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
    return { uri: '', status: '海报地址未通过安全校验 · ' + rejectedPosterHint(candidates[0]) };
  }
  const host = url.substring(8, url.indexOf('/', 8));
  const imagePath = url.split('?')[0];
  const filename = imagePath.substring(imagePath.lastIndexOf('/') + 1);
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
  const temp = path + '.' + Date.now() + '.' + (++posterWriteSequence) + '.part';
  let response: http.HttpResponse;
  try {
    response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.0', 'Accept': 'image/webp,image/jpeg,image/png' },
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
  if (!imageFormat(signature)) {
    return { uri: '', status: '海报 CDN 未返回支持的图片文件头 · ' + host };
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
