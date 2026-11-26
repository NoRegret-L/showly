import { PersonalLibraryRow, hasTrackingEvidence, isPersonalMember, filterPersonalLibrary } from './PersonalLibrary';

export interface CollectionGroup {
  key: string;
  label: string;
  rows: PersonalLibraryRow[];
}
export interface GroupEntry {
  key: string;
  label: string;
  row: PersonalLibraryRow;
}
export function normalizeMode(mode: string): string { return mode === 'movie' ? 'movie' : 'show'; }
export function progressTabs(mode: string): string[] {
  return mode === 'movie' ? ['next','calendar'] : ['next','calendar','history'];
}
export function collectionRows(rows: PersonalLibraryRow[], mode: string, section: string, status: string = 'all'): PersonalLibraryRow[] {
  if (section === 'other') {
    return rows.filter((row: PersonalLibraryRow) => row.media.kind === 'manual' ||
      (row.media.kind === mode && !isPersonalMember(row)));
  }
  const typed = rows.filter((row: PersonalLibraryRow) => row.media.kind === mode);
  if (section === 'queue') { return typed.filter((row: PersonalLibraryRow) => row.queued); }
  if (section !== 'mine') { return []; }
  const members = typed.filter((row: PersonalLibraryRow) => mode === 'show' ? hasTrackingEvidence(row) : row.watched);
  return mode === 'show' && ['watching','finished','upcoming','unclassified'].includes(status) ?
    filterPersonalLibrary(members, status) : members;
}
export function collectionGroups(rows: PersonalLibraryRow[], mode: string, section: string, status: string = 'all'): CollectionGroup[] {
  const members = collectionRows(rows, mode, section, status);
  if (!members.length) { return []; }
  const key = section === 'mine' ? mode === 'show' ? status : 'all' : section;
  const label = key === 'watching' ? '正在追' : key === 'finished' ? '已完结' : key === 'upcoming' ? '等待更新' :
    key === 'unclassified' ? '待核实' : key === 'all' ? '全部' : key === 'queue' ? '待看清单' : '其他条目';
  return [{ key: key, label: label, rows: members }];
}
// One main list, one selected status; never append the same member again in All.
export function groupEntries(groups: CollectionGroup[]): GroupEntry[] {
  const entries: GroupEntry[] = [];
  for (const group of groups) {
    for (const row of group.rows) { entries.push({ key: group.key, label: group.label, row: row }); }
  }
  return entries;
}
export function pageGroups(entries: GroupEntry[], page: number, size: number): CollectionGroup[] {
  const groups: CollectionGroup[] = [];
  for (const entry of entries.slice((page - 1) * size, page * size)) {
    let group = groups[groups.length - 1];
    if (!group || group.key !== entry.key) {
      group = { key: entry.key, label: entry.label, rows: [] };
      groups.push(group);
    }
    group.rows.push(entry.row);
  }
  return groups;
}
export interface MovieDate {
  id: string;
  released: string;
}
export function releasedWatchlist(rows: PersonalLibraryRow[], dates: MovieDate[], today: string): PersonalLibraryRow[] {
  const released: Set<string> = new Set<string>(dates.filter((date: MovieDate) =>
    /^\d{4}-\d{2}-\d{2}$/.test(date.released) && date.released <= today).map((date: MovieDate) => date.id));
  return rows.filter((row: PersonalLibraryRow) => row.media.kind === 'movie' && row.queued && !row.watched && released.has(row.media.id));
}
