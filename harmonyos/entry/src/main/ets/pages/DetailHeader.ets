import { ArtworkImage } from './ArtworkImage';
@Component
export struct DetailHeader {
  @Prop title:string='';
  @Prop subtitle:string='';
  @Prop poster:string='';
  @Prop fanart:string='';
  onBack:()=>void=()=>{};
  onPosterFailure:(uri:string)=>void=()=>{};
  onFanartFailure:(uri:string)=>void=()=>{};
  build(){
    Column({space:8}){
      Row(){
        Button('返回').fontSize(12).height(32).onClick(()=>{this.onBack();})
        Blank()
      }.width('100%')
      if(this.fanart){
        ArtworkImage({uri:this.fanart,widthValue:'100%',ratio:16/9,corner:8,onFailure:(uri:string)=>{this.onFanartFailure(uri);}})
      }
      Row({space:12}){
        ArtworkImage({uri:this.poster,widthValue:92,ratio:2/3,corner:8,onFailure:(uri:string)=>{this.onPosterFailure(uri);}})
        Column({space:6}){
          Text(this.title).fontSize(23).fontWeight(FontWeight.Bold).width('100%')
          if(this.subtitle){Text(this.subtitle).fontSize(13).fontColor($r('app.color.showly_secondary')).width('100%')}
        }.layoutWeight(1)
      }.width('100%')
    }.width('100%')
  }
}
