import { Media } from './Media';
export interface TranslationText { title: string; overview: string; }
export interface TranslationCandidate { title?: string; overview?: string; language?: string; country?: string; }
export interface TitlePresentation { id: string; text: TranslationText; translatedAt: number; posterUrls: string[]; posterUri: string; }
export interface EpisodePresentation { id: number; number: number; text: TranslationText; }
export interface SeasonPresentation { showId: string; season: number; fetchedAt: number; episodes: EpisodePresentation[]; }
export interface PresentationTask { media: Media; artwork: boolean; season: number; posterUrls: string[]; }
const DAY = 86400000;
// Android ConfigVariant release values.
export const TITLE_RETRY = 5 * DAY;
export const SEASON_RETRY = 3 * DAY;
export function validTitleId(id: string): boolean { return /^(show|movie):[1-9][0-9]*$/.test(id); }
export function chineseText(rows: TranslationCandidate[]): TranslationText {
  const p = rows.find((row: TranslationCandidate) => !!row && row.language?.toLowerCase() === 'zh' && row.country?.toLowerCase() === 'cn');
  return { title: typeof p?.title === 'string' ? p.title.trim() : '', overview: typeof p?.overview === 'string' ? p.overview.trim() : '' };
}
// Android TranslationMapper uses the first season translation. Prefer an
// explicitly mainland Chinese entry if present, then a Chinese entry with
// unspecified country, never a foreign-language response.
export function chineseEpisodeText(rows: TranslationCandidate[]): TranslationText {
  const cn = chineseText(rows);
  if (cn.title || cn.overview) { return cn; }
  const p = rows.find((row: TranslationCandidate) => !!row && row.language?.toLowerCase() === 'zh' && !row.country);
  return { title: typeof p?.title === 'string' ? p.title.trim() : '', overview: typeof p?.overview === 'string' ? p.overview.trim() : '' };
}
export function validText(text: TranslationText): boolean {
  return !!text && typeof text.title === 'string' && typeof text.overview === 'string';
}
export function validTitle(row: TitlePresentation): boolean {
  return !!row && validTitleId(row.id) && validText(row.text) && Number.isSafeInteger(row.translatedAt) &&
    row.translatedAt >= 0 && Array.isArray(row.posterUrls) &&
    row.posterUrls.every((url: string) => typeof url === 'string') && typeof row.posterUri === 'string';
}
export function validSeason(row: SeasonPresentation): boolean {
  if (!row || !/^show:[1-9][0-9]*$/.test(row.showId) || !Number.isSafeInteger(row.season) ||
      row.season <= 0 || !Number.isSafeInteger(row.fetchedAt) || row.fetchedAt <= 0 || !Array.isArray(row.episodes)) { return false; }
  const ids = new Set<number>(); const positions = new Set<number>();
  for (const ep of row.episodes) {
    if (!ep || !Number.isSafeInteger(ep.id) || ep.id <= 0 || ids.has(ep.id) ||
        !Number.isSafeInteger(ep.number) || ep.number <= 0 || positions.has(ep.number) || !validText(ep.text)) { return false; }
    ids.add(ep.id); positions.add(ep.number);
  }
  return true;
}
export function titleNeedsTranslation(row: TitlePresentation | undefined, now: number): boolean {
  return !row || ((!row.text.title || !row.text.overview) && (!row.translatedAt || now - row.translatedAt >= TITLE_RETRY));
}
export function seasonNeedsTranslation(row: SeasonPresentation | undefined, now: number): boolean {
  return !row || now - row.fetchedAt >= SEASON_RETRY;
}
export function localizedTitle(media: Media, rows: TitlePresentation[], language: string): string {
  return language === 'zh' ? rows.find((row: TitlePresentation) => row.id === media.id)?.text.title || media.title : media.title;
}
export function localizedEpisode(showId: string, season: number, id: number, original: string,
  rows: SeasonPresentation[], language: string): string {
  if (language !== 'zh') { return original; }
  return rows.find((row: SeasonPresentation) => row.showId === showId && row.season === season)
    ?.episodes.find((ep: EpisodePresentation) => ep.id === id)?.text.title || original;
}
export function searchKey(value: string): string { return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase(); }
export function matchesText(query: string, original: string, localized: string): boolean {
  const key = searchKey(query.trim());
  return !key || searchKey(original).includes(key) || searchKey(localized).includes(key);
}
export function compareTitles(a: string, b: string, language: string): number {
  return a.replace(/^the /i, '').localeCompare(b.replace(/^the /i, ''), language === 'zh' ? 'zh-CN' : 'en');
}
export function mergeText(old: TranslationText, next: TranslationText): TranslationText {
  return { title: next.title || old.title, overview: next.overview || old.overview };
}
export function imageFormat(bytes: Uint8Array): string {
  if (bytes.length >= 12 && bytes[0] === 82 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 70 &&
      bytes[8] === 87 && bytes[9] === 69 && bytes[10] === 66 && bytes[11] === 80) { return 'webp'; }
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) { return 'jpeg'; }
  if (bytes.length >= 8 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 &&
      bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10) { return 'png'; }
  return '';
}
