import { Media } from './Media';
import { ProgressSource } from './ProgressRules';
import { matchesText } from './MediaPresentation';
export interface HistorySource {media:Media;source?:ProgressSource;sourceStateKey?:string;sourceCatalogKey?:string;}
export interface HistoryEpisode {media:Media;id:number;season:number;number:number;title:string;at:number;}
export interface HistoryEntry {key:string;day:string;episode?:HistoryEpisode;}
export interface HistorySnapshot {period:string;query:string;loading:boolean;error:string;count:number;}
export interface HistoryPeriodOption {key:string;label:string;}
export const HISTORY_PERIODS:HistoryPeriodOption[]=[{key:'thisWeek',label:'本周'},{key:'lastWeek',label:'上周'},{key:'thisMonth',label:'本月'},{key:'lastMonth',label:'上月'},{key:'30',label:'最近30天'},{key:'90',label:'最近90天'},{key:'365',label:'最近365天'},{key:'all',label:'全部时间'}];
export function validHistoryPeriod(value:string):boolean{return HISTORY_PERIODS.some((p:HistoryPeriodOption)=>p.key===value);}
export function initialHistory(period:string='all'):HistorySnapshot{return {period:period,query:'',loading:true,error:'',count:0};}
export interface HistoryRange {start:number;end:number;}
export function historyRange(period:string,now:number):HistoryRange{
  const d=new Date(now);d.setHours(0,0,0,0);
  if(period==='thisWeek'||period==='lastWeek'){
    d.setDate(d.getDate()-((d.getDay()+6)%7)-(period==='lastWeek'?7:0));const start=d.getTime();d.setDate(d.getDate()+7);return {start:start,end:d.getTime()-1};
  }
  if(period==='thisMonth'||period==='lastMonth'){
    d.setDate(1);if(period==='lastMonth'){d.setMonth(d.getMonth()-1);}const start=d.getTime();d.setMonth(d.getMonth()+1);return {start:start,end:d.getTime()-1};
  }
  const days=period==='all'?36159:Number(period);return {start:now-days*86400000,end:now};
}
export function historyDay(at:number):string{const d=new Date(at);return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');}
interface IndexedShow {source:ProgressSource;key:string;episodes:HistoryEpisode[];}
export class HistoryOwner {
  private scope:string='';private shows:Map<string,IndexedShow>=new Map<string,IndexedShow>();
  private recomputed:number=0;
  clear():void{this.scope='';this.shows.clear();this.recomputed=0;}
  computations():number{return this.recomputed;}
  update(scope:string,inputs:HistorySource[]):void{
    if(scope!==this.scope){this.clear();this.scope=scope;}
    const seen=new Set<string>();
    for(const input of inputs){
      const source=input.source;if(!source||source.media.id!==input.media.id||input.media.kind!=='show'){continue;}
      seen.add(input.media.id);
      const key=input.sourceStateKey&&input.sourceCatalogKey?JSON.stringify([input.sourceStateKey,input.sourceCatalogKey]):'';
      const prior=this.shows.get(input.media.id);
      if(prior&&(prior.source===source||(key&&prior.key===key))){continue;}
      const episodes:HistoryEpisode[]=[];
      for(const row of source.episodes){
        if(!row.watched||!Number.isSafeInteger(row.watchedAt)||row.watchedAt<=0){continue;}
        episodes.push({media:source.media,id:row.episode.id,season:row.episode.season,number:row.episode.number,title:row.episode.title,at:row.watchedAt});
      }
      this.shows.set(input.media.id,{source:source,key:key,episodes:episodes});this.recomputed++;
    }
    for(const id of this.shows.keys()){if(!seen.has(id)){this.shows.delete(id);}}
  }
  rows(period:string,query:string,now:number,title:(row:HistoryEpisode)=>string,episode:(row:HistoryEpisode)=>string):HistoryEntry[]{
    const range=historyRange(period,now),result:HistoryEpisode[]=[];
    for(const show of this.shows.values()){
      for(const row of show.episodes){
        if(row.at<range.start||row.at>range.end||row.at>now){continue;}
        if(query&&!matchesText(query,row.media.title,title(row))&&!matchesText(query,row.title,episode(row))&&!matchesText(query,historyDay(row.at),new Date(row.at).toLocaleString())){continue;}
        result.push(row);
      }
    }
    result.sort((a:HistoryEpisode,b:HistoryEpisode)=>b.at-a.at||b.season-a.season||b.number-a.number||a.id-b.id);
    const entries:HistoryEntry[]=[];let day='';
    for(const row of result){const next=historyDay(row.at);if(next!==day){day=next;entries.push({key:'day:'+day,day:day});}entries.push({key:'episode:'+row.media.id+':'+row.id,day:day,episode:row});}
    return entries;
  }
}
