import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';
import { Media } from '../model/Media';
import { canReadDetails } from './TraktDetails';

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

export async function readSeriesProgress(item: Media, session: TraktSession): Promise<SeriesProgress> {
  if (item.kind !== 'show' || !canReadDetails(item) ||
      !traktAuth.isCurrent(session.clientId, session.generation)) {
    throw new Error('Invalid show or session');
  }
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/shows/' + item.id.substring(5) +
      '/progress/watched?hidden=false&specials=false&count_specials=false', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
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
    request.destroy();
  }
}

export async function readChinese(item: Media, clientId: string): Promise<ChineseText> {
  if (!clientId || !canReadDetails(item)) {
    throw new Error('Invalid translation request');
  }
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/' +
      (item.kind === 'movie' ? 'movies/' : 'shows/') + item.id.substring(item.kind.length + 1) +
      '/translations/zh', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('Translation HTTP ' + response.responseCode);
    }
    const rows = JSON.parse(response.result) as Translation[];
    if (!Array.isArray(rows)) {
      throw new Error('Invalid translations');
    }
    const chinese = rows.filter((row: Translation) => row.language === 'zh');
    const preferred = chinese.find((row: Translation) => row.country === 'cn') ?? chinese[0];
    return { title: typeof preferred?.title === 'string' ? preferred.title : '',
      overview: typeof preferred?.overview === 'string' ? preferred.overview : '' };
  } finally {
    request.destroy();
  }
}
