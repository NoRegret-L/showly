import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { Series,SeriesMovie } from '../model/AvailabilityRules';
import { openAvailability } from '../data/AvailabilityRepository';
import { SectionOwner,SectionSnapshot,emptySection } from '../model/DetailSections';
import { ReadCancel } from '../model/ReadFlight';
import { LazyRows } from '../model/LazyRows';
import { PresentationRepository } from '../data/PresentationRepository';
import { CustomListArtwork } from './CustomListArtwork';
@Component
export struct MovieSeriesSection{
 @Prop item:Media={id:'',kind:'movie',title:'',year:0,watched:false};
 @Prop client:string='';
 @Prop language:string='zh';
 repository?:PresentationRepository;
 member:(media:Media)=>string=()=>'';
 onOpen:(media:Media)=>void=()=>{};
 @State view:SectionSnapshot<Series>=emptySection<Series>();
 @State sheet:boolean=false;
 @State selected?:Series=undefined;
 @State busy:boolean=false;
 @State status:string='';
 private owner:SectionOwner<Series>=new SectionOwner<Series>();
 private source:LazyRows<SeriesMovie>=new LazyRows<SeriesMovie>();
 private signal:ReadCancel=new ReadCancel();
 private active:boolean=true;
 private visible:boolean=false;
 aboutToAppear():void{this.active=true;}
 aboutToDisappear():void{this.active=false;this.visible=false;this.sheet=false;this.signal.cancel();this.owner.clear();}
 private publish():void{this.view=this.owner.snapshot();}
 private async load(refresh:boolean):Promise<void>{
  if(!this.visible||this.view.busy){return;}const t=this.owner.begin(),s=this.owner.consumer();
  this.owner.publish(t,this.view.rows,true,'',this.view.loaded);this.publish();
  try{const repo=await openAvailability(this.getUIContext().getHostContext() as common.UIAbilityContext),r=await repo.series(this.item,this.client,refresh,s);if(this.visible&&this.owner.current(t)){this.owner.publish(t,r.rows,false,r.stale?'旧缓存 · 更新失败':'',true);this.publish();}}
  catch(error){if(this.visible&&this.owner.current(t)){this.owner.publish(t,this.view.rows,false,'电影系列读取失败，可重试',this.view.loaded);this.publish();}}
 }
 private updateSectionVisibility(v:boolean):void{this.visible=v;if(!v){this.owner.publish(this.owner.begin(),this.view.rows,false,this.view.status,this.view.loaded);this.publish();}else if(!this.view.loaded){this.load(false);}}
 private async openSeries(row:Series,refresh:boolean=false):Promise<void>{
  this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal;this.selected=row;this.sheet=true;this.busy=true;this.status='';if(!refresh){this.source.replace([],[],[]);}
  try{const repo=await openAvailability(this.getUIContext().getHostContext() as common.UIAbilityContext),r=await repo.movies(row,this.item.id,this.client,refresh,signal);
   if(this.active&&this.sheet&&!signal.cancelled()&&this.selected?.id===row.id){this.source.replace(r.rows,r.rows.map((m:SeriesMovie)=>m.media.id),r.rows.map((m:SeriesMovie)=>JSON.stringify(m)));this.status=r.stale?'旧缓存 · 更新失败':'';}}
  catch(error){if(this.active&&this.sheet&&!signal.cancelled()){this.status='系列成员缺失或读取失败，可重试';}}
  finally{if(this.active&&this.sheet&&!signal.cancelled()){this.busy=false;}}
 }
 @Builder content(){
 Column({space:8}){
  Row(){Text(this.selected?.name??'电影系列').fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1);Button('关闭').onClick(()=>{this.sheet=false;this.signal.cancel();})}.width('100%')
  Text(this.selected?.description??'').fontSize(13).width('100%')
  Text('共 '+(this.selected?.count??0)+' 部作品').fontSize(12)
  if(this.busy){LoadingProgress().width(22).height(22)}
  if(this.status){Text(this.status).fontSize(12)}
  Button('刷新').fontSize(12).enabled(!this.busy).onClick(()=>{if(this.selected){this.openSeries(this.selected,true);}})
  List({space:8}){LazyForEach(this.source,(row:SeriesMovie)=>{ListItem(){Row({space:10}){Text((this.source.indexOfId(row.media.id)+1).toString()).fontSize(13);CustomListArtwork({item:row.media,client:this.client,language:this.language,repository:this.repository,widthValue:48,showTitle:true});Column({space:5}){Text(row.media.title).fontSize(15).maxLines(2);Text(row.media.year.toString()+' · '+this.member(row.media)).fontSize(12)}.layoutWeight(1).alignItems(HorizontalAlign.Start);Text('›')}.width('100%').onClick(()=>{if(this.active&&this.sheet){this.sheet=false;this.signal.cancel();this.onOpen(row.media);}})}},(row:SeriesMovie)=>this.source.keyFor(row.media.id))}.layoutWeight(1).width('100%')
 }.width('100%').height('100%').padding(14)
 }
 build(){
 Column({space:8}){
  Text('电影系列').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
  if(this.view.busy){LoadingProgress().width(22).height(22)}
  if(this.view.status){Text(this.view.status).fontSize(12)}
  if(this.view.loaded&&!this.view.rows.length){Text('没有公开官方系列').fontSize(12)}
  ForEach(this.view.rows,(row:Series)=>{Row({space:8}){Column({space:4}){Text(row.name).fontSize(16).maxLines(2);Text(row.count+' 部作品').fontSize(12)}.layoutWeight(1).alignItems(HorizontalAlign.Start);Text('›')}.width('100%').padding(8).onClick(()=>{this.openSeries(row);})},(row:Series)=>row.id.toString())
  Button('刷新电影系列').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.load(true);})
 }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10).onVisibleAreaChange([0],(v:boolean,r:number)=>{this.updateSectionVisibility(v&&r>0);}).bindSheet($$this.sheet,this.content(),{height:SheetSize.LARGE,showClose:true})
 }
}
