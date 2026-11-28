import { GalleryTarget } from '../model/GalleryRules';
import { GalleryPage } from './GalleryPage';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { PersonRow } from '../model/DetailSections';
import { PersonProfile,PersonCredit,PersonCreditRow,projectPersonCredits } from '../model/PeopleRules';
import { openPeople } from '../data/PeopleRepository';
import { PresentationRepository } from '../data/PresentationRepository';
import { ReadCancel } from '../model/ReadFlight';
import { LazyRows } from '../model/LazyRows';
import { PersonArtwork } from './PersonArtwork';
import { CustomListArtwork } from './CustomListArtwork';
@Component
export struct PersonDetails{
  @Prop person:PersonRow={key:'',personId:0,name:'',department:'Acting',roles:[]};
  @Prop client:string='';
  @Prop cacheDir:string='';
  @Prop language:string='zh';
  @Prop scope:string='';
  repository?:PresentationRepository;
  members:()=>Set<string>=()=>new Set<string>();
  current:()=>boolean=()=>false;
  onBack:()=>void=()=>{};
  onOpen:(media:Media)=>void=()=>{};
  @State profile?:PersonProfile=undefined;
  @State galleryOpen:boolean=false;
  @State galleryTarget:GalleryTarget={item:{id:'',kind:'person',title:'',year:0,watched:false},type:'profile',hints:[],initialUri:''};
  @State status:string='';
  @State busy:boolean=false;
  @State kind:string='all';
  @State onlyMembers:boolean=false;
  @State count:number=0;
  private rows:PersonCredit[]=[];
  private source:LazyRows<PersonCreditRow>=new LazyRows<PersonCreditRow>();
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToAppear():void{this.active=true;this.load(false);}
  aboutToDisappear():void{this.active=false;this.signal.cancel();this.rows=[];}
  private allowed(signal:ReadCancel):boolean{return this.active&&this.current()&&!signal.cancelled();}
  private project():void{
    if(!this.active||!this.current()){return;}
    const rows=projectPersonCredits(this.rows,this.kind,this.onlyMembers,this.members());
    this.source.replace(rows,rows.map((r:PersonCreditRow)=>r.key),rows.map((r:PersonCreditRow)=>JSON.stringify(r)));this.count=rows.length;
  }
  private async load(refresh:boolean):Promise<void>{
    if(this.busy||!this.current()){return;}this.signal.cancel();this.signal=new ReadCancel();const signal=this.signal;
    this.busy=true;this.status='正在读取人物资料…';
    try{const repo=await openPeople(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const person=await repo.profile(this.person,this.client,refresh,signal);if(!this.allowed(signal)){return;}this.profile=person.profile;
      this.status=person.cached?'本地人物资料':'Trakt 人物资料';
      try{const credits=await repo.credits(this.person,this.client,refresh,signal);if(!this.allowed(signal)){return;}this.rows=credits.rows;this.project();if(credits.cached){this.status='本地人物或作品资料';}}
      catch(error){if(this.allowed(signal)){this.status='作品资料读取失败；保留已载入内容';}}
    }catch(error){if(this.allowed(signal)){this.status='人物资料读取失败，可重试';}}
    finally{if(this.allowed(signal)){this.busy=false;}}
  }
  private portrait():PersonRow{return {key:this.person.key,personId:this.person.personId,tmdb:this.profile?.identity.tmdb??this.person.tmdb,name:this.profile?.name??this.person.name,department:this.person.department,roles:this.person.roles,headshots:this.profile?.headshots.length?this.profile.headshots:this.person.headshots};}
  private openPersonGallery():void{const p=this.portrait();this.galleryTarget={item:{id:'person:'+p.personId,kind:'person',title:p.name,year:0,watched:false},type:'profile',tmdb:p.tmdb,hints:p.headshots??[],initialUri:''};this.galleryOpen=true;}
  @Builder personGallery(){GalleryPage({target:this.galleryTarget,client:this.client,current:()=>this.active&&this.current()&&this.galleryOpen,onClose:()=>{this.galleryOpen=false;}})}
  private async external(tmdb:boolean):Promise<void>{
    const id=this.profile?.identity.tmdb??this.person.tmdb;if(tmdb&&(!id||!Number.isSafeInteger(id)||id<=0)){return;}
    try{await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({action:'ohos.want.action.viewData',uri:tmdb?'https://www.themoviedb.org/person/'+id:'https://trakt.tv/people/'+this.person.personId});}catch(error){this.status='无法打开外部链接';}
  }
  build(){
    Column({space:8}){
      Row({space:6}){Button('返回').fontSize(12).onClick(()=>this.onBack());Text('人物详情').fontSize(20).layoutWeight(1);Button('刷新').fontSize(12).enabled(!this.busy).onClick(()=>this.load(true));}.width('100%')
      List({space:10}){
        ListItem(){Row({space:12}){PersonArtwork({person:this.portrait(),cacheDir:this.cacheDir,widthValue:90})
          Column({space:6}){Text(this.profile?.name??this.person.name).fontSize(23).fontWeight(FontWeight.Bold);Text(this.person.roles.join(' / ')).fontSize(13)
            if(this.profile?.birthday){Text('出生：'+this.profile.birthday).fontSize(12)}
            if(this.profile?.death){Text('逝世：'+this.profile.death).fontSize(12)}
            if(this.profile?.birthplace){Text(this.profile.birthplace).fontSize(12)}
            Button('人物图库').fontSize(11).onClick(()=>{this.openPersonGallery();})
            Row({space:4}){Button('Trakt').fontSize(11).onClick(()=>this.external(false));if(this.profile?.identity.tmdb||this.person.tmdb){Button('TMDB').fontSize(11).onClick(()=>this.external(true));}}
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')}
        ListItem(){Column({space:6}){Text('人物简介').fontSize(17).fontWeight(FontWeight.Bold);Text(this.profile?.bio||'暂无人物简介').fontSize(14);Text('来源：Trakt（非原版 TMDB 翻译）').fontSize(11);if(this.status){Text(this.status).fontSize(12)}if(this.busy){LoadingProgress().width(24).height(24)}}.width('100%').alignItems(HorizontalAlign.Start)}
        ListItem(){Column({space:6}){Text('影视作品').fontSize(19).fontWeight(FontWeight.Bold)
          Row({space:4}){ForEach(['all','show','movie'],(k:string)=>{Button(k==='all'?'全部':k==='show'?'剧集':'电影').fontSize(12).layoutWeight(1).backgroundColor(this.kind===k?$r('app.color.showly_accent'):$r('app.color.showly_muted_surface')).onClick(()=>{this.kind=k;this.project();})},(k:string)=>k)}
          Button(this.onlyMembers?'仅收藏：开启':'仅收藏：关闭').fontSize(12).onClick(()=>{this.onlyMembers=!this.onlyMembers;this.project();})
          if(!this.busy&&!this.count){Text('暂无符合筛选的作品').fontSize(12)}
        }.width('100%').alignItems(HorizontalAlign.Start)}
        LazyForEach(this.source,(r:PersonCreditRow)=>{ListItem(){
          if(r.credit){Row({space:10}){CustomListArtwork({item:r.credit.media,client:this.client,language:this.language,repository:this.repository,widthValue:48,showTitle:true})
            Column({space:4}){Text(r.credit.media.title).maxLines(2).fontSize(15);Text(r.credit.roles.join(' / ')).fontSize(12).maxLines(2);Text((r.credit.release||'待上映')+(r.member?' · 我的收藏':'' )).fontSize(11)}.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('›').fontSize(20)
          }.width('100%').onClick(()=>{if(r.credit&&this.current()){this.onOpen(r.credit.media);}})}
          else{Text(r.group).fontSize(17).fontWeight(FontWeight.Bold).width('100%')}
        }},(r:PersonCreditRow)=>this.source.keyFor(r.key))
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding(16).bindSheet($$this.galleryOpen,this.personGallery(),{height:SheetSize.LARGE,showClose:true})
  }
}
