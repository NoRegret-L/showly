import { RatingTarget,RatingState } from '../model/RatingRules';
@Component
export struct RatingEditor{
  @Prop target:RatingTarget={kind:'show',id:0,label:''};
  read:()=>Promise<RatingState>=async()=>({known:false,value:0,pending:false,fresh:false});
  save:(expected:RatingState,value:number)=>Promise<RatingState>=async()=>({known:false,value:0,pending:false,fresh:false});
  onClose:()=>void=()=>{};
  @State selected:number=5;
  @State value:RatingState={known:false,value:0,pending:false,fresh:false};
  @State busy:boolean=true;
  @State status:string='';
  private active:boolean=false;
  aboutToAppear():void{this.active=true;this.load();}
  aboutToDisappear():void{this.active=false;}
  private async load():Promise<void>{
    this.busy=true;this.status='正在核对评分…';
    try{const state=await this.read();if(!this.active){return;}this.value=state;this.selected=state.value||5;
      this.status=state.pending?'上次写入结果未确认；仅允许回读核对。':!state.known?'评分状态未知':!state.fresh?'离线快照 · 不允许云端写入':'';
    }catch(error){if(this.active){this.status='评分读取失败，请重试';}}
    finally{if(this.active){this.busy=false;}}
  }
  private async submit(value:number):Promise<void>{
    if(this.busy||!this.value.known||!this.value.fresh||this.value.pending){return;}
    this.busy=true;this.status='正在保存并核对…';
    try{const state=await this.save(this.value,value);if(!this.active){return;}this.value=state;
      if(state.pending){this.status='写入结果尚未确认；禁止重发，请回读核对。';}else{this.onClose();}
    }catch(error){if(this.active){this.value={known:false,value:this.value.value,pending:true,fresh:false};this.status='操作未确认；请回读核对，不会自动重发。';}}
    finally{if(this.active){this.busy=false;}}
  }
  build(){
    Column({space:14}){
      Text(this.target.label).fontSize(18).maxLines(2).fontWeight(FontWeight.Medium)
      Text(this.selected+' / 10').fontSize(36).fontWeight(FontWeight.Bold)
      Row({space:1}){ForEach([1,2,3,4,5,6,7,8,9,10],(n:number)=>{
        Text(n<=this.selected?'★':'☆').fontSize(23).layoutWeight(1).textAlign(TextAlign.Center).fontColor($r('app.color.showly_accent')).enabled(!this.busy).accessibilityText(n+' 分').onClick(()=>{if(!this.busy){this.selected=n;}})
      },(n:number)=>n.toString())}.width('100%')
      if(this.status){Text(this.status).fontSize(13)}
      if(this.busy){LoadingProgress().width(25).height(25)}
      Row({space:8}){
        if(this.value.known&&this.value.value>0){Button('移除评分').layoutWeight(1).enabled(!this.busy&&this.value.fresh&&!this.value.pending).onClick(()=>{this.submit(0);})}
        Button('保存评分').layoutWeight(1).enabled(!this.busy&&this.value.known&&this.value.fresh&&!this.value.pending).onClick(()=>{this.submit(this.selected);})
      }.width('100%')
      if(!this.busy&&(!this.value.fresh||this.value.pending)){Button('只读重新核对').onClick(()=>{this.load();})}
      Button('关闭').enabled(!this.busy).onClick(()=>{this.onClose();})
    }.width('100%').padding(20)
  }
}
