import { Media } from '../model/Media';
import { StatisticsOwner, StatisticsInput, StatisticsRuntime, StatisticsSnapshot, StatisticsRow, StatisticsGenre, StatisticsRating, StatisticsRatingRow, emptyStatistics } from '../model/StatisticsOwner';
import { PresentationRepository } from '../data/PresentationRepository';
import { ReadCancel } from '../model/ReadFlight';
import { readDetails } from '../data/TraktDetails';
import { readSeasonPresentation } from '../data/DetailSectionsRepository';
import { parseSeasonPresentation } from '../model/SeasonPresentation';
import { CustomListArtwork } from './CustomListArtwork';

@Component
export struct StatisticsPage {
  @Prop scope:string='';
  @Prop kind:string='show';
  @Prop client:string='';
  @Prop language:string='zh';
  repository?:PresentationRepository;
  inputs:()=>StatisticsInput[]=()=>[];
  readRatings:()=>Promise<StatisticsRating[]>=async()=>[];
  current:()=>boolean=()=>false;
  onBack:()=>void=()=>{};
  onOpen:(item:Media)=>void=()=>{};
  @State view:StatisticsSnapshot=emptyStatistics();
  @State ratings:StatisticsRatingRow[]=[];
  @State status:string='';
  @State ratingStatus:string='';
  @State busy:boolean=false;
  @State limit:number=5;
  private owner:StatisticsOwner=new StatisticsOwner();
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToAppear():void{this.active=true;this.load(false);}
  aboutToDisappear():void{this.active=false;this.signal.cancel();this.owner.clear();}
  private allowed(signal:ReadCancel):boolean{return this.active&&!!this.scope&&this.current()&&!signal.cancelled();}
  private async load(network:boolean):Promise<void>{
    if(this.busy||!this.current()||!this.scope){return;}
    this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal;
    this.busy=true;this.status='正在读取统计资料…';this.ratingStatus='';this.ratings=[];
    const rows=this.inputs(); // Publish only after cached enrichment, avoiding partial/full recomputation on every refresh.
    try{
      for(const row of rows){
        if(!this.allowed(signal)){return;}
        try{
          if(!row.meta){const cached=await this.repository?.readCachedDetail(row.media,signal);row.meta=cached?.collection;
            if(!row.meta&&network&&this.client){const detail=await readDetails(row.media,this.client,false,signal);row.meta=detail.collection;await this.repository?.saveCachedDetail(row.media,detail,signal);}}
          if(row.media.kind==='show'&&row.source&&row.source.episodes.some(ep=>ep.watched)){
            let raw=await this.repository?.readDetailSection(row.media,'seasons-trakt',signal)??'';
            if(!raw&&network&&this.client){raw=await readSeasonPresentation(row.media,this.client,signal);await this.repository?.saveDetailSection(row.media,'seasons-trakt',raw,signal);}
            if(raw){const runtimes:StatisticsRuntime[]=[];for(const season of parseSeasonPresentation(raw)){for(const ep of season.episodes){if(ep.runtime!==undefined){runtimes.push({id:ep.id,minutes:ep.runtime});}}}row.runtimes=runtimes;}
          }
        }catch(error){if(!this.allowed(signal)){return;}}
      }
      if(!this.allowed(signal)){return;}this.view=this.owner.update(this.scope+':'+this.kind,rows);
      this.status=this.view.missing||this.view.unknownGenres?'部分资料缺失；时长仅统计已确认数据。':'';
      try{const ratings=await this.readRatings();if(this.allowed(signal)){this.ratings=this.owner.ratings(ratings);}}
      catch(error){if(this.allowed(signal)){this.ratingStatus='个人评分未能读取；可重试。';}}
    }catch(error){if(this.allowed(signal)){this.status='统计读取失败；可重试。';}}
    finally{if(this.allowed(signal)){this.busy=false;}}
  }
  @Builder metric(label:string,value:string){
    Column({space:8}){Text(label).fontSize(15).fontColor($r('app.color.showly_secondary'));Text(value).fontSize(29).fontWeight(FontWeight.Bold).fontColor($r('app.color.showly_text'))}
    .width('100%').padding(16).alignItems(HorizontalAlign.Start).borderRadius(12).backgroundColor($r('app.color.showly_surface'))
  }
  build(){
    Column({space:10}){
      Row({space:8}){Button('返回').fontSize(12).onClick(()=>this.onBack());Text(this.kind==='movie'?'电影统计':'剧集统计').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1);Button('补齐资料').fontSize(12).enabled(!this.busy&&!!this.client).onClick(()=>this.load(true));}.width('100%')
      List({space:10}){
        ListItem(){this.metric('累计观看时长',Math.floor(this.view.minutes/60)+' 小时 '+this.view.minutes%60+' 分钟')}
        ListItem(){this.metric(this.kind==='movie'?'已观看电影':'已观看分集',this.kind==='movie'?this.view.titles+' 部':this.view.episodes+' 集 · '+this.view.watchedShows+' 部剧集')}
        if(this.status||this.busy||this.ratingStatus){ListItem(){Column({space:5}){Text(this.status).fontSize(13);if(this.view.missing){Text('缺少时长或分集证据：'+this.view.missing).fontSize(12)}if(this.view.unknownGenres){Text('缺少类型资料：'+this.view.unknownGenres+' 部').fontSize(12)}Button('重新读取本地数据').fontSize(12).enabled(!this.busy).onClick(()=>this.load(false))}.width('100%')}}
        ListItem(){Column({space:8}){Text('常看类型').fontSize(18).fontWeight(FontWeight.Bold);if(!this.view.genres.length){Text('暂无已知类型').fontSize(13)}ForEach(this.view.genres,(g:StatisticsGenre)=>{Row(){Text(g.name).layoutWeight(1);Text(g.count+' 部')}.width('100%')},(g:StatisticsGenre)=>g.name+':'+g.count)}.width('100%').padding(14).borderRadius(12).backgroundColor($r('app.color.showly_surface'))}
        ListItem(){Text('个人评分').fontSize(18).fontWeight(FontWeight.Bold).width('100%')}
        if(this.ratingStatus){ListItem(){Text(this.ratingStatus).fontSize(13)}}else if(!this.ratings.length){ListItem(){Text('暂无可用个人评分').fontSize(13)}}
        ForEach(this.ratings,(r:StatisticsRatingRow)=>{ListItem(){Row({space:12}){CustomListArtwork({item:r.media,client:this.client,language:this.language,repository:this.repository,widthValue:42,showTitle:true});Text(r.media.title).layoutWeight(1).maxLines(2);Text(r.value+' / 10')}.width('100%').padding(8).onClick(()=>this.onOpen(r.media))}},(r:StatisticsRatingRow)=>r.media.id+':'+r.value)
        if(this.kind==='show'){
          ListItem(){Text('观看时长排行 · '+this.view.titles+' 部').fontSize(18).fontWeight(FontWeight.Bold).width('100%')}
          ForEach(this.view.ranking.slice(0,this.limit),(r:StatisticsRow)=>{ListItem(){Row({space:12}){CustomListArtwork({item:r.media,client:this.client,language:this.language,repository:this.repository,widthValue:56,showTitle:true});Column({space:5}){Text(r.media.title).maxLines(2).fontWeight(FontWeight.Medium);Text(r.episodes+' 集 · '+r.seasons+' 季').fontSize(12);Text(r.minutes+' 分钟'+(r.missing?' · 资料不全':'')).fontSize(13)}.layoutWeight(1).alignItems(HorizontalAlign.Start)}.width('100%').padding(8).onClick(()=>this.onOpen(r.media))}},(r:StatisticsRow)=>r.media.id+':'+r.minutes+':'+r.episodes+':'+r.missing)
          if(this.limit<this.view.ranking.length){ListItem(){Button('显示更多').onClick(()=>{this.limit+=5;})}}
        }
        if(!this.busy&&!this.view.titles){ListItem(){Text('暂无可统计的收藏记录').fontSize(14)}}
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding(14)
  }
}
