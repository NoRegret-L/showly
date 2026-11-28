import { common } from '@kit.AbilityKit';
import { ClientSettings } from '../data/ClientSettings';
import { WatchOptions,WATCH_REGIONS } from '../model/AvailabilityRules';
import { configureTmdb,tmdbConfigured } from '../data/AvailabilityRepository';
interface RegionOption{value:string;}
@Component
export struct WatchSettings{
 @Prop options:WatchOptions={enabled:false,region:'us'};
 onChange:(value:WatchOptions)=>void=()=>{};
 onCredential:(version:number)=>void=()=>{};
 @State draft:string='';
 @State status:string='';
 @State busy:boolean=false;
 private active:boolean=false;
 aboutToAppear():void{this.active=true;}
 aboutToDisappear():void{this.active=false;this.draft='';}
 private async change(value:WatchOptions):Promise<void>{if(this.busy){return;}this.busy=true;try{const settings=new ClientSettings(this.getUIContext().getHostContext() as common.UIAbilityContext);await settings.saveWatchOptions(value);if(this.active){this.onChange(value);}}catch(error){if(this.active){this.status='保存设置失败';}}finally{if(this.active){this.busy=false;}}}
 build(){
 Column({space:8}){
  Text('观看平台').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
  Row(){Text('启用观看平台').layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.options.enabled}).enabled(!this.busy).onChange((v:boolean)=>{this.change({enabled:v,region:this.options.region});})}.width('100%')
  Row(){Text('地区').layoutWeight(1);Select(WATCH_REGIONS.map((r:string):RegionOption=>({value:r.toUpperCase()}))).selected(WATCH_REGIONS.indexOf(this.options.region)).value(this.options.region.toUpperCase()).enabled(!this.busy).onSelect((i:number)=>{this.change({enabled:this.options.enabled,region:WATCH_REGIONS[i]});})}.width('100%')
  Text('使用你自己的 TMDB API Read Access Token。本次运行有效，不写入磁盘或备份。').fontSize(12)
  TextInput({placeholder:'TMDB Read Access Token',text:this.draft}).type(InputType.Password).onChange((v:string)=>{this.draft=v;})
  Row({space:5}){Button('应用凭证').enabled(!!this.draft.trim()).onClick(()=>{try{this.onCredential(configureTmdb(this.draft));this.draft='';this.status='已设置本次运行凭证';}catch(error){this.status='凭证格式无效';}})
   Button('清除凭证').onClick(()=>{this.onCredential(configureTmdb(''));this.draft='';this.status='已清除';})}.width('100%')
  Text(this.status||(tmdbConfigured()?'本次运行已配置':'未配置 TMDB')).fontSize(12)
 }.width('100%').padding(12).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
 }
}
