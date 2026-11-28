import { PersonArtwork } from './PersonArtwork';
import { PersonDetails } from './PersonDetails';
import { LazyRows } from '../model/LazyRows';
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
  @Prop cacheDir:string='';
  @Prop language:string='zh';
  members:()=>Set<string>=()=>new Set<string>();
  onOpen:(media:Media)=>void=()=>{};
  @State peopleSheet:boolean=false;
  @State selected?:PersonRow=undefined;
  @State department:string='Acting';
  private full:LazyRows<PersonRow>=new LazyRows<PersonRow>();
  private active:boolean=true;
  private sheetScope:string='';
  @State view:SectionSnapshot<PersonRow>=emptySection<PersonRow>();
  private owner:SectionOwner<PersonRow>=new SectionOwner<PersonRow>();
  private visible:boolean=false;
  private publish():void{const value=this.owner.snapshot();if(value!==this.view){this.view=value;}}
  aboutToAppear():void{this.active=true;}
  aboutToDisappear():void{this.active=false;this.visible=false;this.peopleSheet=false;this.owner.clear();}
  private async load():Promise<void>{
    if(!this.visible||this.view.busy){return;}
    const token=this.owner.begin(),signal=this.owner.consumer(),item=this.item,scope=this.scope,client=this.client;
    const current=():boolean=>this.visible&&this.owner.current(token)&&this.item.id===item.id&&this.scope===scope&&this.client===client;
    this.owner.publish(token,this.view.rows,true,'',this.view.loaded);this.publish();
    try{
      if(!this.view.loaded){
        const raw=await this.repository?.readDetailSection(item,'people-trakt-full',signal);
        if(!current()){return;}
        if(raw){const rows=JSON.parse(raw) as PersonRow[];if(Array.isArray(rows)&&rows.every((r:PersonRow)=>typeof r.key==='string'&&typeof r.name==='string'&&Array.isArray(r.roles))){this.owner.publish(token,rows,true,'本地缓存',true);this.publish();}}
      }
      if(!client){if(current()){this.owner.publish(token,this.view.rows,false,'离线资料',this.view.loaded);this.publish();}return;}
      const rows=await readPeople(item,client,signal);
      if(!current()){return;}
      this.owner.publish(token,rows,false,'',true);this.publish();
      try{await this.repository?.saveDetailSection(item,'people-trakt-full',JSON.stringify(rows),signal);}catch(error){}
    }catch(error){if(current()){this.owner.publish(token,this.view.rows,false,'演员资料读取失败，可重试',this.view.loaded);this.publish();}}
  }
  private updateSectionVisibility(visible:boolean):void{
    this.visible=visible;
    if(!visible){this.owner.publish(this.owner.begin(),this.view.rows,false,this.view.status,this.view.loaded);this.publish();return;}
    if(!this.view.loaded&&!this.view.busy){this.load();}
  }
  @Builder credit(row:PersonRow){
    Column({space:4}){
      PersonArtwork({person:row,cacheDir:this.cacheDir,widthValue:84})
      Text(row.name).fontSize(13).maxLines(2).width(100)
      Text(row.roles.join(' / ')).fontSize(11).maxLines(3).width(100).fontColor($r('app.color.showly_secondary'))
    }.width(104).onClick(()=>{this.openPerson(row);})
  }
  private openPerson(row:PersonRow):void{this.sheetScope=this.scope;this.selected=row;this.peopleSheet=true;}
  private openDepartment(department:string):void{this.department=department;this.selected=undefined;this.sheetScope=this.scope;const rows=this.view.rows.filter((r:PersonRow)=>r.department===department);this.full.replace(rows,rows.map((r:PersonRow)=>r.key),rows.map((r:PersonRow)=>JSON.stringify(r)));this.peopleSheet=true;}
  private sheetCurrent():boolean{return this.active&&this.peopleSheet&&this.sheetScope===this.scope;}
  @Builder peopleContent(){
    if(this.selected){PersonDetails({person:this.selected,client:this.client,cacheDir:this.cacheDir,language:this.language,scope:this.scope,repository:this.repository,members:()=>this.members(),current:()=>this.sheetCurrent(),onBack:()=>{this.peopleSheet=false;},onOpen:(media:Media)=>{if(this.sheetCurrent()){this.peopleSheet=false;this.onOpen(media);}}})}
    else{Column({space:8}){Row(){Text('完整演职人员').fontSize(20).layoutWeight(1);Button('关闭').onClick(()=>{this.peopleSheet=false;})}
      List({space:8}){LazyForEach(this.full,(r:PersonRow)=>{ListItem(){Row({space:10}){PersonArtwork({person:r,cacheDir:this.cacheDir,widthValue:52});Column({space:4}){Text(r.name).fontSize(16);Text(r.roles.join(' / ')).fontSize(12)}.layoutWeight(1).alignItems(HorizontalAlign.Start);Text('›')}.width('100%').onClick(()=>{this.selected=r;})}},(r:PersonRow)=>this.full.keyFor(r.key))}.layoutWeight(1).width('100%')
    }.padding(16).height('100%').width('100%')}
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
          Row(){Text(department==='Acting'?'演员':department==='Directing'?'导演':department==='Writing'?'编剧':'声音部门').fontSize(15).layoutWeight(1);Button('全部').fontSize(11).onClick(()=>{this.openDepartment(department);})}.width('100%')
          List({space:8}){
            ForEach(this.view.rows.filter((r:PersonRow)=>r.department===department).slice(0,department==='Acting'?30:20),(row:PersonRow)=>{ListItem(){this.credit(row)}},(row:PersonRow)=>row.key+':'+row.roles.join('|'))
          }.listDirection(Axis.Horizontal).height(208).width('100%')
        }
      },(department:string)=>department)
      if(!this.view.busy){Button('刷新演职员').fontSize(12).onClick(()=>{this.load();})}
    }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
     .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.updateSectionVisibility(visible&&ratio>0);})
     .bindSheet($$this.peopleSheet,this.peopleContent(),{height:SheetSize.LARGE,showClose:true})
  }
}
