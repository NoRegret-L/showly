@Component
export struct ManualSyncControls {
  @Prop initialImport:boolean=true;
  @Prop initialExport:boolean=true;
  @Prop signedIn:boolean=false;
  @Prop available:boolean=false;
  @State importEnabled:boolean=true;
  @State exportEnabled:boolean=true;
  onDirection:(importEnabled:boolean,exportEnabled:boolean)=>void=()=>{};
  onStart:()=>void=()=>{};
  aboutToAppear():void{this.importEnabled=this.initialImport;this.exportEnabled=this.initialExport;}
  private selectDirection(importEnabled:boolean,exportEnabled:boolean):void{
    this.importEnabled=importEnabled;this.exportEnabled=exportEnabled;this.onDirection(importEnabled,exportEnabled);
  }
  build(){
    Column({space:12}){
      Row({space:8}){
        Checkbox({name:'sync-import',group:'sync-direction'}).select(this.importEnabled).onChange((v:boolean)=>{this.selectDirection(v,this.exportEnabled);})
        Text('从 Trakt.tv 导入到 Showly').fontSize(14).onClick(()=>{this.selectDirection(!this.importEnabled,this.exportEnabled);})
      }.width('100%')
      Row({space:8}){
        Checkbox({name:'sync-export',group:'sync-direction'}).select(this.exportEnabled).onChange((v:boolean)=>{this.selectDirection(this.importEnabled,v);})
        Text('从 Showly 导出到 Trakt.tv').fontSize(14).onClick(()=>{this.selectDirection(this.importEnabled,!this.exportEnabled);})
      }.width('100%')
      Button(this.signedIn?'开始同步':'Trakt.tv 授权').width('100%')
        .enabled(this.available&&(!this.signedIn||this.importEnabled||this.exportEnabled))
        .onClick(()=>{this.onStart();})
    }.width('100%')
  }
}
