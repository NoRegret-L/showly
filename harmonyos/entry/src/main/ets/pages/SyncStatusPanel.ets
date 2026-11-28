import { backgroundReadInfo } from '../data/BackgroundObservation';
import { common } from '@kit.AbilityKit';
import { scheduledHours, setScheduledHours, lastScheduleWake, SYNC_PERIODS } from '../data/SyncSchedule';
import { QueueEntry } from '../data/EpisodeStore';
@Component
export struct SyncStatusPanel {
  @Prop busy: boolean = false;
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
  build() {
    Column({space: 8}) {
      if (this.busy || this.cloudBusy) {
        Row({space: 8}) {
          LoadingProgress().width(22).height(22)
          Text(this.cloudBusy ? '正在核对云端版本' : '正在处理同步任务').fontSize(13).layoutWeight(1)
        }.width('100%')
      }
      Text(this.cloudText).fontSize(12).width('100%')
      if (this.bound) {
        Row({space: 12}) {
          Text('待发送 ' + this.rows.filter((row: QueueEntry)=>!row.blocked).length).fontSize(14).layoutWeight(1)
          Text('待核对/受保护 ' + this.rows.filter((row: QueueEntry)=>row.blocked).length).fontSize(14).layoutWeight(1)
        }.width('100%')
        if (this.lastUpload > 0) {
          Text('最近完整分集上传确认：' + new Date(this.lastUpload).toLocaleString()).fontSize(12).width('100%')
        }
      }
      if (this.lastVerified > 0) {
        Text('上次成功核对云端：' + new Date(this.lastVerified).toLocaleString()).fontSize(12).width('100%')
      }
      Text('系统定时同步').fontSize(14).width('100%')
      Text(this.hours === 0 ? '关闭' : '每 ' + this.hours + ' 小时，实际由系统决定').fontSize(12).width('100%')
      Row({space: 4}) {
        ForEach(SYNC_PERIODS.slice(0,4),(h: number)=>{
          Button(h === 0 ? '关闭' : h + '小时').fontSize(12).layoutWeight(1).enabled(!this.setting && h !== this.hours)
            .onClick(()=>{this.updateSchedule(h);})
        },(h: number)=>h.toString())
      }.width('100%')
      Row({space: 4}) {
        ForEach(SYNC_PERIODS.slice(4),(h: number)=>{
          Button(h/24 + '天').fontSize(12).layoutWeight(1).enabled(!this.setting && h !== this.hours)
            .onClick(()=>{this.updateSchedule(h);})
        },(h: number)=>h.toString())
      }.width('100%')
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
    }.width('100%')
  }
}
