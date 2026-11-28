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
  private owner:ListsOwner=new ListsOwner();
  private lists:LazyRows<CustomList>=new LazyRows<CustomList>();
  private members:LazyRows<ListMember>=new LazyRows<ListMember>();
  private repo?:CustomListsRepository;
  private signal:ReadCancel=new ReadCancel();
  private active:boolean=false;
  aboutToAppear():void{this.active=true;this.load();}
  aboutToDisappear():void{this.active=false;this.signal.cancel();this.owner.clear();this.lists.replace([],[],[]);this.members.replace([],[],[]);}
  private allowed():boolean{return this.active&&!!this.scope&&this.current()&&!this.signal.cancelled();}
  private list():CustomList|undefined{return this.view.rows.find((r:CustomList)=>r.id===this.selected);}
  private updateRows():void{
    const rows=sortLists(this.view.rows,this.query,this.manage?'name':this.listSort,this.manage?false:this.descending);
    this.lists.replace(rows,rows.map((r:CustomList)=>r.id),rows.map((r:CustomList)=>JSON.stringify([r.name,r.description,r.updatedAt,r.members.length,r.members.slice(0,3),r.remote,r.unsupported,this.selectedItem?this.owner.index.contains(r.id,this.selectedItem.id):false])));
    const current=this.list(),members=sortListMembers(current?.members??[],this.kind,this.memberSort,this.descending,this.selected+':'+(current?.updatedAt??0));
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
    const repo=this.repo;if(!repo||!this.allowed()||this.view.busy){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'',this.view.loaded);
    try{const doc=await repo.edit(this.scope,command,()=>this.allowed()&&this.owner.current(token));
      if(!this.allowed()||!this.owner.current(token)){return;}
      if(command.kind==='delete'){this.selected='';}this.editing=false;
      this.publish(token,doc,false,'已保存至本机',true);
    }catch(error){this.publish(token,undefined,false,'列表保存失败，请重试',this.view.loaded);}
  }
  private async importLists():Promise<void>{
    const repo=this.repo,session=traktAuth.session(this.client),scope=this.scope;
    if(!repo||!this.allowed()||this.view.busy||!scope.startsWith('account:')||!session){return;}
    const token=this.owner.begin();this.publish(token,undefined,true,'读取 Trakt 列表…',this.view.loaded);
    const current=():boolean=>this.allowed()&&this.owner.current(token)&&this.scope===scope&&traktAuth.isCurrent(session.clientId,session.generation);
    try{const rows=await readCustomLists(session,scope.substring(8),this.signal);
      if(!current()){return;}const doc=await repo.importRemote(scope,rows,current);
      this.publish(token,doc,false,'Trakt 只读快照已保存',true);
    }catch(error){this.publish(token,undefined,false,'Trakt 读取未完成；保留原快照，可重试',this.view.loaded);}
  }
  private choose(id:string):void{this.selected=id;this.memberSort='rank';this.kind='all';this.descending=false;this.updateRows();}
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
      if(!this.manage){Button('返回').fontSize(12).height(32).onClick(()=>{if(this.selected){this.selected='';this.editing=false;this.updateRows();}else{this.onBack();}})}
      Text(this.manage?'加入自定义列表':this.list()?.name??'我的列表').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      if(!this.selected){Button('新建').fontSize(12).height(32).enabled(this.view.loaded&&!this.view.busy).onClick(()=>{this.startEdit();})}
    }.width('100%')
    if(this.view.busy){LoadingProgress().width(22).height(22)}
    if(this.view.status){Text(this.view.status).fontSize(12).width('100%')}
    if(!this.view.loaded&&!this.view.busy){Button('重试读取').onClick(()=>{this.load();})}
    if(!this.scope){Text('账户尚未验证，列表暂不可用').fontSize(12)}
    if(this.editing){
      TextInput({placeholder:'列表名称',text:this.name}).onChange((v:string)=>{this.name=v;})
      TextInput({placeholder:'描述（可选）',text:this.description}).onChange((v:string)=>{this.description=v;})
      Row({space:8}){
        Button('保存').enabled(!!this.name.trim()&&!this.view.busy).onClick(()=>{this.edit({kind:this.selected?'edit':'create',id:this.selected,name:this.name,description:this.description});})
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
              Button('编辑').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.startEdit(this.list());})
              Button('删除列表').fontSize(12).enabled(!this.view.busy).onClick(()=>{this.confirm({kind:'delete',id:this.selected},'删除本机列表？');})
            }.width('100%')
          }
          Row({space:4}){
            ForEach(['all','show','movie'],(k:string)=>{Button((this.kind===k?'✓ ':'')+(k==='all'?'全部':k==='show'?'剧集':'电影')).fontSize(12).layoutWeight(1).onClick(()=>{this.kind=k;this.updateRows();})})
          }.width('100%')
          Flex({wrap:FlexWrap.Wrap}){
            ForEach(['rank','name','year','rating','userRating','added','random'],(k:string)=>{
              Button((this.memberSort===k?'✓ ':'')+(k==='rank'?'排名':k==='name'?'名称':k==='year'?'年份':k==='rating'?'评分':k==='userRating'?'我的评分':k==='added'?'添加':'随机')).fontSize(11).height(30).margin(2).onClick(()=>{this.memberSort=k;this.updateRows();})
            })
            Button(this.descending?'降序':'升序').fontSize(11).height(30).onClick(()=>{this.descending=!this.descending;this.updateRows();})
          }.width('100%')
          if(this.list()?.remote){Text('远程快照只读；不执行同步写入。').fontSize(12)}
          if(!this.members.totalCount()){Text('无匹配成员，可从影视详情加入本机列表。').fontSize(12)}
          List({space:6}){
            LazyForEach(this.members,(m:ListMember)=>{
              ListItem(){
                Row({space:6}){
                  CustomListArtwork({item:m.media,client:this.client,language:this.language,widthValue:48,showTitle:false,repository:this.presentation})
                  Column({space:4}){
                    Text(m.media.title).fontSize(14).maxLines(2).width('100%').onClick(()=>{this.onOpen(m.media);})
                    Text((m.media.kind==='show'?'剧集':'电影')+' · '+(m.media.year||'')+' · #'+m.rank).fontSize(11)
                    if(m.rating!==undefined){Text('★ '+m.rating.toFixed(1)).fontSize(11)}
                  }.layoutWeight(1)
                  if(this.list()?.remote===false){
                    if(this.memberSort==='rank'&&this.kind==='all'&&!this.descending){
                      Button('↑').fontSize(12).height(30).enabled(!this.view.busy).onClick(()=>{this.edit({kind:'move',id:this.selected,mediaId:m.media.id,direction:-1});})
                      Button('↓').fontSize(12).height(30).enabled(!this.view.busy).onClick(()=>{this.edit({kind:'move',id:this.selected,mediaId:m.media.id,direction:1});})
                    }
                    Button('移除').fontSize(11).height(30).enabled(!this.view.busy).onClick(()=>{this.confirm({kind:'remove',id:this.selected,mediaId:m.media.id},'移除本机列表成员？');})
                  }
                }.width('100%')
              }
            },(m:ListMember)=>this.members.keyFor(m.media.id))
          }.layoutWeight(1).width('100%')
        }
      }.width('100%').height('100%').padding(12)
    }
  }
}
