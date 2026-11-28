import { common } from '@kit.AbilityKit';
import { GalleryTarget,GalleryImage,GALLERY_NEIGHBORS,galleryIndex,tmdbArtworkUrl,galleryTraktUrl } from '../model/GalleryRules';
import { openGallery } from '../data/GalleryRepository';
import { GalleryArtwork } from './GalleryArtwork';
import { ReadCancel } from '../model/ReadFlight';
import { LazyRows } from '../model/LazyRows';
@Component
export struct GalleryPage{
 @Prop target:GalleryTarget={item:{id:'',kind:'show',title:'',year:0,watched:false},type:'poster',hints:[],initialUri:''};
 @Prop client:string='';
 current:()=>boolean=()=>false;
 onClose:()=>void=()=>{};
 @State busy:boolean=false;
 @State status:string='';
 @State selected:number=0;
 @State total:number=0;
 private rows:GalleryImage[]=[];
 private source:LazyRows<GalleryImage>=new LazyRows<GalleryImage>();
 private signal:ReadCancel=new ReadCancel();
 private active:boolean=false;
 aboutToAppear():void{this.active=true;this.loadGallery(false);}
 aboutToDisappear():void{this.active=false;this.signal.cancel();this.rows=[];this.source.replace([],[],[]);}
 private allowed(s:ReadCancel):boolean{return this.active&&this.current()&&!s.cancelled();}
 private async loadGallery(refresh:boolean):Promise<void>{
  if(!this.active||!this.current()||this.busy){return;}this.signal.cancel();this.signal=new ReadCancel();const s=this.signal,previous=this.rows[this.selected]?.url??'';
  this.busy=true;this.status='读取图库…';
  try{const context=this.getUIContext().getHostContext() as common.UIAbilityContext,repo=await openGallery(context),result=await repo.load(context,this.target,this.client,refresh,s);
   if(this.allowed(s)){this.rows=result.rows;this.selected=galleryIndex(this.rows,previous);this.source.replace(this.rows,this.rows.map((r:GalleryImage)=>r.url),this.rows.map((r:GalleryImage)=>r.source));this.total=this.rows.length;this.status=result.status;}
  }catch(error){if(this.allowed(s)){this.status='图库读取失败，保留已加载内容';}}
  finally{if(this.allowed(s)){this.busy=false;}}
 }
 private async openOriginal():Promise<void>{const row=this.rows[this.selected];if(!row||!this.current()){return;}const link=row.source==='tmdb'?tmdbArtworkUrl(row.url):row.source==='trakt'?galleryTraktUrl(row.url):'';if(!link){return;}try{await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({action:'ohos.want.action.viewData',uri:link});}catch(error){this.status='无法打开原图';}}
 build(){
 Column({space:10}){
  Row({space:6}){Button('返回').fontSize(12).onClick(()=>this.onClose());Text(this.target.type==='poster'?'海报图库':this.target.type==='fanart'?'背景图图库':'人物图库').fontSize(20).layoutWeight(1);Button('原图').fontSize(12).enabled(this.total>0&&this.rows[this.selected]?.source!=='local').onClick(()=>{this.openOriginal();})}.width('100%')
  Text(this.target.item.title).fontSize(15).maxLines(1).width('100%')
  if(this.busy){LoadingProgress().width(22).height(22)}
  if(this.status){Text(this.status).fontSize(12)}
  if(this.total>0){
   Swiper(){LazyForEach(this.source,(row:GalleryImage)=>{Column(){GalleryArtwork({item:this.target.item,row:row,type:this.target.type,cacheDir:(this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir})}.width('100%').height('100%').justifyContent(FlexAlign.Center)},(row:GalleryImage)=>this.source.keyFor(row.url))}
    .index(this.selected).cachedCount(GALLERY_NEIGHBORS).loop(false).indicator(false).layoutWeight(1).width('100%').onChange((i:number)=>{this.selected=i;})
   Row(){Button('上一张').fontSize(12).enabled(this.selected>0).onClick(()=>{this.selected--;});Text((this.selected+1)+' / '+this.total).layoutWeight(1).textAlign(TextAlign.Center);Button('下一张').fontSize(12).enabled(this.selected+1<this.total).onClick(()=>{this.selected++;})}.width('100%')
  }else if(!this.busy){Text('暂无可用图片').fontSize(14).layoutWeight(1)}
  Button('刷新图库').fontSize(12).enabled(!this.busy).onClick(()=>{this.loadGallery(true);})
 }.width('100%').height('100%').padding(12)
 }
}
