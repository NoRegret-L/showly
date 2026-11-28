import { Media } from '../model/Media';
import { PresentationRepository } from '../data/PresentationRepository';
import { ReadCancel } from '../model/ReadFlight';
import { ArtworkImage } from './ArtworkImage';
@Component
export struct CustomListArtwork{
  @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
  @Prop client:string='';
  @Prop language:string='zh';
  @Prop widthValue:number=60;
  @Prop showTitle:boolean=false;
  repository?:PresentationRepository;
  @State uri:string='';
  @State title:string='';
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToDisappear():void{this.active=false;this.signal.cancel();}
  private async updateVisible(visible:boolean):Promise<void>{
    if(!visible){this.active=false;this.signal.cancel();return;}
    if(this.active||!this.repository){return;}this.active=true;
    this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal,item=this.item;
    try{const row=await this.repository.listTitle(item,this.client,this.language,signal);
      if(this.active&&!signal.cancelled()&&item.id===this.item.id){this.uri=row.posterUri;this.title=this.language==='zh'?row.text.title:'';}
    }catch(error){}
  }
  build(){
    Column({space:3}){
      ArtworkImage({uri:this.uri,widthValue:this.widthValue,ratio:2/3,corner:6,onFailure:()=>{const uri=this.uri;this.uri='';if(uri){this.repository?.repairArtwork(this.item,uri);}}})
      if(this.showTitle){Text(this.title||this.item.title).fontSize(11).maxLines(2).width(this.widthValue)}
    }.onVisibleAreaChange([0],(v:boolean,r:number)=>{this.updateVisible(v&&r>0);})
  }
}
