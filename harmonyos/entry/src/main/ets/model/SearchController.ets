import { Media } from './Media';
import { SearchRecord, SearchCandidate, SearchCandidateTitles, SearchOptions, SearchInput, validSearchRecord, defaultSearch, publicSearchRecord } from './SearchRules';
export interface SearchSnapshot{revision:number;remoteReady:boolean;offline:boolean;}
export class SearchController{
  source?:SearchRecord[];
  key:string='';
  candidates:SearchCandidate[]=[];
  titles:SearchCandidateTitles=new SearchCandidateTitles();
  stored:Set<string>=new Set<string>();
  remote:SearchRecord[]=[];
  private view:SearchSnapshot={revision:0,remoteReady:false,offline:false};
  snapshot():SearchSnapshot{return this.view;}
  resetRemote():void{this.remote=[];this.view={revision:this.view.revision+1,remoteReady:false,offline:false};}
  acceptRemote(rows:SearchRecord[]):void{this.remote=rows;this.view={revision:this.view.revision+1,remoteReady:true,offline:false};}
  chooseOffline(offline:boolean):void{if(this.view.offline!==offline){this.view={revision:this.view.revision+1,remoteReady:this.view.remoteReady,offline:offline};}}
  clearCandidates():void{this.source=undefined;this.key='';this.candidates=[];this.titles.clear();this.stored.clear();}
  seed(stored:SearchRecord[],key:string,library:Media[],candidate:(row:SearchRecord)=>SearchCandidate):void{
    const merged=new Map<string,SearchRecord>();this.stored.clear();
    for(const row of stored){if(validSearchRecord(row)){merged.set(row.media.id,row);this.stored.add(row.media.id);}}
    for(const item of library){if(!merged.has(item.id)){merged.set(item.id,publicSearchRecord(item));}}
    const ordered=Array.from(merged.values()).sort((a:SearchRecord,b:SearchRecord)=>a.media.id<b.media.id?-1:a.media.id>b.media.id?1:0);
    this.candidates=ordered.map(candidate);this.titles.seed(this.candidates);this.source=stored;this.key=key;
  }
  input(query:string,submitted:boolean,options:SearchOptions,candidate:(row:SearchRecord)=>SearchCandidate):SearchInput{
    const remoteOnly=submitted&&this.view.remoteReady&&!this.view.offline;
    return {catalog:remoteOnly?[]:this.titles.matching(query,this.candidates),remote:remoteOnly?this.remote.map(candidate):[],query:query,suggestions:!submitted,options:options};
  }
}
