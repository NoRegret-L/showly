import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { DiscoverItem, DiscoverRequest } from '../model/DiscoverRules';
import { ChartPage, DiscoverTransport } from '../model/DiscoverRead';
export { DiscoverItem } from '../model/DiscoverRules';
interface DiscoverIds { trakt: number; }
interface DiscoverImages { poster?: string[]; }
interface DiscoverTitle {
  ids: DiscoverIds; title: string; year?: number; rating?: number; images?: DiscoverImages;
  first_aired?: string; released?: string;
}
interface DiscoverRow { movie?: DiscoverTitle; show?: DiscoverTitle; }
export class TraktDiscoverTransport implements DiscoverTransport {
  async read(client: string, options: DiscoverRequest, mode: string, page: number, limit: number): Promise<ChartPage> {
    if (!client || !['movie','show'].includes(options.kind) || !['trending','popular','anticipated'].includes(mode) ||
        !Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1) { throw new Error('Invalid discovery request'); }
    const endpoint = options.kind === 'movie' ? 'movies' : 'shows';
    let url = 'https://api.trakt.tv/' + endpoint + '/' + mode + '?extended=full&page=' + page + '&limit=' + limit;
    if (options.genres.length) { url += '&genres=' + encodeURIComponent(options.genres.join(',')); }
    if (options.kind === 'show' && options.networks.length) { url += '&networks=' + encodeURIComponent(options.networks.join(',')); }
    const request = http.createHttp();
    try {
      const response = await request.request(url,{
        method:http.RequestMethod.GET,
        header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':client,'User-Agent':'Showly-HarmonyOS-Personal/0.7.0'},
        expectDataType:http.HttpDataType.STRING
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') { throw new Error('Trakt discovery HTTP ' + response.responseCode); }
      const rows = JSON.parse(response.result) as DiscoverRow[];
      if (!Array.isArray(rows)) { throw new Error('Invalid discovery response'); }
      const items: DiscoverItem[] = [];
      for (const row of rows) {
        const title: DiscoverTitle | undefined = mode === 'popular' ? (row as DiscoverTitle) : (options.kind === 'movie' ? row.movie : row.show);
        if (!title || !title.ids || !Number.isSafeInteger(title.ids.trakt) || title.ids.trakt <= 0 || typeof title.title !== 'string') { throw new Error('Invalid discovery media'); }
        const media: Media = {id:options.kind+':'+title.ids.trakt,title:title.title,kind:options.kind,year:typeof title.year === 'number' ? title.year : 0,watched:false};
        const posters = title.images?.poster;
        items.push({media:media,rating:typeof title.rating === 'number' ? title.rating : 0,
          posterUrls:Array.isArray(posters) ? posters.filter((url: string) => typeof url === 'string' && url.length > 0) : [],
          posterUri:'',firstAired:options.kind === 'movie' ? title.released ?? '' : title.first_aired ?? ''});
      }
      const headers = JSON.parse(JSON.stringify(response.header).toLowerCase()) as Record<string,string>;
      return {items:items,page:Number(headers['x-pagination-page']),pages:Number(headers['x-pagination-page-count']),
        limit:Number(headers['x-pagination-limit']),count:rows.length};
    } finally { request.destroy(); }
  }
}
