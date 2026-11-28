import { Media } from '../model/Media';
import { RelatedRow, SectionOwner, SectionSnapshot, emptySection, projectRelated } from '../model/DetailSections';
import { PresentationRepository } from '../data/PresentationRepository';
import { readRelated } from '../data/DetailSectionsRepository';
import { ReadCancel } from '../model/ReadFlight';
import { readDetails, cachedPoster, cachePoster } from '../data/TraktDetails';
import { ArtworkImage } from './ArtworkImage';
import { LazyRows } from '../model/LazyRows';
@Component
struct RelatedCard {
  @Prop row:RelatedRow={media:{id:'',kind:'show',title:'',year:0,watched:false},votes:0,posters:[]};
  @Prop client:string='';
  @Prop cacheDir:string='';
  @State poster:string='';
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  onOpen:(item:Media)=>void=()=>{};
  aboutToDisappear():void{this.active=false;this.signal.cancel();}
  private async visible(value:boolean):Promise<void>{
    if(!value){this.active=false;this.signal.cancel();return;}
    if(this.active){return;}this.active=true;
    this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal,item=this.row.media;
    try{
      let urls=this.row.posters;
      if(!urls.length&&this.client){urls=(await readDetails(item,this.client,false,signal)).posterUrls;}
      let uri=await cachedPoster(this.cacheDir,item,urls,signal);
      if(!uri&&urls.length&&this.client){uri=(await cachePoster(this.cacheDir,item,urls,signal)).uri;}
      if(!signal.cancelled()&&this.active){this.poster=uri;}
    }catch(error){}
  }
  build(){
    Column({space:4}){
      ArtworkImage({uri:this.poster,widthValue:102,ratio:2/3,corner:8,onFailure:()=>{this.poster='';}})
      Text(this.row.media.title).fontSize(13).maxLines(2).width(102)
      Text((this.row.media.year>0?this.row.media.year.toString():'')+(this.row.rating!==undefined?' · '+this.row.rating.toFixed(1):'')).fontSize(11).width(102)
    }.width(106).onClick(()=>{this.onOpen(this.row.media);})
     .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.visible(visible&&ratio>0);})
  }
}
@Component
export struct DetailRelatedSection {
  @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
  @Prop client:string='';
  @Prop scope:string='';
  @Prop cacheDir:string='';
  @Prop @Watch('hiddenChanged') hiddenKey:string='';
  repository?:PresentationRepository;
  onOpen:(item:Media)=>void=()=>{};
  @State view:SectionSnapshot<RelatedRow>=emptySection<RelatedRow>();
  private owner:SectionOwner<RelatedRow>=new SectionOwner<RelatedRow>();
  private source:LazyRows<RelatedRow>=new LazyRows<RelatedRow>();
  private visible:boolean=false;
  private hiddenChanged():void{this.updateRows();}
  private updateRows():void{
    let hidden:Set<string>=new Set<string>();
    try{hidden=new Set<string>(JSON.parse(this.hiddenKey) as string[]);}catch(error){}
    const rows=projectRelated(this.view.rows,this.item.id,hidden);
    this.source.replace(rows,rows.map((r:RelatedRow)=>r.media.id),rows.map((r:RelatedRow)=>JSON.stringify(r)));
  }
  private publish():void{const value=this.owner.snapshot();if(value!==this.view){const changed=value.rows!==this.view.rows;this.view=value;if(changed){this.updateRows();}}}
  aboutToDisappear():void{this.visible=false;this.owner.clear();this.source.replace([],[],[]);}
  private async load():Promise<void>{
    if(!this.visible||this.view.busy){return;}
    const token=this.owner.begin(),signal=this.owner.consumer(),item=this.item,scope=this.scope,client=this.client;
    const current=():boolean=>this.visible&&this.owner.current(token)&&this.item.id===item.id&&this.scope===scope&&this.client===client;
    this.owner.publish(token,this.view.rows,true,'',this.view.loaded);this.publish();
    try{
      if(!this.view.loaded){
        const raw=await this.repository?.readDetailSection(item,'related-trakt',signal);
        if(!current()){return;}
        if(raw){const rows=JSON.parse(raw) as RelatedRow[];if(Array.isArray(rows)&&rows.every((r:RelatedRow)=>r.media?.kind===item.kind&&typeof r.media.id==='string'&&Array.isArray(r.posters))){this.owner.publish(token,rows,true,'本地缓存',true);this.publish();}}
      }
      if(!client){if(current()){this.owner.publish(token,this.view.rows,false,'离线资料',this.view.loaded);this.publish();}return;}
      const rows=await readRelated(item,client,signal);if(!current()){return;}
      this.owner.publish(token,rows,false,'',true);this.publish();
      try{await this.repository?.saveDetailSection(item,'related-trakt',JSON.stringify(rows),signal);}catch(error){}
    }catch(error){if(current()){this.owner.publish(token,this.view.rows,false,'相关影视读取失败，可重试',this.view.loaded);this.publish();}}
  }
  private updateSectionVisibility(visible:boolean):void{
    this.visible=visible;
    if(!visible){this.owner.publish(this.owner.begin(),this.view.rows,false,this.view.status,this.view.loaded);this.publish();return;}
    if(!this.view.loaded&&!this.view.busy){this.load();}
  }
  build(){
    Column({space:8}){
      Text('相关影视').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
      if(this.view.busy){LoadingProgress().width(22).height(22)}
      if(this.view.status){Text(this.view.status).fontSize(12).width('100%')}
      if(this.view.loaded&&this.source.totalCount()===0){Text('没有可显示的相关影视').fontSize(12)}
      List({space:8}){
        LazyForEach(this.source,(row:RelatedRow)=>{ListItem(){RelatedCard({row:row,client:this.client,cacheDir:this.cacheDir,onOpen:(item:Media)=>{this.onOpen(item);}})}},(row:RelatedRow)=>this.source.keyFor(row.media.id))
      }.listDirection(Axis.Horizontal).height(212).width('100%')
      if(!this.view.busy){Button('刷新相关影视').fontSize(12).onClick(()=>{this.load();})}
    }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
     .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.updateSectionVisibility(visible&&ratio>0);})
  }
}
