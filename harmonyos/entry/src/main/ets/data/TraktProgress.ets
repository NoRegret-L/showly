import { ReadCancel } from '../model/ReadFlight';
import { http } from '@kit.NetworkKit';
import { checkPresentationService, presentationHttpError, traktPresentationService } from './PresentationHttp';
import { TraktSession, traktAuth } from './TraktAuth';
import { Media } from '../model/Media';
import { canReadDetails } from './TraktDetails';
import { chineseText, chineseEpisodeText, TranslationCandidate, SeasonPresentation, EpisodePresentation, validSeason } from '../model/MediaPresentation';

export interface EpisodeProgress {
  number: number;
  completed: boolean;
}
export interface SeasonProgress {
  number: number;
  aired: number;
  completed: number;
  episodes: EpisodeProgress[];
}
export interface SeriesProgress {
  aired: number;
  completed: number;
  seasons: SeasonProgress[];
}
interface Translation {
  title?: string;
  overview?: string;
  language?: string;
  country?: string;
}
export interface ChineseText {
  title: string;
  overview: string;
}

function count(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

export async function readSeriesProgress(item: Media, session: TraktSession, scope?: ReadCancel): Promise<SeriesProgress> {
  if (item.kind !== 'show' || !canReadDetails(item) ||
      !traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Invalid show or session');
  }
  scope?.check();
  const request = http.createHttp();
  let closed=false;
  const close=(): void=>{ if (!closed) { closed=true; request.destroy(); } };
  scope?.subscribe(close);
  try {
    const response = await request.request('https://api.trakt.tv/shows/' + item.id.substring(5) +
      '/progress/watched?hidden=false&specials=false&count_specials=false', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    scope?.check();
    if (!traktAuth.isCurrent(session.clientId, session.generation) ||
        response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Progress HTTP ' + response.responseCode);
    }
    const data = JSON.parse(response.result) as SeriesProgress;
    if (!count(data.aired) || !count(data.completed) || data.completed > data.aired ||
        !Array.isArray(data.seasons)) {
      throw new Error('Invalid progress response');
    }
    const seen: Set<number> = new Set<number>();
    for (const season of data.seasons) {
      if (!count(season.number) || season.number === 0 || seen.has(season.number) ||
          !count(season.aired) || !count(season.completed) || season.completed > season.aired ||
          !Array.isArray(season.episodes)) {
        throw new Error('Invalid season');
      }
      seen.add(season.number);
      const episodes: Set<number> = new Set<number>();
      for (const episode of season.episodes) {
        if (!count(episode.number) || episodes.has(episode.number) || typeof episode.completed !== 'boolean') {
          throw new Error('Invalid episode');
        }
        episodes.add(episode.number);
      }
    }
    return data;
  } finally {
    scope?.unsubscribe(close); close();
  }
}

export async function readChinese(item: Media, clientId: string, scope?: ReadCancel): Promise<ChineseText> {
  if (!clientId || !canReadDetails(item)) {
    throw new Error('Invalid translation request');
  }
  const service=traktPresentationService(clientId);
  checkPresentationService(service);
  scope?.check();
  const request = http.createHttp();
  let closed=false;
  const close=(): void=>{ if (!closed) { closed=true; request.destroy(); } };
  scope?.subscribe(close);
  try {
    const response = await request.request('https://api.trakt.tv/' +
      (item.kind === 'movie' ? 'movies/' : 'shows/') + item.id.substring(item.kind.length + 1) +
      '/translations/zh', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    scope?.check();
    if (response.responseCode === 404) { return { title: '', overview: '' }; }
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);
    }
    const rows = JSON.parse(response.result) as Translation[];
    if (!Array.isArray(rows)) {
      throw new Error('Invalid translations');
    }
    const text = chineseText(rows.map((row: Translation): TranslationCandidate => ({ title: row.title, overview: row.overview, language: row.language, country: row.country })));
    return { title: text.title, overview: text.overview };
  } finally {
    scope?.unsubscribe(close); close();
  }
}

interface SeasonTranslationIds { trakt: number; }
interface RemoteSeasonTranslation { season: number; number: number; ids: SeasonTranslationIds; translations?: TranslationCandidate[]; }
export async function readChineseSeason(item: Media, season: number, clientId: string, scope?: ReadCancel): Promise<SeasonPresentation> {
  if (!clientId || item.kind !== 'show' || !canReadDetails(item) || !Number.isSafeInteger(season) || season <= 0) {
    throw new Error('Invalid season translation identity');
  }
  const service=traktPresentationService(clientId);
  checkPresentationService(service);
  scope?.check();
  const request = http.createHttp();
  let closed=false;
  const close=(): void=>{ if (!closed) { closed=true; request.destroy(); } };
  scope?.subscribe(close);
  try {
    const response = await request.request('https://api.trakt.tv/shows/' + item.id.substring(5) +
      '/seasons/' + season + '?translations=zh', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    scope?.check();
    if (response.responseCode === 404) { return { showId: item.id, season: season, fetchedAt: Date.now(), episodes: [] }; }
    if (response.responseCode !== 200 || typeof response.result !== 'string') { throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true); }
    const rows = JSON.parse(response.result) as RemoteSeasonTranslation[];
    if (!Array.isArray(rows)) { throw new Error('Invalid season translation response'); }
    const episodes: EpisodePresentation[] = [];
    for (const row of rows) {
      if (!row || row.season !== season || !row.ids ||
          (row.translations !== undefined && row.translations !== null && !Array.isArray(row.translations))) { throw new Error('Season translation identity mismatch'); }
      episodes.push({ id: row.ids.trakt, number: row.number, text: chineseEpisodeText(row.translations ?? []) });
    }
    const result: SeasonPresentation = { showId: item.id, season: season, fetchedAt: Date.now(), episodes: episodes };
    if (!validSeason(result)) { throw new Error('Invalid translated episode identity'); }
    return result;
  } finally { scope?.unsubscribe(close); close(); }
}
