import { ListPreference, defaultListPreference, localListBackup, mergeListBackup } from '../model/ListPersistence';
import { exportCustomListBackup, selectCustomListBackup } from '../data/CustomListBackup';
import { CollectionRating } from '../data/TraktLibrary';
import { TitlePresentation } from '../model/MediaPresentation';
import { common } from '@kit.AbilityKit';
import { Media } from '../model/Media';
import { CustomList, ListMember, ListCommand, ListSnapshot, ListDocument, ListsOwner, emptyListSnapshot, sortLists, sortListMembers } from '../model/CustomLists';
import { CustomListsRepository, openCustomLists } from '../data/CustomListsRepository';
import { readCustomLists } from '../data/TraktCustomLists';
import { traktAuth } from '../data/TraktAuth';
import { PresentationRepository } from '../data/PresentationRepository';
import { LazyRows } from '../model/LazyRows';
import { ReadCancel } from '../model/ReadFlight';
import { CustomListArtwork } from './CustomListArtwork';

@Component
export struct CustomListsPage{
  @Prop scope:string='';
  @Prop client:string='';
  @Prop language:string='zh';
  @Prop selectedItem?:Media=undefined;
  @Prop manage:boolean=false;
  presentation?:PresentationRepository;
  onBack:()=>void=()=>{};
  onOpen:(item:Media)=>void=()=>{};
  current:()=>boolean=()=>false;
  writable:()=>boolean=()=>true;
  @State view:ListSnapshot=emptyListSnapshot();
  @State selected:string='';
  @State query:string='';
  @State name:string='';
  @State description:string='';
  @State editing:boolean=false;
  @State listSort:string='updated';
  @State memberSort:string='rank';
  @State kind:string='all';
  @State descending:boolean=false;
  @State reorderMode:boolean=false;
  private savedPreference:ListPreference=defaultListPreference();
  private preferenceRevision:number=0;
  private memberScroll:Scroller=new Scroller();
  private anchor:string='';
  private metadata:Map<string,TitlePresentation>=new Map<string,TitlePresentation>();
  private ratings:Map<string,number>=new Map<string,number>();
  private enrichment:ReadCancel=new ReadCancel();
  readRatings:()=>Promise<CollectionRating[]>=async()=>[];
  private owner:ListsOwner=new ListsOwner();
  private lists:LazyRows<CustomList>=new LazyRows<CustomList>();
  private members:LazyRows<ListMember>=new LazyRows<ListMember>();
  private repo?:CustomListsRepository;
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToAppear():void{this.active=true;this.load();}
  aboutToDisappear():void{this.active=false;this.signal.cancel();this.enrichment.cancel();this.metadata.clear();this.ratings.clear();this.owner.clear();this.lists.replace([],[],[]);this.members.replace([],[],[]);}
  private allowed():boolean{return this.active&&!!this.scope&&this.current()&&!this.signal.cancelled();}
  private list():CustomList|undefined{return this.view.rows.find((r:CustomList)=>r.id===this.selected);}
  private updateRows():void{
    const rows=sortLists(this.view.rows,this.query,this.manage?'name':this.listSort,this.manage?false:this.descending);
    this.lists.replace(rows,rows.map((r:CustomList)=>r.id),rows.map((r:CustomList)=>JSON.stringify([r.name,r.description,r.updatedAt,r.members.length,r.members.slice(0,3),r.remote,r.unsupported,this.selectedItem?this.owner.index.contains(r.id,this.selectedItem.id):false])));
    const current=this.list();
    const projected=(current?.members??[]).map((m:ListMember):ListMember=>{
      const meta=this.metadata.get(m.media.id);
      return {media:m.media,rank:m.rank,listedAt:m.listedAt,rating:meta?.collection?.rating??m.rating,userRating:this.ratings.get(m.media.id),date:meta?.collection?.release??m.date,localized:this.language==='zh'?meta?.text.title||m.localized:undefined};
    });
    const members=sortListMembers(projected,this.reorderMode?'all':this.kind,this.reorderMode?'rank':this.memberSort,this.reorderMode?false:this.descending,this.selected+':'+(current?.updatedAt??0));
    this.members.replace(members,members.map((r:ListMember)=>r.media.id),members.map((r:ListMember)=>JSON.stringify(r)));
  }
  private publish(token:number,doc:ListDocument|undefined,busy:boolean,status:string,loaded:boolean):void{
    if(!this.allowed()||!this.owner.current(token)){return;}
    this.owner.publish(token,doc?doc.local.concat(doc.remote):this.view.rows,busy,status,loaded);
    const next=this.owner.snapshot();if(next!==this.view){const changed=next.rows!==this.view.rows;this.view=next;if(changed){this.updateRows();}}
  }
  private async load():Promise<void>{
    if(!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'',this.view.loaded);
    try{
      const repo=await openCustomLists(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if(!this.allowed()||!this.owner.current(token)){return;}this.repo=repo;
      const doc=await repo.read(this.scope,()=>this.allowed()&&this.owner.current(token));
      this.publish(token,doc,false,'',true);
    }catch(error){this.publish(token,undefined,false,'列表读取失败，可重试；未覆盖数据',this.view.loaded);}
  }
  private async edit(command:ListCommand):Promise<void>{
    if(!this.writable()){return;}
    const repo=this.repo;if(!repo||!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'',this.view.loaded);
    try{const doc=await repo.edit(this.scope,command,()=>this.allowed()&&this.writable()&&this.owner.current(token));
      if(!this.allowed()||!this.owner.current(token)){return;}
      if(command.kind==='delete'){this.selected='';}this.editing=false;
      this.publish(token,doc,false,'已保存至本机',true);
    }catch(error){this.publish(token,undefined,false,'列表保存失败，请重试',this.view.loaded);}
  }
  private async importLists():Promise<void>{
    if(!this.writable()){return;}
    const repo=this.repo,session=traktAuth.session(this.client),scope=this.scope;
    if(!repo||!this.allowed()||this.view.busy||!scope.startsWith('account:')||!session){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'读取 Trakt 列表…',this.view.loaded);
    const current=():boolean=>this.allowed()&&this.owner.current(token)&&this.scope===scope&&traktAuth.isCurrent(session.clientId,session.generation);
    try{const rows=await readCustomLists(session,scope.substring(8),this.signal);
      if(!current()){return;}const doc=await repo.importRemote(scope,rows,current);
      this.publish(token,doc,false,'Trakt 只读快照已保存',true);
    }catch(error){this.publish(token,undefined,false,'Trakt 读取未完成；保留原快照，可重试',this.view.loaded);}
  }
  private async choose(id:string):Promise<void>{
    this.selected=id;this.reorderMode=false;this.metadata.clear();this.ratings.clear();this.enrichment.cancel();this.enrichment=new ReadCancel();
    const signal=this.enrichment,revision=++this.preferenceRevision;this.memberSort='rank';this.kind='all';this.descending=false;this.updateRows();
    try{const p=await this.repo?.preference(this.scope,id,()=>this.allowed()&&this.selected===id&&revision===this.preferenceRevision);
      if(p&&this.allowed()&&this.selected===id&&revision===this.preferenceRevision){this.memberSort=p.sort;this.kind=p.kind;this.descending=p.descending;this.updateRows();}
    }catch(error){}
    if(!this.allowed()||signal.cancelled()||this.selected!==id){return;}
    // Hydrate business metadata only, never posters; share the persistent title cache.
    for(const m of this.list()?.members??[]){
      if(!this.allowed()||signal.cancelled()||this.selected!==id){return;}
      try{const row=await this.presentation?.cachedListTitle(m.media,signal);if(row&&!signal.cancelled()){this.metadata.set(m.media.id,row);}}catch(error){}
    }
    if(!this.allowed()||signal.cancelled()||this.selected!==id){return;}
    this.updateRows();
    try{const ratings=await this.readRatings();if(this.allowed()&&!signal.cancelled()&&this.selected===id){for(const r of ratings){this.ratings.set(r.id,r.value);}this.updateRows();}}catch(error){}
  }
  private savePreference():void{
    if(!this.writable()){return;}
    if(this.reorderMode||!this.selected){return;}const id=this.selected,revision=++this.preferenceRevision;
    const p:ListPreference={sort:this.memberSort,kind:this.kind,descending:this.descending};
    this.repo?.savePreference(this.scope,id,p,()=>this.allowed()&&this.writable()&&this.selected===id&&revision===this.preferenceRevision).catch(()=>{});
  }
  private toggleReorder():void{
    if(this.view.busy||this.list()?.remote!==false){return;}
    if(!this.reorderMode){this.savedPreference={sort:this.memberSort,kind:this.kind,descending:this.descending};this.reorderMode=true;}
    else{this.reorderMode=false;this.memberSort=this.savedPreference.sort;this.kind=this.savedPreference.kind;this.descending=this.savedPreference.descending;}
    this.updateRows();
  }
  private moveMember(from:number,to:number):void{
    if(!this.reorderMode||this.view.busy||this.list()?.remote!==false||from===to){return;}
    const media=this.members.idAt(from),target=this.members.idAt(to);if(!media||!target){return;}
    this.edit({kind:'reorder',id:this.selected,mediaId:media,targetId:target});
  }
  private async exportLists():Promise<void>{
    const repo=this.repo;if(!repo||!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'导出本机列表…',true);
    try{const doc=await repo.read(this.scope,()=>this.allowed()&&this.owner.current(token));
      const saved=await exportCustomListBackup(this.getUIContext().getHostContext() as common.UIAbilityContext,localListBackup(doc));
      this.publish(token,undefined,false,saved?'本机列表备份已回读校验':'已取消',true);
    }catch(error){this.publish(token,undefined,false,'列表备份失败',true);}
  }
  private async restoreLists():Promise<void>{
    if(!this.writable()){return;}
    const repo=this.repo;if(!repo||!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'选择本机列表备份…',true);
    try{const backup=await selectCustomListBackup(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if(!backup||!this.allowed()||!this.owner.current(token)){this.publish(token,undefined,false,'已取消',true);return;}
      const old=await repo.read(this.scope,()=>this.allowed()&&this.owner.current(token)),next=mergeListBackup(old,backup);
      this.publish(token,undefined,false,'可新增 '+(next.local.length-old.local.length)+' 个列表；原有数据不覆盖',true);
      if(next===old){return;}
      this.getUIContext().showActionSheet({title:'确认恢复本机列表',message:'只新增缺失列表，不覆盖现有列表，不写入 Trakt。',autoCancel:true,sheets:[{title:'确认恢复',action:()=>{this.confirmRestore(backup,old);}}]});
    }catch(error){this.publish(token,undefined,false,'备份验证失败；未修改数据',true);}
  }
  private async confirmRestore(backup:ListDocument,old:ListDocument):Promise<void>{
    if(!this.writable()){return;}
    const repo=this.repo;if(!repo||!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'恢复列表…',true);
    try{const doc=await repo.restoreLocal(this.scope,backup,old,()=>this.allowed()&&this.writable()&&this.owner.current(token));this.publish(token,doc,false,'本机列表恢复成功',true);}
    catch(error){this.publish(token,undefined,false,'恢复失败或预览变化；请重新选择',true);}
  }
  private startEdit(row?:CustomList):void{this.name=row?.name??'';this.description=row?.description??'';this.editing=true;}
  private confirm(command:ListCommand,label:string):void{
    const scope=this.scope;
    this.getUIContext().showActionSheet({title:label,message:'仅修改本机自定义列表，不影响观看历史或 Trakt。',autoCancel:true,sheets:[{title:'确认',action:()=>{if(this.allowed()&&scope===this.scope){this.edit(command);}}}]});
  }
  @Builder cover(row:CustomList){
    Row({space:4}){
      ForEach(sortListMembers(row.members,'all','rank',false).slice(0,3),(m:ListMember)=>{
        CustomListArtwork({item:m.media,client:this.client,language:this.language,widthValue:52,repository:this.presentation})
      },(m:ListMember)=>m.media.id)
      if(!row.members.length){Text('空列表').fontSize(12)}
    }
  }
  @Builder header(){
    Row({space:8}){
      if(!this.manage){Button('返回').fontSize(12).height(32).onClick(()=>{if(this.selected){this.enrichment.cancel();this.selected='';this.reorderMode=false;this.editing=false;this.updateRows();}else{this.onBack();}})}
      Text(this.manage?'加入自定义列表':this.list()?.name??'我的列表').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      if(!this.selected){Button('新建').fontSize(12).height(32).enabled(this.writable()&&this.view.loaded&&!this.view.busy).onClick(()=>{this.startEdit();})}
    }.width('100%')
    if(this.view.busy){LoadingProgress().width(22).height(22)}
    if(this.view.status){Text(this.view.status).fontSize(12).width('100%')}
    if(!this.view.loaded&&!this.view.busy){Button('重试读取').onClick(()=>{this.load();})}
    if(!this.scope){Text('账户尚未验证，列表暂不可用').fontSize(12)}
    else if(!this.writable()){Text('显示本账户上次列表；在线核验后可编辑。').fontSize(12)}
    if(this.editing){
      TextInput({placeholder:'列表名称',text:this.name}).onChange((v:string)=>{this.name=v;})
      TextInput({placeholder:'描述（可选）',text:this.description}).onChange((v:string)=>{this.description=v;})
      Row({space:8}){
        Button('保存').enabled(this.writable()&&!!this.name.trim()&&!this.view.busy).onClick(()=>{this.edit({kind:this.selected?'edit':'create',id:this.selected,name:this.name,description:this.description});})
        Button('取消').onClick(()=>{this.editing=false;})
      }
    }
  }
  build(){
    if(this.manage){
      Column({space:6}){
        this.header()
        if(this.view.loaded){
          ForEach(this.view.rows,(r:CustomList)=>{
            Row({space:6}){
              Text(r.name+(r.remote?' · Trakt 只读':'')).layoutWeight(1).fontSize(13)
              Button(this.selectedItem&&this.owner.index.contains(r.id,this.selectedItem.id)?'✓ 已加入':'加入').fontSize(12).height(30)
                .enabled(!r.remote&&!this.view.busy&&!!this.selectedItem)
                .onClick(()=>{const item=this.selectedItem;if(item){this.edit({kind:this.owner.index.contains(r.id,item.id)?'remove':'add',id:r.id,media:item,mediaId:item.id});}})
            }.width('100%')
          },(r:CustomList)=>r.id+':'+this.view.revision)
        }
      }.width('100%').padding(8)
    }else{
      Column({space:8}){
        this.header()
        if(!this.selected){
          TextInput({placeholder:'搜索列表名称或描述',text:this.query}).onChange((v:string)=>{this.query=v;this.updateRows();})
          Row({space:5}){
            Button('名称').fontSize(12).layoutWeight(1).onClick(()=>{this.listSort='name';this.updateRows();})
            Button('创建').fontSize(12).layoutWeight(1).onClick(()=>{this.listSort='created';this.updateRows();})
            Button('更新').fontSize(12).layoutWeight(1).onClick(()=>{this.listSort='updated';this.updateRows();})
            Button(this.descending?'降序':'升序').fontSize(12).onClick(()=>{this.descending=!this.descending;this.updateRows();})
          }.width('100%')
          if(this.scope.startsWith('account:')){Button('读取 Trakt 列表（只读）').fontSize(12).enabled(this.view.loaded&&!this.view.busy).onClick(()=>{this.importLists();})}
          Row({space:5}){Button('导出列表备份').fontSize(12).enabled(this.view.loaded&&!this.view.busy).onClick(()=>{this.exportLists();});Button('恢复列表备份').fontSize(12).enabled(this.view.loaded&&!this.view.busy).onClick(()=>{this.restoreLists();})}.width('100%')
          if(this.view.loaded&&!this.lists.totalCount()){Text('暂无列表').fontSize(14)}
          List({space:8}){
            LazyForEach(this.lists,(r:CustomList)=>{
              ListItem(){
                Column({space:6}){
                  this.cover(r)
                  Text(r.name).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
                  if(r.description){Text(r.description).fontSize(12).maxLines(2).width('100%')}
                  Text(r.members.length+' 部影视'+(r.remote?' · Trakt 只读':' · 本机')+(r.unsupported?' · '+r.unsupported+' 项其他类型未展示':'')).fontSize(12).width('100%')
                }.padding(10).width('100%').backgroundColor($r('app.color.showly_surface')).borderRadius(10).onClick(()=>{this.choose(r.id);})
              }
            },(r:CustomList)=>this.lists.keyFor(r.id))
          }.layoutWeight(1).width('100%')
        }else{
          Text(this.list()?.description??'').fontSize(12).width('100%')
          if(this.list()?.remote===false){
            Row({space:6}){
              Button(this.reorderMode?'完成重排':'调整顺序').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.toggleReorder();})
              Button('编辑').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.startEdit(this.list());})
              Button('删除列表').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.confirm({kind:'delete',id:this.selected},'删除本机列表？');})
            }.width('100%')
          }
          if(!this.reorderMode){
          Row({space:4}){
            ForEach(['all','show','movie'],(k:string)=>{Button((this.kind===k?'✓ ':'')+(k==='all'?'全部':k==='show'?'剧集':'电影')).fontSize(12).layoutWeight(1).onClick(()=>{this.kind=k;this.updateRows();this.savePreference();})})
          }.width('100%')
          Flex({wrap:FlexWrap.Wrap}){
            ForEach(['rank','name','year','rating','userRating','added','random'],(k:string)=>{
              Button((this.memberSort===k?'✓ ':'')+(k==='rank'?'排名':k==='name'?'名称':k==='year'?'年份':k==='rating'?'评分':k==='userRating'?'我的评分':k==='added'?'添加':'随机')).fontSize(11).height(30).margin(2).onClick(()=>{this.memberSort=k;this.updateRows();this.savePreference();})
            })
            Button(this.descending?'降序':'升序').fontSize(11).height(30).onClick(()=>{this.descending=!this.descending;this.updateRows();this.savePreference();})
          }.width('100%')
          }else{Text('拖动成员调整顺序，完成后恢复原筛选和排序。').fontSize(12)}
          if(this.list()?.remote){Text('远程快照只读；不执行同步写入。').fontSize(12)}
          if(!this.members.totalCount()){Text('无匹配成员，可从影视详情加入本机列表。').fontSize(12)}
          List({space:6,scroller:this.memberScroll}){
            LazyForEach(this.members,(m:ListMember)=>{
              ListItem(){
                Row({space:6}){
                  CustomListArtwork({item:m.media,client:this.client,language:this.language,widthValue:48,showTitle:false,repository:this.presentation})
                  Column({space:4}){
                    Text(m.localized||m.media.title).fontSize(14).maxLines(2).width('100%').onClick(()=>{this.onOpen(m.media);})
                    Text((m.media.kind==='show'?'剧集':'电影')+' · '+(m.media.year||'')+' · #'+m.rank).fontSize(11)
                    if(m.rating!==undefined){Text('★ '+m.rating.toFixed(1)).fontSize(11)}
                    if(m.userRating!==undefined){Text('我的评分 '+m.userRating).fontSize(11)}
                  }.layoutWeight(1)
                  if(this.list()?.remote===false){
                    if(this.reorderMode){
                      Button('↑').fontSize(12).height(30).enabled(!this.view.busy).onClick(()=>{this.edit({kind:'move',id:this.selected,mediaId:m.media.id,direction:-1});})
                      Button('↓').fontSize(12).height(30).enabled(!this.view.busy).onClick(()=>{this.edit({kind:'move',id:this.selected,mediaId:m.media.id,direction:1});})
                    }
                    Button('移除').fontSize(11).height(30).enabled(!this.view.busy).onClick(()=>{this.confirm({kind:'remove',id:this.selected,mediaId:m.media.id},'移除本机列表成员？');})
                  }
                }.width('100%')
              }
            },(m:ListMember)=>this.members.keyFor(m.media.id)).onMove((from:number,to:number)=>{this.moveMember(from,to);})
          }.layoutWeight(1).width('100%').onScrollIndex((start:number)=>{this.anchor=this.members.idAt(start);})
        }
      }.width('100%').height('100%').padding(12)
    }
  }
}
