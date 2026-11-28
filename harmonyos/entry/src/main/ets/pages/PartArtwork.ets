import { Media } from '../model/Media';
import { ReadCancel } from '../model/ReadFlight';
import { cachedPoster, cachePoster } from '../data/TraktDetails';
import { ArtworkImage } from './ArtworkImage';
@Component
export struct PartArtwork{
  @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
  @Prop urls:string[]=[];
  @Prop cacheDir:string='';
  @Prop widthValue:number=64;
  @Prop ratio:number=2/3;
  @State uri:string='';
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToDisappear():void{this.active=false;this.signal.cancel();}
  private async load(visible:boolean):Promise<void>{
    if(!visible){this.active=false;this.signal.cancel();return;}
    if(this.active){return;}this.active=true;
    this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal,urls=this.urls,item=this.item;
    if(!urls.length||!this.cacheDir){return;}
    try{
      let uri=await cachedPoster(this.cacheDir,item,urls,signal,'fanart');
      if(!uri){uri=(await cachePoster(this.cacheDir,item,urls,signal,'fanart')).uri;}
      if(this.active&&!signal.cancelled()&&this.item.id===item.id&&this.urls===urls){this.uri=uri;}
    }catch(error){}
  }
  build(){
    ArtworkImage({uri:this.uri,widthValue:this.widthValue,ratio:this.ratio,onFailure:()=>{this.uri='';}})
      .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.load(visible&&ratio>0);})
  }
}
