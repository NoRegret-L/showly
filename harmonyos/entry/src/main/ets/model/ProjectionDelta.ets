// Reconstructible display-only index built from a fully validated journal.
// No write permission, receipt, checkpoint or upload consent is produced.
export class ProjectionInputIndex<S,I> {
  private stateByShow: Map<string,S>=new Map<string,S>();
  private intentByShow: Map<string,I[]>=new Map<string,I[]>();
  private owner: Map<number,string>=new Map<number,string>();
  private stateId: (state:S)=>string;
  private showId: (intent:I)=>string;
  private episodeId: (intent:I)=>number;
  constructor(stateId: (state:S)=>string,showId: (intent:I)=>string,episodeId: (intent:I)=>number) {
    this.stateId=stateId; this.showId=showId; this.episodeId=episodeId;
  }
  clear(): void { this.stateByShow.clear(); this.intentByShow.clear(); this.owner.clear(); }
  replaceAll(states: S[],intents: I[]): void {
    this.clear();
    for (const state of states) {
      const id=this.stateId(state);
      if (this.stateByShow.has(id)) { this.clear(); throw new Error('Duplicate catalog identity'); }
      this.stateByShow.set(id,state);
    }
    for (const intent of intents) {
      const id=this.showId(intent),ep=this.episodeId(intent);
      if (this.owner.has(ep)) { this.clear(); throw new Error('Conflicting episode identity'); }
      this.owner.set(ep,id);
      let rows=this.intentByShow.get(id);
      if (!rows) { rows=[];this.intentByShow.set(id,rows); }
      rows.push(intent);
    }
  }
  replaceShow(id: string,states: S[],intents: I[]): void {
    if (states.length>1 || states.some((state:S)=>this.stateId(state)!==id)) { throw new Error('Invalid scoped catalog'); }
    const seen=new Set<number>();
    for (const intent of intents) {
      const ep=this.episodeId(intent),owner=this.owner.get(ep);
      if (this.showId(intent)!==id || seen.has(ep) || (owner!==undefined && owner!==id)) { throw new Error('Conflicting episode identity'); }
      seen.add(ep);
    }
    for (const intent of this.intentByShow.get(id)??[]) { this.owner.delete(this.episodeId(intent)); }
    for (const intent of intents) { this.owner.set(this.episodeId(intent),id); }
    if (states.length) { this.stateByShow.set(id,states[0]); } else { this.stateByShow.delete(id); }
    if (intents.length) { this.intentByShow.set(id,intents); } else { this.intentByShow.delete(id); }
  }
  states(): S[] {
    const result:S[]=[];
    for (const id of Array.from(this.stateByShow.keys()).sort()) { const row=this.stateByShow.get(id); if (row!==undefined) { result.push(row); } }
    return result;
  }
  intents(): I[] {
    const result:I[]=[];
    for (const rows of this.intentByShow.values()) { for (const row of rows) { result.push(row); } }
    return result;
  }
}
