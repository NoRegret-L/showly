import { LazyRows } from '../model/LazyRows';
import { EpisodeDisplayRow } from '../model/EpisodeRowsOwner';
// Only the current season is supplied to the native list. Confirmation and
// data-source ownership belong to this child, not to the global screen.
@Component
export struct DetailEpisodeList {
  @Prop count: number=0;
  @Prop title: string='';
  @Prop season: number=0;
  @Prop completed: number=0;
  @Prop eligibleCount:number=0;
  @Prop editable: boolean=false;
  @Prop busy: boolean=false;
  @Prop status: string='';
  @State confirming: boolean=false;
  @State confirmWatched: boolean=true;
  source: LazyRows<EpisodeDisplayRow>=new LazyRows<EpisodeDisplayRow>();
  onBack: ()=>void=()=>{};
  onToggle: (id: number,watched: boolean)=>void=()=>{};
  onMarkSeason: (watched: boolean)=>void=()=>{};
  onQuickProgress:(id:number)=>void=()=>{};
  build() {
    List({ space: 8 }) {
      ListItem() {
        Column({ space: 8 }) {
          Button('返回详情').onClick(()=>{ this.onBack(); })
          Text(this.title+' · 第 '+this.season+' 季').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
          Text('已看 '+this.completed+' / '+this.eligibleCount+' 已播集 · 目录 '+this.count+' 集').fontSize(14).width('100%')
          if (this.status) { Text(this.status).fontSize(12).width('100%') }
          Row({ space: 8 }) {
            Button('整季已看').layoutWeight(1).enabled(this.editable && !this.busy && this.completed<this.eligibleCount)
              .onClick(()=>{ this.confirmWatched=true; this.confirming=true; })
            Button('整季撤销').layoutWeight(1).enabled(this.editable && !this.busy && this.completed>0)
              .onClick(()=>{ this.confirmWatched=false; this.confirming=true; })
          }.width('100%')
          if (this.confirming) {
            Text(this.confirmWatched?'确认将本季已播集全部标记已看？':'确认撤销本季已看状态？同步删除需单独确认。').fontSize(13)
            Row({ space: 8 }) {
              Button('取消').layoutWeight(1).onClick(()=>{ this.confirming=false; })
              Button('确认').layoutWeight(1).enabled(this.editable && !this.busy)
                .onClick(()=>{ this.confirming=false; this.onMarkSeason(this.confirmWatched); })
            }.width('100%')
          }
        }.width('100%')
      }
      LazyForEach(this.source,(row: EpisodeDisplayRow)=>{
        ListItem() {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text('第 '+row.number+' 集').fontSize(14).width('100%')
              if (row.title) { Text(row.title).fontSize(12).maxLines(2).width('100%').fontColor($r('app.color.showly_secondary')) }
              Text(row.firstAired?row.firstAired.substring(0,10):'播出日期待确认').fontSize(11).width('100%')
              if(row.eligible===false){Text('待播或未验证 · 只读').fontSize(11).width('100%')}
              if(row.eligible!==false){Button('补齐至本集').fontSize(11).height(28).enabled(this.editable&&!this.busy).onClick(()=>{this.onQuickProgress(row.id);})}
            }.layoutWeight(1)
            Button(row.watched?'✓ 撤销':'○ 已看').fontSize(12).height(34).enabled(this.editable && !this.busy && row.eligible!==false)
              .onClick(()=>{ this.onToggle(row.id,!row.watched); })
          }.width('100%').padding(10).borderRadius(8).backgroundColor($r('app.color.showly_surface'))
        }
      },(row: EpisodeDisplayRow)=>this.source.keyFor(row.id.toString()))
    }.width('100%').height('100%').padding(16)
  }
}
