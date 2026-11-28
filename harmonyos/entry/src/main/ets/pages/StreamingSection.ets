import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { Provider,safeProviderLink } from '../model/AvailabilityRules';
import { openAvailability,tmdbConfigured } from '../data/AvailabilityRepository';
import { SectionOwner,SectionSnapshot,emptySection } from '../model/DetailSections';
@Component
export struct StreamingSection{
 @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
 @Prop client:string='';
 @Prop region:string='us';
 @Prop version:number=0;
 @State view:SectionSnapshot<Provider>=emptySection<Provider>();
 private owner:SectionOwner<Provider>=new SectionOwner<Provider>();
 private visible:boolean=false;
 aboutToDisappear():void{this.visible=false;this.owner.clear();}
 private publish():void{this.view=this.owner.snapshot();}
 private async load(refresh:boolean):Promise<void>{
  if(!this.visible||this.view.busy){return;}const t=this.owner.begin(),s=this.owner.consumer(),item=this.item,region=this.region,version=this.version;
  const current=():boolean=>this.visible&&this.owner.current(t)&&this.item.id===item.id&&this.region===region&&this.version===version;
  this.owner.publish(t,this.view.rows,true,'',this.view.loaded);this.publish();
  try{const repo=await openAvailability(this.getUIContext().getHostContext() as common.UIAbilityContext),r=await repo.providers(item,this.client,region,refresh,s);if(current()){this.owner.publish(t,r.rows,false,r.stale?'旧缓存 · 更新失败':r.cached?'本地缓存':'',true);this.publish();}}
  catch(error){if(current()){this.owner.publish(t,this.view.rows,false,tmdbConfigured()?'平台资料读取失败，可重试':'未配置 TMDB 或无可用缓存',this.view.loaded);this.publish();}}
 }
 private visibility(v:boolean):void{this.visible=v;if(!v){this.owner.publish(this.owner.begin(),this.view.rows,false,this.view.status,this.view.loaded);this.publish();}else if(!this.view.loaded){this.load(false);}}
 private async open(row:Provider):Promise<void>{const link=safeProviderLink(row.link);if(!link){return;}try{await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({action:'ohos.want.action.viewData',uri:link});}catch(error){}}
 build(){
 Column({space:8}){
  Row(){Text('观看平台').fontSize(19).fontWeight(FontWeight.Medium).layoutWeight(1);Text(this.region.toUpperCase()).fontSize(12)}.width('100%')
  if(this.view.busy){LoadingProgress().width(22).height(22)}
  if(this.view.status){Text(this.view.status).fontSize(12)}
  if(this.view.loaded&&!this.view.rows.length){Text('该地区暂无平台记录').fontSize(12)}
  if(this.view.rows.length){List({space:8}){ForEach(this.view.rows,(p:Provider)=>{ListItem(){Column({space:4}){if(p.logo){Image(p.logo).width(48).height(48).borderRadius(6).syncLoad(false)}else{Text(p.name.substring(0,1)).width(48).height(48).textAlign(TextAlign.Center)}Text(p.name).fontSize(12).maxLines(2).width(104);Text(p.options.join(' · ')).fontSize(11).maxLines(2).width(104)}.width(108).onClick(()=>{this.open(p);})}},(p:Provider)=>p.key)}.width('100%').height(126).listDirection(Axis.Horizontal)}
  Text('观看数据：TMDB / JustWatch').fontSize(11).width('100%')
  Button('刷新观看平台').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.load(true);})
 }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10).onVisibleAreaChange([0],(v:boolean,r:number)=>{this.visibility(v&&r>0);})
 }
}
