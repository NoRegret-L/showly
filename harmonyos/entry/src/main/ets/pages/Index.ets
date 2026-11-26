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
import { DiscoverItem, readDiscover } from '../data/TraktDiscover';
import { EpisodeProgress, SeasonProgress, SeriesProgress, ChineseText, readSeriesProgress, readChinese } from '../data/TraktProgress';
import { AppearanceStore, applyAppearance } from '../data/AppearanceStore';
import { EpisodeStore, LocalSeriesState, LocalSeasonState, LocalEpisodeState, AutoConsent, QueueEntry, fetchEpisodeCatalog } from '../data/EpisodeStore';
import { SyncAccount, SyncPreview, SyncDifference, readSyncAccount, buildSyncPreview } from '../data/TraktSyncPreview';
import { uploadSelectedEpisode } from '../data/TraktSyncUpload';
import { removeSelectedPlay } from '../data/TraktSyncRemove';
import { uploadBatch } from '../data/TraktSyncBatch';

@Entry
@Component
struct Index {
  @State title: string = '';
  @State tab: string = 'progress';
  private episodeStore?: EpisodeStore;
  @State syncBusy: boolean = false;
  @State syncStatus: string = '';
  @State syncAccount?: SyncAccount = undefined;
  @State syncBound: boolean = false;
  @State syncPreview?: SyncPreview = undefined;
  @State syncFilter: string = 'addition';
  @State syncPage: number = 1;
  @State uploadSelectedId: number = 0;
  @State removeSelectedId: number = 0;
  @State batchIds: number[] = [];
  @State batchConfirm: boolean = false;
  @State importConfirm: boolean = false;
  @State autoConsent?: AutoConsent = undefined;
  @State queueRows: QueueEntry[] = [];
  @State showSyncLogs: boolean = false;
  @State queueConfirm: boolean = false;
  @State autoStatus: string = '';
  @State syncLogs: string[] = [];
  @State uploadStatus: string = '';
  @State episodeReady: boolean = false;
  @State episodeInitStatus: string = '';
  @State localSeries?: LocalSeriesState = undefined;
  @State localSeason: number = -1;
  @State localBusy: boolean = false;
  @State localStatus: string = '';
  @State localRecent: Media[] = [];
  @State confirmSeason: number = -1;
  @State confirmWatched: boolean = true;
  @State themeMode: string = 'system';
  @State themeStatus: string = '';
  @State themeBusy: boolean = false;
  private appearance?: AppearanceStore;
  @State refreshing: boolean = false;
  @State trackingPage: number = 1;
  @State trackingQuery: string = '';
  private translationCache: Map<string, ChineseText> = new Map<string, ChineseText>();
  @State collectionFilter: string = 'queue';
  @State collectionPage: number = 1;
  @State collectionGrid: boolean = true;
  @State collectionCards: DiscoverItem[] = [];
  @State collectionBusy: boolean = false;
  @State collectionStatus: string = '';
  private collectionRevision: number = 0;
  private readonly collectionPageSize: number = 12;
  @State progress?: SeriesProgress = undefined;
  @State progressBusy: boolean = false;
  @State progressStatus: string = '';
  @State seasonNumber: number = -1;
  @State chineseTitle: string = '';
  @State chineseOverview: string = '';
  @State translationBusy: boolean = false;
  @State translationStatus: string = '';
  @State discoverKind: string = 'movie';
  @State discoverMode: string = 'trending';
  @State discoverItems: DiscoverItem[] = [];
  @State discoverPage: number = 1;
  @State discoverPages: number = 0;
  @State discoverBusy: boolean = false;
  @State discoverStatus: string = '';
  private discoverRevision: number = 0;
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
      this.appearance = new AppearanceStore(context);
      this.themeMode = this.appearance.load();
      applyAppearance(context, this.themeMode);
    } catch (error) {
      this.themeStatus = '主题设置暂不可用';
    }
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
    this.initializeEpisodes(context);
  }

  onPageShow(): void {
    if (this.clientId && !this.setupBusy && !this.cloudBusy && !this.syncBusy) {
      if (this.episodeReady && this.autoActive()) { this.resumeQueued(); }
      else { traktAuth.restore(this.clientId); }
    }
  }

  private async initializeEpisodes(context: common.UIAbilityContext): Promise<void> {
    try {
      this.episodeStore = await EpisodeStore.open(context);
      this.localRecent = await this.episodeStore.recent();
      this.episodeReady = true;
      const consent = await this.episodeStore.autoConsent();
      if (consent && consent.clientId === this.clientId) { this.autoConsent = consent; }
      await this.reloadQueue();
      this.resumeQueued();
    } catch (error) {
      this.episodeInitStatus = '分集数据库打开失败，已停止分集写入；旧收藏不受影响。';
    }
  }

  private async loadLocalEpisodes(item: Media, refresh: boolean = false): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.syncBusy || item.kind !== 'show') { return; }
    const revision = this.detailRevision;
    const clientId = this.clientId;
    this.localBusy = true;
    this.localStatus = '读取本机分集记录…';
    try {
      let state = await store.read(item.id);
      if (revision !== this.detailRevision) { return; }
      if (state) {
        this.localSeries = state;
        if (this.localSeason < 0 && state.seasons.length > 0) { this.localSeason = state.seasons[0].number; }
      }
      if (refresh && clientId) {
        const catalog = await fetchEpisodeCatalog(item, clientId);
        if (revision !== this.detailRevision || this.clientId !== clientId) { return; }
        this.invalidateSync();
        await store.saveCatalog(catalog);
        state = await store.read(item.id);
      }
      if (revision === this.detailRevision) {
        this.localSeries = state;
        if (state && state.seasons.length > 0 && !state.seasons.some((season: LocalSeasonState) => season.number === this.localSeason)) {
          this.localSeason = state.seasons[0].number;
        }
        this.localStatus = state ? '本机状态（可含已导入云端记录）· 手动模式不会上传' : '首次使用请联网下载分集目录';
      }
    } catch (error) {
      if (revision === this.detailRevision) {
        this.localStatus = '读取或更新失败，保留已有本机记录。';
      }
    } finally {
      this.localBusy = false;
    }
  }

  private async markLocal(item: Media, ids: number[], watched: boolean): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.syncBusy || ids.length === 0) { return; }
    const revision = this.detailRevision;
    this.localBusy = true;
    this.confirmSeason = -1;
    const auto = this.autoActive() ? this.autoConsent : undefined;
    let saved = false;
    try {
      this.invalidateSync();
      await store.mark(item.id, ids, watched, watched && auto ? auto.uuid : '');
      saved = true;
      const state = await store.read(item.id);
      this.localRecent = await store.recent();
      await this.reloadQueue();
      if (revision === this.detailRevision) {
        this.localSeries = state;
        this.localStatus = '已保存到本机 · 本地操作完成';
      }
    } catch (error) {
      if (revision === this.detailRevision) {
        this.localStatus = '保存或回读失败，请重新读取本机记录确认结果。';
      }
    } finally {
      this.localBusy = false;
    }
    if (saved && watched && auto && this.autoActive()) { await this.resumeQueued(); }
  }

  @Builder
  localEpisodesView(item: Media) {
    Column({ space: 10 }) {
      Text('本机分集管理').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Text('本机明确操作优先于已导入的云端记录。仅统计已播普通集；持久自动新增须主动开启。')
        .fontSize(12).fontColor($r('app.color.showly_secondary')).width('100%')
      if (!this.episodeReady) {
        Text(this.episodeInitStatus || '正在打开分集数据库…').fontSize(13).width('100%')
      } else {
        Row({ space: 8 }) {
          Button('读取本机').layoutWeight(1).enabled(!this.localBusy && !this.syncBusy)
            .onClick(() => { this.loadLocalEpisodes(item); })
          Button('更新分集目录').layoutWeight(1).enabled(!this.localBusy && !this.syncBusy && !!this.clientId)
            .onClick(() => { this.loadLocalEpisodes(item, true); })
        }.width('100%')
        Text(this.localStatus).fontSize(12).width('100%')
        if (this.autoStatus) { Text(this.autoStatus).fontSize(12).width('100%') }
        if (this.localSeries) {
          Text('本机已看 ' + this.localSeries.completed + ' / ' + this.localSeries.catalog.episodes.length + ' 集')
            .fontSize(16).width('100%')
          if (this.localSeries.catalog.episodes.length > 0) {
            Progress({ value: this.localSeries.completed, total: this.localSeries.catalog.episodes.length,
              type: ProgressType.Linear }).width('100%').color($r('app.color.showly_accent'))
            Text(this.localSeries.next ? '下一集：' + this.localSeries.next : '当前目录已看完')
              .fontSize(14).width('100%')
          }
          ForEach(this.localSeries.seasons, (season: LocalSeasonState) => {
            Column({ space: 8 }) {
              Button('第 ' + season.number + ' 季 · ' + season.completed + '/' + season.episodes.length +
                (this.localSeason === season.number ? '  收起' : '  展开')).width('100%').fontSize(14)
                .onClick(() => { this.localSeason = this.localSeason === season.number ? -1 : season.number; this.confirmSeason = -1; })
              if (this.localSeason === season.number) {
                Row({ space: 8 }) {
                  Button('整季已看').layoutWeight(1).enabled(!this.localBusy && !this.syncBusy && season.completed < season.episodes.length)
                    .onClick(() => { this.confirmSeason = season.number; this.confirmWatched = true; })
                  Button('整季撤销').layoutWeight(1).enabled(!this.localBusy && !this.syncBusy && season.completed > 0)
                    .onClick(() => { this.confirmSeason = season.number; this.confirmWatched = false; })
                }.width('100%')
                if (this.confirmSeason === season.number) {
                  Text(this.confirmWatched ? '确认将本季已播集全部标记已看？' : '确认撤销本季全部本机已看标记？').fontSize(13)
                  Row({ space: 8 }) {
                    Button('取消').layoutWeight(1).onClick(() => { this.confirmSeason = -1; })
                    Button('确认').layoutWeight(1).enabled(!this.localBusy && !this.syncBusy)
                      .onClick(() => {
                        this.markLocal(item, season.episodes.filter((ep: LocalEpisodeState) =>
                          ep.watched !== this.confirmWatched).map((ep: LocalEpisodeState) => ep.episode.id), this.confirmWatched);
                      })
                  }.width('100%')
                }
                ForEach(season.episodes, (entry: LocalEpisodeState) => {
                  Row({ space: 8 }) {
                    Column({ space: 3 }) {
                      Text('第 ' + entry.episode.number + ' 集').fontSize(14).width('100%')
                      if (entry.episode.title) {
                        Text(entry.episode.title).fontSize(12).maxLines(2).width('100%')
                          .fontColor($r('app.color.showly_secondary'))
                      }
                    }.layoutWeight(1)
                    Button(entry.watched ? '撤销已看' : '标记已看').fontSize(12).enabled(!this.localBusy && !this.syncBusy)
                      .onClick(() => { this.markLocal(item, [entry.episode.id], !entry.watched); })
                  }.width('100%')
                }, (entry: LocalEpisodeState) => entry.episode.id + ':' + entry.watched)
              }
            }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
          }, (season: LocalSeasonState) => season.number + ':' + season.completed)
        }
      }
    }.width('100%')
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
    if (!this.settings || this.setupBusy || this.authBusy || this.searching || this.cloudBusy || this.syncBusy) {
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
        await this.revokeAuto();
        if (!traktAuth.disconnect()) {
          this.setupStatus = '无法清除旧授权，未切换 Client ID。';
          return;
        }
        await this.settings.save(next);
        this.clientId = next;
        this.translationCache.clear();
        this.resetCollection();
        this.resetDiscover();
        clearDetailMemory();
        this.closeDetail();
        this.results = [];
        this.clearCloud();
      }
      this.configuring = false;
      this.setupStatus = 'Client ID 已验证并保存到本机';
      if (login) {
        await this.revokeAuto();
        await traktAuth.begin(this.context(), this.clientId);
      }
    } catch (error) {
      this.setupStatus = '验证或保存失败，请检查网络和设备存储。';
    } finally {
      this.setupBusy = false;
    }
  }

  private async clearClient(): Promise<void> {
    if (!this.settings || this.setupBusy || this.authBusy || this.searching || this.cloudBusy || this.syncBusy) {
      return;
    }
    this.setupBusy = true;
    try {
      await this.revokeAuto();
      if (!traktAuth.disconnect()) {
        this.setupStatus = '无法清除旧授权，请重试。';
        return;
      }
      await this.settings.save('');
      this.clientId = '';
      this.translationCache.clear();
      this.resetCollection();
      this.resetDiscover();
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

  private invalidateSync(): void {
    this.batchIds = [];
    this.batchConfirm = false;
    this.importConfirm = false;
    this.queueConfirm = false;
    this.syncLogs = [];
    this.uploadSelectedId = 0;
    this.removeSelectedId = 0;
    this.uploadStatus = '';
    this.syncPreview = undefined;
    this.syncAccount = undefined;
    this.syncBound = false;
    this.syncStatus = '';
    this.syncPage = 1;
  }

  private async verifySync(): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.syncBusy || this.localBusy ||
        this.cloudBusy || this.authBusy || this.setupBusy || !this.clientId) { return; }
    this.invalidateSync();
    this.syncBusy = true;
    this.syncStatus = '正在验证当前 Trakt 账户…';
    const clientId = this.clientId;
    try {
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Sign in required'); }
      const account = await readSyncAccount(session);
      const bound = await store.boundAccount();
      if (this.clientId !== clientId || !traktAuth.isCurrent(clientId, session.generation)) {
        throw new Error('Session changed');
      }
      this.syncAccount = account;
      this.syncBound = bound === account.uuid;
      if (this.syncBound) { this.syncLogs = await store.syncLogs(account.uuid); await this.reloadQueue(); }
      this.syncStatus = this.syncBound ? '账户已验证，可以生成差异预览。' :
        bound ? '本机已绑定另一 Trakt 账户，禁止生成预览或重新绑定。' : '请核对账户并确认绑定；不会上传记录。';
      if (bound && bound !== account.uuid) { this.syncAccount = undefined; }
    } catch (error) {
      this.syncStatus = '账户验证失败，请检查登录或网络。';
    } finally { this.syncBusy = false; }
  }

  private async confirmSyncAccount(): Promise<void> {
    const store = this.episodeStore;
    const expected = this.syncAccount;
    const clientId = this.clientId;
    if (!store || !expected || this.syncBusy || this.localBusy || this.cloudBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, expected.generation)) { return; }
    this.syncBusy = true;
    try {
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Session changed'); }
      const verified = await readSyncAccount(session);
      if (verified.uuid !== expected.uuid || this.clientId !== clientId ||
          !traktAuth.isCurrent(clientId, session.generation)) { throw new Error('Account changed'); }
      await store.bindAccount(verified.uuid);
      this.syncBound = true;
      this.syncLogs = await store.syncLogs(verified.uuid);
      await this.reloadQueue();
      this.syncStatus = '账户绑定成功；尚未同步任何记录。';
    } catch (error) {
      this.invalidateSync();
      this.syncStatus = '账户绑定失败或身份变化，请重新验证。';
    } finally { this.syncBusy = false; }
  }

  private async generateSyncPreview(): Promise<void> {
    const store = this.episodeStore;
    const expected = this.syncAccount;
    const clientId = this.clientId;
    if (!store || !expected || !this.syncBound || this.syncBusy || this.localBusy || this.cloudBusy ||
        this.setupBusy || !traktAuth.isCurrent(clientId, expected.generation)) { return; }
    this.syncBusy = true;
    this.syncPreview = undefined;
    this.batchIds = [];
    this.batchConfirm = false;
    this.importConfirm = false;
    this.uploadSelectedId = 0;
    this.removeSelectedId = 0;
    this.syncPage = 1;
    this.syncStatus = '正在读取完整云端分集记录并比较…';
    try {
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Session changed'); }
      const preview = await buildSyncPreview(store, session);
      if (preview.account.uuid !== expected.uuid || this.clientId !== clientId ||
          !traktAuth.isCurrent(clientId, session.generation)) { throw new Error('Account changed'); }
      this.syncPreview = preview;
      this.syncLogs = await store.syncLogs(preview.account.uuid);
      this.syncStatus = '预览完成；本机与云端观看记录均未改动。';
    } catch (error) {
      this.syncStatus = '预览失败：账户、分页或活动快照无法验证。请检查网络并重试。';
    } finally { this.syncBusy = false; }
  }

  private autoActive(): boolean {
    return !!this.autoConsent && !!this.clientId && this.autoConsent.clientId === this.clientId;
  }

  private async reloadQueue(): Promise<void> {
    const store = this.episodeStore;
    if (!store) { return; }
    const uuid = await store.boundAccount();
    this.queueRows = uuid ? await store.queueEntries(uuid) : [];
  }

  private async setAuto(enabled: boolean): Promise<void> {
    const store = this.episodeStore;
    const account = this.syncAccount;
    if (!store || this.syncBusy || this.localBusy || this.cloudBusy || this.setupBusy) { return; }
    this.syncBusy = true;
    try {
      if (!enabled) {
        await store.clearAutoConsent();
        this.autoConsent = undefined;
        this.autoStatus = '自动新增已关闭；待同步记录保留，须手动确认处理。';
      } else {
        const session = traktAuth.session(this.clientId);
        if (!account || !session || !this.syncBound || account.generation !== session.generation) {
          throw new Error('Verify account first');
        }
        const verified = await readSyncAccount(session);
        if (verified.uuid !== account.uuid || await store.boundAccount() !== account.uuid) {
          throw new Error('Account mismatch');
        }
        await store.saveAutoConsent(account.uuid, this.clientId);
        this.autoConsent = { uuid: account.uuid, clientId: this.clientId };
        this.autoStatus = '持久自动新增已开启；仅新授权事件进入队列，联网且账户验证通过后前台同步。';
      }
      await this.reloadQueue();
    } catch (error) {
      this.autoStatus = '同步模式保存失败，请重试。';
    } finally { this.syncBusy = false; }
  }

  // Before an explicit credential change, disable persisted authorization.
  // Keep queued events; they remain bound to the original UUID.
  private async revokeAuto(): Promise<void> {
    this.autoConsent = undefined;
    if (this.episodeStore) { await this.episodeStore.clearAutoConsent(); }
    this.autoStatus = '自动新增已关闭；旧队列仍保留。';
  }

  private async resumeQueued(manual: boolean = false): Promise<void> {
    const store = this.episodeStore;
    const clientId = this.clientId;
    const consent = this.autoConsent;
    if (!store || !this.episodeReady || !clientId || this.syncBusy || this.localBusy ||
        this.cloudBusy || this.authBusy || this.setupBusy || (!manual && !this.autoActive())) { return; }
    if (manual && (!this.syncAccount || !this.syncBound || !this.queueConfirm)) { return; }
    const expected = manual ? this.syncAccount?.uuid : consent?.uuid;
    if (!expected) { return; }
    this.syncBusy = true;
    this.queueConfirm = false;
    this.autoStatus = '正在读取待同步队列…';
    try {
      const pending = await store.queueEntries(expected);
      if (!pending.length) {
        this.queueRows = [];
        this.autoStatus = '没有待同步新增。';
        return;
      }
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Offline or sign-in required'); }
      const account = await readSyncAccount(session);
      if (account.uuid !== expected || this.clientId !== clientId || await store.boundAccount() !== expected) {
        if (!manual) { await this.revokeAuto(); }
        throw new Error('Account mismatch');
      }
      if (!manual && (!this.autoActive() || this.autoConsent?.uuid !== expected)) {
        throw new Error('Auto disabled');
      }
      const ids = pending.map((entry: QueueEntry) => entry.episodeId);
      const result = await uploadBatch(store, session, expected, ids, new Date().toISOString(), 'queue', undefined, pending);
      for (const entry of pending) {
        if (result.completedIds.includes(entry.episodeId)) { await store.finishQueue(expected, entry); }
      }
      this.autoStatus = result.message;
      this.syncLogs = await store.syncLogs(expected);
    } catch (error) {
      this.autoStatus = '队列未完成，已保留本机操作；联网后可再次处理未发送项，受保护项不会盲目重试。';
    } finally {
      try { await this.reloadQueue(); } catch (error) {}
      this.syncPreview = undefined;
      this.syncBusy = false;
    }
  }

  private async disconnectSyncAccount(): Promise<void> {
    if (this.syncBusy || this.localBusy || this.setupBusy || this.cloudBusy) { return; }
    this.setupBusy = true;
    try {
      await this.revokeAuto();
      if (traktAuth.disconnect()) { this.clearCloud(); }
    } catch (error) {
      this.setupStatus = '无法安全关闭同步授权，未断开登录。';
    } finally { this.setupBusy = false; }
  }

  private async beginSyncLogin(): Promise<void> {
    if (this.syncBusy || this.localBusy || this.setupBusy || this.cloudBusy) { return; }
    this.setupBusy = true;
    try {
      await this.revokeAuto();
      await traktAuth.begin(this.context(), this.clientId);
    } catch (error) {
      this.setupStatus = '无法安全关闭旧同步授权，未开始登录。';
    } finally { this.setupBusy = false; }
  }

  private toggleBatch(id: number): void {
    if (this.syncBusy || this.batchConfirm) { return; }
    this.uploadSelectedId = 0;
    this.removeSelectedId = 0;
    this.importConfirm = false;
    this.batchIds = this.batchIds.includes(id) ? this.batchIds.filter((value: number) => value !== id) :
      [...this.batchIds, id];
  }

  private selectBatchPage(): void {
    if (this.syncBusy || this.batchConfirm) { return; }
    const ids: Set<number> = new Set<number>(this.batchIds);
    for (const row of this.syncSlice()) {
      if (row.kind === 'addition' && !row.uploadBlocked) { ids.add(row.episodeId); }
    }
    this.batchIds = Array.from(ids);
    this.uploadSelectedId = 0;
    this.removeSelectedId = 0;
    this.importConfirm = false;
  }

  private batchLabels(): SyncDifference[] {
    return this.syncPreview?.rows.filter((row: SyncDifference) => this.batchIds.includes(row.episodeId)) ?? [];
  }

  private async confirmBatchUpload(): Promise<void> {
    const store = this.episodeStore;
    const preview = this.syncPreview;
    const ids = [...this.batchIds];
    if (!store || !preview || !this.syncBound || !this.batchConfirm || !ids.length ||
        this.syncBusy || this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(this.clientId, preview.account.generation)) { return; }
    const session = traktAuth.session(this.clientId);
    if (!session) { return; }
    this.syncBusy = true;
    this.batchIds = [];
    this.batchConfirm = false;
    this.uploadStatus = '正在复核批量新增…';
    try {
      const result = await uploadBatch(store, session, preview.account.uuid, ids,
        new Date().toISOString(), 'manual', preview);
      this.uploadStatus = result.message;
      this.syncLogs = await store.syncLogs(preview.account.uuid);
    } catch (error) {
      this.uploadStatus = '批量流程未完成，请重新预览并核对云端；不会盲目重试。';
    } finally {
      this.syncPreview = undefined;
      this.syncPage = 1;
      this.syncStatus = '批量流程结束；请重新生成预览。';
      this.syncBusy = false;
    }
  }

  private async confirmCloudImport(): Promise<void> {
    const store = this.episodeStore;
    const preview = this.syncPreview;
    if (!store || !preview || !this.syncBound || !this.importConfirm || this.syncBusy ||
        this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(this.clientId, preview.account.generation)) { return; }
    const session = traktAuth.session(this.clientId);
    if (!session) { return; }
    this.syncBusy = true;
    this.importConfirm = false;
    this.batchIds = [];
    this.batchConfirm = false;
    try {
      const fresh = await buildSyncPreview(store, session, true);
      if (fresh.account.uuid !== preview.account.uuid || !traktAuth.isCurrent(this.clientId, session.generation)) {
        throw new Error('Account changed');
      }
      const added = await store.importCloudBaseline(fresh.account.uuid, fresh.cloudIds);
      this.uploadStatus = '已新增保存 ' + added + ' 个云端已看分集 ID 到本机基线；明确本机操作优先，未修改 Trakt。';
      await store.logSync(fresh.account.uuid, 'import', [], this.uploadStatus);
      this.syncLogs = await store.syncLogs(fresh.account.uuid);
      this.syncPreview = fresh;
    } catch (error) {
      this.uploadStatus = '导入流程未完成，请核对本机记录；未向云端写入。';
    } finally { this.syncBusy = false; }
  }

  private async confirmEpisodeUpload(): Promise<void> {
    const store = this.episodeStore;
    const preview = this.syncPreview;
    const episodeId = this.uploadSelectedId;
    const clientId = this.clientId;
    if (!store || !preview || !this.syncBound || episodeId <= 0 || this.syncBusy ||
        this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, preview.account.generation)) { return; }
    const session = traktAuth.session(clientId);
    if (!session) { return; }
    const watchedAt = new Date().toISOString();
    this.syncBusy = true;
    this.uploadSelectedId = 0;
    this.removeSelectedId = 0;
    this.uploadStatus = '正在重新校验账户、分集及云端记录…';
    try {
      const result = await uploadSelectedEpisode(store, session, preview, episodeId, watchedAt);
      this.uploadStatus = result.message;
      await store.logSync(preview.account.uuid, 'single', [episodeId], result.message);
      this.syncLogs = await store.syncLogs(preview.account.uuid);
      await this.reloadQueue();
    } catch (error) {
      this.uploadStatus = '未能完成安全上传流程。可能已保留尝试凭证；请重新生成预览并在 Trakt 核对，不会自动重试。';
    } finally {
      this.syncPreview = undefined;
      this.syncPage = 1;
      this.syncStatus = '本次流程已结束。重新生成差异预览可查看最新状态。';
      this.syncBusy = false;
    }
  }

  private async confirmEpisodeRemoval(): Promise<void> {
    const store = this.episodeStore;
    const preview = this.syncPreview;
    const episodeId = this.removeSelectedId;
    const clientId = this.clientId;
    if (!store || !preview || !this.syncBound || episodeId <= 0 || this.syncBusy ||
        this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, preview.account.generation)) { return; }
    const session = traktAuth.session(clientId);
    if (!session) { return; }
    this.syncBusy = true;
    this.removeSelectedId = 0;
    this.uploadSelectedId = 0;
    this.uploadStatus = '正在验证账户及目标单次历史…';
    try {
      const result = await removeSelectedPlay(store, session, preview, episodeId);
      this.uploadStatus = result.message;
      await store.logSync(preview.account.uuid, 'remove', [episodeId], result.message);
      this.syncLogs = await store.syncLogs(preview.account.uuid);
      await this.reloadQueue();
    } catch (error) {
      this.uploadStatus = '安全撤销流程未完成，请重新生成预览并在 Trakt 核对；不会自动重试。';
    } finally {
      this.syncPreview = undefined;
      this.syncPage = 1;
      this.syncStatus = '本次流程已结束。重新生成差异预览可查看最新状态。';
      this.syncBusy = false;
    }
  }

  private visibleSyncRows(): SyncDifference[] {
    return this.syncPreview?.rows.filter((row: SyncDifference) => row.kind === this.syncFilter) ?? [];
  }

  private syncSlice(): SyncDifference[] {
    const start = (this.syncPage - 1) * this.collectionPageSize;
    return this.visibleSyncRows().slice(start, start + this.collectionPageSize);
  }

  private syncPages(): number {
    return Math.max(1, Math.ceil(this.visibleSyncRows().length / this.collectionPageSize));
  }

  @Builder
  syncFilterButton(label: string, value: string) {
    Button(label).layoutWeight(1).fontSize(12)
      .backgroundColor(this.syncFilter === value ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.syncFilter === value ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.syncFilter = value; this.syncPage = 1; this.removeSelectedId = 0; this.uploadSelectedId = 0; })
  }

  @Builder
  syncPreviewView() {
    Column({ space: 10 }) {
      Text('分集同步预览').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
      Text('默认手动模式。批量新增和云端基线导入需确认；撤销仍仅允许具备历史凭证的单次操作。')
        .fontSize(12).width('100%').fontColor($r('app.color.showly_secondary'))
      Button(this.syncBusy ? '处理中…' : '验证同步账户')
        .enabled(this.episodeReady && this.signedIn && !this.syncBusy && !this.localBusy && !this.cloudBusy && !this.authBusy && !this.setupBusy)
        .onClick(() => { this.verifySync(); })
      Text(this.syncStatus).fontSize(13).width('100%')
      if (this.uploadStatus) { Text(this.uploadStatus).fontSize(14).width('100%') }
      if (this.syncAccount && this.signedIn && traktAuth.isCurrent(this.clientId, this.syncAccount.generation)) {
        Text('当前账户：' + this.syncAccount.username).fontSize(14).width('100%')
        if (!this.syncBound) {
          Text('首次绑定不会修改观看记录。本机分集日志此前没有账户归属，确认后仅对此账户开放预览；暂不支持换绑。')
            .fontSize(12).width('100%')
          Button('确认绑定此账户').enabled(!this.syncBusy && !this.localBusy)
            .onClick(() => { this.confirmSyncAccount(); })
        } else {
          Button('生成同步差异预览').enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy && !this.authBusy)
            .onClick(() => { this.generateSyncPreview(); })
          Text(this.autoActive() ? '同步模式：持久自动新增' : '同步模式：手动（默认）').fontSize(14).width('100%')
          Text('开启后新标记已看的分集进入持久队列；联网且核实同一账户后在前台同步。重启保留授权，主动换号或断开登录会关闭；不追溯旧日志，不自动删除。')
            .fontSize(12).width('100%')
          Button(this.autoActive() ? '关闭自动新增' : '授权开启持久自动新增')
            .enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy && !this.authBusy)
            .onClick(() => { this.setAuto(!this.autoActive()); })
          if (this.autoStatus) { Text(this.autoStatus).fontSize(13).width('100%') }
          Text('待同步队列：' + this.queueRows.length + ' 集（含受保护项）').fontSize(15).width('100%')
          ForEach(this.queueRows.slice(0, this.collectionPageSize), (entry: QueueEntry) => {
            Text(entry.label + ' · ' + (entry.blocked ? '受保护，禁止重发/目录异常' : '等待核验'))
              .fontSize(12).width('100%')
          }, (entry: QueueEntry) => entry.seq + ':' + entry.episodeId)
          if (this.queueRows.length > this.collectionPageSize) {
            Text('仅预览前 ' + this.collectionPageSize + ' 集；处理时会核验完整队列。').fontSize(12)
          }
          Button('核对并处理待同步队列').enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy &&
            !this.authBusy && this.queueRows.length > 0)
            .onClick(() => { this.queueConfirm = true; })
          if (this.queueConfirm) {
            Text('确认处理此前已授权的 ' + this.queueRows.length + ' 集？使用原本机标记时间；跳过云端已有记录，未知结果不重发。')
              .fontSize(12).width('100%')
            Row({ space: 8 }) {
              Button('取消').layoutWeight(1).onClick(() => { this.queueConfirm = false; })
              Button('确认处理队列').layoutWeight(1).enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy)
                .onClick(() => { this.resumeQueued(true); })
            }.width('100%')
          }
          Button(this.showSyncLogs ? '收起同步日志' : '查看同步日志')
            .onClick(() => { this.showSyncLogs = !this.showSyncLogs; })
          if (this.showSyncLogs) {
            Text('最近同步日志（最多 12 条）').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
            if (!this.syncLogs.length) { Text('暂无记录').fontSize(12) }
            ForEach(this.syncLogs, (log: string, index: number) => {
              Text(log).fontSize(12).width('100%')
            }, (log: string, index: number) => index.toString() + log)
          }
        }
        if (this.syncPreview && this.syncBound) {
          Text('本机明确操作 ' + this.syncPreview.localCount + ' 集 · 云端已看 ' + this.syncPreview.cloudCount + ' 集')
            .fontSize(14).width('100%')
          Text('待核对新增 ' + this.syncPreview.additions + ' · 一致 ' + this.syncPreview.matches +
            ' · 撤销冲突 ' + this.syncPreview.conflicts + ' · 目录异常 ' + this.syncPreview.unknown)
            .fontSize(14).width('100%')
          Text('仅云端存在 ' + this.syncPreview.cloudOnly + ' 集（含可能的特别篇），保留原记录。')
            .fontSize(13).width('100%')
          Button('导入云端已看状态到本机').enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy)
            .onClick(() => { this.importConfirm = true; this.batchConfirm = false; this.batchIds = []; this.uploadSelectedId = 0; this.removeSelectedId = 0; })
          if (this.importConfirm) {
            Text('确认保存当前账户的云端已看 ID？只新增本机基线，不覆盖本机明确标记或撤销；已缓存分集目录可离线显示，不导入单次历史时间。')
              .fontSize(12).width('100%')
            Row({ space: 8 }) {
              Button('取消').layoutWeight(1).enabled(!this.syncBusy).onClick(() => { this.importConfirm = false; })
              Button('确认导入').layoutWeight(1).enabled(!this.syncBusy).onClick(() => { this.confirmCloudImport(); })
            }.width('100%')
          }
          if (this.syncFilter === 'addition') {
            Row({ space: 6 }) {
              Button('选择本页可上传').layoutWeight(1).fontSize(12).enabled(!this.syncBusy && !this.batchConfirm)
                .onClick(() => { this.selectBatchPage(); })
              Button('清空选择').layoutWeight(1).fontSize(12).enabled(!this.syncBusy)
                .onClick(() => { this.batchIds = []; this.batchConfirm = false; })
            }.width('100%')
          }
          if (this.batchIds.length > 0) {
            Text('已选 ' + this.batchIds.length + ' 集（支持跨页选择）').fontSize(14).width('100%')
            Button('核对批量新增').enabled(!this.syncBusy && !this.batchConfirm)
              .onClick(() => { this.batchConfirm = true; this.importConfirm = false; this.uploadSelectedId = 0; this.removeSelectedId = 0; })
            if (this.batchConfirm) {
              Text('确认以下分集确实看过？将尝试新增各一次观看，使用确认时刻；可能影响 Trakt 追剧进度。')
                .fontSize(13).width('100%')
              ForEach(this.batchLabels(), (row: SyncDifference) => {
                Text(row.label).fontSize(12).width('100%')
              }, (row: SyncDifference) => row.episodeId.toString())
              Row({ space: 8 }) {
                Button('取消').layoutWeight(1).enabled(!this.syncBusy).onClick(() => { this.batchConfirm = false; })
                Button('确认上传所选').layoutWeight(1).enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy)
                  .onClick(() => { this.confirmBatchUpload(); })
              }.width('100%')
            }
          }
          Row({ space: 4 }) {
            this.syncFilterButton('新增', 'addition')
            this.syncFilterButton('一致', 'match')
            this.syncFilterButton('冲突', 'conflict')
            this.syncFilterButton('异常', 'unknown')
          }.width('100%')
          if (this.visibleSyncRows().length === 0) { Text('本分类没有记录').fontSize(13).width('100%') }
          ForEach(this.syncSlice(), (row: SyncDifference) => {
            Column({ space: 4 }) {
              Text(row.label).fontSize(14).width('100%')
              Text('本机 ' + (row.localWatched ? '已看' : '撤销') + ' / 云端 ' +
                (row.cloudWatched ? '已看' : '无已看记录')).fontSize(12).width('100%')
                .fontColor($r('app.color.showly_secondary'))
              if (row.kind === 'addition' && row.uploadBlocked) {
                Text('已有上传保护凭证，禁止重发；请核对 Trakt。').fontSize(12).width('100%')
              }
              if (row.kind === 'addition' && !row.uploadBlocked) {
                Button(this.batchIds.includes(row.episodeId) ? '已选入批量' : '加入批量选择')
                  .fontSize(12).enabled(!this.syncBusy && !this.batchConfirm)
                  .onClick(() => { this.toggleBatch(row.episodeId); })
                Button(this.uploadSelectedId === row.episodeId ? '取消选择' : '选择上传此集')
                  .fontSize(12).enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy)
                  .onClick(() => { this.batchIds = []; this.batchConfirm = false; this.importConfirm = false; this.removeSelectedId = 0; this.uploadSelectedId = this.uploadSelectedId === row.episodeId ? 0 : row.episodeId; })
                if (this.uploadSelectedId === row.episodeId) {
                  Text('确认将 ' + row.label + ' 的一次观看记录新增至当前已绑定 Trakt 账户？观看时间为确认时刻。')
                    .fontSize(13).width('100%')
                  Text('不会删除旧历史；Trakt 可能自动更新追剧进度或待看列表。其他设备同时写入仍可能产生重复。')
                    .fontSize(12).width('100%')
                  Row({ space: 8 }) {
                    Button('取消').layoutWeight(1).enabled(!this.syncBusy)
                      .onClick(() => { this.uploadSelectedId = 0; })
                    Button('确认上传 1 集').layoutWeight(1).enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy && !this.authBusy && !this.setupBusy)
                      .onClick(() => { this.confirmEpisodeUpload(); })
                  }.width('100%')
                }
              }
              if (row.kind === 'conflict') {
                if (row.undoHistoryId > 0 && row.undoState === 0) {
                  Text('本机上传回执：' + row.undoWatchedAt + ' · 历史 ID ' + row.undoHistoryId)
                    .fontSize(12).width('100%')
                  Button(this.removeSelectedId === row.episodeId ? '取消撤销选择' : '选择撤销此条历史')
                    .fontSize(12).enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy)
                    .onClick(() => { this.batchIds = []; this.batchConfirm = false; this.importConfirm = false; this.uploadSelectedId = 0; this.removeSelectedId = this.removeSelectedId === row.episodeId ? 0 : row.episodeId; })
                  if (this.removeSelectedId === row.episodeId) {
                    Text('确认删除 ' + row.label + ' 的上述一次云端观看历史？请核对观看时间。此操作不可直接恢复。')
                      .fontSize(13).width('100%')
                    Text('若存在多次观看、历史变化或无法确认 ID，将停止。不会按剧集、季或整部剧删除。')
                      .fontSize(12).width('100%')
                    Row({ space: 8 }) {
                      Button('取消').layoutWeight(1).enabled(!this.syncBusy)
                        .onClick(() => { this.removeSelectedId = 0; })
                      Button('确认删除 1 条历史').layoutWeight(1)
                        .enabled(!this.syncBusy && !this.localBusy && !this.cloudBusy && !this.authBusy && !this.setupBusy)
                        .onClick(() => { this.confirmEpisodeRemoval(); })
                    }.width('100%')
                  }
                } else {
                  Text(row.undoState === 1 ? '已有撤销尝试，禁止重复删除；请在 Trakt 核对。' :
                    row.undoState === 2 ? '此前目标历史已确认不存在；保留其他云端记录。' :
                    '无可验证的单次历史凭证（含旧版上传），保留云端记录，请在 Trakt 手动处理。')
                    .fontSize(12).width('100%')
                }
              }
            }.width('100%').padding(10).borderRadius(8).backgroundColor($r('app.color.showly_muted_surface'))
          }, (row: SyncDifference) => row.episodeId.toString())
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.syncPage > 1).onClick(() => { this.syncPage--; })
            Text(this.syncPage + ' / ' + this.syncPages()).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.syncPage < this.syncPages()).onClick(() => { this.syncPage++; })
          }.width('100%')
        }
      }
      Divider()
    }.width('100%')
  }

  private clearCloud(): void {
    this.invalidateSync();
    this.cloud = undefined;
    this.cloudStatus = '';
    this.trackingPage = 1;
    this.trackingQuery = '';
    if (this.collectionFilter === 'tracking') { this.resetCollection(); }
  }

  private async loadCloud(): Promise<void> {
    if (this.cloudBusy || this.syncBusy || this.setupBusy || this.authBusy || !this.clientId) {
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
        if (this.collectionFilter === 'tracking') { this.resetCollection(); }
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
      this.resetCollection();
      if (this.collectionGrid && this.tab === 'library' && !this.selectedMedia) { this.loadCollectionPosters(); }
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

  private resetDiscover(): void {
    ++this.discoverRevision;
    this.discoverItems = [];
    this.discoverPage = 1;
    this.discoverPages = 0;
    this.discoverBusy = false;
    this.discoverStatus = '';
  }

  private async loadDiscover(page: number = 1): Promise<void> {
    if (this.discoverBusy || this.setupBusy || !this.clientId || page < 1) {
      return;
    }
    const revision = ++this.discoverRevision;
    const clientId = this.clientId;
    this.discoverBusy = true;
    this.discoverStatus = '正在读取影视榜单…';
    try {
      const result = await readDiscover(clientId, this.discoverKind, this.discoverMode, page);
      if (revision !== this.discoverRevision || clientId !== this.clientId) {
        return;
      }
      this.discoverItems = result.items;
      this.discoverPage = result.page;
      this.discoverPages = result.pages;
      this.discoverStatus = result.items.length === 0 ? '没有影视结果' : '正在加载本页海报…';
      const dir = this.context().cacheDir;
      // The list already carries artwork: no per-title summary API fan-out.
      // Download one image at a time, only for the requested page.
      let missing = 0;
      for (const item of result.items) {
        if (revision !== this.discoverRevision || clientId !== this.clientId || this.tab !== 'discover') {
          return;
        }
        let uri = '';
        try {
          const poster = await cachePoster(dir, item.media, item.posterUrls);
          uri = poster.uri;
        } catch (error) {
          // One missing image must not remove the media card.
        }
        if (revision !== this.discoverRevision || clientId !== this.clientId) {
          return;
        }
        if (!uri) {
          missing++;
        }
        const loaded: DiscoverItem = { media: item.media, posterUrls: item.posterUrls,
          posterUri: uri, rating: item.rating };
        this.discoverItems = this.discoverItems.map((old: DiscoverItem) =>
          old.media.id === item.media.id ? loaded : old);
      }
      this.discoverStatus = result.items.length === 0 ? '没有影视结果' :
        (missing > 0 ? '已加载本页；' + missing + ' 张海报暂不可用' : '已加载本页海报');
    } catch (error) {
      if (revision === this.discoverRevision) {
        this.discoverStatus = '榜单读取失败，请检查网络、API 权限或调用限额后重试。';
      }
    } finally {
      if (revision === this.discoverRevision) {
        this.discoverBusy = false;
      }
    }
  }

  private changeDiscover(kind: string, mode: string): void {
    if (kind === this.discoverKind && mode === this.discoverMode) {
      return;
    }
    this.resetDiscover();
    this.discoverKind = kind;
    this.discoverMode = mode;
    this.loadDiscover();
  }

  @Builder
  discoverCard(item: DiscoverItem) {
    Column({ space: 6 }) {
      if (item.posterUri) {
        Image(item.posterUri).width('100%').aspectRatio(0.667)
          .objectFit(ImageFit.Cover).borderRadius(10)
      } else {
        Column() {
          Text('海报').fontColor($r('app.color.showly_secondary')).fontSize(14)
        }.width('100%').aspectRatio(0.667)
          .justifyContent(FlexAlign.Center).backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
      }
      Text(item.media.title).fontSize(15).fontWeight(FontWeight.Medium)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text((item.media.year > 0 ? item.media.year.toString() : '年份未知') +
        (item.rating > 0 ? ' · ★ ' + item.rating.toFixed(1) : ''))
        .fontSize(12).fontColor($r('app.color.showly_secondary')).width('100%')
    }.width('48%').padding({ bottom: 12 })
      .onClick(() => { this.openDetail(item.media); })
  }

  @Builder
  discoverView() {
    Column({ space: 12 }) {
      Text('发现').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      if (!this.clientId) {
        Text('请先在账户页配置自己的 Trakt Client ID。').fontSize(14)
        Button('前往账户').onClick(() => { this.tab = 'account'; })
      } else {
        Row({ space: 8 }) {
          Button('电影').layoutWeight(1)
            .backgroundColor(this.discoverKind === 'movie' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
            .fontColor(this.discoverKind === 'movie' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
            .onClick(() => { this.changeDiscover('movie', this.discoverMode); })
          Button('剧集').layoutWeight(1)
            .backgroundColor(this.discoverKind === 'show' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
            .fontColor(this.discoverKind === 'show' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
            .onClick(() => { this.changeDiscover('show', this.discoverMode); })
        }.width('100%')
        Row({ space: 6 }) {
          this.discoverModeButton('趋势', 'trending')
          this.discoverModeButton('热门', 'popular')
          this.discoverModeButton('即将上映', 'anticipated')
        }.width('100%')
        Text(this.discoverStatus).fontSize(12).width('100%')
        Button(this.discoverBusy ? '加载中…' : '刷新本页')
          .enabled(!this.discoverBusy && !this.setupBusy)
          .onClick(() => { this.loadDiscover(this.discoverPage); })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.discoverItems, (item: DiscoverItem) => {
            this.discoverCard(item)
          }, (item: DiscoverItem) => item.media.id + ':' + item.posterUri)
        }.width('100%')
        Row({ space: 8 }) {
          Button('上一页').layoutWeight(1)
            .enabled(!this.discoverBusy && this.discoverPage > 1)
            .onClick(() => { this.loadDiscover(this.discoverPage - 1); })
          Text(this.discoverPage + ' / ' + (this.discoverPages || 1)).fontSize(13)
          Button('下一页').layoutWeight(1)
            .enabled(!this.discoverBusy && this.discoverPage < this.discoverPages)
            .onClick(() => { this.loadDiscover(this.discoverPage + 1); })
        }.width('100%')
      }
    }.width('100%')
  }

  @Builder
  discoverModeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .backgroundColor(this.discoverMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.discoverMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.changeDiscover(this.discoverKind, mode); })
  }

  private async changeTheme(mode: string): Promise<void> {
    if (!this.appearance || this.themeBusy || mode === this.themeMode) { return; }
    this.themeBusy = true;
    try {
      applyAppearance(this.context(), mode);
      this.themeMode = mode;
      await this.appearance.save(mode);
      this.themeStatus = '';
    } catch (error) {
      this.themeStatus = '主题切换或保存失败，请重试。';
    } finally {
      this.themeBusy = false;
    }
  }

  @Builder
  themeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .enabled(!this.themeBusy)
      .backgroundColor(this.themeMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.themeMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.changeTheme(mode); })
  }

  private trackingItems(): ShowProgress[] {
    const snapshot = this.cloud;
    if (!snapshot || !this.signedIn || !traktAuth.isCurrent(this.clientId, snapshot.generation)) {
      return [];
    }
    const query = this.trackingQuery.trim().toLowerCase();
    return snapshot.shows.filter((show: ShowProgress) => show.title.toLowerCase().includes(query));
  }

  private trackingSlice(): ShowProgress[] {
    const start = (this.trackingPage - 1) * this.collectionPageSize;
    return this.trackingItems().slice(start, start + this.collectionPageSize);
  }

  private trackingPages(): number {
    return Math.max(1, Math.ceil(this.trackingItems().length / this.collectionPageSize));
  }

  @Builder
  progressView() {
    Column({ space: 12 }) {
      Text('观看进度').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      if (this.localRecent.length > 0) {
        Text('最近本机分集记录').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
        ForEach(this.localRecent, (item: Media) => {
          Row() {
            Text(item.title).layoutWeight(1).fontSize(16)
            Text('查看 ›').fontSize(13).fontColor($r('app.color.showly_secondary'))
          }.width('100%').padding(12).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
            .onClick(() => { this.openDetail(item); })
        }, (item: Media) => item.id)
      }
      Text('Trakt 观看记录').fontSize(14).fontColor($r('app.color.showly_secondary')).width('100%')
      if (!this.signedIn && !this.cloudBusy) {
        Text('登录 Trakt 后查看已看剧集与分集进度。').width('100%')
        Button('连接 Trakt').onClick(() => { this.navigate('account'); })
      } else {
        Row({ space: 8 }) {
          Text('看过的剧集 ' + this.trackingItems().length).fontSize(16).layoutWeight(1)
          Button(this.cloudBusy ? '读取中…' : '刷新')
            .enabled(!this.cloudBusy && !this.authBusy && !this.saving && !this.setupBusy)
            .onClick(() => { this.loadCloud(); })
        }.width('100%')
        if (this.cloudStatus) { Text(this.cloudStatus).fontSize(12).width('100%') }
        if (this.cloud) {
          TextInput({ placeholder: '筛选剧集', text: this.trackingQuery })
            .onChange((value: string) => { this.trackingQuery = value; this.trackingPage = 1; })
          ForEach(this.trackingSlice(), (show: ShowProgress) => {
            Row({ space: 12 }) {
              Column({ space: 6 }) {
                Text(show.title).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
                Text('已看 ' + show.watchedEpisodes + ' 集 · 点击查看分集')
                  .fontSize(12).fontColor($r('app.color.showly_secondary')).width('100%')
              }.layoutWeight(1)
              Text('›').fontSize(24).fontColor($r('app.color.showly_secondary'))
            }.padding(14).width('100%').borderRadius(12)
              .backgroundColor($r('app.color.showly_surface'))
              .onClick(() => {
                this.openDetail({ id: show.id, title: show.title, kind: 'show', year: 0, watched: false });
              })
          }, (show: ShowProgress) => show.id)
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.trackingPage > 1)
              .onClick(() => { this.trackingPage--; })
            Text(this.trackingPage + ' / ' + this.trackingPages()).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.trackingPage < this.trackingPages())
              .onClick(() => { this.trackingPage++; })
          }.width('100%')
          Text('含已追完的剧集。分季分集状态仅供查看。').fontSize(12).width('100%')
        }
        Button('云端导入与管理').onClick(() => { this.navigate('cloud'); })
      }
      Divider()
      Text('本地待看').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Text('待看 ' + this.items.filter((item: Media) => !item.watched).length + ' 部影视').width('100%')
      Button('打开收藏').onClick(() => { this.chooseCollection('queue'); this.navigate('library'); })
    }.width('100%')
  }

  private async refreshPage(): Promise<void> {
    try {
      if (this.selectedMedia) {
        await this.openDetail(this.selectedMedia, true);
      } else if (this.tab === 'discover') {
        await this.loadDiscover(this.discoverPage);
      } else if (this.tab === 'library') {
        if (this.collectionGrid) { await this.loadCollectionPosters(); }
      } else if (this.tab === 'progress' || this.tab === 'cloud') {
        if (this.signedIn) { await this.loadCloud(); }
      } else if (this.tab === 'search' && this.title.trim()) {
        await this.search();
      }
    } finally {
      this.refreshing = false;
    }
  }

  private resetCollection(): void {
    ++this.collectionRevision;
    this.collectionPage = 1;
    this.collectionCards = [];
    this.collectionBusy = false;
    this.collectionStatus = '';
  }

  private collectionItems(): Media[] {
    if (this.collectionFilter === 'tracking') {
      const snapshot = this.cloud;
      if (!snapshot || !this.signedIn || !traktAuth.isCurrent(this.clientId, snapshot.generation)) {
        return [];
      }
      return snapshot.shows.map((show: ShowProgress): Media => {
        return { id: show.id, title: show.title, kind: 'show', year: 0, watched: false };
      });
    }
    return this.items.filter((item: Media) => item.watched === (this.collectionFilter === 'watched'));
  }

  private collectionSlice(): Media[] {
    const start = (this.collectionPage - 1) * this.collectionPageSize;
    return this.collectionItems().slice(start, start + this.collectionPageSize);
  }

  private collectionPages(): number {
    return Math.max(1, Math.ceil(this.collectionItems().length / this.collectionPageSize));
  }

  private chooseCollection(filter: string): void {
    if (this.collectionFilter !== filter) {
      this.resetCollection();
      this.collectionFilter = filter;
      if (this.collectionGrid && this.tab === 'library') { this.loadCollectionPosters(); }
    }
  }

  private goCollectionPage(page: number): void {
    if (page < 1 || page > this.collectionPages()) {
      return;
    }
    this.resetCollection();
    this.collectionPage = page;
    if (this.collectionGrid && this.tab === 'library') { this.loadCollectionPosters(); }
  }

  private async loadCollectionPosters(): Promise<void> {
    if (!this.clientId || this.collectionBusy || this.setupBusy) {
      return;
    }
    const revision = ++this.collectionRevision;
    const clientId = this.clientId;
    const items = this.collectionSlice();
    this.collectionBusy = true;
    this.collectionStatus = '正在读取本页海报…';
    this.collectionCards = items.map((media: Media): DiscoverItem => {
      return { media: media, posterUri: '', posterUrls: [], rating: 0 };
    });
    try {
      let unavailable = 0;
      for (const item of items) {
        if (revision !== this.collectionRevision || this.tab !== 'library' || clientId !== this.clientId) {
          return;
        }
        let uri = '';
        let rating = 0;
        if (canReadDetails(item)) {
          try {
            const detail = await readDetails(item, clientId);
            if (revision !== this.collectionRevision || clientId !== this.clientId) {
              return;
            }
            rating = detail.rating;
            const poster = await cachePoster(this.context().cacheDir, item, detail.posterUrls);
            uri = poster.uri;
          } catch (error) {
            // Keep the title usable even when metadata or artwork fails.
          }
        }
        if (revision !== this.collectionRevision || clientId !== this.clientId) {
          return;
        }
        if (!uri) { unavailable++; }
        const card: DiscoverItem = { media: item, posterUri: uri, posterUrls: [], rating: rating };
        this.collectionCards = this.collectionCards.map((old: DiscoverItem) =>
          old.media.id === item.id ? card : old);
      }
      this.collectionStatus = unavailable > 0 ? '本页加载完成；' + unavailable + ' 张海报不可用' : '本页海报已加载';
    } finally {
      if (revision === this.collectionRevision) { this.collectionBusy = false; }
    }
  }

  @Builder
  collectionFilterButton(label: string, value: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .backgroundColor(this.collectionFilter === value ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.collectionFilter === value ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.chooseCollection(value); })
  }

  @Builder
  collectionView() {
    Column({ space: 12 }) {
      Text('我的收藏').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      Text(this.libraryStatus).fontSize(13)
      Row({ space: 6 }) {
        this.collectionFilterButton('待看', 'queue')
        this.collectionFilterButton('追剧记录', 'tracking')
        this.collectionFilterButton('已看', 'watched')
      }.width('100%')
      if (this.collectionFilter === 'tracking') {
        Text('Trakt 看过的剧集（含可能已追完的剧集），只读。').fontSize(12)
        if (!this.cloud || !this.signedIn) {
          Button('前往云端读取记录').onClick(() => { this.tab = 'cloud'; })
        }
      }
      Text('共 ' + this.collectionItems().length + ' 部').fontSize(14)
      Row({ space: 8 }) {
        Button(this.collectionGrid ? '切换文字列表' : '切换海报网格').layoutWeight(1)
          .onClick(() => {
            this.collectionGrid = !this.collectionGrid;
            if (this.collectionGrid) { this.loadCollectionPosters(); }
          })
        if (this.collectionGrid) {
          Button(this.collectionBusy ? '加载中…' : '加载本页海报').layoutWeight(1)
            .enabled(!this.collectionBusy && !this.setupBusy && !!this.clientId)
            .onClick(() => { this.loadCollectionPosters(); })
        }
      }.width('100%')
      if (this.collectionGrid) {
        Text(this.collectionStatus).fontSize(12)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.collectionSlice(), (item: Media) => {
            Column({ space: 6 }) {
              if (this.collectionCards.find((card: DiscoverItem) => card.media.id === item.id)?.posterUri) {
                Image(this.collectionCards.find((card: DiscoverItem) => card.media.id === item.id)?.posterUri)
                  .width('100%').aspectRatio(0.667).objectFit(ImageFit.Cover).borderRadius(10)
              } else {
                Column() {
                  Text('海报').fontSize(13).fontColor($r('app.color.showly_secondary'))
                }.width('100%').aspectRatio(0.667).justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
              }
              Text(mediaLabel(item)).fontSize(14).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              if (this.collectionFilter !== 'tracking') {
                Button(item.watched ? '撤销' : '已看').fontSize(12)
                  .enabled(this.ready && !this.saving && !this.cloudBusy)
                  .onClick(() => { this.save(setWatched(this.items, item.id, !item.watched)); })
              }
            }.width('48%').padding({ bottom: 12 })
              .onClick(() => { this.openDetail(item); })
          }, (item: Media) => item.id + ':' +
            (this.collectionCards.find((card: DiscoverItem) => card.media.id === item.id)?.posterUri ?? ''))
        }.width('100%')
      } else {
        ForEach(this.collectionSlice(), (item: Media) => {
          if (this.collectionFilter === 'tracking') {
            Row({ space: 8 }) {
              Text(item.title).layoutWeight(1)
              Text('已看 ' + (this.cloud?.shows.find((show: ShowProgress) => show.id === item.id)?.watchedEpisodes ?? 0) + ' 集')
                .fontSize(13)
              Button('详情').fontSize(12).onClick(() => { this.openDetail(item); })
            }.width('100%')
          } else {
            this.libraryRow(item)
          }
        }, (item: Media) => item.id)
      }
      Row({ space: 8 }) {
        Button('上一页').layoutWeight(1).enabled(!this.collectionBusy && this.collectionPage > 1)
          .onClick(() => { this.goCollectionPage(this.collectionPage - 1); })
        Text(this.collectionPage + ' / ' + this.collectionPages()).fontSize(13)
        Button('下一页').layoutWeight(1).enabled(!this.collectionBusy && this.collectionPage < this.collectionPages())
          .onClick(() => { this.goCollectionPage(this.collectionPage + 1); })
      }.width('100%')
    }.width('100%')
  }

  private async loadProgress(item: Media): Promise<void> {
    if (this.progressBusy || this.authBusy || this.setupBusy || item.kind !== 'show') {
      return;
    }
    const revision = this.detailRevision;
    const clientId = this.clientId;
    this.progressBusy = true;
    this.progress = undefined;
    this.seasonNumber = -1;
    this.progressStatus = '正在读取真实分集进度…';
    try {
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Sign in required'); }
      const progress = await readSeriesProgress(item, session);
      if (revision === this.detailRevision && this.clientId === clientId &&
          traktAuth.isCurrent(clientId, session.generation)) {
        this.progress = progress;
        this.seasonNumber = progress.seasons.length > 0 ? progress.seasons[0].number : -1;
        this.progressStatus = '仅统计已播普通集数，不含隐藏季与特别篇。';
      }
    } catch (error) {
      if (revision === this.detailRevision) {
        this.progressStatus = '分集进度读取失败，请检查 Trakt 登录和网络。';
      }
    } finally {
      this.progressBusy = false;
    }
  }

  private async translateDetail(item: Media): Promise<void> {
    if (this.translationBusy || !this.clientId) { return; }
    const revision = this.detailRevision;
    const clientId = this.clientId;
    const cacheKey = clientId + ':' + item.id;
    const cached = this.translationCache.get(cacheKey);
    if (cached) {
      this.chineseTitle = cached.title;
      this.chineseOverview = cached.overview;
      this.translationStatus = cached.title || cached.overview ? '已应用可用中文翻译' : '暂无中文翻译，保留原文';
      return;
    }
    this.translationBusy = true;
    this.translationStatus = '正在读取中文译名…';
    try {
      const result = await readChinese(item, clientId);
      if (revision === this.detailRevision && this.clientId === clientId) {
        this.translationCache.set(cacheKey, result);
        this.chineseTitle = result.title;
        this.chineseOverview = result.overview;
        this.translationStatus = result.title || result.overview ? '已应用可用中文翻译' : '暂无中文翻译，保留原文';
      }
    } catch (error) {
      if (revision === this.detailRevision) { this.translationStatus = '中文翻译读取失败，保留原文'; }
    } finally {
      if (revision === this.detailRevision) { this.translationBusy = false; }
    }
  }

  @Builder
  seriesProgressView(item: Media) {
    Column({ space: 8 }) {
      Text('Trakt 云端分集进度（只读）').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Button(this.progressBusy ? '读取中…' : '读取分季分集进度')
        .enabled(this.signedIn && !this.progressBusy && !this.authBusy)
        .onClick(() => { this.loadProgress(item); })
      if (!this.signedIn) { Text('登录 Trakt 后查看观看状态').fontSize(13) }
      Text(this.progressStatus).fontSize(12).width('100%')
      if (this.progress && this.signedIn) {
        Text('已看 ' + this.progress.completed + ' / ' + this.progress.aired + ' 集').fontSize(16)
        if (this.progress.aired > 0) {
          Progress({ value: this.progress.completed, total: this.progress.aired,
            type: ProgressType.Linear }).width('100%')
        }
        ForEach(this.progress.seasons, (season: SeasonProgress) => {
          Column({ space: 6 }) {
            Button('第 ' + season.number + ' 季 · ' + season.completed + '/' + season.aired +
              (this.seasonNumber === season.number ? '  收起' : '  展开'))
              .width('100%').fontSize(14)
              .onClick(() => { this.seasonNumber = this.seasonNumber === season.number ? -1 : season.number; })
            if (this.seasonNumber === season.number) {
              ForEach(season.episodes, (episode: EpisodeProgress) => {
                Row() {
                  Text('第 ' + episode.number + ' 集').layoutWeight(1)
                  Text(episode.completed ? '已看' : '未看').fontSize(13)
                }.width('100%')
              }, (episode: EpisodeProgress) => episode.number.toString())
            }
          }.width('100%')
        }, (season: SeasonProgress) => season.number.toString())
      }
    }.width('100%')
  }

  private closeDetail(): void {
    this.detailRevision++;
    this.localSeries = undefined;
    this.localSeason = -1;
    this.localStatus = '';
    this.confirmSeason = -1;
    this.progress = undefined;
    this.progressStatus = '';
    this.seasonNumber = -1;
    this.translationBusy = false;
    this.chineseTitle = '';
    this.chineseOverview = '';
    this.translationStatus = '';
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
    if (this.tab === 'search' || this.tab === 'cloud' || this.tab === 'account') {
      this.navigate('progress');
      return true;
    }
    return false;
  }

  private async openDetail(item: Media, reload: boolean = false): Promise<void> {
    if (this.detailBusy || this.localBusy || this.setupBusy || !canReadDetails(item) || (!this.clientId && item.kind !== 'show')) {
      return;
    }
    this.closeDetail();
    const revision = ++this.detailRevision;
    const clientId = this.clientId;
    this.selectedMedia = item;
    this.detail = undefined;
    this.posterUri = '';
    this.detailBusy = true;
    this.detailStatus = '正在读取影视详情…';
    if (item.kind === 'show') { this.loadLocalEpisodes(item); }
    if (!clientId) {
      this.detailStatus = '离线本机详情';
      this.detailBusy = false;
      return;
    }
    try {
      const data = await readDetails(item, clientId, reload);
      if (revision !== this.detailRevision || this.clientId !== clientId) {
        return;
      }
      this.detail = data;
      this.detailStatus = '';
      this.translateDetail(item);
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

  private navigate(value: string): void {
    this.closeDetail();
    if (this.tab === 'discover' && value !== 'discover' && this.discoverBusy) { this.resetDiscover(); }
    if (this.tab === 'library' && value !== 'library' && this.collectionBusy) { this.resetCollection(); }
    this.tab = value;
    if (value === 'discover' && this.discoverItems.length === 0 && !this.discoverBusy) {
      this.loadDiscover();
    }
    if (value === 'library' && this.collectionGrid && this.collectionCards.length === 0 && !this.collectionBusy) {
      this.loadCollectionPosters();
    }
  }

  @Builder
  navigationTab(name: string, value: string, icon: Resource) {
    Column({ space: 4 }) {
      Image(icon).width(26).height(26)
        .fillColor(this.tab === value ? $r('app.color.showly_accent') : $r('app.color.showly_secondary'))
      Text(name).fontSize(12)
        .fontWeight(this.tab === value ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.tab === value ? $r('app.color.showly_accent') : $r('app.color.showly_secondary'))
    }.layoutWeight(1).height(54).justifyContent(FlexAlign.Center)
      .onClick(() => { this.navigate(value); })
  }

  @Builder
  headerAction(label: string, value: string) {
    Button(label).fontSize(12).height(34)
      .backgroundColor(this.tab === value ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.tab === value ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.navigate(value); })
  }

  @Builder
  detailPage(item: Media) {
    Column({ space: 12 }) {
      Button('返回').onClick(() => { this.closeDetail(); })
      Text(this.chineseTitle || (this.detail ? this.detail.title : item.title))
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
          Text(this.detailBusy ? '正在加载海报…' : '海报未显示').fontColor($r('app.color.showly_secondary'))
        }.width(180).height(270).justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
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
        Text(this.chineseOverview || this.detail.overview || '暂无简介').fontSize(15).width('100%')
        Button('重试中文资料').enabled(!this.translationBusy)
          .onClick(() => { this.translateDetail(item); })
        Text(this.translationStatus).fontSize(12)
      }
      if (item.kind === 'show') {
        this.localEpisodesView(item)
        Divider()
        this.seriesProgressView(item)
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
        this.headerAction('搜索', 'search')
        this.headerAction('云端', 'cloud')
        this.headerAction('设置', 'account')
      }.width('100%').padding(12).backgroundColor($r('app.color.showly_surface'))
      Divider().color($r('app.color.showly_line'))
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
        Column({ space: 14 }) {
          if (this.selectedMedia) {
            this.detailPage(this.selectedMedia)
          } else if (this.tab === 'progress') {
            this.progressView()
          } else if (this.tab === 'discover') {
            this.discoverView()
          } else if (this.tab === 'library') {
            this.collectionView()
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
            Text('默认手动同步；自动新增需主动授权，云端撤销仍需单独确认。').fontSize(13)
            this.syncPreviewView()
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
              Button('查看剧集进度').onClick(() => { this.navigate('progress'); })
              Button('清除云端预览').enabled(!this.cloudBusy).onClick(() => { this.clearCloud(); })
            }
          }
          } else {
            Text('账户与设置').fontSize(23).fontWeight(FontWeight.Bold)
            Text('外观').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 8 }) {
              this.themeButton('跟随系统', 'system')
              this.themeButton('浅色', 'light')
              this.themeButton('深色', 'dark')
            }.width('100%')
            Text(this.themeStatus).fontSize(12)
            Text('版本 0.8.5').fontSize(12).fontColor($r('app.color.showly_secondary'))
            Text('非官方应用，使用 Trakt，但未获 Trakt 认可或认证。')
              .fontSize(12).fontColor($r('app.color.showly_secondary'))
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
              Button('取消编辑').enabled(!this.setupBusy && !this.cloudBusy && !this.syncBusy)
                .onClick(() => { this.draftId = this.clientId; this.configuring = false; })
            }
            Text('也可暂不配置，继续使用下方离线清单。').fontSize(12)
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.showly_surface'))
        }
        Text(this.setupStatus).fontSize(13)
        if (this.clientId && !this.configuring) {
          Text(this.authStatus).fontSize(14)
          if (!this.signedIn && !this.authBusy) {
            Button('登录 Trakt').enabled(!this.setupBusy && !this.cloudBusy && !this.syncBusy).onClick(() => {
              this.clearCloud();
              this.beginSyncLogin();
            })
            Button('重试恢复登录').enabled(!this.setupBusy && !this.cloudBusy && !this.syncBusy).onClick(() => {
              traktAuth.restore(this.clientId, true);
            })
          }
          if (this.authBusy) {
            Button('取消当前操作').enabled(!this.setupBusy && !this.cloudBusy && !this.syncBusy).onClick(() => { traktAuth.cancel(); })
          } else {
            if (this.signedIn) {
              Button('断开本机登录').enabled(!this.setupBusy && !this.cloudBusy && !this.syncBusy).onClick(() => { this.disconnectSyncAccount(); })
            }
            Button('修改 Client ID').enabled(!this.setupBusy && !this.searching && !this.cloudBusy && !this.syncBusy).onClick(() => {
              this.draftId = this.clientId;
              this.configuring = true;
            })
            Button('清除 Client ID 与本机授权').enabled(!this.setupBusy && !this.searching && !this.cloudBusy && !this.syncBusy)
              .onClick(() => { this.clearClient(); })
          }
          Text('登录使用 Trakt 官方浏览器页面。同步模式在云端页设置；云端撤销需手动确认。').fontSize(12)

        }

          }
        }.width('100%').padding(16)
        }.width('100%').height('100%').align(Alignment.TopStart)
      }.width('100%').layoutWeight(1)
        .onRefreshing(() => { this.refreshPage(); })
      Divider().color($r('app.color.showly_line'))
      Row({ space: 6 }) {
        this.navigationTab('进度', 'progress', $r('app.media.nav_ic_check_menu'))
        this.navigationTab('发现', 'discover', $r('app.media.nav_ic_search'))
        this.navigationTab('收藏', 'library', $r('app.media.nav_ic_bookmark'))
      }.padding({ left: 12, right: 12, top: 4, bottom: 4 }).width('100%')
        .backgroundColor($r('app.color.showly_surface'))
    }.width('100%').height('100%').backgroundColor($r('app.color.showly_background'))
  }
}
