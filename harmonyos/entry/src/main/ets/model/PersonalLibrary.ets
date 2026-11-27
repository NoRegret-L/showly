import { Media } from './Media';
import { MediaRecord, inLocalWatchlist } from './MediaState';

// Counts describe separate observations, not additive histories.
export interface LibraryShowEvidence {
  media: Media;
  watchedEpisodes: number;
  sections?: string[];
  merged?: boolean;
  effectiveWatched?: number;
  effectiveTotal?: number;
}
export interface PersonalLibraryRow {
  media: Media;
  localRecord?: MediaRecord;
  queued: boolean;
  watched: boolean;
  localEpisodes: number;
  cloudEpisodes: number;
  sections?: string[];
  merged?: boolean;
  effectiveWatched?: number;
  effectiveTotal?: number;
}

function addRow(rows: Map<string, PersonalLibraryRow>, media: Media): PersonalLibraryRow {
  const existing = rows.get(media.id);
  if (existing) { return existing; }
  const row: PersonalLibraryRow = { media: media, queued: false, watched: false,
    localEpisodes: -1, cloudEpisodes: -1 };
  rows.set(media.id, row);
  return row;
}

// Read-only union. Explicit device intents override positive cloud observations
// for the corresponding domain only. Legacy fallbacks are not sync intents.
// A missing catalog or remote observation is unknown, not a negative fact.
export function buildPersonalLibrary(records: MediaRecord[], cloudMovies: Media[], cloudWatchlist: Media[],
  cloudShows: LibraryShowEvidence[], localShows: LibraryShowEvidence[]): PersonalLibraryRow[] {
  const rows: Map<string, PersonalLibraryRow> = new Map<string, PersonalLibraryRow>();
  for (const record of records) {
    const row = addRow(rows, record.media);
    row.localRecord = record;
    row.queued = inLocalWatchlist(record);
    row.watched = record.media.watched;
  }
  for (const media of cloudMovies) {
    const row = addRow(rows, media);
    if (row.localRecord?.movieState !== 'no') { row.watched = true; }
  }
  for (const media of cloudWatchlist) {
    const row = addRow(rows, media);
    if (row.localRecord?.watchlistState !== 'no' && row.localRecord?.followState !== 'yes') { row.queued = true; }
  }
  for (const show of cloudShows) {
    const row = addRow(rows, show.media);
    row.cloudEpisodes = show.watchedEpisodes;
  }
  for (const show of localShows) {
    // Opening a detail page may cache a catalog without following the title.
    if (show.watchedEpisodes > 0 || rows.has(show.media.id)) {
      const row = addRow(rows, show.media);
      row.localEpisodes = show.watchedEpisodes;
      row.sections = show.sections;
      row.merged = show.merged;
      row.effectiveWatched = show.effectiveWatched;
      row.effectiveTotal = show.effectiveTotal;
    }
  }
  return Array.from(rows.values());
}

export function hasTrackingEvidence(row: PersonalLibraryRow): boolean {
  return row.media.kind === 'show' && (row.localRecord?.followState === 'yes' ||
    (row.localRecord?.followState !== 'no' && (row.localEpisodes > 0 || row.cloudEpisodes >= 0)));
}

export function filterPersonalLibrary(rows: PersonalLibraryRow[], filter: string): PersonalLibraryRow[] {
  if (filter === 'queue') { return rows.filter((row: PersonalLibraryRow) => row.queued); }
  if (filter === 'tracking') { return rows.filter((row: PersonalLibraryRow) => hasTrackingEvidence(row)); }
  if (filter === 'watching' || filter === 'finished' || filter === 'upcoming') {
    return rows.filter((row: PersonalLibraryRow) => hasTrackingEvidence(row) &&
      (row.sections?.includes(filter) ?? false) && (row.merged === true || row.cloudEpisodes <= row.localEpisodes));
  }
  if (filter === 'unclassified') {
    return rows.filter((row: PersonalLibraryRow) => hasTrackingEvidence(row) &&
      (!(row.sections?.length) || (!row.merged && row.cloudEpisodes > row.localEpisodes)));
  }
  if (filter === 'watched') { return rows.filter((row: PersonalLibraryRow) => row.watched); }
  return rows;
}

export function personalLibraryLabel(row: PersonalLibraryRow): string {
  const labels: string[] = [];
  if (row.queued) { labels.push('待看'); }
  if (row.watched) { labels.push(row.media.kind === 'show' ? '本机旧已看标记' : '已看'); }
  if (row.localEpisodes >= 0) { labels.push('本机已看 ' + row.localEpisodes + ' 集'); }
  if (row.cloudEpisodes >= 0) { labels.push('云端已看 ' + row.cloudEpisodes + ' 集'); }
  if (hasTrackingEvidence(row)) {
    if (row.localRecord?.followState === 'yes') { labels.push('本机追剧'); }
    const sections = row.sections ?? [];
    if (sections.length === 0 || (!row.merged && row.cloudEpisodes > row.localEpisodes)) { labels.push('追剧状态待核实'); }
    else {
      if (sections.includes('watching')) { labels.push('正在追'); }
      if (sections.includes('finished')) { labels.push('已追完结剧'); }
      if (sections.includes('upcoming')) { labels.push('等待更新'); }
    }
  }
  if (!row.localRecord) { labels.push('仅浏览'); }
  return labels.join(' · ');
}

export function businessLibraryLabel(row: PersonalLibraryRow): string {
  const labels: string[] = [];
  if (row.queued) { labels.push('待看'); }
  if (row.media.kind !== 'show' && row.watched) { labels.push('已看'); }
  if (hasTrackingEvidence(row)) {
    const sections = row.sections ?? [];
    if (!sections.length || (!row.merged && row.cloudEpisodes > row.localEpisodes)) {
      labels.push('追剧状态待核实');
    } else {
      if (sections.includes('watching')) { labels.push('正在追'); }
      if (sections.includes('finished')) { labels.push('已完结'); }
      if (sections.includes('upcoming')) { labels.push('等待更新'); }
    }
  }
  if (row.media.kind === 'show' && row.effectiveWatched !== undefined && row.effectiveTotal !== undefined) {
    labels.push('已看 ' + row.effectiveWatched + ' / ' + row.effectiveTotal + ' 集');
  }
  return labels.join(' · ');
}
export function isPersonalMember(row: PersonalLibraryRow): boolean {
  return row.queued || row.watched || hasTrackingEvidence(row);
}

function sameMedia(a:Media,b:Media):boolean{
  return a===b||(a.id===b.id&&a.kind===b.kind&&a.title===b.title&&a.year===b.year&&a.watched===b.watched);
}
function sameRecord(a?:MediaRecord,b?:MediaRecord):boolean{
  return a===b||!!a&&!!b&&sameMedia(a.media,b.media)&&a.movieState===b.movieState&&a.watchlistState===b.watchlistState&&a.followState===b.followState&&a.restoredWatchlist===b.restoredWatchlist;
}
export function sameLibraryRow(a:PersonalLibraryRow,b:PersonalLibraryRow):boolean{
  const sectionsA=a.sections,sectionsB=b.sections;
  return a===b||sameMedia(a.media,b.media)&&sameRecord(a.localRecord,b.localRecord)&&
    a.queued===b.queued&&a.watched===b.watched&&a.localEpisodes===b.localEpisodes&&a.cloudEpisodes===b.cloudEpisodes&&
    a.merged===b.merged&&a.effectiveWatched===b.effectiveWatched&&a.effectiveTotal===b.effectiveTotal&&
    (sectionsA===sectionsB||!!sectionsA&&!!sectionsB&&sectionsA.length===sectionsB.length&&sectionsA.every((x:string,i:number)=>x===sectionsB[i]));
}

export interface LibraryOrder { segment:number; position:number; }
export interface PersonalLibraryChange { id:string; row?:PersonalLibraryRow; ordinal?:LibraryOrder; }
function compareLibraryOrder(a:LibraryOrder,b:LibraryOrder):number{return a.segment-b.segment||a.position-b.position;}
// A derived union index. Local records retain their order; cloud-only rows retain
// first-observation order. Changes to unknown source order invalidate the index.
export class PersonalLibraryIndex {
  private rows:PersonalLibraryRow[]=[];
  private byId:Map<string,PersonalLibraryRow>=new Map<string,PersonalLibraryRow>();
  private positions:Map<string,number>=new Map<string,number>();
  private order:Map<string,LibraryOrder>=new Map<string,LibraryOrder>();
  private recordOrder:Map<string,number>=new Map<string,number>();
  private cloudOrder:Map<string,number>=new Map<string,number>();
  private cloudMedia:Map<string,Media>=new Map<string,Media>();
  private cloudMovies:Map<string,Media>=new Map<string,Media>();
  private cloudWatchlist:Map<string,Media>=new Map<string,Media>();
  private cloudShows:Map<string,LibraryShowEvidence>=new Map<string,LibraryShowEvidence>();
  private localShows:Map<string,LibraryShowEvidence>=new Map<string,LibraryShowEvidence>();
  private cloudToken?:object;
  private evidenceToken?:LibraryShowEvidence[];
  private localAllowed:boolean=false;
  private seeded:boolean=false;
  private nextRecordOrder:number=0;
  clear():void{
    this.rows=[];this.byId.clear();this.positions.clear();this.order.clear();this.recordOrder.clear();
    this.cloudOrder.clear();this.cloudMedia.clear();this.cloudMovies.clear();this.cloudWatchlist.clear();
    this.cloudShows.clear();this.localShows.clear();this.cloudToken=undefined;this.evidenceToken=undefined;
    this.localAllowed=false;this.seeded=false;this.nextRecordOrder=0;
  }
  matches(cloud:object|undefined,evidence:LibraryShowEvidence[],localAllowed:boolean):boolean{
    return this.seeded&&this.cloudToken===cloud&&this.evidenceToken===evidence&&this.localAllowed===localAllowed;
  }
  rowsView():PersonalLibraryRow[]{return this.rows;}
  get(id:string):PersonalLibraryRow|undefined{return this.byId.get(id);}
  ordinal(id:string):LibraryOrder|undefined{return this.order.get(id);}
  seed(records:MediaRecord[],cloudMovies:Media[],cloudWatchlist:Media[],cloudShows:LibraryShowEvidence[],
    localShows:LibraryShowEvidence[],cloud:object|undefined,evidence:LibraryShowEvidence[],localAllowed:boolean,
    rows:PersonalLibraryRow[]):void{
    this.clear();this.cloudToken=cloud;this.evidenceToken=evidence;this.localAllowed=localAllowed;this.rows=rows;
    for(const row of rows){this.byId.set(row.media.id,row);}
    for(let i=0;i<records.length;i++){this.recordOrder.set(records[i].media.id,i);}
    this.nextRecordOrder=records.length;
    let rank=0;
    const mark=(media:Media):void=>{
      if(!this.cloudOrder.has(media.id)){this.cloudOrder.set(media.id,rank++);this.cloudMedia.set(media.id,media);}
    };
    for(const media of cloudMovies){mark(media);if(!this.cloudMovies.has(media.id)){this.cloudMovies.set(media.id,media);}}
    for(const media of cloudWatchlist){mark(media);if(!this.cloudWatchlist.has(media.id)){this.cloudWatchlist.set(media.id,media);}}
    for(const show of cloudShows){mark(show.media);this.cloudShows.set(show.media.id,show);}
    for(const show of localShows){
      if(show.watchedEpisodes>0||this.byId.has(show.media.id)){mark(show.media);}
      this.localShows.set(show.media.id,show);
    }
    for(let i=0;i<rows.length;i++){
      const row=rows[i];this.positions.set(row.media.id,i);
      const recordPosition=this.recordOrder.get(row.media.id);
      this.order.set(row.media.id,recordPosition!==undefined?{segment:0,position:recordPosition}:
        {segment:1,position:this.cloudOrder.get(row.media.id)??rank});
    }
    this.seeded=true;
  }
  private compose(id:string,record:MediaRecord|undefined):PersonalLibraryRow|undefined{
    const movie=this.cloudMovies.get(id),queue=this.cloudWatchlist.get(id),cloudShow=this.cloudShows.get(id),localShow=this.localShows.get(id);
    if(!record&&!movie&&!queue&&!cloudShow&&!(localShow&&localShow.watchedEpisodes>0)){return undefined;}
    const media=record?.media??this.cloudMedia.get(id)??localShow?.media;
    if(!media){return undefined;}
    let queued=record?inLocalWatchlist(record):false;
    if(queue&&record?.watchlistState!=='no'&&record?.followState!=='yes'){queued=true;}
    let watched=record?.media.watched??false;
    if(movie&&record?.movieState!=='no'){watched=true;}
    return {media:media,localRecord:record,queued:queued,watched:watched,
      localEpisodes:localShow?.watchedEpisodes??-1,cloudEpisodes:cloudShow?.watchedEpisodes??-1,
      sections:localShow?.sections,merged:localShow?.merged,effectiveWatched:localShow?.effectiveWatched,
      effectiveTotal:localShow?.effectiveTotal};
  }
  private reindex(from:number):void{for(let i=from;i<this.rows.length;i++){this.positions.set(this.rows[i].media.id,i);}}
  private removeAt(index:number,id:string):void{this.rows.splice(index,1);this.positions.delete(id);this.reindex(index);}
  private insert(row:PersonalLibraryRow,ordinal:LibraryOrder):void{
    let lo=0,hi=this.rows.length;
    while(lo<hi){
      const mid=Math.floor((lo+hi)/2),other=this.order.get(this.rows[mid].media.id);
      if(other&&compareLibraryOrder(other,ordinal)<=0){lo=mid+1;}else{hi=mid;}
    }
    this.rows.splice(lo,0,row);this.reindex(lo);
  }
  updateRecords(records:Map<string,MediaRecord>,ids:string[],appendOnly:boolean,cloud:object|undefined,
    evidence:LibraryShowEvidence[],localAllowed:boolean):PersonalLibraryChange[]|undefined{
    if(!this.matches(cloud,evidence,localAllowed)||!appendOnly||(cloud!==undefined&&!localAllowed)){return undefined;}
    const changes:PersonalLibraryChange[]=[];
    for(const id of ids){
      const record=records.get(id);
      if(record){if(!this.recordOrder.has(id)){this.recordOrder.set(id,this.nextRecordOrder++);}}
      else{this.recordOrder.delete(id);}
      const row=this.compose(id,record),oldIndex=this.positions.get(id),recordPosition=this.recordOrder.get(id);
      const cloudPosition=this.cloudOrder.get(id);
      if(!row){
        if(oldIndex!==undefined){this.removeAt(oldIndex,id);}
        this.byId.delete(id);this.order.delete(id);changes.push({id:id});continue;
      }
      const ordinal:LibraryOrder|undefined=recordPosition!==undefined?{segment:0,position:recordPosition}:
        cloudPosition!==undefined?{segment:1,position:cloudPosition}:undefined;
      if(!ordinal){return undefined;}
      const priorOrder=this.order.get(id);
      if(oldIndex!==undefined&&priorOrder&&compareLibraryOrder(priorOrder,ordinal)===0){
        this.rows[oldIndex]=row;this.byId.set(id,row);this.order.set(id,ordinal);
      }else{
        if(oldIndex!==undefined){this.removeAt(oldIndex,id);}
        this.byId.set(id,row);this.order.set(id,ordinal);this.insert(row,ordinal);
      }
      changes.push({id:id,row:row,ordinal:ordinal});
    }
    return changes;
  }
}
