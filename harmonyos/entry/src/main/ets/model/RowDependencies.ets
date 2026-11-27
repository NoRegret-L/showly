// Rebuilt only when a list snapshot commits. Multiple cards may depend on one
// media ID, and a grid row may depend on multiple media IDs.
export class RowDependencies {
  private byId: Map<string,number>=new Map<string,number>();
  private reverse: Map<string,number[]>=new Map<string,number[]>();
  rebuild(ids: string[],dependencies: string[][]): void {
    this.byId.clear(); this.reverse.clear();
    for (let i=0;i<ids.length;i++) {
      this.byId.set(ids[i],i);
      for (const dep of new Set<string>(dependencies[i]??[])) {
        let rows=this.reverse.get(dep);
        if (!rows) { rows=[]; this.reverse.set(dep,rows); }
        rows.push(i);
      }
    }
  }
  indexOf(id: string): number { return this.byId.get(id)??-1; }
  affected(ids: string[]): number[] {
    const result=new Set<number>();
    for (const id of ids) { for (const index of this.reverse.get(id)??[]) { result.add(index); } }
    return Array.from(result);
  }
}
