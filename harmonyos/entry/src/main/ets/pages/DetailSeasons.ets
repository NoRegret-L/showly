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
  onRefresh:()=>void=()=>{};
  onOpen:(season:number)=>void=()=>{};
  build(){
    Column({space:8}){
      Row(){
        Text('分季分集').fontSize(19).fontWeight(FontWeight.Medium)
        Blank()
        Button(this.busy?'更新中':'刷新').height(32).fontSize(12).enabled(this.refreshable&&!this.busy).onClick(()=>{this.onRefresh();})
      }.width('100%')
      if(!this.ready||this.status){Text(this.status||'正在读取分集数据库…').fontSize(12).width('100%')}
      if(this.verify){Text('恢复的资料需刷新后才能编辑。').fontSize(12).width('100%')}
      if(this.ready&&this.rows.length){
        Text('已播普通集 '+this.completed+' / '+this.count).fontSize(14).width('100%')
        if(this.count>0){Progress({value:this.completed,total:this.count,type:ProgressType.Linear}).width('100%').color($r('app.color.showly_accent'))}
        if(this.next){Text('下一集：'+this.next).fontSize(12).width('100%')}
        ForEach(this.rows,(row:DetailSeasonRow)=>{
          Row({space:10}){
            Column({space:4}){
              Text(row.number===0?'特别篇':'第 '+row.number+' 季').fontSize(16).width('100%')
              Text('已看 '+row.completed+' / '+row.count+' · 目录 '+row.total+' 集').fontSize(12).width('100%')
              if(row.count>0){Progress({value:row.completed,total:row.count,type:ProgressType.Linear}).width('100%').color($r('app.color.showly_accent'))}
            }.layoutWeight(1)
            Text(row.count>0&&row.completed===row.count?'✓':'›').fontSize(20)
          }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(8).onClick(()=>{this.onOpen(row.number);})
        },(row:DetailSeasonRow)=>row.number+':'+row.completed+':'+row.count+':'+row.total)
      }
    }.width('100%')
  }
}
