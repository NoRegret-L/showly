import { ProgressRow, ProgressPreferences, ProgressFlag, sortProgressCandidates } from './ProgressRules';
import { MovieProgressSource, MovieProgressOptions, movieProgressRows } from './MovieProgressRules';
import { CollectionCandidate, CollectionOptions, projectCollection } from './CollectionRules';
import { PersonalLibraryRow } from './PersonalLibrary';
export interface ProgressSortInput { rows: ProgressRow[]; prefs: ProgressPreferences; filter: string; query: string; }
export interface MovieSortInput { sources: MovieProgressSource[]; flags: ProgressFlag[]; options: MovieProgressOptions; utc: string; query: string; seed: number; }
export interface CollectionSortInput { candidates: CollectionCandidate[]; options: CollectionOptions; section: string; query: string; now: number; }
export function sortShowDisplay(input: ProgressSortInput): ProgressRow[] {
  return sortProgressCandidates(input.rows,input.prefs,input.filter,input.query);
}
export function sortMovieDisplay(input: MovieSortInput): PersonalLibraryRow[] {
  return movieProgressRows(input.sources,input.flags,input.options,input.utc,input.query,input.seed);
}
export function sortCollectionDisplay(input: CollectionSortInput): PersonalLibraryRow[] {
  return projectCollection(input.candidates,input.options,input.section,input.query,input.now).map((x: CollectionCandidate) => x.row);
}
