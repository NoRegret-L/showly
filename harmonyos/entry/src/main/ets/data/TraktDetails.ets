import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';
import { artworkIdentity, legacyPosterName } from '../model/ArtworkRules';
import { http } from '@kit.NetworkKit';
import { PresentationFailure } from '../model/PresentationPolicy';
import { checkPresentationService, presentationHttpError, traktPresentationService } from './PresentationHttp';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Media } from '../model/Media';
import { ReadFlight, ReadCancel, ConsumerReadFlight } from '../model/ReadFlight';
import { CollectionMeta, imageFormat } from '../model/MediaPresentation';

interface TraktIds {
  trakt: number;
}
interface Images {
  poster?: string[];
  fanart?: string[];
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
  network?: string;
  first_aired?: string;
  released?: string;
  aired_episodes?: number;
  certification?: string;
  country?: string;
  language?: string;
  tagline?: string;
  votes?: number;
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
  fanartUrls?: string[];
  certification?: string;
  country?: string;
  language?: string;
  tagline?: string;
  votes?: number;
  collection?: CollectionMeta;
}
let posterWriteSequence: number = 0;
const summaries: Map<string, MediaDetail> = new Map<string, MediaDetail>();
const summaryFlights = new ConsumerReadFlight<MediaDetail>();
const posterFlights = new ConsumerReadFlight<PosterResult>();
let summaryEpoch = 0;

export function canReadDetails(item: Media): boolean {
  return (item.kind === 'show' || item.kind === 'movie') &&
    new RegExp('^' + item.kind + ':[1-9][0-9]*$').test(item.id);
}

export async function readDetails(item: Media, clientId: string, reload: boolean = false, consumer?: ReadCancel): Promise<MediaDetail> {
  if (!canReadDetails(item) || !clientId) {
    throw new Error('Missing Trakt media identity');
  }
  consumer?.check();
  const key = clientId + ':' + item.id;
  const cached = summaries.get(key);
  if (cached && !reload) {
    return cached;
  }
  const epoch = summaryEpoch;
  return summaryFlights.run(JSON.stringify([epoch,clientId,item.id]), (scope: ReadCancel) => fetchDetails(item,clientId,key,epoch,scope),consumer);
}
async function fetchDetails(item: Media, clientId: string, key: string, epoch: number, scope: ReadCancel): Promise<MediaDetail> {
  const id = item.id.substring(item.kind.length + 1);
  const service=traktPresentationService(clientId);
  checkPresentationService(service);
  scope.check();
  const request = http.createHttp();
  let destroyed=false;
  const close=(): void=>{ if (!destroyed) { destroyed=true; request.destroy(); } };
  scope.subscribe(close);
  try {
    scope.check();
    const response = await request.request('https://api.trakt.tv/' +
      (item.kind === 'show' ? 'shows/' : 'movies/') + id + '?extended=full', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId, 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.0' },
      expectDataType: http.HttpDataType.STRING
    });
    scope.check();
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);
    }
    const data = JSON.parse(response.result) as Summary;
    if (typeof data.title !== 'string' || !data.ids || data.ids.trakt !== Number(id)) {
      throw new Error('Invalid summary identity');
    }
    const poster = data.images?.poster;
    const release = item.kind === 'show' ? data.first_aired : data.released;
    const result: MediaDetail = {
      title: data.title,
      year: typeof data.year === 'number' ? data.year : item.year,
      overview: typeof data.overview === 'string' ? data.overview : '',
      runtime: typeof data.runtime === 'number' ? data.runtime : 0,
      rating: typeof data.rating === 'number' ? data.rating : 0,
      status: typeof data.status === 'string' ? data.status : '',
      genres: Array.isArray(data.genres) ? data.genres.join(' / ') : '',
      collection: { genres: Array.isArray(data.genres) ? data.genres.filter((g: string) => typeof g === 'string') : [],
        network: typeof data.network === 'string' ? data.network : '', release: typeof release === 'string' ? release : '',
        rating: typeof data.rating === 'number' && Number.isFinite(data.rating) && data.rating >= 0 && data.rating <= 10 ? data.rating : undefined,
        runtime: typeof data.runtime === 'number' && Number.isFinite(data.runtime) && data.runtime >= 0 ? data.runtime : undefined },
      airedEpisodes: typeof data.aired_episodes === 'number' ? data.aired_episodes : 0,
      certification: typeof data.certification === 'string' ? data.certification : undefined,
      country: typeof data.country === 'string' ? data.country : undefined,
      language: typeof data.language === 'string' ? data.language : undefined,
      tagline: typeof data.tagline === 'string' ? data.tagline : undefined,
      votes: typeof data.votes === 'number' && Number.isSafeInteger(data.votes) && data.votes >= 0 ? data.votes : undefined,
      posterUrls: Array.isArray(poster) ? poster.filter((value: string) => typeof value === 'string' && value.length > 0) : [],
      fanartUrls: Array.isArray(data.images?.fanart) ? data.images?.fanart?.filter((value: string) => typeof value === 'string' && value.length > 0) : []
    };
    if (epoch === summaryEpoch) { summaries.set(key, result); }
    return result;
  } finally {
    scope.unsubscribe(close); close();
  }
}

export function clearDetailMemory(): void {
  summaryEpoch++;
  summaries.clear();
}

export interface PosterResult {
  uri: string;
  status: string;
  failure?: PresentationFailure;
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
// URI rejection is session-local; never delete a file selected by another
// consumer. A fresh verified download atomically replaces it.
const rejectedPosterUris: Set<string>=new Set<string>();
export function rejectPosterUri(uri: string): void { if (uri) { rejectedPosterUris.add(uri); } }
export async function posterPath(cacheDir: string,item: Media,url: string,type:string='poster'): Promise<string> {
  const key=type==='poster'?artworkIdentity('trakt','poster',item.id,url):artworkIdentity('trakt','fanart',item.id,url);
  // normalizePoster accepts ASCII paths and authority; encode UTF-8 explicitly
  // for query strings as well, without storing signed URLs in file names.
  const data=new util.TextEncoder().encodeInto(key);
  const md=cryptoFramework.createMd('SHA256');
  await md.update({data:data});
  const digest=await md.digest();
  let hex='';
  for (const byte of digest.data) { hex+=byte.toString(16).padStart(2,'0'); }
  return cacheDir+'/showly_artwork_'+hex;
}
async function validPosterFile(path: string,scope?: ReadCancel): Promise<boolean> {
  scope?.check();
  try {
    const stat=await fileIo.stat(path);
    if (stat.size<=0) { return false; }
    const uri=fileUri.getUriFromPath(path);
    if (rejectedPosterUris.has(uri)) { return false; }
    const file=await fileIo.open(path,fileIo.OpenMode.READ_ONLY);
    try {
      const source=image.createImageSource(file.fd);
      try {
        const info=await source.getImageInfo();
        scope?.check();
        return info.size.width>0 && info.size.height>0;
      } finally { await source.release(); }
    } finally { await fileIo.close(file); }
  } catch (error) { scope?.check(); return false; }
}
export async function cachedPoster(cacheDir: string, item: Media, candidates: string[],scope?: ReadCancel,type:string='poster'): Promise<string> {
  if (!canReadDetails(item)) { return ''; }
  const urls=Array.from(new Set<string>(candidates.map((candidate: string)=>normalizePoster(candidate)).filter((url: string)=>!!url)));
  for (const url of urls) {
    scope?.check();
    const path=await posterPath(cacheDir,item,url,type);
    if (await validPosterFile(path,scope)) { return fileUri.getUriFromPath(path); }
  }
  if(type!=='poster'){return '';}
  // Existing offline files are a compatibility fallback only. Never promote
  // them to the new exact identity, and reject ambiguous legacy basenames.
  for (const url of urls) {
    const name=legacyPosterName(url);
    if (urls.filter((other: string)=>legacyPosterName(other)===name).length!==1) { continue; }
    const path=cacheDir+'/showly_poster_'+item.kind+'_'+item.id.substring(item.kind.length+1)+'_'+name;
    if (await validPosterFile(path,scope)) { return fileUri.getUriFromPath(path); }
  }
  return '';
}
export async function cachePoster(cacheDir: string, item: Media, candidates: string[], consumer?: ReadCancel,type:string='poster'): Promise<PosterResult> {
  const selected=candidates.map((candidate: string)=>normalizePoster(candidate)).find((url: string)=>!!url)??'';
  const key=JSON.stringify([cacheDir,artworkIdentity('trakt',type,item.id,selected),selected?'':candidates[0]??'']);
  return posterFlights.run(key,(scope: ReadCancel)=>downloadPoster(cacheDir,item,candidates,scope,type),consumer);
}
async function downloadPoster(cacheDir: string, item: Media, candidates: string[], scope: ReadCancel,type:string): Promise<PosterResult> {
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
  const path=await posterPath(cacheDir,item,url,type);
  if (await validPosterFile(path,scope)) {
    return { uri:fileUri.getUriFromPath(path),status:'海报来自本地缓存 · '+host };
  }
  const service='poster:'+host;
  checkPresentationService(service);
  scope.check();
  const request = http.createHttp();
  let closed=false;
  const close=(): void=>{ if (!closed) { closed=true; request.destroy(); } };
  scope.subscribe(close);
  const temp = path + '.' + Date.now() + '.' + (++posterWriteSequence) + '.part';
  let response: http.HttpResponse;
  try {
    response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.0', 'Accept': 'image/webp,image/jpeg,image/png' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
  } catch (error) {
    scope.check();
    const code = (error as BusinessError).code;
    return { uri: '', status: networkError(code) + '（' + host + '，错误码 ' + code + '）', failure:new PresentationFailure('temporary',0) };
  } finally {
    scope.unsubscribe(close); close();
  }
  scope.check();
  if (response.responseCode !== 200) {
    return { uri: '', status: '海报 CDN HTTP ' + response.responseCode + ' · ' + host,
      failure:presentationHttpError(service,response.responseCode,JSON.stringify(response.header),false) };
  }
  if (!(response.result instanceof ArrayBuffer)) {
    return { uri: '', status: '海报 CDN 返回 HTTP 200，但响应不是二进制图片 · ' + host, failure:new PresentationFailure('temporary',200) };
  }
  const bytes = response.result;
  const signature = new Uint8Array(bytes);
  if (!imageFormat(signature)) {
    return { uri: '', status: '海报 CDN 未返回支持的图片文件头 · ' + host, failure:new PresentationFailure('temporary',200) };
  }
  try {
    const file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const written = await fileIo.write(file.fd, bytes);
      if (written !== bytes.byteLength) {
        throw new Error('Incomplete poster cache write');
      }
    } finally {
      await fileIo.close(file);
    }
    scope.check();
    if (!await validPosterFile(temp,scope)) { throw new Error('Invalid poster image metadata'); }
    scope.check();
    await fileIo.rename(temp, path);
    rejectedPosterUris.delete(fileUri.getUriFromPath(path));
    return { uri: fileUri.getUriFromPath(path), status: '海报已下载并缓存 · ' + host };
  } catch (error) {
    scope.check();
    return { uri: '', status: '海报下载成功，但本地缓存写入失败（错误码 ' + (error as BusinessError).code + '）', failure:new PresentationFailure('temporary',0) };
  } finally {
    try {
      await fileIo.unlink(temp);
    } catch (error) {
      // A temporary cache file is not a library record.
    }
  }
}
