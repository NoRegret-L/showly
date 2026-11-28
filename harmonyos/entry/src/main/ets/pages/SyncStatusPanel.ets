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
      Text('系统定时唤醒（下次打开应用时核对）').fontSize(14).width('100%')
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
      Text('后台仅记录唤醒，不登录或上传；前台按原有授权核对。').fontSize(12).width('100%')
    }.width('100%')
  }
}
