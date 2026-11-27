import { Media } from '../model/Media';
import { EpisodeStore, EpisodeBackupState, LocalEpisode } from './EpisodeStore';
import { showSections } from '../model/ShowCatalog';
import { ProgressSource } from '../model/ProgressRules';

export interface NextShow {
  media: Media;
  total: number;
  completed: number;
  nextSeason: number;
  nextNumber: number;
  nextTitle: string;
  lastSeq: number;
  sections?: string[];
  source?: ProgressSource;
  sourceStateKey?: string;
  sourceCatalogKey?: string;
}

export function projectShow(state: EpisodeBackupState, lastSeq: number): NextShow {
  const watched: Set<number> = new Set<number>(state.watchedIds);
  const ordered = [...state.catalog.episodes].sort((a: LocalEpisode, b: LocalEpisode) =>
    a.season - b.season || a.number - b.number);
  const next = ordered.find((ep: LocalEpisode) => !watched.has(ep.id));
  return { media: { id: state.catalog.showId, title: state.catalog.title, kind: 'show',
    year: state.catalog.year, watched: false }, total: ordered.length,
    completed: ordered.filter((ep: LocalEpisode) => watched.has(ep.id)).length,
    nextSeason: next?.season ?? 0, nextNumber: next?.number ?? 0, nextTitle: next?.title ?? '',
    lastSeq: lastSeq };
}

export async function readNextShows(store: EpisodeStore): Promise<NextShow[]> {
  const revision = store.readModelRevision();
  const inputs = await store.projectionLocalInputs(await store.boundAccount());
  const states = inputs.states;
  const intents = inputs.intents;
  const schedules = await store.projectionCatalogs(new Set<string>(states.map((state: EpisodeBackupState) => state.catalog.showId)));
  if (store.readModelRevision() !== revision) { throw new Error('Local read inputs changed'); }
  const latest: Map<string, number> = new Map<string, number>();
  for (const intent of intents) {
    latest.set(intent.showId, Math.max(latest.get(intent.showId) ?? 0, intent.seq));
  }
  const result: NextShow[] = [];
  const now = Date.now();
  for (const state of states) {
    const row = projectShow(state, latest.get(state.catalog.showId) ?? 0);
    const full = schedules.get(state.catalog.showId);
    if (full) { row.sections = showSections(full, state.watchedIds, now); }
    result.push(row);
  }
  return result;
}

export function sortNextShows(rows: NextShow[], mode: string): NextShow[] {
  return [...rows].sort((a: NextShow, b: NextShow) => {
    if (mode === 'remaining') {
      const remaining = (a.total - a.completed) - (b.total - b.completed);
      if (remaining !== 0) { return remaining; }
    }
    if (mode === 'recent' && a.lastSeq !== b.lastSeq) { return b.lastSeq - a.lastSeq; }
    return a.media.title.localeCompare(b.media.title) || a.media.id.localeCompare(b.media.id);
  });
}
