import { http } from '@kit.NetworkKit';
import { TraktSession, traktAuth } from './TraktAuth';

interface HistoryIds { trakt: number; }
interface HistoryEpisode { ids: HistoryIds; }
export interface SinglePlay {
  id: number;
  watched_at: string;
  action: string;
  episode: HistoryEpisode;
}
export interface EpisodeHistory {
  count: number;
  plays: SinglePlay[];
}

export function sameMinute(a: string, b: string): boolean {
  const left = Date.parse(a);
  const right = Date.parse(b);
  return Number.isFinite(left) && Number.isFinite(right) &&
    Math.floor(left / 60000) === Math.floor(right / 60000);
}

// Two rows are enough to reject ambiguous histories; do not pick a newest
// play when more than one exists. Require validated pagination metadata.
export async function readEpisodeHistory(session: TraktSession, episodeId: number): Promise<EpisodeHistory> {
  if (!Number.isSafeInteger(episodeId) || episodeId <= 0 ||
      !traktAuth.isCurrent(session.clientId, session.generation)) { throw new Error('Invalid history request'); }
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/sync/history/episodes/' + episodeId + '?page=1&limit=2', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
        'trakt-api-key': session.clientId, 'Authorization': 'Bearer ' + session.token },
      expectDataType: http.HttpDataType.STRING
    });
    if (!traktAuth.isCurrent(session.clientId, session.generation) ||
        response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('History verification HTTP ' + response.responseCode);
    }
    const rows = JSON.parse(response.result) as SinglePlay[];
    const headers = JSON.parse(JSON.stringify(response.header).toLowerCase()) as Record<string, string>;
    const count = Number(headers['x-pagination-item-count']);
    const page = Number(headers['x-pagination-page']);
    const pages = Number(headers['x-pagination-page-count']);
    if (!Array.isArray(rows) || page !== 1 || !Number.isSafeInteger(count) || count < 0 ||
        !Number.isSafeInteger(pages) || pages < 0 || rows.length !== Math.min(count, 2) ||
        (count > 0 && pages < 1)) { throw new Error('Incomplete history response'); }
    const seen: Set<number> = new Set<number>();
    for (const row of rows) {
      // History IDs are int64. Reject unsafe JS integers rather than round.
      if (!Number.isSafeInteger(row.id) || row.id <= 0 || seen.has(row.id) ||
          row.episode?.ids?.trakt !== episodeId || typeof row.watched_at !== 'string' ||
          !Number.isFinite(Date.parse(row.watched_at)) || typeof row.action !== 'string') {
        throw new Error('Invalid history identity');
      }
      seen.add(row.id);
    }
    return { count: count, plays: rows };
  } finally { request.destroy(); }
}
