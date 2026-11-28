import { common } from '@kit.AbilityKit';
import { CommentTarget,CommentRow,CommentIndex,hasSpoiler,ownComment,canDeleteComment,validComment } from '../model/CommentRules';
import { openComments,CommentsRepository } from '../data/CommentsRepository';
import { TraktSession } from '../data/TraktAuth';
import { ReadCancel } from '../model/ReadFlight';
import { LazyRows } from '../model/LazyRows';
@Component
export struct CommentsPage{
 @Prop target:CommentTarget={kind:'show',id:0,label:''};
 @Prop client:string='';
 @Prop scope:string='';
 session:()=>TraktSession|undefined=()=>undefined;
 current:()=>boolean=()=>false;
 onClose:()=>void=()=>{};
 @State busy:boolean=false;
 @State status:string='';
 @State username:string='';
 @State uuid:string='';
 @State pending:boolean=false;
 @State nextPage:number=1;
 @State composing:boolean=false;
 @State draft:string='';
 @State spoiler:boolean=false;
 @State replyTo:number=0;
 @State deleting:number=0;
 private index:CommentIndex=new CommentIndex();
 private source:LazyRows<CommentRow>=new LazyRows<CommentRow>();
 private replyNext:Map<number,number>=new Map<number,number>();
 private signal:ReadCancel=new ReadCancel();
 private repo?:CommentsRepository;
 private active:boolean=false;
 aboutToAppear():void{this.active=true;this.initialize();}
 aboutToDisappear():void{this.active=false;this.signal.cancel();this.index.clear();this.draft='';}
 private allowed():boolean{return this.active&&this.current()&&!this.signal.cancelled();}
 private commentRowKey(row:CommentRow):string{return JSON.stringify([row,this.index.isRevealed(row),this.uuid,this.username,this.pending,this.replyNext.get(row.id)??-1,this.deleting]);}
 private publish():void{const rows=this.index.project(this.uuid,this.username);this.source.replace(rows,rows.map((r:CommentRow)=>r.id.toString()),rows.map((r:CommentRow)=>this.commentRowKey(r)));}
 private async initialize():Promise<void>{
  try{this.repo=await openComments(this.getUIContext().getHostContext() as common.UIAbilityContext);if(!this.allowed()){return;}
   const session=this.session();if(session&&this.scope.startsWith('account:')){try{const a=await this.repo.account(this.scope,session,()=>this.allowed());if(this.allowed()){this.uuid=a.uuid;this.username=a.username;this.pending=await this.repo.pending(this.scope);}}catch(error){this.uuid='';this.username='';}}
   if(this.allowed()){await this.load(0,1,true);}
  }catch(error){if(this.allowed()){this.status='评论读取失败';}}
 }
 private async load(parent:number,page:number,reset:boolean=false):Promise<void>{
  if(!this.repo||!this.allowed()||this.busy||page<1){return;}this.busy=true;this.status='';
  try{const data=await this.repo.page(this.target,parent,page,this.client,this.signal);if(!this.allowed()){return;}
   if(reset){this.index.clear();this.replyNext.clear();}
   this.index.append(data.rows,parent);if(parent){this.replyNext.set(parent,data.next);}else{this.nextPage=data.next;}
   this.publish();this.status=data.cached?'离线缓存 · 可能不是最新数据':'';
  }catch(error){if(this.allowed()){this.status='读取失败，保留已加载评论';}}
  finally{if(this.allowed()){this.busy=false;}}
 }
 private compose(parent:number):void{if(this.busy||!this.uuid||this.pending){return;}this.replyTo=parent;this.draft='';this.spoiler=false;this.composing=true;}
 private async submit():Promise<void>{
  const session=this.session();if(!this.repo||!session||!this.allowed()||!this.uuid||this.pending||this.busy||!validComment(this.draft)){return;}
  this.busy=true;
  try{await this.repo.post(this.scope,this.target,this.replyTo,this.draft,this.spoiler,session,()=>this.allowed());if(!this.allowed()){return;}this.composing=false;this.draft='';this.busy=false;await this.load(0,1,true);}
  catch(error){if(this.allowed()){this.pending=true;this.status='发表未确认或操作被阻止。请只读刷新，不会重发。';this.publish();}}
  finally{if(this.allowed()){this.busy=false;}}
 }
 private async erase(row:CommentRow):Promise<void>{
  const session=this.session();if(!this.repo||!session||!this.allowed()||this.pending||this.busy||this.deleting!==row.id||!canDeleteComment(row,this.uuid,this.username,Date.now())){return;}
  this.busy=true;
  try{await this.repo.remove(this.scope,this.target,row,session,()=>this.allowed());if(this.allowed()){this.deleting=0;this.index.remove(row);this.publish();this.busy=false;await this.load(0,1,true);}}
  catch(error){if(this.allowed()){this.pending=true;this.status='删除未确认或评论发生变化，请只读刷新';this.publish();}}
  finally{if(this.allowed()){this.busy=false;}}
 }
 @Builder commentCard(row:CommentRow){
  Column({space:6}){
   Row({space:8}){
    if(row.avatar){Image(row.avatar).width(36).height(36).borderRadius(18).syncLoad(false)}else{Text(row.username.substring(0,1)).width(36).height(36).borderRadius(18).textAlign(TextAlign.Center).backgroundColor($r('app.color.showly_placeholder'))}
    Column({space:3}){Text(row.username+(ownComment(row,this.uuid,this.username)?' · 我':'')).fontSize(14).fontWeight(FontWeight.Medium);Text(row.updated?new Date(row.updated).toLocaleString():row.created?new Date(row.created).toLocaleString():'日期未知').fontSize(11)}.layoutWeight(1).alignItems(HorizontalAlign.Start)
    if(row.rating){Text(row.rating+' / 10').fontSize(12)}
   }.width('100%')
   if(hasSpoiler(row)&&!this.index.isRevealed(row)){Button('包含剧透，点击查看').fontSize(13).onClick(()=>{this.index.reveal(row);this.source.patchRow(row.id.toString(),row,this.commentRowKey(row));})}
   else{Text(row.text).fontSize(14).width('100%')}
   Row({space:6}){
    if(!row.parent&&row.replies>0&&(!this.index.loaded(row.id)||(this.replyNext.get(row.id)??0)>0)){Button(this.index.loaded(row.id)?'更多回复':'查看 '+row.replies+' 条回复').fontSize(11).enabled(!this.busy).onClick(()=>{this.load(row.id,this.replyNext.get(row.id)??1);})}
    if(this.uuid&&!this.pending){Button('回复').fontSize(11).enabled(!this.busy).onClick(()=>{this.compose(row.parent||row.id);})}
    if(!this.pending&&canDeleteComment(row,this.uuid,this.username,Date.now())){Button(this.deleting===row.id?'确认删除':'删除').fontSize(11).enabled(!this.busy).onClick(()=>{if(this.deleting===row.id){this.erase(row);}else{this.deleting=row.id;this.publish();}})}
    if(this.deleting===row.id){Button('取消').fontSize(11).onClick(()=>{this.deleting=0;this.publish();})}
   }.width('100%')
  }.width('100%').padding({left:row.parent?24:8,right:8,top:8,bottom:8}).backgroundColor($r('app.color.showly_surface')).borderRadius(8)
 }
 build(){
  Column({space:8}){
   Row(){Button('返回').fontSize(12).onClick(()=>this.onClose());Text('评论 · '+this.target.label).fontSize(18).maxLines(1).layoutWeight(1);Button('刷新').fontSize(12).enabled(!this.busy).onClick(()=>{this.load(0,1,true);})}.width('100%')
   if(this.status){Text(this.status).fontSize(12).width('100%')}
   if(this.pending){Text('存在未确认写入凭证；禁止继续发表或删除。请在 Trakt 核对。').fontSize(12)}
   if(this.uuid&&!this.pending){Button('发表评论').fontSize(12).enabled(!this.busy).onClick(()=>this.compose(0))}
   if(this.composing){Column({space:5}){Text(this.replyTo?'回复评论':'发表评论').fontSize(15);TextArea({placeholder:'至少5个有效词',text:this.draft}).height(92).onChange((v:string)=>{this.draft=v;});Row(){Text('包含剧透').layoutWeight(1);Toggle({type:ToggleType.Switch,isOn:this.spoiler}).onChange((v:boolean)=>{this.spoiler=v;})}.width('100%');Row(){Button('取消').enabled(!this.busy).onClick(()=>{this.composing=false;this.draft='';});Button('确认发表').enabled(!this.busy&&!this.pending&&validComment(this.draft)).onClick(()=>{this.submit();})}}.width('100%')}
   if(this.busy){LoadingProgress().width(22).height(22)}
   List({space:6}){LazyForEach(this.source,(row:CommentRow)=>{ListItem(){this.commentCard(row)}},(row:CommentRow)=>this.source.keyFor(row.id.toString()))
    if(this.nextPage>1){ListItem(){Button('加载更多评论').enabled(!this.busy).onClick(()=>{this.load(0,this.nextPage);})}}
   }.layoutWeight(1).width('100%')
  }.width('100%').height('100%').padding(12)
 }
}
