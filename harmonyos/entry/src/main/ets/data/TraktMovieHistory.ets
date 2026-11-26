import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';

interface MovieIds { trakt: number; }
interface HistoryMovie { ids: MovieIds; }
export interface MoviePlay { id: number; watched_at: string; action: string; movie: HistoryMovie; }
export interface MovieHistory { count: number; plays: MoviePlay[]; }

export async function readMovieHistory(session: TraktSession, movieId: number): Promise<MovieHistory> {
  if (!Number.isSafeInteger(movieId) || movieId <= 0 ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Invalid movie request'); }
  const req = http.createHttp();
  try {
    const res = await req.request('https://api.trakt.tv/sync/history/movies/' + movieId + '?page=1&limit=2', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    if (!traktAuth.isCurrent(session.clientId, session.generation) ||
        res.responseCode !== 200 || typeof res.result !== 'string') {
      throw new Error('History verification HTTP ' + res.responseCode);
    }
    const rows = JSON.parse(res.result) as MoviePlay[];
    const headers = JSON.parse(JSON.stringify(res.header).toLowerCase()) as Record<string, string>;
    const count = Number(headers['x-pagination-item-count']);
    const page = Number(headers['x-pagination-page']);
    const pages = Number(headers['x-pagination-page-count']);
    if (!Array.isArray(rows) || page !== 1 || !Number.isSafeInteger(count) || count < 0 ||
        !Number.isSafeInteger(pages) || pages < 0 || rows.length !== Math.min(count, 2) ||
        (count > 0 && pages < 1)) { throw new Error('Incomplete history response'); }
    const seen: Set<number> = new Set<number>();
    for (const row of rows) {
      if (!Number.isSafeInteger(row.id) || row.id <= 0 || seen.has(row.id) ||
          row.movie?.ids?.trakt !== movieId || typeof row.watched_at !== 'string' ||
          !Number.isFinite(Date.parse(row.watched_at)) || typeof row.action !== 'string') {
        throw new Error('Invalid history identity');
      }
      seen.add(row.id);
    }
    return { count: count, plays: rows };
  } finally { req.destroy(); }
}
