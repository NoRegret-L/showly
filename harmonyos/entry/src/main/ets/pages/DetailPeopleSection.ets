import { Media } from '../model/Media';
import { PersonRow, SectionOwner, SectionSnapshot, emptySection } from '../model/DetailSections';
import { PresentationRepository } from '../data/PresentationRepository';
import { readPeople } from '../data/DetailSectionsRepository';
@Component
export struct DetailPeopleSection {
  @Prop item:Media={id:'',kind:'show',title:'',year:0,watched:false};
  @Prop client:string='';
  @Prop scope:string='';
  repository?:PresentationRepository;
  @State view:SectionSnapshot<PersonRow>=emptySection<PersonRow>();
  private owner:SectionOwner<PersonRow>=new SectionOwner<PersonRow>();
  private visible:boolean=false;
  private publish():void{const value=this.owner.snapshot();if(value!==this.view){this.view=value;}}
  aboutToDisappear():void{this.visible=false;this.owner.clear();}
  private async load():Promise<void>{
    if(!this.visible||this.view.busy){return;}
    const token=this.owner.begin(),signal=this.owner.consumer(),item=this.item,scope=this.scope,client=this.client;
    const current=():boolean=>this.visible&&this.owner.current(token)&&this.item.id===item.id&&this.scope===scope&&this.client===client;
    this.owner.publish(token,this.view.rows,true,'',this.view.loaded);this.publish();
    try{
      if(!this.view.loaded){
        const raw=await this.repository?.readDetailSection(item,'people-trakt',signal);
        if(!current()){return;}
        if(raw){const rows=JSON.parse(raw) as PersonRow[];if(Array.isArray(rows)&&rows.every((r:PersonRow)=>typeof r.key==='string'&&typeof r.name==='string'&&Array.isArray(r.roles))){this.owner.publish(token,rows,true,'本地缓存',true);this.publish();}}
      }
      if(!client){if(current()){this.owner.publish(token,this.view.rows,false,'离线资料',this.view.loaded);this.publish();}return;}
      const rows=await readPeople(item,client,signal);
      if(!current()){return;}
      this.owner.publish(token,rows,false,'',true);this.publish();
      try{await this.repository?.saveDetailSection(item,'people-trakt',JSON.stringify(rows),signal);}catch(error){}
    }catch(error){if(current()){this.owner.publish(token,this.view.rows,false,'演员资料读取失败，可重试',this.view.loaded);this.publish();}}
  }
  private updateSectionVisibility(visible:boolean):void{
    this.visible=visible;
    if(!visible){this.owner.publish(this.owner.begin(),this.view.rows,false,this.view.status,this.view.loaded);this.publish();return;}
    if(!this.view.loaded&&!this.view.busy){this.load();}
  }
  @Builder credit(row:PersonRow){
    Column({space:4}){
      Text(row.name.substring(0,1)).fontSize(24).width(84).height(94).textAlign(TextAlign.Center).backgroundColor($r('app.color.showly_placeholder')).borderRadius(8)
      Text(row.name).fontSize(13).maxLines(2).width(100)
      Text(row.roles.join(' / ')).fontSize(11).maxLines(3).width(100).fontColor($r('app.color.showly_secondary'))
    }.width(104)
  }
  build(){
    Column({space:8}){
      Text('演员与幕后人员').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
      Text('Trakt 演职员资料 · 与原版 TMDB 来源不同').fontSize(11).fontColor($r('app.color.showly_secondary')).width('100%')
      if(this.view.busy){LoadingProgress().width(22).height(22)}
      if(this.view.status){Text(this.view.status).fontSize(12).width('100%')}
      if(this.view.loaded&&this.view.rows.length===0){Text('未返回演职员资料').fontSize(12)}
      ForEach(['Acting','Directing','Writing','Sound'],(department:string)=>{
        if(this.view.rows.some((r:PersonRow)=>r.department===department)){
          Text(department==='Acting'?'演员':department==='Directing'?'导演':department==='Writing'?'编剧':'声音部门').fontSize(15).width('100%')
          List({space:8}){
            ForEach(this.view.rows.filter((r:PersonRow)=>r.department===department),(row:PersonRow)=>{ListItem(){this.credit(row)}},(row:PersonRow)=>row.key+':'+row.roles.join('|'))
          }.listDirection(Axis.Horizontal).height(174).width('100%')
        }
      },(department:string)=>department)
      if(!this.view.busy){Button('刷新演职员').fontSize(12).onClick(()=>{this.load();})}
    }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
     .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.updateSectionVisibility(visible&&ratio>0);})
  }
}
