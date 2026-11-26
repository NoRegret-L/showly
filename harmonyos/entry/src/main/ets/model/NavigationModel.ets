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
export function collectionRows(rows: PersonalLibraryRow[], mode: string, section: string): PersonalLibraryRow[] {
  if (section === 'other') {
    return rows.filter((row: PersonalLibraryRow) => row.media.kind === 'manual' ||
      (row.media.kind === mode && !isPersonalMember(row)));
  }
  const typed = rows.filter((row: PersonalLibraryRow) => row.media.kind === mode);
  if (section === 'queue') { return typed.filter((row: PersonalLibraryRow) => row.queued); }
  if (section !== 'mine') { return []; }
  return typed.filter((row: PersonalLibraryRow) => mode === 'show' ? hasTrackingEvidence(row) : row.watched);
}
export function collectionGroups(rows: PersonalLibraryRow[], mode: string, section: string): CollectionGroup[] {
  const members = collectionRows(rows, mode, section);
  const groups: CollectionGroup[] = [];
  if (section === 'mine' && mode === 'show') {
    for (const key of ['watching','finished','upcoming']) {
      const selected = filterPersonalLibrary(members, key);
      if (selected.length) {
        groups.push({ key: key, label: key === 'watching' ? '正在追' : key === 'finished' ? '已完结' : '等待更新', rows: selected });
      }
    }
  }
  if (members.length) {
    groups.push({ key: section === 'mine' ? 'all' : section,
      label: section === 'mine' ? '全部' : section === 'queue' ? '待看清单' : '其他条目', rows: members });
  }
  return groups;
}
// Original sections may contain the same title as All. Pagination retains
// headings; poster requests deduplicate IDs separately.
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
