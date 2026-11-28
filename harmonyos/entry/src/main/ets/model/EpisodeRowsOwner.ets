import { LazyRows } from './LazyRows';
export interface EpisodeDisplayRow { id:number; number:number; title:string; originalTitle?:string; watched:boolean; eligible?:boolean; firstAired?:string; }
function rowKey(row:EpisodeDisplayRow):string{return JSON.stringify([row.number,row.title,row.watched,row.eligible,row.firstAired]);}
// Independent derived season state. Native datasource identity is stable.
export class EpisodeRowsOwner {
  readonly source:LazyRows<EpisodeDisplayRow>=new LazyRows<EpisodeDisplayRow>();
  private scope:string='';
  clear():void{this.scope='';this.source.replace([],[],[]);}
  replace(scope:string,rows:EpisodeDisplayRow[]):void{
    let same=this.scope===scope&&this.source.totalCount()===rows.length;
    if(same){for(let i=0;i<rows.length;i++){if(this.source.idAt(i)!==rows[i].id.toString()){same=false;break;}}}
    this.scope=scope;
    if(!same){this.source.replace(rows,rows.map((row:EpisodeDisplayRow)=>row.id.toString()),rows.map((row:EpisodeDisplayRow)=>rowKey(row)));return;}
    for(let i=0;i<rows.length;i++){
      const old=this.source.getData(i),row=rows[i];
      if(old.number!==row.number||old.title!==row.title||old.watched!==row.watched||old.originalTitle!==row.originalTitle||old.eligible!==row.eligible||old.firstAired!==row.firstAired){this.source.patchRow(row.id.toString(),row,rowKey(row));}
    }
  }
  updateTitle(scope:string,id:number,title:string):void{
    if(scope!==this.scope){return;}
    const index=this.source.indexOfId(id.toString());
    if(index<0){return;}
    const old=this.source.getData(index);
    const resolved=title||old.originalTitle||'';
    if(old.title===resolved){return;}
    const row:EpisodeDisplayRow={id:old.id,number:old.number,title:resolved,originalTitle:old.originalTitle,watched:old.watched,eligible:old.eligible,firstAired:old.firstAired};
    this.source.patchRow(id.toString(),row,rowKey(row));
  }
}
