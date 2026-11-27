// Stable identity, independent content signatures. Legacy ArkUI onDataMove
// exchanges two positions; do not interpret it as a RecyclerView splice.
export interface ListDiffInput {
  oldIds: string[];
  oldKeys: string[];
  ids: string[];
  keys: string[];
}
export interface ListEdit { kind: string; index: number; to: number; }
export function sameListOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((id: string,i: number) => id === b[i]);
}
export function planListDiff(input: ListDiffInput): ListEdit[] {
  const oldIds = input.oldIds;
  const ids = input.ids;
  if (oldIds.length !== input.oldKeys.length || ids.length !== input.keys.length ||
      new Set<string>(oldIds).size !== oldIds.length || new Set<string>(ids).size !== ids.length) {
    return [{kind:'reload',index:0,to:0}];
  }
  if (!oldIds.length || !ids.length) {
    return oldIds.length === ids.length ? [] : [{kind:'reload',index:0,to:0}];
  }
  const edits: ListEdit[] = [];
  const target = new Set<string>(ids);
  const keys = new Map<string,string>();
  oldIds.forEach((id: string,i: number) => { keys.set(id,input.oldKeys[i]); });
  const work = [...oldIds];
  for (let i = work.length-1; i >= 0; i--) {
    if (!target.has(work[i])) { work.splice(i,1); edits.push({kind:'delete',index:i,to:0}); }
  }
  const known = new Set<string>(work);
  // Insert missing IDs into their final positions. Existing IDs are exchanged
  // subsequently; every notification uses the current array coordinates.
  for (let i = 0; i < ids.length; i++) {
    if (!known.has(ids[i])) {
      work.splice(i,0,ids[i]); known.add(ids[i]);
      keys.set(ids[i],input.keys[i]); edits.push({kind:'add',index:i,to:0});
    }
  }
  const positions = new Map<string,number>();
  work.forEach((id: string,i: number) => { positions.set(id,i); });
  for (let i = 0; i < ids.length; i++) {
    if (work[i] === ids[i]) { continue; }
    const from = positions.get(ids[i]) ?? -1;
    if (from < 0) { return [{kind:'reload',index:0,to:0}]; }
    const other = work[i];
    work[i] = work[from]; work[from] = other;
    positions.set(work[i],i); positions.set(other,from);
    edits.push({kind:'move',index:from,to:i});
  }
  for (let i = 0; i < ids.length; i++) {
    if (keys.get(ids[i]) !== input.keys[i]) { edits.push({kind:'change',index:i,to:0}); }
  }
  return edits;
}
