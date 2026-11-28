import { FullEpisodeCatalog, ScheduledEpisode } from './ShowCatalog';
import { SeasonSummary } from './DetailSession';
export interface VerifiedEpisode { id:number; season:number; number:number; title:string; watched:boolean; }
export interface DetailSeasonRow extends SeasonSummary { total:number; }
export interface SeasonDetailSnapshot { revision:number; seasons:DetailSeasonRow[]; count:number; }
export function emptySeasonDetail():SeasonDetailSnapshot{return {revision:0,seasons:[],count:0};}
export interface DetailEpisodeEntry extends VerifiedEpisode { eligible:boolean; firstAired:string; }
export interface QuickProgressDelta { add:number[]; remove:number[]; valid:boolean; }
// Derived state only. All writes must recheck authoritative evidence.
export class SeasonDetailOwner{
  private scope:string='';private value:SeasonDetailSnapshot=emptySeasonDetail();
  private rows:Map<number,DetailEpisodeEntry>=new Map<number,DetailEpisodeEntry>();
  private groups:Map<number,DetailEpisodeEntry[]>=new Map<number,DetailEpisodeEntry[]>();
  private visits:number=0;
  snapshot():SeasonDetailSnapshot{return this.value;}
  updates():number{return this.visits;}
  clear():void{this.scope='';this.rows.clear();this.groups.clear();this.value=emptySeasonDetail();}
  season(number:number):DetailEpisodeEntry[]{return this.groups.get(number)??[];}
  episode(id:number):DetailEpisodeEntry|undefined{return this.rows.get(id);}
  update(scope:string,full:FullEpisodeCatalog|undefined,verified:VerifiedEpisode[]):SeasonDetailSnapshot{
    const old=this.scope===scope?this.rows:new Map<number,DetailEpisodeEntry>();
    const exact=new Map<number,VerifiedEpisode>();
    for(const ep of verified){exact.set(ep.id,ep);}
    const next=new Map<number,DetailEpisodeEntry>(),groups=new Map<number,DetailEpisodeEntry[]>();
    const put=(id:number,season:number,number:number,title:string,firstAired:string):void=>{
      const v=exact.get(id);const eligible=!!v&&v.season===season&&v.number===number;
      const watched=eligible&&!!v?.watched;const prior=old.get(id);
      const row:DetailEpisodeEntry=prior&&prior.season===season&&prior.number===number&&prior.title===title&&prior.firstAired===firstAired&&prior.eligible===eligible&&prior.watched===watched?prior:
        {id:id,season:season,number:number,title:title,firstAired:firstAired,eligible:eligible,watched:watched};
      if(row!==prior){this.visits++;}
      if(next.has(id)){return;}next.set(id,row);
      let group=groups.get(season);if(!group){group=[];groups.set(season,group);}group.push(row);
    };
    for(const season of full?.seasons??[]){for(const ep of season.episodes){put(ep.id,ep.season,ep.number,ep.title,ep.firstAired);}}
    for(const ep of verified){if(!next.has(ep.id)){put(ep.id,ep.season,ep.number,ep.title,'');}}
    const summaries:DetailSeasonRow[]=[];
    for(const number of Array.from(groups.keys()).sort((a:number,b:number)=>b-a)){
      const group=groups.get(number)??[];group.sort((a:DetailEpisodeEntry,b:DetailEpisodeEntry)=>a.number-b.number||a.id-b.id);
      const count=group.filter((row:DetailEpisodeEntry)=>row.eligible).length;
      const completed=group.filter((row:DetailEpisodeEntry)=>row.eligible&&row.watched).length;
      const prior=this.scope===scope?this.value.seasons.find((s:DetailSeasonRow)=>s.number===number):undefined;
      summaries.push(prior&&prior.count===count&&prior.completed===completed&&prior.total===group.length?prior:{number:number,count:count,completed:completed,total:group.length});
    }
    const changed=this.scope!==scope||summaries.length!==this.value.seasons.length||summaries.some((s:DetailSeasonRow,i:number)=>s!==this.value.seasons[i]);
    this.scope=scope;this.rows=next;this.groups=groups;
    if(changed){this.value={revision:this.value.revision+1,seasons:summaries,count:this.value.count};}
    return this.value;
  }
  count(value:number):SeasonDetailSnapshot{
    if(this.value.count!==value){this.value={revision:this.value.revision+1,seasons:this.value.seasons,count:value};}return this.value;
  }
  delta(target:number):QuickProgressDelta{
    const selected=this.rows.get(target);const add:number[]=[],remove:number[]=[];
    if(!selected||!selected.eligible||selected.season<=0){return {add:add,remove:remove,valid:false};}
    for(const row of this.rows.values()){
      if(!row.eligible||row.season<=0){continue;}
      const desired=row.season<selected.season||(row.season===selected.season&&row.number<=selected.number);
      if(desired&&!row.watched){add.push(row.id);}else if(!desired&&row.watched){remove.push(row.id);}
    }
    return {add:add,remove:remove,valid:true};
  }
}
