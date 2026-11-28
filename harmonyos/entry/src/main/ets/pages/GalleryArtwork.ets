import { Media } from '../model/Media';
import { GalleryImage } from '../model/GalleryRules';
import { cachedPoster,cachePoster,rejectPosterUri } from '../data/TraktDetails';
import { ReadCancel } from '../model/ReadFlight';
import { ArtworkImage } from './ArtworkImage';
@Component
export struct GalleryArtwork{
 @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
 @Prop row:GalleryImage={url:'',source:'trakt'};
 @Prop type:string='poster';
 @Prop cacheDir:string='';
 @State uri:string='';
 @State status:string='';
 private signal:ReadCancel=new ReadCancel();
 private resident:boolean=false;
 private retried:boolean=false;
 aboutToDisappear():void{this.resident=false;this.signal.cancel();this.uri='';}
 private async loadGalleryImage(force:boolean=false):Promise<void>{
  if(!this.resident){return;}this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal,row=this.row,item=this.item;
  if(row.source==='local'){this.uri=row.url;return;}
  this.status='读取图片…';try{
   const type=this.type==='poster'?'poster':'fanart';
   let uri=force?'':await cachedPoster(this.cacheDir,item,[row.url],signal,type);
   if(!uri){uri=(await cachePoster(this.cacheDir,item,[row.url],signal,type)).uri;}
   if(this.resident&&!signal.cancelled()&&this.row.url===row.url&&this.item.id===item.id){this.uri=uri;this.status=uri?'':'图片不可用，可重试';}
  }catch(error){if(this.resident&&!signal.cancelled()){this.status='图片读取失败，可重试';}}
 }
 private updateGalleryVisibility(v:boolean):void{if(v===this.resident){return;}this.resident=v;if(v){this.retried=false;this.loadGalleryImage();}else{this.signal.cancel();this.uri='';}}
 private recoverImage(uri:string):void{if(!this.resident||this.uri!==uri){return;}this.uri='';if(this.row.source==='local'||this.retried){this.status='图片损坏或不可用';return;}this.retried=true;rejectPosterUri(uri);this.loadGalleryImage(true);}
 build(){
 Column({space:6}){
  ArtworkImage({uri:this.uri,widthValue:'100%',ratio:this.type==='fanart'?16/9:2/3,contain:true,corner:4,onFailure:(uri:string)=>{this.recoverImage(uri);}})
  if(this.status){Text(this.status).fontSize(12);if(!this.uri){Button('重试图片').fontSize(11).onClick(()=>{this.retried=false;this.loadGalleryImage(true);})}}
 }.width('100%').onVisibleAreaChange([0],(v:boolean,r:number)=>{this.updateGalleryVisibility(v&&r>0);})
 }
}
