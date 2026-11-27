import { http } from '@kit.NetworkKit';
import { SearchRecord, publicSearchRecord, SEARCH_LIMIT } from '../model/SearchRules';
import { checkPresentationService, presentationHttpError, traktPresentationService } from './PresentationHttp';

interface TraktIds {
  trakt: number;
}

interface TraktTitle {
  title: string;
  year?: number;
  votes?: number;
  ids: TraktIds;
}

interface SearchResult {
  type: string;
  show?: TraktTitle;
  movie?: TraktTitle;
}

export async function searchTrakt(query: string, clientId: string): Promise<SearchRecord[]> {
  const service=traktPresentationService(clientId);
  checkPresentationService(service);
  const request = http.createHttp();
  try {
    const response = await request.request(
      'https://api.trakt.tv/search/show,movie?query=' + encodeURIComponent(query) + '&extended=full&limit=' + SEARCH_LIMIT,
      {
        method: http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
        expectDataType: http.HttpDataType.STRING
      });
    if (response.responseCode !== 200) {
      throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);
    }
    if (typeof response.result !== 'string') {
      throw new Error('Invalid Trakt response');
    }
    const results = JSON.parse(response.result) as SearchResult[];
    if (!Array.isArray(results)) {
      throw new Error('Invalid Trakt results');
    }
    const items: SearchRecord[] = [];
    const ids: Set<string> = new Set<string>();
    for (const result of results) {
      if (result.type !== 'show' && result.type !== 'movie') {
        continue;
      }
      const value = result.type === 'show' ? result.show : result.movie;
      if (!value || !value.ids || !Number.isSafeInteger(value.ids.trakt) || value.ids.trakt <= 0 || typeof value.title !== 'string') {
        continue;
      }
      const id: string = result.type + ':' + value.ids.trakt;
      if (ids.has(id)) {
        continue;
      }
      ids.add(id);
      items.push(publicSearchRecord({id:id,title:value.title,kind:result.type,year:Number.isSafeInteger(value.year ?? 0) && (value.year ?? 0)>=0 ? value.year ?? 0 : 0,watched:false},Number.isFinite(value.votes ?? 0) && (value.votes ?? 0)>=0 ? value.votes ?? 0 : 0));
    }
    return items;
  } finally {
    request.destroy();
  }
}
