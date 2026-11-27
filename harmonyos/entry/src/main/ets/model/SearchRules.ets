import { Media } from './Media';
import { matchesText, validTitleId } from './MediaPresentation';
export const SEARCH_LIMIT: number=50;
export const SEARCH_SUGGESTIONS: number=5;
export const SEARCH_RECENTS: number=5;
export const SEARCH_MIN_SUGGESTION: number=2;
export interface SearchRecord { media: Media; votes: number; }
export interface SearchCandidate { media: Media; votes: number; localized: string; }
export interface SearchOptions { kind: string; sort: string; descending: boolean; }
export interface SearchInput { catalog: SearchCandidate[]; remote: SearchCandidate[]; query: string; suggestions: boolean; options: SearchOptions; }
export function defaultSearch(): SearchOptions { return {kind:'all',sort:'rank',descending:false}; }
export function validSearchRecord(row: SearchRecord): boolean {
  return !!row && !!row.media && validTitleId(row.media.id) && row.media.id.startsWith(row.media.kind+':') &&
    typeof row.media.title==='string' && !!row.media.title.trim() && Number.isSafeInteger(row.media.year) &&
    row.media.year>=0 && Number.isFinite(row.votes) && row.votes>=0;
}
export function publicSearchRecord(media: Media,votes: number=0): SearchRecord {
  return {media:{id:media.id,kind:media.kind,title:media.title,year:media.year,watched:false},votes:votes};
}
export function searchScope(client: string,account: string): string { return account ? JSON.stringify([client,account]) : ''; }
export class SearchGeneration {
  private serial: number=0;
  begin(): number { return ++this.serial; }
  current(token: number): boolean { return token===this.serial; }
  cancel(): void { this.serial++; }
}
export function searchRows(input: SearchInput): Media[] {
  const query=input.query.trim();
  if (!query || (input.suggestions && query.length<SEARCH_MIN_SUGGESTION)) { return []; }
  const seen=new Set<string>();
  const rows: SearchCandidate[]=[];
  const allowed=(row: SearchCandidate): boolean=>input.options.kind==='all' || row.media.kind===input.options.kind;
  if (input.suggestions) {
    let shows=0; let movies=0;
    for (const row of input.catalog) {
      if (!allowed(row) || seen.has(row.media.id) || !matchesText(query,row.media.title,row.localized)) { continue; }
      if (row.media.kind==='show' && shows<SEARCH_SUGGESTIONS) { shows++; }
      else if (row.media.kind==='movie' && movies<SEARCH_SUGGESTIONS) { movies++; }
      else { continue; }
      seen.add(row.media.id); rows.push(row);
    }
    rows.sort((a: SearchCandidate,b: SearchCandidate)=>b.votes-a.votes);
  } else {
    for (const row of input.remote) {
      if (allowed(row) && !seen.has(row.media.id)) { seen.add(row.media.id); rows.push(row); }
    }
    for (const row of input.catalog) {
      if (allowed(row) && !seen.has(row.media.id) && matchesText(query,row.media.title,row.localized)) { seen.add(row.media.id); rows.push(row); }
    }
    if (input.options.sort==='rank') {
      if (input.options.descending) { rows.reverse(); }
    } else {
      const sign=input.options.descending ? -1 : 1;
      rows.sort((a: SearchCandidate,b: SearchCandidate)=>{
        if (input.options.sort==='year') { return sign*(a.media.year-b.media.year); }
        const x=(a.localized || a.media.title).toUpperCase();
        const y=(b.localized || b.media.title).toUpperCase();
        return sign*(x<y ? -1 : x>y ? 1 : 0);
      });
    }
  }
  return rows.map((row: SearchCandidate)=>row.media);
}

// Keep ID ordering and candidate identity across translation-only updates.
// Catalog/account/membership changes still use the original full reconstruction.
export class SearchCandidateTitles {
  private rows:SearchCandidate[]=[];
  private positions:Map<string,number>=new Map<string,number>();
  private patches:number=0;
  clear():void{this.rows=[];this.positions.clear();}
  seed(rows:SearchCandidate[]):void{
    this.clear();this.rows=rows;
    for(let i=0;i<rows.length;i++){if(this.positions.has(rows[i].media.id)){this.clear();return;}this.positions.set(rows[i].media.id,i);}
  }
  get(id:string):SearchCandidate|undefined{const pos=this.positions.get(id);return pos===undefined?undefined:this.rows[pos];}
  private reindex(from:number):void{for(let i=from;i<this.rows.length;i++){this.positions.set(this.rows[i].media.id,i);}}
  upsert(row:SearchCandidate):void{
    const id=row.media.id,pos=this.positions.get(id);
    if(pos!==undefined){const old=this.rows[pos];if(old.media===row.media&&old.votes===row.votes&&old.localized===row.localized){return;}
      this.rows[pos]=row;this.patches++;return;}
    let lo=0,hi=this.rows.length;
    while(lo<hi){const mid=Math.floor((lo+hi)/2);if(this.rows[mid].media.id<id){lo=mid+1;}else{hi=mid;}}
    this.rows.splice(lo,0,row);this.reindex(lo);this.patches++;
  }
  remove(id:string):void{const pos=this.positions.get(id);if(pos===undefined){return;}this.rows.splice(pos,1);this.positions.delete(id);this.reindex(pos);this.patches++;}
  patch(id:string,title:string):void{
    const pos=this.positions.get(id);if(pos===undefined){return;}
    const old=this.rows[pos];if(old.localized===title){return;}
    this.rows[pos]={media:old.media,votes:old.votes,localized:title};this.patches++;
  }
  patchCount():number{return this.patches;}
}

// Columnar wire format preserves every SearchCandidate field and input order.
// It removes repeated JSON field names, not search semantics.
export interface SearchColumns {id:string[];kind:string[];title:string[];year:number[];watched:boolean[];votes:number[];localized:string[];}
export interface SearchWire {catalog:SearchColumns;remote:SearchColumns;query:string;suggestions:boolean;options:SearchOptions;}
function packSearchRows(rows:SearchCandidate[]):SearchColumns{
  const result:SearchColumns={id:[],kind:[],title:[],year:[],watched:[],votes:[],localized:[]};
  for(const row of rows){result.id.push(row.media.id);result.kind.push(row.media.kind);result.title.push(row.media.title);result.year.push(row.media.year);
    result.watched.push(row.media.watched);result.votes.push(row.votes);result.localized.push(row.localized);}
  return result;
}
function unpackSearchRows(rows:SearchColumns):SearchCandidate[]{
  const result:SearchCandidate[]=[];
  for(let i=0;i<rows.id.length;i++){result.push({media:{id:rows.id[i],kind:rows.kind[i],title:rows.title[i],year:rows.year[i],watched:rows.watched[i]},votes:rows.votes[i],localized:rows.localized[i]});}
  return result;
}
export function packSearch(input:SearchInput):SearchWire{
  return {catalog:packSearchRows(input.catalog),remote:packSearchRows(input.remote),query:input.query,suggestions:input.suggestions,options:input.options};
}
export function unpackSearch(input:SearchWire):SearchInput{
  return {catalog:unpackSearchRows(input.catalog),remote:unpackSearchRows(input.remote),query:input.query,suggestions:input.suggestions,options:input.options};
}
