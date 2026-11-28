import { MediaDetail } from '../data/TraktDetails';
import { CollectionSpoilers, defaultCollectionSpoilers, collectionSpoilerText } from '../model/CollectionViewOwner';
@Component
export struct DetailSummarySection{
  @Prop summary?:MediaDetail=undefined;
  @Prop kind:string='';
  @Prop overview:string='';
  @Prop chinese:boolean=false;
  @Prop spoilers:CollectionSpoilers=defaultCollectionSpoilers();
  @Prop ratingRevealed:boolean=false;
  @Prop descriptionRevealed:boolean=false;
  onTranslate:()=>void=()=>{};
  onToggle:(field:string)=>void=()=>{};
  onReveal:(field:string)=>void=()=>{};
  build(){
    Column(){
      if(this.summary){
        Column({space:6}){
          Text('影视资料').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
          if(this.summary.collection?.release){Text('日期：'+this.summary.collection?.release).fontSize(13).width('100%')}
          if(this.summary.collection?.network){Text('电视网：'+this.summary.collection?.network).fontSize(13).width('100%')}
          if(this.summary.genres){Text(this.summary.genres).fontSize(13).width('100%')}
          if(this.summary.certification){Text('分级：'+this.summary.certification).fontSize(13).width('100%')}
          if(this.summary.country){Text('国家：'+this.summary.country).fontSize(13).width('100%')}
          if(this.summary.language){Text('语言：'+this.summary.language).fontSize(13).width('100%')}
          if(this.kind==='show'&&this.summary.airedEpisodes>0){Text('已播 '+this.summary.airedEpisodes+' 集').fontSize(13).width('100%')}
          if(this.summary.rating>0){Text('Trakt '+collectionSpoilerText(this.summary.rating.toFixed(1),this.spoilers.rating,this.ratingRevealed,true)+' / 10').fontSize(16).width('100%').onClick(()=>{this.onReveal('rating');})}
          if(this.summary.votes!==undefined){Text('评分人数：'+this.summary.votes).fontSize(12).width('100%')}
          Text('剧情简介').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
          Text(collectionSpoilerText(this.overview||'暂无简介',this.spoilers.description,this.descriptionRevealed)).fontSize(15).width('100%').onClick(()=>{this.onReveal('description');})
          if(this.chinese){Button('重试中文资料').fontSize(12).onClick(()=>{this.onTranslate();})}
          Row({space:4}){
            Button(this.spoilers.description?'简介隐藏':'简介显示').fontSize(11).layoutWeight(1).onClick(()=>{this.onToggle('description');})
            Button(this.spoilers.rating?'评分隐藏':'评分显示').fontSize(11).layoutWeight(1).onClick(()=>{this.onToggle('rating');})
            Button(this.spoilers.reveal?'允许揭示':'禁止揭示').fontSize(11).layoutWeight(1).onClick(()=>{this.onToggle('reveal');})
          }.width('100%')
        }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
      }
    }.width('100%')
  }
}
