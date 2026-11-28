import { PersonRow } from '../model/DetailSections';
import { Media } from '../model/Media';
import { PartArtwork } from './PartArtwork';
@Component
export struct PersonArtwork{
  @Prop person:PersonRow={key:'',personId:0,name:'',department:'Acting',roles:[]};
  @Prop cacheDir:string='';
  @Prop widthValue:number=84;
  private media():Media{return {id:'person:'+this.person.personId,kind:'person',title:this.person.name,year:0,watched:false};}
  build(){
    if(this.person.headshots?.length){PartArtwork({item:this.media(),urls:this.person.headshots??[],cacheDir:this.cacheDir,widthValue:this.widthValue,ratio:2/3})}
    else{Text(this.person.name.substring(0,1)).fontSize(24).width(this.widthValue).height(this.widthValue*1.5).textAlign(TextAlign.Center).backgroundColor($r('app.color.showly_placeholder')).borderRadius(8)}
  }
}
