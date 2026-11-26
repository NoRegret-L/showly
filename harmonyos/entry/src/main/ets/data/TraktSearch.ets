import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';

interface TraktIds {
  trakt: number;
}

interface TraktTitle {
  title: string;
  year?: number;
  ids: TraktIds;
}

interface SearchResult {
  type: string;
  show?: TraktTitle;
  movie?: TraktTitle;
}

export async function searchTrakt(query: string, clientId: string): Promise<Media[]> {
  const request = http.createHttp();
  try {
    const response = await request.request(
      'https://api.trakt.tv/search/show,movie?query=' + encodeURIComponent(query),
      {
        method: http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
        expectDataType: http.HttpDataType.STRING
      });
    if (response.responseCode !== 200) {
      throw new Error('Trakt HTTP ' + response.responseCode);
    }
    if (typeof response.result !== 'string') {
      throw new Error('Invalid Trakt response');
    }
    const results = JSON.parse(response.result) as SearchResult[];
    if (!Array.isArray(results)) {
      throw new Error('Invalid Trakt results');
    }
    const items: Media[] = [];
    const ids: Set<string> = new Set<string>();
    for (const result of results) {
      if (result.type !== 'show' && result.type !== 'movie') {
        continue;
      }
      const value = result.type === 'show' ? result.show : result.movie;
      if (!value || !value.ids || typeof value.ids.trakt !== 'number' || typeof value.title !== 'string') {
        continue;
      }
      const id: string = result.type + ':' + value.ids.trakt;
      if (ids.has(id)) {
        continue;
      }
      ids.add(id);
      items.push({ id: id, title: value.title, kind: result.type, year: value.year ?? 0, watched: false });
    }
    return items;
  } finally {
    request.destroy();
  }
}
