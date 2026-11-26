import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';

interface DiscoverIds {
  trakt: number;
}
interface DiscoverImages {
  poster?: string[];
}
interface DiscoverTitle {
  ids: DiscoverIds;
  title: string;
  year?: number;
  rating?: number;
  images?: DiscoverImages;
}
interface DiscoverRow {
  movie?: DiscoverTitle;
  show?: DiscoverTitle;
}
export interface DiscoverItem {
  media: Media;
  posterUrls: string[];
  posterUri: string;
  rating: number;
}
export interface DiscoverPage {
  items: DiscoverItem[];
  page: number;
  pages: number;
}

// Two columns, six rows per page: bounded UI and no whole-library prefetch.
const PAGE_SIZE: number = 12;

export async function readDiscover(clientId: string, kind: string, mode: string,
  page: number): Promise<DiscoverPage> {
  if (!clientId || (kind !== 'movie' && kind !== 'show') ||
      (mode !== 'trending' && mode !== 'popular' && mode !== 'anticipated') ||
      !Number.isInteger(page) || page < 1) {
    throw new Error('Invalid discovery request');
  }
  const endpoint = kind === 'movie' ? 'movies' : 'shows';
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/' + endpoint + '/' + mode +
      '?extended=full&page=' + page + '&limit=' + PAGE_SIZE, {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': clientId, 'User-Agent': 'Showly-HarmonyOS-Personal/0.7.0' },
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Trakt discovery HTTP ' + response.responseCode);
    }
    const items: DiscoverItem[] = [];
    const seen: Set<string> = new Set<string>();
    const rows = JSON.parse(response.result) as DiscoverRow[];
    if (!Array.isArray(rows)) {
      throw new Error('Invalid discovery response');
    }
    for (const row of rows) {
      // Popular returns bare media; trending and anticipated wrap movie/show.
      const title: DiscoverTitle | undefined = mode === 'popular' ?
        (row as DiscoverTitle) : (kind === 'movie' ? row.movie : row.show);
      if (!title || !title.ids || !Number.isSafeInteger(title.ids.trakt) ||
          title.ids.trakt <= 0 || typeof title.title !== 'string') {
        throw new Error('Invalid discovery media');
      }
      const id = kind + ':' + title.ids.trakt;
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
      const posters = title.images?.poster;
      const media: Media = { id: id, title: title.title, kind: kind,
        year: typeof title.year === 'number' ? title.year : 0, watched: false };
      items.push({ media: media, rating: typeof title.rating === 'number' ? title.rating : 0,
        posterUrls: Array.isArray(posters) ? posters.filter((url: string) => typeof url === 'string' && url.length > 0) : [],
        posterUri: '' });
    }
    const headers = JSON.parse(JSON.stringify(response.header).toLowerCase()) as Record<string, string>;
    const pages = Number(headers['x-pagination-page-count']);
    const current = Number(headers['x-pagination-page']);
    if (!Number.isInteger(pages) || pages < 0 || current !== page ||
        (pages < page && !(page === 1 && rows.length === 0 && pages === 0))) {
      throw new Error('Invalid discovery pagination');
    }
    return { items: items, page: page, pages: pages };
  } finally {
    request.destroy();
  }
}
