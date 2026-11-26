import { common } from '@kit.AbilityKit';
import { Media, mediaLabel, setWatched } from '../model/Media';
import { LibraryStore } from '../data/LibraryStore';
import { searchTrakt } from '../data/TraktSearch';
import { TRAKT_APPS_URL, TRAKT_REDIRECT_URI } from '../config/TraktConfig';
import { ClientSettings, validateClientId } from '../data/ClientSettings';
import { pasteboard } from '@kit.BasicServicesKit';
import { traktAuth } from '../data/TraktAuth';
import { CloudLibrary, ShowProgress, readCloudLibrary, mergeNewTitles } from '../data/TraktLibrary';
import { MediaDetail, canReadDetails, readDetails, cachePoster, clearDetailMemory } from '../data/TraktDetails';

@Entry
@Component
struct Index {
  @State title: string = '';
  @State tab: string = 'library';
  @State selectedMedia?: Media = undefined;
  @State detail?: MediaDetail = undefined;
  @State detailBusy: boolean = false;
  @State detailStatus: string = '';
  @State posterUri: string = '';
  private detailRevision: number = 0;
  @State clientId: string = '';
  @State draftId: string = '';
  @State configuring: boolean = false;
  @State setupBusy: boolean = false;
  @State settingsReady: boolean = false;
  @State setupStatus: string = '';
  @State cloud?: CloudLibrary = undefined;
  @State cloudBusy: boolean = false;
  @State cloudStatus: string = '';
  private settings?: ClientSettings;
  @StorageLink('traktAuthStatus') authStatus: string = '尚未登录 Trakt';
  @StorageLink('traktAuthBusy') authBusy: boolean = false;
  @StorageLink('traktSignedIn') signedIn: boolean = false;
  @State items: Media[] = [];
  @State results: Media[] = [];
  @State ready: boolean = false;
  @State saving: boolean = false;
  @State searching: boolean = false;
  @State libraryStatus: string = '';
  @State searchStatus: string = '';
  private store?: LibraryStore;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.settings = new ClientSettings(context);
      this.clientId = this.settings.load();
      this.draftId = this.clientId;
      this.configuring = !this.clientId;
      if (!this.clientId) { this.tab = 'account'; }
      this.settingsReady = true;
      if (this.clientId) {
        traktAuth.restore(this.clientId);
      }
    } catch (error) {
      this.setupStatus = '无法读取 Trakt 配置，请重启应用。';
    }
    try {
      this.store = new LibraryStore(context);
      this.items = this.store.load();
      this.ready = true;
    } catch (error) {
      this.libraryStatus = '本地记录读取失败，已停止写入以保护原数据。';
    }
  }

  onPageShow(): void {
    if (this.clientId && !this.setupBusy && !this.cloudBusy) {
      traktAuth.restore(this.clientId);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async openGuide(): Promise<void> {
    try {
      await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: TRAKT_APPS_URL });
    } catch (error) {
      this.setupStatus = '请在浏览器访问 ' + TRAKT_APPS_URL;
    }
  }

  private async copyValue(value: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      this.setupStatus = '已复制';
    } catch (error) {
      this.setupStatus = '复制失败，请手动输入上方内容。';
    }
  }

  private async applyClient(login: boolean): Promise<void> {
    if (!this.settings || this.setupBusy || this.authBusy || this.searching || this.cloudBusy) {
      return;
    }
    const next = this.draftId.trim();
    if (!/^[A-Za-z0-9_-]+$/.test(next)) {
      this.setupStatus = '请输入 Client ID，不要输入 Client Secret。';
      return;
    }
    this.setupBusy = true;
    this.setupStatus = '正在验证 Client ID…';
    try {
      const status = await validateClientId(next);
      if (status !== 200) {
        this.setupStatus = '验证未通过（HTTP ' + status + '），原配置保留。';
        return;
      }
      if (next !== this.clientId) {
        if (!traktAuth.disconnect()) {
          this.setupStatus = '无法清除旧授权，未切换 Client ID。';
          return;
        }
        await this.settings.save(next);
        this.clientId = next;
        clearDetailMemory();
        this.closeDetail();
        this.results = [];
        this.clearCloud();
      }
      this.configuring = false;
      this.setupStatus = 'Client ID 已验证并保存到本机';
      if (login) {
        await traktAuth.begin(this.context(), this.clientId);
      }
    } catch (error) {
      this.setupStatus = '验证或保存失败，请检查网络和设备存储。';
    } finally {
      this.setupBusy = false;
    }
  }

  private async clearClient(): Promise<void> {
    if (!this.settings || this.setupBusy || this.authBusy || this.searching || this.cloudBusy) {
      return;
    }
    this.setupBusy = true;
    try {
      if (!traktAuth.disconnect()) {
        this.setupStatus = '无法清除旧授权，请重试。';
        return;
      }
      await this.settings.save('');
      this.clientId = '';
      clearDetailMemory();
      this.closeDetail();
      this.clearCloud();
      this.draftId = '';
      this.results = [];
      this.configuring = true;
      this.setupStatus = '已清除本机 Trakt 配置，影视清单保留。';
    } catch (error) {
      this.setupStatus = '清除配置失败，请重试。';
    } finally {
      this.setupBusy = false;
    }
  }

  private clearCloud(): void {
    this.cloud = undefined;
    this.cloudStatus = '';
  }

  private async loadCloud(): Promise<void> {
    if (this.cloudBusy || this.setupBusy || this.authBusy || !this.clientId) {
      return;
    }
    this.cloudBusy = true;
    this.clearCloud();
    this.cloudStatus = '正在读取 Trakt 云端清单，请勿切换账户…';
    try {
      await traktAuth.restore(this.clientId, true);
      const session = traktAuth.session(this.clientId);
      if (!session) {
        this.cloudStatus = '请先完成 Trakt 登录。';
        return;
      }
      const snapshot = await readCloudLibrary(session);
      if (traktAuth.isCurrent(this.clientId, snapshot.generation)) {
        this.cloud = snapshot;
        this.cloudStatus = '云端读取完成；尚未修改本机或云端记录。';
      }
    } catch (error) {
      this.clearCloud();
      this.cloudStatus = '读取失败或数据在读取中变化。请检查网络、授权及 API 限额后重试；原记录未改动。';
    } finally {
      this.cloudBusy = false;
    }
  }

  private async importCloud(): Promise<void> {
    const snapshot = this.cloud;
    if (!snapshot || this.cloudBusy || this.saving || !this.ready || this.authBusy || this.setupBusy) {
      return;
    }
    if (!traktAuth.isCurrent(this.clientId, snapshot.generation)) {
      this.clearCloud();
      this.cloudStatus = '授权已变化，请重新读取云端清单。';
      return;
    }
    const next = mergeNewTitles(this.items, snapshot);
    const added = next.length - this.items.length;
    if (added === 0) {
      this.cloudStatus = '无新增影视；已有本机记录均保留。';
      return;
    }
    this.cloudBusy = true;
    try {
      const saved = await this.save(next);
      this.cloudStatus = saved ? '已导入 ' + added + ' 部新影视，已有本机记录未覆盖。' :
        '导入保存失败，请重启应用检查本机记录。';
    } finally {
      this.cloudBusy = false;
    }
  }

  private async save(next: Media[]): Promise<boolean> {
    if (!this.ready || this.saving || !this.store) {
      return false;
    }
    this.saving = true;
    try {
      await this.store.save(next);
      this.items = next;
      this.libraryStatus = '已保存到本机';
      return true;
    } catch (error) {
      this.libraryStatus = '保存失败，已停止写入，请重启应用检查记录。';
      this.ready = false;
      return false;
    } finally {
      this.saving = false;
    }
  }

  private add(item: Media): void {
    if (!this.ready || this.saving || this.cloudBusy || this.items.some((value: Media) => value.id === item.id)) {
      return;
    }
    this.save([...this.items, item]);
  }

  private async search(): Promise<void> {
    if (this.searching || this.title.trim().length === 0 || this.clientId.length === 0) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.searchStatus = '搜索中…';
    try {
      this.results = await searchTrakt(this.title.trim(), this.clientId);
      this.searchStatus = this.results.length === 0 ? '没有搜索结果' : '搜索完成';
    } catch (error) {
      this.searchStatus = '搜索失败：请检查网络、Client ID 或 Trakt API 权限与限额。';
    } finally {
      this.searching = false;
    }
  }

  private closeDetail(): void {
    this.detailRevision++;
    this.selectedMedia = undefined;
    this.detail = undefined;
    this.posterUri = '';
    this.detailStatus = '';
  }

  onBackPress(): boolean {
    if (this.selectedMedia) {
      this.closeDetail();
      return true;
    }
    return false;
  }

  private async openDetail(item: Media, reload: boolean = false): Promise<void> {
    if (this.detailBusy || this.setupBusy || !this.clientId || !canReadDetails(item)) {
      return;
    }
    const revision = ++this.detailRevision;
    const clientId = this.clientId;
    this.selectedMedia = item;
    this.detail = undefined;
    this.posterUri = '';
    this.detailBusy = true;
    this.detailStatus = '正在读取影视详情…';
    try {
      const data = await readDetails(item, clientId, reload);
      if (revision !== this.detailRevision || this.clientId !== clientId) {
        return;
      }
      this.detail = data;
      this.detailStatus = '';
      try {
        const poster = await cachePoster(this.context().cacheDir, item, data.posterUrls);
        if (revision === this.detailRevision && this.clientId === clientId) {
          this.posterUri = poster.uri;
          this.detailStatus = poster.status;
        }
      } catch (error) {
        if (revision === this.detailRevision) {
          this.detailStatus = '海报缓存失败，其他详情仍可查看。';
        }
      }
    } catch (error) {
      if (revision === this.detailRevision) {
        this.detailStatus = '详情读取失败，请检查网络或 Trakt API 权限后重试。';
      }
    } finally {
      this.detailBusy = false;
    }
  }

  @Builder
  navigationTab(name: string, value: string) {
    Button(name)
      .layoutWeight(1)
      .backgroundColor(this.tab === value ? '#2267D9' : '#F0F2F5')
      .fontColor(this.tab === value ? '#FFFFFF' : '#263446')
      .fontSize(13)
      .onClick(() => {
        this.closeDetail();
        this.tab = value;
      })
  }

  @Builder
  detailPage(item: Media) {
    Column({ space: 12 }) {
      Button('返回').onClick(() => { this.closeDetail(); })
      Text(this.detail ? this.detail.title : item.title)
        .fontSize(26).fontWeight(FontWeight.Bold).width('100%')
      if (this.posterUri) {
        Image(this.posterUri)
          .width(180).height(270).objectFit(ImageFit.Contain).borderRadius(10)
          .onError(() => {
            this.posterUri = '';
            this.detailStatus = '海报已缓存，但鸿蒙 Image 组件解码或读取失败';
          })
      } else {
        Column() {
          Text(this.detailBusy ? '正在加载海报…' : '海报未显示').fontColor('#657185')
        }.width(180).height(270).justifyContent(FlexAlign.Center)
          .backgroundColor('#E8EDF4').borderRadius(10)
      }
      if (this.detail) {
        Text((this.detail.year > 0 ? this.detail.year + ' · ' : '') +
          (item.kind === 'movie' ? '电影' : '剧集') +
          (this.detail.runtime > 0 ? ' · ' + this.detail.runtime + ' 分钟' : '')).fontSize(15)
        if (this.detail.rating > 0) {
          Text('Trakt 评分 ' + this.detail.rating.toFixed(1) + ' / 10').fontSize(16)
        }
        if (this.detail.genres) {
          Text(this.detail.genres).fontSize(14)
        }
        if (this.detail.status) {
          Text('状态：' + this.detail.status).fontSize(14)
        }
        if (item.kind === 'show' && this.detail.airedEpisodes > 0) {
          Text('已播 ' + this.detail.airedEpisodes + ' 集').fontSize(14)
        }
        Text('剧情简介').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
        Text(this.detail.overview || '暂无简介').fontSize(15).width('100%')
      }
      Text(this.detailStatus).fontSize(13).width('100%')
      if (this.detailStatus) {
        Button('复制海报诊断信息').fontSize(13)
          .onClick(() => { this.copyValue(this.detailStatus); })
      }
      Button('刷新详情').enabled(!this.detailBusy && !this.setupBusy)
        .onClick(() => { this.openDetail(item, true); })
      Button(this.items.some((value: Media) => value.id === item.id) ? '已在本地清单' : '加入本地待看')
        .enabled(this.ready && !this.saving && !this.cloudBusy &&
          !this.items.some((value: Media) => value.id === item.id))
        .onClick(() => { this.add(item); })
    }.width('100%')
  }

  @Builder
  libraryRow(item: Media) {
    Row({ space: 8 }) {
      Text(mediaLabel(item)).layoutWeight(1)
        .onClick(() => { this.openDetail(item); })
      if (this.clientId && canReadDetails(item)) {
        Button('详情').fontSize(12).enabled(!this.detailBusy && !this.setupBusy)
          .onClick(() => { this.openDetail(item); })
      }
      Button(item.watched ? '撤销' : '已看')
        .enabled(this.ready && !this.saving && !this.cloudBusy)
        .onClick(() => { this.save(setWatched(this.items, item.id, !item.watched)); })
    }.width('100%')
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('Showly').fontSize(27).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text('Preview 0.6.1').fontSize(12).fontColor('#687887')
      }.width('100%').padding(16)
      Divider()
      Scroll() {
        Column({ space: 14 }) {
          if (this.selectedMedia) {
            this.detailPage(this.selectedMedia)
          } else if (this.tab === 'library') {
            Text('我的清单').fontSize(23).fontWeight(FontWeight.Bold)
        Text(this.libraryStatus).fontSize(13)
        Text('待看 (' + this.items.filter((item: Media) => !item.watched).length + ')')
          .fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.items.filter((item: Media) => !item.watched), (item: Media) => {
          this.libraryRow(item)
        }, (item: Media) => item.id)
        Text('已看 (' + this.items.filter((item: Media) => item.watched).length + ')')
          .fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.items.filter((item: Media) => item.watched), (item: Media) => {
          this.libraryRow(item)
        }, (item: Media) => item.id)
          } else if (this.tab === 'search') {
        Text('影视搜索').fontSize(20).fontWeight(FontWeight.Medium)
        TextInput({ placeholder: '电影或剧集名称', text: this.title })
          .onChange((value: string) => { this.title = value; })
        Row({ space: 8 }) {
          Button('搜索 Trakt').layoutWeight(1)
            .enabled(!this.searching && !this.setupBusy && this.title.trim().length > 0 && this.clientId.length > 0)
            .onClick(() => { this.search(); })
          Button('手动添加').layoutWeight(1)
            .enabled(this.ready && !this.saving && !this.cloudBusy && this.title.trim().length > 0)
            .onClick(() => {
              const title: string = this.title.trim();
              const item: Media = { id: 'local:' + title.toLowerCase(), title: title,
                kind: 'manual', year: 0, watched: false };
              this.add(item);
            })
        }.width('100%')
        Text(this.searchStatus).fontSize(13)
        ForEach(this.results, (item: Media) => {
          Row({ space: 8 }) {
            Text(mediaLabel(item)).layoutWeight(1)
              .onClick(() => { this.openDetail(item); })
            Button('详情').fontSize(12).enabled(!this.detailBusy && !this.setupBusy)
              .onClick(() => { this.openDetail(item); })
            Button(this.items.some((value: Media) => value.id === item.id) ? '已添加' : '添加')
              .enabled(this.ready && !this.saving && !this.cloudBusy && !this.items.some((value: Media) => value.id === item.id))
              .onClick(() => { this.add(item); })
          }.width('100%')
        }, (item: Media) => item.id)
        Divider()

          } else if (this.tab === 'cloud') {
            Text('Trakt 云端').fontSize(23).fontWeight(FontWeight.Bold)
            Text('只读预览和本地新增导入，不会修改云端。').fontSize(13)
            if (!this.signedIn && !this.cloudBusy) {
              Text('请先在账户页面登录 Trakt。').fontSize(14)
              Button('前往账户').onClick(() => { this.tab = 'account'; })
            }
          if (this.signedIn || this.cloudBusy) {
            Button(this.cloudBusy ? '正在处理…' : '读取 Trakt 云端记录')
              .enabled(!this.cloudBusy && !this.setupBusy && !this.authBusy && !this.saving)
              .onClick(() => { this.loadCloud(); })
            Text(this.cloudStatus).fontSize(13)
            if (this.cloud && this.signedIn) {
              Text('云端待看：' + this.cloud.watchlist.length +
                ' · 已看电影：' + this.cloud.watchedMovies.length +
                ' · 看过的剧集：' + this.cloud.shows.length).fontSize(14)
              Button('仅导入新待看与已看电影到本机')
                .enabled(this.ready && !this.saving && !this.cloudBusy && !this.authBusy)
                .onClick(() => { this.importCloud(); })
              Text('已有本机记录不覆盖；剧集观看进度仅展示，不标记整部剧已看。').fontSize(12)
              Text('Trakt 剧集进度').fontSize(18).fontWeight(FontWeight.Medium)
              ForEach(this.cloud.shows, (show: ShowProgress) => {
                Row() {
                  Text(show.title).layoutWeight(1)
                    .onClick(() => { this.openDetail({ id: show.id, title: show.title, kind: 'show', year: 0, watched: false }); })
                  Text('已看 ' + show.watchedEpisodes + ' 集').fontSize(13)
                }.width('100%')
              }, (show: ShowProgress) => show.id)
              Button('清除云端预览').enabled(!this.cloudBusy).onClick(() => { this.clearCloud(); })
            }
          }
          } else {
            Text('账户与设置').fontSize(23).fontWeight(FontWeight.Bold)
            Text('非官方应用，使用 Trakt，但未获 Trakt 认可或认证。')
              .fontSize(12).fontColor('#687887')
        Text('Trakt 账户').fontSize(20).fontWeight(FontWeight.Medium)
        if (!this.clientId || this.configuring) {
          Column({ space: 10 }) {
            Text('首次配置 · 个人自用').fontSize(18).fontWeight(FontWeight.Medium)
            Text('1. 打开 Trakt 官方开发者页面，登录并绑定已验证的 GitHub 账号。')
              .fontSize(14)
            Button('打开官方申请页面').onClick(() => { this.openGuide(); })
            Text('2. 创建个人 Development 应用（Standard 免费），按页面要求填写信息。').fontSize(14)
            Text('应用名称：Showly HarmonyOS Personal').fontSize(14)
            Button('复制应用名称').onClick(() => { this.copyValue('Showly HarmonyOS Personal'); })
            Text('Redirect URI：' + TRAKT_REDIRECT_URI).fontSize(14)
            Button('复制回调地址').onClick(() => { this.copyValue(TRAKT_REDIRECT_URI); })
            Text('3. 复制 Client ID，返回这里粘贴。不要提供 Client Secret。').fontSize(14)
            TextInput({ placeholder: '粘贴你的 Client ID', text: this.draftId })
              .onChange((value: string) => { this.draftId = value; })
              .enabled(!this.setupBusy && !this.authBusy)
            Button('验证、保存并登录 Trakt')
              .enabled(this.settingsReady && !this.setupBusy && !this.authBusy && !this.searching && this.draftId.trim().length > 0)
              .onClick(() => { this.applyClient(true); })
            Button('仅验证并保存')
              .enabled(this.settingsReady && !this.setupBusy && !this.authBusy && !this.searching && this.draftId.trim().length > 0)
              .onClick(() => { this.applyClient(false); })
            if (this.clientId) {
              Button('取消编辑').enabled(!this.setupBusy && !this.cloudBusy)
                .onClick(() => { this.draftId = this.clientId; this.configuring = false; })
            }
            Text('也可暂不配置，继续使用下方离线清单。').fontSize(12)
          }.width('100%').padding(12).borderRadius(12).backgroundColor('#F1F4F8')
        }
        Text(this.setupStatus).fontSize(13)
        if (this.clientId && !this.configuring) {
          Text(this.authStatus).fontSize(14)
          if (!this.signedIn && !this.authBusy) {
            Button('登录 Trakt').enabled(!this.setupBusy && !this.cloudBusy).onClick(() => {
              this.clearCloud();
              traktAuth.begin(this.context(), this.clientId);
            })
            Button('重试恢复登录').enabled(!this.setupBusy && !this.cloudBusy).onClick(() => {
              traktAuth.restore(this.clientId, true);
            })
          }
          if (this.authBusy) {
            Button('取消当前操作').enabled(!this.setupBusy && !this.cloudBusy).onClick(() => { traktAuth.cancel(); })
          } else {
            if (this.signedIn) {
              Button('断开本机登录').enabled(!this.setupBusy && !this.cloudBusy).onClick(() => { if (traktAuth.disconnect()) { this.clearCloud(); } })
            }
            Button('修改 Client ID').enabled(!this.setupBusy && !this.searching && !this.cloudBusy).onClick(() => {
              this.draftId = this.clientId;
              this.configuring = true;
            })
            Button('清除 Client ID 与本机授权').enabled(!this.setupBusy && !this.searching && !this.cloudBusy)
              .onClick(() => { this.clearClient(); })
          }
          Text('登录使用 Trakt 官方浏览器页面。云端仅只读，不会上传或删除记录。').fontSize(12)

        }

          }
        }.width('100%').padding(16)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      Divider()
      Row({ space: 6 }) {
        this.navigationTab('清单', 'library')
        this.navigationTab('搜索', 'search')
        this.navigationTab('云端', 'cloud')
        this.navigationTab('账户', 'account')
      }.padding(12).width('100%')
    }.width('100%').height('100%')
  }
}
