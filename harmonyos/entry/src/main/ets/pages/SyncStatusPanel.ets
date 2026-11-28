import { readSyncRun } from '../data/SyncRunJournal';
import { SyncRunRecord, runPhaseLabel } from '../model/SyncRunState';
import { backgroundReadInfo } from '../data/BackgroundObservation';
import { common } from '@kit.AbilityKit';
import { scheduledHours, setScheduledHours, lastScheduleWake, SYNC_PERIODS } from '../data/SyncSchedule';
import { QueueEntry } from '../data/EpisodeStore';
@Component
export struct SyncStatusPanel {
  @Prop busy: boolean = false;
  @Prop details: boolean = false;
  @Prop cloudBusy: boolean = false;
  @Prop cloudText: string = '';
  @Prop bound: boolean = false;
  @Prop rows: QueueEntry[] = [];
  @Prop lastUpload: number = 0;
  @Prop lastVerified: number = 0;
  @Prop uuid: string = '';
  @Prop clientId: string = '';
  onBackgroundRead: (enabled:boolean)=>Promise<boolean> = async (enabled:boolean)=>false;
  @State backgroundEnabled: boolean = false;
  @State backgroundExpiry: number = 0;
  @State backgroundVerified: number = 0;
  @State runStatus?: SyncRunRecord;
  @State hours: number = 0;
  @State wake: number = 0;
  @State scheduleStatus: string = '';
  @State setting: boolean = false;
  aboutToAppear(): void { this.refreshSchedule(); }
  private async refreshSchedule(): Promise<void> {
    try {
      this.hours = await scheduledHours();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.wake = lastScheduleWake(context.filesDir);
      this.runStatus=readSyncRun(context.filesDir,this.uuid,this.clientId);
      const info=backgroundReadInfo(context.filesDir,this.uuid,this.clientId);
      this.backgroundEnabled=info.enabled;this.backgroundExpiry=info.expiresAt;this.backgroundVerified=info.verifiedAt;
    } catch (error) { this.scheduleStatus = '系统调度状态不可用'; }
  }
  private async updateSchedule(hours: number): Promise<void> {
    if (this.setting) { return; }
    this.setting = true;
    try {
      await setScheduledHours(hours);
      await this.refreshSchedule();
      this.scheduleStatus = '系统调度设置已更新';
    } catch (error) { this.scheduleStatus = '系统未接受设置，请重试'; await this.refreshSchedule(); }
    finally { this.setting = false; }
  }
  private async toggleBackground(): Promise<void> {
    if (this.setting) { return; }
    this.setting=true;
    try {
      const ok=await this.onBackgroundRead(!this.backgroundEnabled);
      await this.refreshSchedule();
      this.scheduleStatus=ok ? '后台只读授权已更新' : '未改变授权：请确认账户或等待当前核对完成';
    } finally { this.setting=false; }
  }
  private periodLabel(hours:number):string { return hours===0?'关闭':hours<24?hours+'小时':(hours/24)+'天'; }
  build() {
    Column({space: 8}) {
      Button(this.hours===0?'定时同步时间':'定时同步：'+this.periodLabel(this.hours))
        .fontSize(14).enabled(!this.setting&&!this.busy&&!this.cloudBusy)
        .onClick(()=>{
          const choices:SheetInfo[]=SYNC_PERIODS.map((hours:number):SheetInfo=>({
            title:(hours===this.hours?'✓ ':'')+this.periodLabel(hours),action:()=>{this.updateSchedule(hours);}
          }));
          this.getUIContext().showActionSheet({title:'定时同步时间',message:'实际执行由系统决定；后台只读需单独授权。',autoCancel:true,sheets:choices});
        })
      if(this.bound&&this.runStatus&&this.runStatus.uuid===this.uuid&&this.runStatus.clientId===this.clientId){
        Text(runPhaseLabel(this.runStatus.phase)).fontSize(13).width('100%')
        if(this.runStatus.lastImportAt>0){Text('最近核对成功的导入：'+new Date(this.runStatus.lastImportAt).toLocaleString()).fontSize(12).width('100%')}
      }
      if(this.lastVerified>0){Text('上次云端核对：'+new Date(this.lastVerified).toLocaleString()).fontSize(12).textAlign(TextAlign.Center)}
      if(this.scheduleStatus){Text(this.scheduleStatus).fontSize(12).textAlign(TextAlign.Center)}
      if(this.details){
      Text(this.cloudText).fontSize(12).width('100%')
      if (this.bound) {
        Row({space:12}){
          Text('待发送 '+this.rows.filter((row:QueueEntry)=>!row.blocked).length).fontSize(14).layoutWeight(1)
          Text('待核对/受保护 '+this.rows.filter((row:QueueEntry)=>row.blocked).length).fontSize(14).layoutWeight(1)
        }.width('100%')
        if(this.lastUpload>0){Text('最近完整分集上传确认：'+new Date(this.lastUpload).toLocaleString()).fontSize(12).width('100%')}
      }
      if (this.wake > 0) { Text('最近系统唤醒：' + new Date(this.wake).toLocaleString()).fontSize(12).width('100%') }
      if (this.scheduleStatus) { Text(this.scheduleStatus).fontSize(12).width('100%') }
      if (this.bound) {
        Button(this.backgroundEnabled ? '关闭后台只读同步' : '授权后台只读同步').width('100%')
          .enabled(!this.setting && !this.busy && !this.cloudBusy)
          .onClick(()=>{this.toggleBackground();})
        Text('开启后使用安全存储中的有效访问令牌，在系统允许时读取本账户个人库。不会后台刷新令牌、上传或删除记录。').fontSize(12).width('100%')
        if (this.backgroundEnabled && this.backgroundExpiry <= Date.now()) {
          Text('后台访问令牌已过期；前台登录并核对账户后恢复。').fontSize(12).width('100%')
        }
        if (this.backgroundVerified > 0) {
          Text('最近后台读取确认：' + new Date(this.backgroundVerified).toLocaleString()).fontSize(12).width('100%')
        }
      }
      Text('未授权后台读取时，仅记录系统唤醒，前台按原有授权核对。').fontSize(12).width('100%')
      }
    }.width('100%')
  }
}
