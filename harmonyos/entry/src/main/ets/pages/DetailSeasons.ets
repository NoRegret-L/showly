import { Media } from '../model/Media';
import { SeasonInfo, SeasonPresentationOwner } from '../model/SeasonPresentation';
import { PartArtwork } from './PartArtwork';
import { collectionSpoilerText } from '../model/CollectionViewOwner';
import { DetailSeasonRow } from '../model/SeasonDetailOwner';
@Component
export struct DetailSeasons{
  @Prop rows:DetailSeasonRow[]=[];
  @Prop ready:boolean=false;
  @Prop busy:boolean=false;
  @Prop editable:boolean=false;
  @Prop verify:boolean=false;
  @Prop refreshable:boolean=false;
  @Prop status:string='';
  @Prop completed:number=0;
  @Prop count:number=0;
  @Prop next:string='';
  @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
  @Prop cacheDir:string='';
  @Prop special:boolean=false;
  @Prop publicStatus:string='';
  @Prop ratingStatus:string='';
  @Prop ratingScope:string='';
  @Prop hideRating:boolean=false;
  @Prop tapReveal:boolean=true;
  @Prop metadataRevision:number=0;
  private revealed:Set<number>=new Set<number>();
  @State revealRevision:number=0;
  presentation:SeasonPresentationOwner=new SeasonPresentationOwner();
  onSpecial:()=>void=()=>{};
  onMetadata:()=>void=()=>{};
  onRefresh:()=>void=()=>{};
  onOpen:(season:number)=>void=()=>{};
  build(){
    Column({space:8}){
      Row(){
        Text('分季分集').fontSize(19).fontWeight(FontWeight.Medium)
        Blank()
        Button(this.busy?'更新中':'刷新').height(32).fontSize(12).enabled(this.refreshable&&!this.busy).onClick(()=>{this.onRefresh();})
      }.width('100%')
      Row({space:8}){
        Button(this.special?'特别篇：显示':'特别篇：隐藏').fontSize(12).height(32).onClick(()=>{this.onSpecial();})
        Button('刷新评分及资料').fontSize(12).height(32).onClick(()=>{this.onMetadata();})
      }.width('100%')
      if(this.publicStatus){Text(this.publicStatus).fontSize(12).width('100%')}
      if(this.ratingStatus){Text(this.ratingStatus).fontSize(12).width('100%')}
      if(!this.ready||this.status){Text(this.status||'正在读取分集数据库…').fontSize(12).width('100%')}
      if(this.verify){Text('恢复的资料需刷新后才能编辑。').fontSize(12).width('100%')}
      if(this.ready&&this.rows.length){
        Text('已播普通集 '+this.completed+' / '+this.count).fontSize(14).width('100%')
        if(this.count>0){Progress({value:this.completed,total:this.count,type:ProgressType.Linear}).width('100%').color($r('app.color.showly_accent'))}
        if(this.next){Text('下一集：'+this.next).fontSize(12).width('100%')}
        ForEach(this.rows,(row:DetailSeasonRow)=>{
          Row({space:10}){
            PartArtwork({item:this.item,urls:this.presentation.season(row.number)?.images??[],cacheDir:this.cacheDir,widthValue:48,ratio:2/3})
            Column({space:4}){
              Text(row.number===0?'特别篇':'第 '+row.number+' 季').fontSize(16).width('100%')
              Text(row.number===0?'公开资料 · 只读':('已看 '+row.completed+' / '+row.count+' · 目录 '+row.total+' 集')).fontSize(12).width('100%')
              if(this.presentation.season(row.number)?.rating!==undefined){
                Text('★ '+collectionSpoilerText((this.presentation.season(row.number)?.rating??0).toFixed(1),this.hideRating,this.revealRevision>0&&this.revealed.has(row.number),true)).fontSize(12)
                  .onClick(()=>{if(this.tapReveal){this.revealed.add(row.number);this.revealRevision++;}})
              }
              if(this.presentation.seasonRating(row.number,this.ratingScope)!==undefined){Text('我的评分 '+this.presentation.seasonRating(row.number,this.ratingScope)).fontSize(12)}
              if(row.count>0){Progress({value:row.completed,total:row.count,type:ProgressType.Linear}).width('100%').color($r('app.color.showly_accent'))}
            }.layoutWeight(1)
            Text(row.count>0&&row.completed===row.count?'✓':'›').fontSize(20)
          }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(8).onClick(()=>{this.onOpen(row.number);})
        },(row:DetailSeasonRow)=>row.number+':'+row.completed+':'+row.count+':'+row.total+':'+this.metadataRevision)
      }
    }.width('100%')
  }
}
