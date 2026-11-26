import { common } from '@kit.AbilityKit';
import { Media, mediaLabel, setWatched } from '../model/Media';
import { LibraryStore } from '../data/LibraryStore';
import { MediaStore } from '../data/MediaStore';
import { BackupData, RestorePlan, createBackup, exportBackup, selectBackup, planRestore, restoreBackup } from '../data/LocalBackup';
import { MediaRecord, migrateLegacy, isTraktMedia, applyLegacyEdit, setMediaIntent, inLocalWatchlist } from '../model/MediaState';
import { MediaPreview, MediaDifference, buildMediaPreview } from '../data/TraktMediaPreview';
import { syncSelectedMedia, reconcilePendingMedia } from '../data/TraktMediaSync';
import { checkpointEpisodes, checkpointMedia, adoptEpisodeCloud, adoptMediaCloud } from '../data/ThreeWaySync';
import { threeWayLabel } from '../model/ThreeWay';
import { NextShow, readNextShows, sortNextShows } from '../data/NextShows';
import { CalendarSnapshot, CalendarEntry, readCalendar, calendarWindow } from '../data/TraktCalendar';
import { PersonalMovie, PersonalMovieSnapshot, readPersonalMovies, readPersonalMovieDate } from '../data/TraktLibrary';
import { MovieCalendarItem, addLocalMovies, filterMovies, moviePage } from '../data/MovieCalendar';
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
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { reconcileQueue } from '../data/TraktQueueReconcile';
import { safeSyncError } from '../data/SyncDiagnostics';
import { APP_VERSION, RELEASES_URL } from '../config/BuildInfo';
import { UpdateInfo, UpstreamInfo, checkRelease, checkUpstream } from '../data/ReleaseUpdates';

@Entry
@Component
struct Index {
  @State title: string = '';
  @State updateBusy: boolean = false;
  @State updateStatus: string = '';
  @State availableUpdate?: UpdateInfo = undefined;
  @State upstreamInfo?: UpstreamInfo = undefined;
  @State upstreamStatus: string = '';
  @State tab: string = 'progress';
  private episodeStore?: EpisodeStore;
  @State @Watch('onRecoveryGateChanged') syncBusy: boolean = false;
  @State syncStatus: string = '';
  @State threeWayStatus: string = '';
  @State baselineReview: string = '';
  @State adoptEpisodeId: number = 0;
  @State adoptMediaKey: string = '';
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
  private pageVisible: boolean = false;
  private recoveryPending: boolean = false;
  private mediaRecoveryPending: boolean = false;
  private netListener?: connection.NetConnection;
  private netId: number = -1;
  private netValidated: boolean = false;
  @State networkStatus: string = '';
  @State showSyncLogs: boolean = false;
  @State queueConfirm: boolean = false;
  @State autoStatus: string = '';
  @State syncLogs: string[] = [];
  @State uploadStatus: string = '';
  @State episodeReady: boolean = false;
  @State episodeInitStatus: string = '';
  @State localSeries?: LocalSeriesState = undefined;
  @State localSeason: number = -1;
  @State @Watch('onRecoveryGateChanged') localBusy: boolean = false;
  @State localStatus: string = '';
  @State localRecent: Media[] = [];
  @State progressMode: string = 'next';
  @State nextShows: NextShow[] = [];
  @State nextStatus: string = '';
  @State nextSort: string = 'recent';
  @State nextFilter: string = 'remaining';
  @State nextQuery: string = '';
  @State nextPage: number = 1;
  @State calendarKind: string = 'show';
  @State calendarWeek: number = 0;
  @State calendarPage: number = 1;
  @State calendarBusy: boolean = false;
  @State calendarStatus: string = '';
  @State calendarData?: CalendarSnapshot = undefined;
  @State movieCalendarData?: PersonalMovieSnapshot = undefined;
  @State movieCalendarMode: string = 'future';
  @State movieCalendarQuery: string = '';
  private calendarRevision: number = 0;
  @State confirmSeason: number = -1;
  @State confirmWatched: boolean = true;
  @State backupBusy: boolean = false;
  @State backupStatus: string = '';
  @State backupReview: string = '';
  @State backupCanRestore: boolean = false;
  private backupData?: BackupData;
  private backupPlan?: RestorePlan;
  @State localCatalogNeedsVerification: boolean = false;
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
  @State @Watch('onRecoveryGateChanged') setupBusy: boolean = false;
  @State settingsReady: boolean = false;
  @State setupStatus: string = '';
  @State cloud?: CloudLibrary = undefined;
  @State @Watch('onRecoveryGateChanged') cloudBusy: boolean = false;
  @State cloudStatus: string = '';
  private settings?: ClientSettings;
  @StorageLink('traktAuthStatus') authStatus: string = '尚未登录 Trakt';
  @StorageLink('traktAuthBusy') @Watch('onRecoveryGateChanged') authBusy: boolean = false;
  @StorageLink('traktSignedIn') signedIn: boolean = false;
  @State items: Media[] = [];
  @State results: Media[] = [];
  @State ready: boolean = false;
  @State @Watch('onRecoveryGateChanged') saving: boolean = false;
  @State searching: boolean = false;
  @State libraryStatus: string = '';
  @State searchStatus: string = '';
  private mediaStore?: MediaStore;
  @State mediaRecords: MediaRecord[] = [];
  @State migrationStatus: string = '';
  @State mediaPreview?: MediaPreview = undefined;
  @State mediaPreviewStatus: string = '';
  @State mediaDomain: string = 'movie';
  @State mediaCategory: string = 'unknown';
  @State mediaPage: number = 1;
  @State mediaSelected?: MediaDifference = undefined;
  @State mediaWatchTime: string = '';
  @State mediaSyncStatus: string = '';
  @State mediaLogs: string[] = [];
  @State showMediaLogs: boolean = false;

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
    this.initializeMedia(context);
    this.initializeEpisodes(context);
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.startNetworkListener();
    if (this.backupBusy) { return; }
    this.requestMediaRecovery();
    if (this.autoActive()) { this.requestRecovery(); }
    else if (this.clientId && !this.setupBusy && !this.cloudBusy && !this.syncBusy) {
      traktAuth.restore(this.clientId);
    }
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.recoveryPending = false;
    this.mediaRecoveryPending = false;
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.recoveryPending = false;
    this.mediaRecoveryPending = false;
    const listener = this.netListener;
    this.netListener = undefined;
    if (listener) {
      try { listener.unregister((error: BusinessError) => {}); } catch (error) {}
    }
  }

  private startNetworkListener(): void {
    if (this.netListener) { return; }
    try {
      const listener = connection.createNetConnection();
      this.netListener = listener;
      listener.on('netAvailable', (handle: connection.NetHandle) => {
        if (this.netListener !== listener) { return; }
        if (this.netId !== handle.netId) {
          this.netId = handle.netId;
          this.netValidated = false;
          this.networkStatus = '网络已连接，等待 Trakt 核验';
          this.requestRecovery();
          this.requestMediaRecovery();
        }
      });
      listener.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        if (this.netListener !== listener) { return; }
        const validated = info.netCap.networkCap?.includes(connection.NetCap.NET_CAPABILITY_VALIDATED) === true;
        const changed = this.netId !== info.netHandle.netId || (!this.netValidated && validated);
        this.netId = info.netHandle.netId;
        this.netValidated = validated;
        if (changed && validated) {
          this.networkStatus = '系统网络已验证，正在核对待同步记录';
          this.requestRecovery();
          this.requestMediaRecovery();
        }
      });
      listener.on('netLost', (handle: connection.NetHandle) => {
        if (this.netListener !== listener || this.netId !== handle.netId) { return; }
        this.netId = -1;
        this.netValidated = false;
        this.networkStatus = '网络断开；本机记录保留';
      });
      listener.register((error: BusinessError) => {
        if (this.netListener !== listener) {
          if (!error) { try { listener.unregister((failure: BusinessError) => {}); } catch (failure) {} }
          return;
        }
        if (error) {
          this.netListener = undefined;
          this.networkStatus = '网络监听注册失败：SDK 错误码 ' + error.code + '；仍可手动处理队列';
        }
      });
    } catch (error) {
      this.netListener = undefined;
      this.networkStatus = '网络监听不可用；仍可手动处理队列';
    }
  }

  private requestRecovery(): void {
    if (this.backupBusy || !this.pageVisible || !this.autoActive() || !this.episodeReady) { return; }
    this.recoveryPending = true;
    this.onRecoveryGateChanged();
  }

  // A busy auth/DB/sync operation no longer drops the network-resume event.
  // Coalesce to a single pending event, not a periodic retry loop.
  private onRecoveryGateChanged(): void {
    if (this.backupBusy || !this.pageVisible || this.syncBusy || this.localBusy || this.cloudBusy ||
        this.authBusy || this.setupBusy) { return; }
    if (this.recoveryPending && this.autoActive() && this.episodeReady) {
      this.recoveryPending = false;
      this.resumeQueued();
      return;
    }
    if (this.mediaRecoveryPending && !this.saving) {
      this.mediaRecoveryPending = false;
      this.recoverMediaPending();
    }
  }

  private requestMediaRecovery(): void {
    if (this.backupBusy || !this.pageVisible || !this.ready || !this.mediaStore || !this.syncBound || !this.syncAccount ||
        !traktAuth.isCurrent(this.clientId, this.syncAccount.generation)) { return; }
    this.mediaRecoveryPending = true;
    this.onRecoveryGateChanged();
  }

  private async recoverMediaPending(): Promise<void> {
    const store = this.mediaStore;
    const binding = this.episodeStore;
    const account = this.syncAccount;
    const clientId = this.clientId;
    if (!store || !binding || !account || !this.ready || !this.pageVisible || !this.syncBound ||
        this.syncBusy || this.saving || this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, account.generation)) { return; }
    const session = traktAuth.session(clientId);
    if (!session) { return; }
    this.syncBusy = true;
    try {
      if (!(await store.pendingTargets(account.uuid)).length) { return; }
      this.mediaSelected = undefined;
      this.mediaWatchTime = '';
      this.mediaPreview = undefined;
      this.mediaSyncStatus = '正在自动只读核对已保留的电影与待看操作…';
      const result = await reconcilePendingMedia(store, binding, session, account.uuid);
      if (this.syncAccount?.uuid === account.uuid && traktAuth.isCurrent(clientId, session.generation)) {
        this.mediaSyncStatus = result.message;
        this.mediaPreviewStatus = '操作凭证已核对；需要时重新生成差异预览。';
      }
    } catch (error) {
      this.mediaSyncStatus = '自动只读核对中断：' + safeSyncError(error as Error) + '；不会重发。';
    } finally {
      try {
        if (this.syncAccount?.uuid === account.uuid && traktAuth.isCurrent(clientId, session.generation)) {
          this.mediaLogs = await store.operationLogs(account.uuid);
        }
      } catch (error) {}
      this.syncBusy = false;
    }
  }

  private async initializeMedia(context: common.UIAbilityContext): Promise<void> {
    this.ready = false;
    this.migrationStatus = '正在检查本机收藏及迁移状态…';
    try {
      const legacy = new LibraryStore(context).load();
      // Read-only legacy projection while the new database opens.
      this.items = legacy;
      this.mediaRecords = migrateLegacy(legacy);
      const store = await MediaStore.open(context, legacy);
      const records = await store.load();
      this.mediaStore = store;
      this.invalidateMovieCalendar();
      this.mediaRecords = records;
      this.items = records.map((record: MediaRecord) => record.media);
      this.resetCollection();
      this.migrationStatus = '收藏数据库已就绪 · ' + records.length + ' 部；旧版 Preferences 保留。';
      this.ready = true;
    } catch (error) {
      this.migrationStatus = '收藏迁移或读取失败；仅显示可读的旧版快照，已停止收藏写入。请勿卸载或清除数据。';
      this.libraryStatus = this.migrationStatus;
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
      if (this.tab === 'progress' && this.progressMode === 'next') { await this.loadNextShows(); }
      this.requestRecovery();
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
        this.localCatalogNeedsVerification = await store.needsCatalogVerification(item.id);
        if (this.localSeason < 0 && state.seasons.length > 0) { this.localSeason = state.seasons[0].number; }
      }
      if (refresh && clientId) {
        const catalog = await fetchEpisodeCatalog(item, clientId);
        if (revision !== this.detailRevision || this.clientId !== clientId) { return; }
        this.invalidateSync();
        await store.saveCatalog(catalog);
        this.invalidateNextShows();
        state = await store.read(item.id);
      }
      if (revision === this.detailRevision) {
        this.localSeries = state;
        this.localCatalogNeedsVerification = state ? await store.needsCatalogVerification(item.id) : false;
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
    if (this.localCatalogNeedsVerification) {
      this.localStatus = '备份恢复的目录需要联网更新后才能修改分集状态。';
      return;
    }
    const revision = this.detailRevision;
    this.localBusy = true;
    this.confirmSeason = -1;
    const auto = this.autoActive() ? this.autoConsent : undefined;
    let saved = false;
    try {
      this.invalidateSync();
      await store.mark(item.id, ids, watched, watched && auto ? auto.uuid : '');
      this.invalidateNextShows();
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
    if (saved && watched && auto && this.autoActive()) { this.requestRecovery(); }
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
          if (this.localCatalogNeedsVerification) { Text('备份目录仅供本机查看，联网更新分集目录后才可编辑。').fontSize(12).width('100%') }
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
                  Button('整季已看').layoutWeight(1).enabled(!this.localCatalogNeedsVerification && !this.localBusy && !this.syncBusy && season.completed < season.episodes.length)
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
                    Button(entry.watched ? '撤销已看' : '标记已看').fontSize(12).enabled(!this.localCatalogNeedsVerification && !this.localBusy && !this.syncBusy)
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

  private async checkAppUpdate(): Promise<void> {
    if (this.updateBusy) { return; }
    this.updateBusy = true;
    this.availableUpdate = undefined;
    this.upstreamInfo = undefined;
    this.updateStatus = '正在检查鸿蒙预览版…';
    this.upstreamStatus = '';
    try {
      this.availableUpdate = await checkRelease();
      this.updateStatus = this.availableUpdate ? '发现新版本 ' + this.availableUpdate.version :
        '未发现比当前版本更新且完整发布的鸿蒙预览包。';
    } catch (error) {
      this.updateStatus = '版本检查失败，请检查 GitHub 连通性或 API 限额。';
    }
    try {
      this.upstreamInfo = await checkUpstream();
      this.upstreamStatus = this.upstreamInfo.changed ?
        '检测到 Android 上游变化，尚未自动移植 · ' + this.upstreamInfo.sha.substring(0, 12) :
        'Android 上游与本版记录的检测基线一致 · ' + this.upstreamInfo.sha.substring(0, 12);
    } catch (error) {
      this.upstreamStatus = '上游版本检查失败，不影响当前应用。';
    } finally { this.updateBusy = false; }
  }

  private async openReleasePage(upstream: boolean = false): Promise<void> {
    const target = upstream ? this.upstreamInfo?.url : this.availableUpdate?.url ?? RELEASES_URL;
    if (!target) { return; }
    try {
      await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: target });
    } catch (error) {
      this.updateStatus = '无法打开浏览器，可从 GitHub Releases 手动下载。';
    }
  }

  private async openFeatureAudit(): Promise<void> {
    try {
      await this.context().startAbility({ action: 'ohos.want.action.viewData',
        uri: 'https://github.com/NoRegret-L/showly/blob/harmonyos-v0.9.1-b20/harmonyos/docs/FEATURE_AUDIT.md' });
    } catch (error) {
      this.updateStatus = '无法打开功能审计报告，请从鸿蒙 GitHub 发布页进入。';
    }
  }

  private backupAvailable(): boolean {
    return this.ready && this.episodeReady && !!this.mediaStore && !!this.episodeStore &&
      !this.backupBusy && !this.syncBusy && !this.saving && !this.localBusy && !this.cloudBusy &&
      !this.authBusy && !this.setupBusy;
  }

  private beginBackup(): void {
    this.backupBusy = true;
    this.syncBusy = true;
  }

  private endBackup(): void {
    // Picker foreground/network events must not trigger existing auto uploads
    // as a side effect of a local-only backup operation.
    this.recoveryPending = false;
    this.mediaRecoveryPending = false;
    this.syncBusy = false;
    this.backupBusy = false;
  }

  private clearBackupReview(): void {
    this.backupData = undefined;
    this.backupPlan = undefined;
    this.backupCanRestore = false;
    this.backupReview = '';
  }

  private backupError(error: Error): string {
    const message = error.message;
    if (typeof message === 'string' &&
        /^(Unsupported backup (?:schema|file)|Backup checksum mismatch|Invalid backup (?:title|title state|show|show identity|size \(maximum 32 MiB\))|Invalid watched episode IDs|Duplicate backup (?:title|show)|Duplicate cross-show episode ID|Backup exceeds 32 MiB|Incomplete backup (?:read|write)|Backup file readback mismatch|Restore preview changed|Episode restore transaction failed)$/.test(message)) {
      return message;
    }
    return safeSyncError(error);
  }

  private async saveLocalBackup(): Promise<void> {
    const media = this.mediaStore;
    const episodes = this.episodeStore;
    if (!media || !episodes || !this.backupAvailable()) { return; }
    this.clearBackupReview();
    this.beginBackup();
    this.backupStatus = '正在生成本机快照…';
    try {
      const snapshot = await createBackup(media, episodes);
      const saved = await exportBackup(this.context(), snapshot);
      this.backupStatus = saved ? '备份文件已保存并回读校验 · ' + snapshot.titles.length + ' 部收藏 / ' +
        snapshot.shows.length + ' 部剧集目录。请妥善保管文件。' : '已取消保存。';
    } catch (error) {
      this.backupStatus = '备份未确认成功：' + this.backupError(error as Error) + '；请勿使用可能不完整的文件。';
    } finally { this.endBackup(); }
  }

  private async reviewLocalBackup(): Promise<void> {
    const media = this.mediaStore;
    const episodes = this.episodeStore;
    if (!media || !episodes || !this.backupAvailable()) { return; }
    this.clearBackupReview();
    this.beginBackup();
    this.backupStatus = '请选择 Showly 鸿蒙备份 JSON 文件…';
    try {
      const data = await selectBackup(this.context());
      if (!data) { this.backupStatus = '已取消选择。'; return; }
      const plan = await planRestore(data, media, episodes);
      this.backupData = data;
      this.backupPlan = plan;
      this.backupCanRestore = plan.titles.length > 0 || plan.shows.length > 0;
      this.backupReview = '备份时间：' + new Date(data.createdAt).toLocaleString() +
        '\n收藏新增 ' + plan.titles.length + ' 部，跳过已有 ' + plan.skippedTitles + ' 部' +
        '\n分集目录新增 ' + plan.shows.length + ' 部，跳过已有 ' + plan.skippedShows + ' 部' +
        '\n恢复已看分集 ' + plan.watchedEpisodes + ' 集（仅本机）';
      this.backupStatus = this.backupCanRestore ? '文件校验通过。请核对预览；尚未修改数据。' :
        '文件校验通过；已有记录全部保留，没有需要补充的内容。';
    } catch (error) {
      this.clearBackupReview();
      this.backupStatus = '备份读取或校验失败：' + this.backupError(error as Error) + '；未修改数据。';
    } finally { this.endBackup(); }
  }

  private async applyLocalBackup(): Promise<void> {
    const media = this.mediaStore;
    const episodes = this.episodeStore;
    const data = this.backupData;
    const plan = this.backupPlan;
    if (!media || !episodes || !data || !plan || !this.backupCanRestore || !this.backupAvailable()) { return; }
    this.beginBackup();
    this.backupStatus = '正在补充缺失的本机数据…';
    this.clearBackupReview();
    try {
      const result = await restoreBackup(data, plan, media, episodes);
      this.backupStatus = '恢复完成：新增收藏 ' + result.titles + ' 部，新增分集目录 ' + result.shows +
        ' 部；原有记录未覆盖，未发送 Trakt 写入。';
    } catch (error) {
      this.backupStatus = '恢复中断：' + this.backupError(error as Error) +
        '；可能已有部分本机记录提交。重新选择同一文件可补充剩余内容，既有记录不会覆盖。';
    } finally {
      try {
        const records = await media.load();
        this.invalidateMovieCalendar();
        this.mediaRecords = records;
        this.items = records.map((record: MediaRecord) => record.media);
        this.migrationStatus = '收藏数据库已就绪 · ' + records.length + ' 部；旧版 Preferences 保留。';
        this.resetCollection();
        this.invalidateNextShows();
        this.localRecent = await episodes.recent();
        this.localSeries = undefined;
        this.localCatalogNeedsVerification = false;
        this.invalidateSync();
        await this.reloadQueue();
      } catch (error) {
        this.ready = false;
        this.backupStatus += '；本机回读失败，请重启检查，不要清除数据。';
      }
      this.endBackup();
    }
  }

  @Builder
  backupView() {
    Column({ space: 8 }) {
      Text('本地备份与恢复').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
      Text('导出收藏、待看和本机可见的分集进度及目录。文件不加密，请保存在可信位置；不含 OAuth、API 密钥、账户绑定、同步凭证或待上传队列。')
        .fontSize(12).width('100%')
      Button('导出本地备份 JSON').enabled(this.backupAvailable()).onClick(() => { this.saveLocalBackup(); })
      Button('选择备份并预览恢复').enabled(this.backupAvailable()).onClick(() => { this.reviewLocalBackup(); })
      if (this.backupStatus) { Text(this.backupStatus).fontSize(13).width('100%') }
      if (this.backupReview) {
        Text(this.backupReview).fontSize(13).width('100%')
        Text('只补充缺失条目，现有收藏和整部剧集目录不覆盖。恢复后的状态不是同步意图；分集目录须联网更新后才能编辑。')
          .fontSize(12).width('100%')
        Row({ space: 8 }) {
          Button('关闭预览').layoutWeight(1).enabled(!this.backupBusy).onClick(() => { this.clearBackupReview(); })
          Button('确认补充恢复').layoutWeight(1).enabled(this.backupCanRestore && this.backupAvailable())
            .onClick(() => { this.applyLocalBackup(); })
        }.width('100%')
      }
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.showly_surface'))
  }

  @Builder
  updateView() {
    Column({ space: 8 }) {
      Text('版本与更新').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
      Text('当前版本 ' + APP_VERSION + ' · 未签名个人预览版 · 0.9.3c.1').fontSize(13)
        .fontColor($r('app.color.showly_secondary')).width('100%')
      Text('v0.9.3c.1 个人电影上映日历修复版。').fontSize(12).width('100%')
      Button('查看功能审计与验收计划').onClick(() => { this.openFeatureAudit(); })
      Button(this.updateBusy ? '检查中…' : '检查更新').enabled(!this.updateBusy)
        .onClick(() => { this.checkAppUpdate(); })
      if (this.updateStatus) { Text(this.updateStatus).fontSize(13).width('100%') }
      if (this.availableUpdate) {
        Text('新版本 ' + this.availableUpdate.version + ' · SHA-256 ' + this.availableUpdate.digest.substring(7))
          .fontSize(12).width('100%')
      }
      Button(this.availableUpdate ? '打开新版本下载页' : '打开鸿蒙发布页')
        .onClick(() => { this.openReleasePage(); })
      Text('仅检查公开 GitHub 发布信息，不发送 Trakt 凭据或观看记录。不自动下载、安装或卸载；请核对哈希并用原安装方式覆盖安装。')
        .fontSize(12).width('100%')
      if (this.upstreamStatus) { Text(this.upstreamStatus).fontSize(12).width('100%') }
      if (this.upstreamInfo) {
        Button('查看 Android 上游变更').onClick(() => { this.openReleasePage(true); })
      }
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.showly_surface'))
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
    this.clearThreeWayReview();
    this.threeWayStatus = '';
    this.mediaRecoveryPending = false;
    this.mediaSelected = undefined;
    this.mediaWatchTime = '';
    this.mediaSyncStatus = '';
    this.mediaLogs = [];
    this.mediaPreview = undefined;
    this.mediaPreviewStatus = '';
    this.mediaPage = 1;
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
      if (this.syncBound) { this.requestMediaRecovery(); }
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
      this.requestMediaRecovery();
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
    this.clearThreeWayReview();
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

  private async refreshSyncLogs(): Promise<void> {
    const store = this.episodeStore;
    const account = this.syncAccount;
    if (!store || !account || !this.syncBound ||
        !traktAuth.isCurrent(this.clientId, account.generation)) { return; }
    try { this.syncLogs = await store.syncLogs(account.uuid); } catch (error) {
      this.autoStatus = '日志读取失败：' + safeSyncError(error as Error);
    }
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
        this.recoveryPending = false;
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
    if (enabled && this.autoActive()) { this.requestRecovery(); }
  }

  // Before an explicit credential change, disable persisted authorization.
  // Keep queued events; they remain bound to the original UUID.
  private async revokeAuto(): Promise<void> {
    this.recoveryPending = false;
    this.autoConsent = undefined;
    if (this.episodeStore) { await this.episodeStore.clearAutoConsent(); }
    this.autoStatus = '自动新增已关闭；旧队列仍保留。';
  }

  private async resumeQueued(manual: boolean = false): Promise<void> {
    const store = this.episodeStore;
    const clientId = this.clientId;
    const consent = this.autoConsent;
    if (!store || !this.episodeReady || !clientId || !this.pageVisible || this.syncBusy || this.localBusy ||
        this.cloudBusy || this.authBusy || this.setupBusy || (!manual && !this.autoActive())) { return; }
    if (manual && (!this.syncAccount || !this.syncBound || !this.queueConfirm)) { return; }
    const expected = manual ? this.syncAccount?.uuid : consent?.uuid;
    if (!expected) { return; }
    this.syncBusy = true;
    this.queueConfirm = false;
    this.autoStatus = '正在读取待同步队列…';
    let stage = '读取本机队列';
    let ids: number[] = [];
    try {
      let pending = await store.queueEntries(expected);
      ids = pending.map((entry: QueueEntry) => entry.episodeId);
      if (!pending.length) {
        this.queueRows = [];
        this.autoStatus = '没有待同步新增。';
        return;
      }
      stage = '恢复登录';
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Offline or sign-in required'); }
      stage = '核对账户';
      const account = await readSyncAccount(session);
      if (account.uuid !== expected || this.clientId !== clientId || await store.boundAccount() !== expected) {
        if (!manual) { await this.revokeAuto(); }
        throw new Error('Account mismatch');
      }
      this.syncAccount = account;
      this.syncBound = true;
      const canSend = (): boolean => {
        return this.pageVisible && this.clientId === clientId &&
          traktAuth.isCurrent(clientId, session.generation) &&
          (manual || (this.autoActive() && this.autoConsent?.uuid === expected));
      };
      let reconciled = 0;
      if (pending.some((entry: QueueEntry) => entry.blocked)) {
        stage = '只读核对受保护队列';
        this.autoStatus = '正在只读核对已有凭证，不会重复上传…';
        const checked = await reconcileQueue(store, session, expected, pending);
        reconciled += checked.completed.length;
        pending = checked.remaining;
        if (checked.completed.length) {
          await store.logSync(expected, 'reconcile', checked.completed,
            '只读核对确认云端存在 ' + checked.completed.length + ' 集，已清理队列；未重发。');
        }
      }
      const eligible = pending.filter((entry: QueueEntry) => !entry.blocked);
      if (!eligible.length) {
        this.autoStatus = '只读核对完成：已清理 ' + reconciled + ' 集；剩余 ' + pending.length +
          ' 集受保护或目录异常，未发送新增请求。';
        return;
      }
      stage = '上传未发送的新增分集';
      if (!canSend()) { throw new Error('Foreground ended'); }
      this.autoStatus = '正在校验并处理 ' + eligible.length + ' 集未发送记录…';
      const result = await uploadBatch(store, session, expected,
        eligible.map((entry: QueueEntry) => entry.episodeId), new Date().toISOString(),
        'queue', undefined, eligible, canSend);
      stage = '保存已完成队列';
      for (const entry of eligible) {
        if (result.completedIds.includes(entry.episodeId)) { await store.finishQueue(expected, entry); }
      }
      this.autoStatus = result.message;
      // Only one additional fresh READ, never a second POST. If the app exits
      // or this read fails, the next foreground/network event can reconcile.
      const remaining = await store.queueEntries(expected);
      const attempted = remaining.filter((entry: QueueEntry) => entry.blocked &&
        eligible.some((old: QueueEntry) => old.episodeId === entry.episodeId && old.seq === entry.seq));
      if (attempted.length > 0 && this.pageVisible) {
        stage = '上传后补充只读核对';
        const checked = await reconcileQueue(store, session, expected, attempted);
        reconciled += checked.completed.length;
        await store.logSync(expected, 'reconcile', checked.completed,
          '上传后只读核对：确认 ' + checked.completed.length + ' 集，未重发；剩余队列 ' + checked.remaining.length + ' 集。');
      }
      if (reconciled) { this.autoStatus += ' 只读补充核对清理 ' + reconciled + ' 集。'; }
    } catch (error) {
      this.autoStatus = '队列未完成 · 阶段：' + stage + ' · ' + safeSyncError(error as Error) +
        '。本机记录保留，受保护项不会重发。';
      try { await store.logSync(expected, 'queue', ids, this.autoStatus); } catch (failure) {}
    } finally {
      try {
        await this.reloadQueue();
        this.syncLogs = await store.syncLogs(expected);
      } catch (error) {
        this.autoStatus += '；本机队列或日志刷新失败：' + safeSyncError(error as Error);
      }
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
      this.invalidateNextShows();
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

  private clearThreeWayReview(): void {
    this.baselineReview = '';
    this.adoptEpisodeId = 0;
    this.adoptMediaKey = '';
  }

  private threeWayAvailable(): boolean {
    return !!this.syncAccount && this.syncBound && this.episodeReady && this.ready && this.pageVisible &&
      !this.syncBusy && !this.saving && !this.localBusy && !this.cloudBusy && !this.authBusy && !this.setupBusy &&
      !this.backupBusy && traktAuth.isCurrent(this.clientId, this.syncAccount.generation);
  }

  private episodeCheckpointCount(): number {
    return this.syncPreview?.rows.filter((row: SyncDifference) => row.kind === 'match').length ?? 0;
  }

  private mediaCheckpointCount(): number {
    return this.mediaPreview?.rows.filter((row: MediaDifference) => row.domain === this.mediaDomain &&
      row.category === 'match' && !row.operation).length ?? 0;
  }

  private async confirmCommonBaseline(domain: string): Promise<void> {
    const binding = this.episodeStore;
    const store = this.mediaStore;
    const account = this.syncAccount;
    const session = traktAuth.session(this.clientId);
    const ep = this.syncPreview;
    const media = this.mediaPreview;
    if (!binding || !account || !session || !this.threeWayAvailable() || this.baselineReview !== domain) { return; }
    if (domain === 'episode' ? (!ep || ep.account.uuid !== account.uuid) :
        (!store || !media || media.account.uuid !== account.uuid || domain !== this.mediaDomain)) { return; }
    this.syncBusy = true;
    this.clearThreeWayReview();
    this.threeWayStatus = '正在重新读取云端并校验已一致的条目…';
    try {
      let count = 0;
      if (domain === 'episode' && ep) {
        count = await checkpointEpisodes(binding, session, ep);
      } else if (store && media) {
        count = await checkpointMedia(store, binding, session, media, domain);
      }
      this.threeWayStatus = '已保存 ' + count + ' 条共同基线；未修改观看记录、待看、队列或 Trakt。请重新生成预览。';
    } catch (error) {
      this.threeWayStatus = '基线保存未确认：' + safeSyncError(error as Error) + '；请重新生成预览。';
    } finally {
      this.syncPreview = undefined;
      this.mediaPreview = undefined;
      this.mediaSelected = undefined;
      this.batchIds = [];
      this.batchConfirm = false;
      this.importConfirm = false;
      this.uploadSelectedId = 0;
      this.removeSelectedId = 0;
      this.syncBusy = false;
    }
  }

  private async confirmAdoptEpisode(): Promise<void> {
    const store = this.episodeStore;
    const preview = this.syncPreview;
    const account = this.syncAccount;
    const session = traktAuth.session(this.clientId);
    const id = this.adoptEpisodeId;
    if (!store || !preview || !account || !session || !this.threeWayAvailable() || preview.account.uuid !== account.uuid) { return; }
    const row = preview.rows.find((item: SyncDifference) => item.episodeId === id && item.kind === 'remote');
    if (!row) { return; }
    this.syncBusy = true;
    this.clearThreeWayReview();
    this.threeWayStatus = '正在校验所选分集的最新云端状态…';
    try {
      await adoptEpisodeCloud(store, session, preview, row);
      this.invalidateNextShows();
      this.threeWayStatus = '已采用云端分集状态并保存共同基线；仅修改本机，不上传或删除云端历史。';
      this.localRecent = await store.recent();
      this.localSeries = undefined;
      await this.reloadQueue();
    } catch (error) {
      this.threeWayStatus = '采用云端状态未确认：' + safeSyncError(error as Error) + '；请重新读取本机并生成预览。';
    } finally {
      this.syncPreview = undefined;
      this.batchIds = [];
      this.batchConfirm = false;
      this.importConfirm = false;
      this.uploadSelectedId = 0;
      this.removeSelectedId = 0;
      this.syncBusy = false;
    }
  }

  private async confirmAdoptMedia(): Promise<void> {
    const store = this.mediaStore;
    const binding = this.episodeStore;
    const preview = this.mediaPreview;
    const account = this.syncAccount;
    const session = traktAuth.session(this.clientId);
    const key = this.adoptMediaKey;
    if (!store || !binding || !preview || !account || !session || !this.threeWayAvailable() ||
        preview.account.uuid !== account.uuid) { return; }
    const row = preview.rows.find((item: MediaDifference) => item.domain + ':' + item.id === key && item.category === 'remote');
    if (!row) { return; }
    this.syncBusy = true;
    this.clearThreeWayReview();
    this.threeWayStatus = '正在校验所选电影或待看条目的最新云端状态…';
    try {
      const records = await adoptMediaCloud(store, binding, session, preview, row);
      this.invalidateMovieCalendar();
      this.mediaRecords = records;
      this.items = records.map((record: MediaRecord) => record.media);
      this.resetCollection();
      this.threeWayStatus = '已采用云端状态并保存共同基线；仅修改所选本机状态域，未写入 Trakt。';
    } catch (error) {
      this.threeWayStatus = '采用云端状态未确认：' + safeSyncError(error as Error) + '；请重新生成预览。';
      try {
        const records = await store.load();
        this.invalidateMovieCalendar();
        this.mediaRecords = records;
        this.items = records.map((record: MediaRecord) => record.media);
        this.resetCollection();
      } catch (failure) { this.ready = false; }
    } finally {
      this.mediaPreview = undefined;
      this.mediaSelected = undefined;
      this.mediaWatchTime = '';
      this.syncBusy = false;
    }
  }

  @Builder
  commonBaselineView(domain: string, count: number) {
    Column({ space: 6 }) {
      Text('三方共同基线：只保存已明确一致的状态，不将未知记录或云端独有条目当成删除。')
        .fontSize(12).width('100%')
      Button('保存一致状态为共同基线 · ' + count + ' 条').fontSize(13)
        .enabled(this.threeWayAvailable() && count > 0)
        .onClick(() => { this.clearThreeWayReview(); this.baselineReview = domain; })
      if (this.baselineReview === domain) {
        Text('确认记录这 ' + count + ' 条双方一致的状态？仅保存比较依据，不创建观看历史或同步权限。')
          .fontSize(12).width('100%')
        Row({ space: 8 }) {
          Button('取消').layoutWeight(1).onClick(() => { this.clearThreeWayReview(); })
          Button('确认保存基线').layoutWeight(1).enabled(this.threeWayAvailable())
            .onClick(() => { this.confirmCommonBaseline(domain); })
        }.width('100%')
      }
    }.width('100%')
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
      .onClick(() => { this.clearThreeWayReview(); this.syncFilter = value; this.syncPage = 1; this.removeSelectedId = 0; this.uploadSelectedId = 0; })
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
      if (this.threeWayStatus) { Text(this.threeWayStatus).fontSize(13).width('100%') }
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
          if (this.networkStatus) { Text(this.networkStatus).fontSize(12).width('100%') }
          if (this.autoStatus) { Text(this.autoStatus).fontSize(13).width('100%') }
          Text('待同步队列：' + this.queueRows.length + ' 集（含受保护项）').fontSize(15).width('100%')
          ForEach(this.queueRows.slice(0, this.collectionPageSize), (entry: QueueEntry) => {
            Text(entry.label + ' · ' + (entry.blocked ? entry.protection : '等待核验'))
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
            .onClick(() => { this.showSyncLogs = !this.showSyncLogs; if (this.showSyncLogs) { this.refreshSyncLogs(); } })
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
            ' · 撤销冲突 ' + this.syncPreview.conflicts + ' · 目录异常 ' + this.syncPreview.unknown +
            ' · 仅云端变化 ' + this.syncPreview.remoteChanges)
            .fontSize(14).width('100%')
          this.commonBaselineView('episode', this.episodeCheckpointCount())
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
          Row({ space: 4 }) { this.syncFilterButton('仅云端变化', 'remote') }.width('100%')
          if (this.visibleSyncRows().length === 0) { Text('本分类没有记录').fontSize(13).width('100%') }
          ForEach(this.syncSlice(), (row: SyncDifference) => {
            Column({ space: 4 }) {
              Text(row.label).fontSize(14).width('100%')
              Text('本机 ' + (row.localWatched ? '已看' : '撤销') + ' / 云端 ' +
                (row.cloudWatched ? '已看' : '无已看记录')).fontSize(12).width('100%')
                .fontColor($r('app.color.showly_secondary'))
              Text(threeWayLabel(row.threeWay, row.baseline)).fontSize(12).width('100%')
              if (row.kind === 'remote' && row.threeWay === 'remote') {
                Button('采用云端状态（仅本机）').fontSize(12).enabled(this.threeWayAvailable())
                  .onClick(() => { this.clearThreeWayReview(); this.adoptEpisodeId = row.episodeId; })
                if (this.adoptEpisodeId === row.episodeId) {
                  Text('确认将本机此集设为' + (row.cloudWatched ? '已看' : '未看') + '？原有云端历史和保护凭证不变。').fontSize(12).width('100%')
                  Row({ space: 8 }) {
                    Button('取消').layoutWeight(1).onClick(() => { this.clearThreeWayReview(); })
                    Button('确认采用').layoutWeight(1).enabled(this.threeWayAvailable()).onClick(() => { this.confirmAdoptEpisode(); })
                  }.width('100%')
                }
              }
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
    this.resetCalendar();
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
      const saved = await this.save(next, 'import');
      this.cloudStatus = saved ? '已导入 ' + added + ' 部新影视，已有本机记录未覆盖。' :
        '导入保存失败，请重启应用检查本机记录。';
    } finally {
      this.cloudBusy = false;
    }
  }

  private async persistMedia(records: MediaRecord[]): Promise<boolean> {
    const store = this.mediaStore;
    if (!this.ready || this.saving || this.syncBusy || !store) { return false; }
    this.saving = true;
    this.clearThreeWayReview();
    this.mediaSelected = undefined;
    this.mediaWatchTime = '';
    this.mediaPreview = undefined;
    this.mediaPreviewStatus = '';
    this.mediaPage = 1;
    try {
      const verified = await store.save(records);
      this.invalidateMovieCalendar();
      this.mediaRecords = verified;
      this.items = verified.map((record: MediaRecord) => record.media);
      this.resetCollection();
      if (this.collectionGrid && this.tab === 'library' && !this.selectedMedia) { this.loadCollectionPosters(); }
      this.libraryStatus = '已保存到本机；未修改 Trakt';
      this.migrationStatus = '收藏数据库已就绪 · ' + verified.length + ' 部；旧版 Preferences 保留。';
      return true;
    } catch (error) {
      this.libraryStatus = '保存或回读失败，已停止写入；请重启应用检查记录，不要清除数据。';
      this.ready = false;
      return false;
    } finally { this.saving = false; }
  }

  private async save(next: Media[], origin: string = 'toggle'): Promise<boolean> {
    if (!this.ready || this.saving || this.syncBusy) { return false; }
    try {
      return await this.persistMedia(applyLegacyEdit(this.mediaRecords, next, origin));
    } catch (error) {
      this.libraryStatus = '收藏状态校验失败，未保存。';
      return false;
    }
  }

  private add(item: Media): void {
    if (!this.ready || this.saving || this.cloudBusy || this.syncBusy ||
        this.items.some((value: Media) => value.id === item.id)) { return; }
    this.save([...this.items, item], 'add');
  }

  private mediaIntent(item: Media, domain: string): string {
    const record = this.mediaRecords.find((row: MediaRecord) => row.media.id === item.id);
    return domain === 'movie' ? record?.movieState ?? 'unknown' : record?.watchlistState ?? 'unknown';
  }

  private localIntentLabel(value: string): string {
    return value === 'yes' ? '明确标记' : value === 'no' ? '明确撤销/移出' : '未明确设置（旧记录保留）';
  }

  private async changeMediaIntent(item: Media, domain: string, value: string): Promise<void> {
    if (!this.ready || this.saving || this.cloudBusy || this.syncBusy) { return; }
    try {
      await this.persistMedia(setMediaIntent(this.mediaRecords, item, domain, value));
    } catch (error) {
      this.libraryStatus = '本机状态校验失败，未保存。';
    }
  }

  @Builder
  mediaStateView(item: Media) {
    Column({ space: 8 }) {
      Text('独立本机状态').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Text('电影已看和待看清单互不覆盖。旧收藏没有明确同步意图；以下按钮只保存本机。')
        .fontSize(12).width('100%')
      if (item.kind === 'movie') {
        Text('电影观看：' + this.localIntentLabel(this.mediaIntent(item, 'movie'))).fontSize(14).width('100%')
        Row({ space: 8 }) {
          Button('标记电影已看').layoutWeight(1).enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
            .onClick(() => { this.changeMediaIntent(item, 'movie', 'yes'); })
          Button('撤销电影已看').layoutWeight(1).enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
            .onClick(() => { this.changeMediaIntent(item, 'movie', 'no'); })
        }.width('100%')
      }
      Text('待看清单：' + this.localIntentLabel(this.mediaIntent(item, 'watchlist'))).fontSize(14).width('100%')
      Row({ space: 8 }) {
        Button('加入待看').layoutWeight(1).enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
          .onClick(() => { this.changeMediaIntent(item, 'watchlist', 'yes'); })
        Button('移出待看').layoutWeight(1).enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
          .onClick(() => { this.changeMediaIntent(item, 'watchlist', 'no'); })
      }.width('100%')
      Text(this.libraryStatus).fontSize(12).width('100%')
    }.width('100%').padding(10).backgroundColor($r('app.color.showly_surface')).borderRadius(10)
  }

  private async loadMediaPreview(): Promise<void> {
    const store = this.episodeStore;
    const account = this.syncAccount;
    const clientId = this.clientId;
    if (!this.ready || !store || !account || !this.syncBound || this.syncBusy || this.saving ||
        this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, account.generation)) { return; }
    const session = traktAuth.session(clientId);
    if (!session) { return; }
    this.syncBusy = true;
    this.clearThreeWayReview();
    this.mediaPreview = undefined;
    this.mediaSelected = undefined;
    this.mediaWatchTime = '';
    this.mediaPage = 1;
    this.mediaPreviewStatus = '读取电影与待看清单的完整云端快照…';
    try {
      if (this.mediaStore && (await this.mediaStore.pendingTargets(account.uuid)).length > 0) {
        const checked = await reconcilePendingMedia(this.mediaStore, store, session, account.uuid);
        this.mediaSyncStatus = checked.message;
        this.mediaLogs = await this.mediaStore.operationLogs(account.uuid);
        if (checked.failed > 0) {
          this.mediaPreviewStatus = '只读核对暂未完成，已保留保护；请联网后再试。';
          return;
        }
      }
      const result = await buildMediaPreview(store, session, this.mediaRecords, account.uuid, this.mediaStore);
      if (this.clientId !== clientId || !traktAuth.isCurrent(clientId, session.generation) ||
          this.syncAccount?.uuid !== account.uuid || !this.syncBound) { throw new Error('Account changed'); }
      this.mediaPreview = result;
      if (this.mediaStore) { this.mediaLogs = await this.mediaStore.operationLogs(account.uuid); }
      this.mediaPreviewStatus = '预览完成；未修改本机或云端观看记录。';
    } catch (error) {
      this.mediaPreviewStatus = '预览失败：' + safeSyncError(error as Error) + '；未修改观看记录。';
    } finally { this.syncBusy = false; }
  }

  private mediaOperationLabel(row: MediaDifference): string {
    if (row.operation === 'reconcile') { return '只读核对未确认操作'; }
    if (row.domain === 'movie') { return row.operation === 'add' ? '上传电影已看' : '撤销单次电影历史'; }
    return row.operation === 'add' ? '加入云端待看' : '移出云端待看';
  }

  private selectMediaOperation(row: MediaDifference): void {
    if (this.syncBusy || this.saving || !this.mediaPreview || !row.operation) { return; }
    this.mediaSelected = row;
    this.mediaWatchTime = new Date().toISOString();
    this.mediaSyncStatus = '';
  }

  private async confirmMediaOperation(): Promise<void> {
    const store = this.mediaStore;
    const binding = this.episodeStore;
    const preview = this.mediaPreview;
    const selected = this.mediaSelected;
    const clientId = this.clientId;
    const watchedAt = this.mediaWatchTime;
    if (!store || !binding || !preview || !selected || !this.ready || !this.syncBound ||
        this.syncAccount?.uuid !== preview.account.uuid || !this.pageVisible || this.syncBusy || this.saving ||
        this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        !traktAuth.isCurrent(clientId, preview.account.generation)) { return; }
    const session = traktAuth.session(clientId);
    if (!session) { return; }
    this.syncBusy = true;
    this.mediaSelected = undefined;
    this.mediaWatchTime = '';
    this.mediaSyncStatus = '正在复核本机意图、账户及云端记录…';
    try {
      const result = await syncSelectedMedia(store, binding, session, preview, selected, watchedAt, (): boolean => {
        return this.pageVisible && this.clientId === clientId &&
          this.syncAccount?.uuid === preview.account.uuid && this.syncBound &&
          traktAuth.isCurrent(clientId, session.generation);
      });
      this.mediaSyncStatus = result.message;
      this.syncPreview = undefined;
      this.invalidateMovieCalendar();
      this.cloud = undefined;
      this.cloudStatus = '电影/待看操作已结束；云端清单请重新读取。';
      if (this.collectionFilter === 'tracking') { this.resetCollection(); }
      this.mediaPreview = undefined;
      // Supplemental read only after a not-yet-visible result or a revision
      // race, not repeated network/429 errors. Never resubmit a mutation.
      const op = await store.latestOperation(preview.account.uuid, selected.domain, selected.id);
      if (op?.state === 'pending' && this.pageVisible && !result.message.includes('HTTP 429') &&
          (result.message.includes('云端尚未显示目标状态') || result.message.includes('Cloud changed during readback'))) {
        const checked = await reconcilePendingMedia(store, binding, session, preview.account.uuid);
        this.mediaSyncStatus += ' ' + checked.message;
        if (checked.failed > 0) {
          this.mediaPreviewStatus = '补充核对中断，请联网后重新生成预览。';
          return;
        }
      }
      // Refresh is independent from persisted operation confirmation. A
      // failed full-list refresh must not be reported as a failed upload.
      const remaining = await store.latestOperation(preview.account.uuid, selected.domain, selected.id);
      if (remaining?.state === 'pending' || result.message.includes('HTTP 429')) {
        this.mediaPreviewStatus = '操作仍受保护；重新联网或生成预览时自动只读核对。';
        return;
      }
      try {
        const fresh = await buildMediaPreview(binding, session, this.mediaRecords, preview.account.uuid, store);
        if (traktAuth.isCurrent(clientId, session.generation) && this.syncAccount?.uuid === preview.account.uuid && this.syncBound) {
          this.mediaPreview = fresh;
          this.mediaPreviewStatus = '已刷新只读差异预览。';
          this.mediaPage = 1;
        }
      } catch (error) {
        this.mediaPreviewStatus = '差异列表刷新失败：' + safeSyncError(error as Error) + '；已保存的操作结果不受影响。';
      }
    } catch (error) {
      this.mediaPreview = undefined;
      this.mediaSyncStatus += '；流程中断：' + safeSyncError(error as Error) + '；保护凭证不会重发。';
    } finally {
      try {
        if (this.syncAccount?.uuid === preview.account.uuid && traktAuth.isCurrent(clientId, session.generation)) {
          this.mediaLogs = await store.operationLogs(preview.account.uuid);
        }
      } catch (error) { this.mediaPreviewStatus += '；本机日志刷新失败。'; }
      this.syncBusy = false;
    }
  }

  private async refreshMediaLogs(): Promise<void> {
    const store = this.mediaStore;
    const account = this.syncAccount;
    if (!store || !account || !this.syncBound || !traktAuth.isCurrent(this.clientId, account.generation)) { return; }
    try { this.mediaLogs = await store.operationLogs(account.uuid); } catch (error) {
      this.mediaSyncStatus = '电影与待看日志读取失败。';
    }
  }

  private mediaRows(category: string = this.mediaCategory): MediaDifference[] {
    return this.mediaPreview?.rows.filter((row: MediaDifference) =>
      row.domain === this.mediaDomain && row.category === category) ?? [];
  }

  private mediaPages(): number {
    return Math.max(1, Math.ceil(this.mediaRows().length / this.collectionPageSize));
  }

  private mediaSlice(): MediaDifference[] {
    const start = (this.mediaPage - 1) * this.collectionPageSize;
    return this.mediaRows().slice(start, start + this.collectionPageSize);
  }

  @Builder
  mediaCategoryButton(label: string, category: string) {
    Button(label + ' ' + this.mediaRows(category).length).fontSize(12).layoutWeight(1)
      .backgroundColor(this.mediaCategory === category ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.mediaCategory === category ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.clearThreeWayReview(); this.mediaCategory = category; this.mediaPage = 1; this.mediaSelected = undefined; })
  }

  @Builder
  mediaPreviewView() {
    Column({ space: 10 }) {
      Text('电影与待看差异预览').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
      Text(this.migrationStatus).fontSize(12).width('100%')
      Text('只比较明确本机操作。新增/删除仍须逐条手动确认；已有保护凭证会自动只读核对，不会重发。')
        .fontSize(12).width('100%')
      if (!this.syncBound || !this.syncAccount || !traktAuth.isCurrent(this.clientId, this.syncAccount.generation)) {
        Text('请先在上方验证并绑定同步账户。').fontSize(13).width('100%')
      } else {
        Button(this.syncBusy ? '处理中…' : '生成电影与待看差异预览')
          .enabled(this.ready && !this.syncBusy && !this.saving && !this.localBusy && !this.cloudBusy && !this.authBusy && !this.setupBusy)
          .onClick(() => { this.loadMediaPreview(); })
        Text(this.mediaPreviewStatus).fontSize(13).width('100%')
        if (this.mediaSyncStatus) { Text(this.mediaSyncStatus).fontSize(13).width('100%') }
        if (this.threeWayStatus) { Text(this.threeWayStatus).fontSize(13).width('100%') }
        Button(this.showMediaLogs ? '收起电影与待看日志' : '查看电影与待看日志')
          .onClick(() => { this.showMediaLogs = !this.showMediaLogs; if (this.showMediaLogs) { this.refreshMediaLogs(); } })
        if (this.showMediaLogs) {
          Text('最近操作（最多 12 条）').fontSize(14).width('100%')
          if (!this.mediaLogs.length) { Text('暂无操作').fontSize(12) }
          ForEach(this.mediaLogs, (log: string, index: number) => {
            Text(log).fontSize(12).width('100%')
          }, (log: string, index: number) => index.toString() + log)
        }
        if (this.mediaPreview && this.mediaPreview.account.uuid === this.syncAccount.uuid &&
            traktAuth.isCurrent(this.clientId, this.mediaPreview.account.generation)) {
          Text('云端电影已看 ' + this.mediaPreview.watchedCount + ' 部 · 待看电影/剧集 ' +
            this.mediaPreview.watchlistCount + ' 部；非标准本机 ID 排除 ' + this.mediaPreview.excluded + ' 部')
            .fontSize(13).width('100%')
          Row({ space: 8 }) {
            Button('电影观看').layoutWeight(1)
              .backgroundColor(this.mediaDomain === 'movie' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
              .fontColor(this.mediaDomain === 'movie' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
              .onClick(() => { this.clearThreeWayReview(); this.mediaDomain = 'movie'; this.mediaPage = 1; this.mediaSelected = undefined; })
            Button('待看清单').layoutWeight(1)
              .backgroundColor(this.mediaDomain === 'watchlist' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
              .fontColor(this.mediaDomain === 'watchlist' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
              .onClick(() => { this.clearThreeWayReview(); this.mediaDomain = 'watchlist'; this.mediaPage = 1; this.mediaSelected = undefined; })
          }.width('100%')
          this.commonBaselineView(this.mediaDomain, this.mediaCheckpointCount())
          Row({ space: 4 }) {
            this.mediaCategoryButton('新增', 'addition')
            this.mediaCategoryButton('一致', 'match')
            this.mediaCategoryButton('冲突', 'conflict')
          }.width('100%')
          Row({ space: 4 }) {
            this.mediaCategoryButton('本机未知', 'unknown')
            this.mediaCategoryButton('仅云端', 'cloud')
            this.mediaCategoryButton('云端变化', 'remote')
          }.width('100%')
          if (!this.mediaRows().length) { Text('本分类没有记录').fontSize(13) }
          ForEach(this.mediaSlice(), (row: MediaDifference) => {
            Column({ space: 4 }) {
              Text(row.title + ' · ' + row.id).fontSize(14).width('100%')
              Text('本机 ' + this.localIntentLabel(row.local) + ' / 云端 ' + (row.remote ? '存在' : '不存在'))
                .fontSize(12).width('100%')
              Text(threeWayLabel(row.threeWay, row.baseline)).fontSize(12).width('100%')
              if (row.operationNote) { Text(row.operationNote).fontSize(12).width('100%') }
              if (row.category === 'remote' && row.threeWay === 'remote' && !row.operation) {
                Button('采用云端状态（仅本机）').fontSize(12).enabled(this.threeWayAvailable())
                  .onClick(() => { this.clearThreeWayReview(); this.adoptMediaKey = row.domain + ':' + row.id; })
                if (this.adoptMediaKey === row.domain + ':' + row.id) {
                  Text('确认将本机' + (row.domain === 'movie' ? '电影已看' : '待看') + '状态设为' + (row.remote ? '存在' : '不存在') + '？不写入 Trakt。').fontSize(12).width('100%')
                  Row({ space: 8 }) {
                    Button('取消').layoutWeight(1).onClick(() => { this.clearThreeWayReview(); })
                    Button('确认采用').layoutWeight(1).enabled(this.threeWayAvailable()).onClick(() => { this.confirmAdoptMedia(); })
                  }.width('100%')
                }
              }
              if (row.operation) {
                Button(this.mediaOperationLabel(row)).fontSize(12)
                  .enabled(!this.syncBusy && !this.saving && !this.cloudBusy && !this.authBusy && !this.setupBusy)
                  .onClick(() => { this.selectMediaOperation(row); })
              }
              if (this.mediaSelected?.id === row.id && this.mediaSelected?.domain === row.domain) {
                Text('确认：' + this.mediaOperationLabel(row) + ' · ' + row.title)
                  .fontSize(14).width('100%')
                Text('目标账户：上方已验证的 Trakt 账户。只处理此条记录。').fontSize(12).width('100%')
                if (row.domain === 'movie' && row.operation === 'add') {
                  Text('仅在确实已观看时确认。本次观看时间使用确认准备时间：' + new Date(this.mediaWatchTime).toLocaleString() +
                    '。Trakt 可能自动移出云端待看；本机待看不改变，也不会自动补加。')
                    .fontSize(12).width('100%')
                }
                if (row.operation === 'remove') {
                  Text(row.domain === 'movie' ? '只删除本应用确认的单次历史 ID；多次观看或凭证不符时拒绝。' :
                    '仅移出指定电影或剧集的云端待看，不删除观看历史。').fontSize(12).width('100%')
                }
                if (row.operation === 'reconcile') { Text('仅发送 GET 核对，不执行新增或删除。').fontSize(12).width('100%') }
                Row({ space: 8 }) {
                  Button('取消').layoutWeight(1).onClick(() => { this.mediaSelected = undefined; this.mediaWatchTime = ''; })
                  Button('确认执行').layoutWeight(1).enabled(!this.syncBusy && !this.saving && !this.cloudBusy && !this.authBusy && !this.setupBusy)
                    .onClick(() => { this.confirmMediaOperation(); })
                }.width('100%')
              }
            }.width('100%').padding(10).borderRadius(8).backgroundColor($r('app.color.showly_muted_surface'))
          }, (row: MediaDifference) => row.domain + ':' + row.id)
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.mediaPage > 1).onClick(() => { this.mediaPage--; this.mediaSelected = undefined; })
            Text(this.mediaPage + ' / ' + this.mediaPages()).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.mediaPage < this.mediaPages()).onClick(() => { this.mediaPage++; this.mediaSelected = undefined; })
          }.width('100%')
        }
      }
      Divider()
    }.width('100%')
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

  private invalidateNextShows(): void {
    this.nextShows = [];
    this.nextPage = 1;
    this.nextStatus = '本机记录已变化，请刷新追剧进度。';
  }

  private async loadNextShows(): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.syncBusy || this.backupBusy) { return; }
    this.localBusy = true;
    this.nextStatus = '正在计算本机已缓存剧集进度…';
    try {
      this.nextShows = await readNextShows(store);
      this.nextPage = 1;
      this.nextStatus = this.nextShows.length ? '已读取 ' + this.nextShows.length + ' 部本机缓存目录；不代表全部云端剧集。' :
        '没有缓存分集目录。请打开剧集详情并更新分集目录。';
    } catch (error) {
      this.invalidateNextShows();
      this.nextStatus = '本机进度读取失败：' + safeSyncError(error as Error);
    } finally { this.localBusy = false; }
  }

  private nextFiltered(): NextShow[] {
    const q = this.nextQuery.trim().toLowerCase();
    return sortNextShows(this.nextShows.filter((row: NextShow) =>
      (this.nextFilter === 'all' || (this.nextFilter === 'remaining' ? row.nextSeason > 0 :
        row.total > 0 && row.completed === row.total)) &&
      (!q || row.media.title.toLowerCase().includes(q))), this.nextSort);
  }

  private nextPages(): number { return Math.max(1, Math.ceil(this.nextFiltered().length / this.collectionPageSize)); }
  private nextSlice(): NextShow[] {
    return this.nextFiltered().slice((this.nextPage - 1) * this.collectionPageSize, this.nextPage * this.collectionPageSize);
  }

  private invalidateMovieCalendar(): void {
    this.movieCalendarData = undefined;
    if (this.calendarKind === 'movie') {
      ++this.calendarRevision;
      this.calendarBusy = false;
      this.calendarPage = 1;
      this.calendarStatus = '个人电影库已变化，请刷新日历。';
    }
  }

  private resetCalendar(): void {
    ++this.calendarRevision;
    this.movieCalendarData = undefined;
    this.calendarData = undefined;
    this.calendarBusy = false;
    this.calendarPage = 1;
    this.calendarStatus = '';
  }

  private async loadCalendar(): Promise<void> {
    if (this.calendarBusy || this.authBusy || this.setupBusy || this.syncBusy || !this.signedIn || !this.clientId) { return; }
    const session = traktAuth.session(this.clientId);
    if (!session) { this.calendarStatus = '登录会话尚不可用，请恢复 Trakt 登录后重试。'; return; }
    const revision = ++this.calendarRevision;
    const kind = this.calendarKind;
    const week = this.calendarWeek;
    this.calendarBusy = true;
    this.calendarData = undefined;
    this.calendarPage = 1;
    this.calendarStatus = '正在读取 Trakt 个人日历…';
    try {
      if (kind === 'movie') {
        this.movieCalendarData = undefined;
        const personal = await readPersonalMovies(session);
        if (revision !== this.calendarRevision || this.calendarKind !== kind ||
            !this.signedIn || !traktAuth.isCurrent(this.clientId, session.generation)) { return; }
        this.movieCalendarData = addLocalMovies(personal, this.mediaRecords);
        this.calendarStatus = '已读取个人电影库，共 ' + this.movieCalendarData.movies.length + ' 部。';
        return;
      }
      const result = await readCalendar(session, kind, week);
      if (revision !== this.calendarRevision || this.calendarKind !== kind || this.calendarWeek !== week ||
          !this.signedIn || !traktAuth.isCurrent(this.clientId, session.generation)) { return; }
      this.calendarData = result;
      this.calendarStatus = (result.entries.length ? '日历读取完成，共 ' + result.entries.length + ' 条。' : '此日期范围暂无返回的日历记录。') +
        (result.skipped ? ' 跳过日期或标识不完整的 ' + result.skipped + ' 条。' : '');
    } catch (error) {
      if (revision === this.calendarRevision) {
        this.calendarStatus = '日历读取失败：' + safeSyncError(error as Error) + '；未改动观看记录。';
      }
    } finally { if (revision === this.calendarRevision) { this.calendarBusy = false; } }
  }

  private calendarRangeLabel(): string {
    const range = calendarWindow(new Date(), this.calendarWeek);
    return range.from + ' 至 ' + range.to;
  }

  private calendarCurrent(): boolean {
    if (this.calendarKind === 'movie') { return this.movieCalendarCurrent(); }
    return !!this.calendarData && this.signedIn &&
      traktAuth.isCurrent(this.clientId, this.calendarData.generation) &&
      this.calendarData.window.from === calendarWindow(new Date(), this.calendarWeek).from &&
      this.calendarData.window.startMs === calendarWindow(new Date(), this.calendarWeek).startMs;
  }

  private calendarSlice(): CalendarEntry[] {
    if (!this.calendarCurrent()) { return []; }
    return this.calendarData?.entries.slice((this.calendarPage - 1) * this.collectionPageSize,
      this.calendarPage * this.collectionPageSize) ?? [];
  }

  private calendarPages(): number {
    return Math.max(1, Math.ceil((this.calendarData?.entries.length ?? 0) / this.collectionPageSize));
  }

  private changeCalendar(kind: string, week: number): void {
    if (this.calendarBusy) { return; }
    ++this.calendarRevision;
    this.calendarData = undefined;
    this.calendarPage = 1;
    this.calendarStatus = '';
    this.calendarKind = kind;
    this.calendarWeek = week;
    if (kind === 'movie' && this.movieCalendarCurrent()) {
      this.calendarStatus = '已读取个人电影库，共 ' + (this.movieCalendarData?.movies.length ?? 0) + ' 部。';
    } else { this.loadCalendar(); }
  }

  private chooseProgressMode(mode: string): void {
    this.progressMode = mode;
    if (mode === 'next' && !this.nextShows.length) { this.loadNextShows(); }
    if (mode === 'calendar' && !this.calendarCurrent()) { this.loadCalendar(); }
  }

  @Builder
  progressModeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .backgroundColor(this.progressMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.progressMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.chooseProgressMode(mode); })
  }

  @Builder
  nextFilterButton(label: string, filter: string) {
    Button(label).layoutWeight(1).fontSize(12)
      .backgroundColor(this.nextFilter === filter ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.nextFilter === filter ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.nextFilter = filter; this.nextPage = 1; })
  }

  @Builder
  nextSortButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(12)
      .backgroundColor(this.nextSort === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.nextSort === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.nextSort = mode; this.nextPage = 1; })
  }

  @Builder
  nextShowsView() {
    Column({ space: 10 }) {
      Text('下一集 · 本机追剧进度').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
      Text('按本机已缓存目录计算最早未看普通集。已导入云端进度与本机操作按现有规则合并；未缓存和未来分集不推断。')
        .fontSize(12).width('100%')
      Button(this.localBusy ? '读取中…' : '刷新本机追剧进度')
        .enabled(this.episodeReady && !this.localBusy && !this.syncBusy && !this.backupBusy)
        .onClick(() => { this.loadNextShows(); })
      if (this.nextStatus) { Text(this.nextStatus).fontSize(12).width('100%') }
      Row({ space: 4 }) {
        this.nextFilterButton('待追', 'remaining')
        this.nextFilterButton('已追完目录', 'completed')
        this.nextFilterButton('全部目录', 'all')
      }.width('100%')
      Row({ space: 4 }) {
        this.nextSortButton('最近操作', 'recent')
        this.nextSortButton('剩余集数', 'remaining')
        this.nextSortButton('片名', 'title')
      }.width('100%')
      TextInput({ placeholder: '筛选剧集', text: this.nextQuery })
        .onChange((value: string) => { this.nextQuery = value; this.nextPage = 1; })
      Text('符合条件 ' + this.nextFiltered().length + ' 部').fontSize(13).width('100%')
      ForEach(this.nextSlice(), (row: NextShow) => {
        Column({ space: 6 }) {
          Text(row.media.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
          Text('已看 ' + row.completed + ' / ' + row.total + ' 集 · 剩余 ' + (row.total - row.completed) + ' 集')
            .fontSize(12).width('100%')
          if (row.total > 0) {
            Progress({ value: row.completed, total: row.total, type: ProgressType.Linear }).width('100%').color($r('app.color.showly_accent'))
          }
          Text(row.nextSeason > 0 ? '下一集：S' + row.nextSeason + 'E' + row.nextNumber +
            (row.nextTitle ? ' · ' + row.nextTitle : '') : row.total > 0 ? '当前缓存目录已追完' : '暂无已播分集')
            .fontSize(14).width('100%')
          Button(row.nextSeason > 0 ? '查看下一集所在季' : '查看剧集详情')
            .fontSize(12).enabled(!this.localBusy && !this.syncBusy && !this.detailBusy)
            .onClick(() => { this.openDetail(row.media, false, row.nextSeason); })
        }.padding(12).borderRadius(10).width('100%').backgroundColor($r('app.color.showly_surface'))
      }, (row: NextShow) => row.media.id + ':' + row.completed + ':' + row.nextSeason + ':' + row.nextNumber)
      Row({ space: 8 }) {
        Button('上一页').layoutWeight(1).enabled(this.nextPage > 1).onClick(() => { this.nextPage--; })
        Text(this.nextPage + ' / ' + this.nextPages()).fontSize(13)
        Button('下一页').layoutWeight(1).enabled(this.nextPage < this.nextPages()).onClick(() => { this.nextPage++; })
      }.width('100%')
    }.width('100%')
  }

  private movieCalendarCurrent(): boolean {
    return !!this.movieCalendarData && this.signedIn &&
      traktAuth.isCurrent(this.clientId, this.movieCalendarData.generation);
  }

  private movieRows(mode: string = this.movieCalendarMode, query: string = this.movieCalendarQuery): PersonalMovie[] {
    if (!this.movieCalendarCurrent()) { return []; }
    return filterMovies(this.movieCalendarData?.movies ?? [], mode, query, new Date());
  }

  private moviePages(): number {
    return Math.max(1, Math.ceil(this.movieRows().length / this.collectionPageSize));
  }

  private movieSlice(): MovieCalendarItem[] {
    return moviePage(this.movieRows(), (this.calendarPage - 1) * this.collectionPageSize, this.collectionPageSize, new Date());
  }

  private async lookupMovieDate(row: PersonalMovie): Promise<void> {
    const snapshot = this.movieCalendarData;
    const session = traktAuth.session(this.clientId);
    if (!snapshot || !session || !this.movieCalendarCurrent() || this.calendarBusy || this.syncBusy ||
        this.authBusy || this.setupBusy || row.released || !snapshot.movies.some((item: PersonalMovie) => item.media.id === row.media.id)) { return; }
    const revision = ++this.calendarRevision;
    this.calendarBusy = true;
    this.calendarStatus = '正在补查电影上映日期…';
    try {
      const date = await readPersonalMovieDate(session, row.media);
      if (revision !== this.calendarRevision || !this.movieCalendarCurrent() || this.movieCalendarData !== snapshot) { return; }
      this.movieCalendarData = { generation: snapshot.generation, activity: snapshot.activity,
        movies: snapshot.movies.map((item: PersonalMovie): PersonalMovie => item.media.id === row.media.id ?
          { media: item.media, released: date, cloudWatched: item.cloudWatched, cloudWatchlist: item.cloudWatchlist,
            localOnly: item.localOnly } : item) };
      this.calendarPage = 1;
      this.calendarStatus = date ? '已补查到 ' + row.media.title + ' 的上映日期：' + date + '。' :
        'Trakt 仍未提供该电影的有效上映日期。';
    } catch (error) {
      if (revision === this.calendarRevision) { this.calendarStatus = '日期补查失败：' + safeSyncError(error as Error); }
    } finally { if (revision === this.calendarRevision) { this.calendarBusy = false; } }
  }

  @Builder
  movieModeButton(label: string, mode: string) {
    Button(label + ' ' + this.movieRows(mode, '').length).layoutWeight(1).fontSize(12)
      .backgroundColor(this.movieCalendarMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.movieCalendarMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.movieCalendarMode = mode; this.calendarPage = 1; })
  }

  @Builder
  personalMovieCalendarView() {
    Column({ space: 10 }) {
      Text('个人已看及待看电影；不限制未来日期。另含本机明确标记的电影。仅展示 Trakt 上映日期，不代表当地影院排期。')
        .fontSize(12).width('100%')
      if (!this.signedIn) {
        Text('登录 Trakt 后读取个人电影库。').fontSize(13).width('100%')
        Button('连接 Trakt').onClick(() => { this.navigate('account'); })
      } else {
        Button(this.calendarBusy ? '读取中…' : '刷新个人电影日历')
          .enabled(!this.calendarBusy && !this.authBusy && !this.syncBusy && !this.setupBusy)
          .onClick(() => { this.loadCalendar(); })
        if (this.calendarStatus) { Text(this.calendarStatus).fontSize(13).width('100%') }
        if (this.movieCalendarCurrent()) {
          Row({ space: 4 }) {
            this.movieModeButton('即将上映', 'future')
            this.movieModeButton('已上映', 'past')
            this.movieModeButton('日期待确认', 'unknown')
          }.width('100%')
          TextInput({ placeholder: '筛选电影片名或上映日期', text: this.movieCalendarQuery })
            .onChange((value: string) => { this.movieCalendarQuery = value; this.calendarPage = 1; })
          if (!this.movieRows().length) {
            Text('此分类暂无电影，可切换已上映或日期待确认。').fontSize(13).width('100%')
          }
          ForEach(this.movieSlice(), (row: MovieCalendarItem) => {
            Column({ space: 6 }) {
              if (row.heading) { Text(row.group).fontSize(18).fontWeight(FontWeight.Bold).width('100%') }
              Column({ space: 6 }) {
                Text(row.movie.released || '上映日期待确认').fontSize(13)
                  .fontColor($r('app.color.showly_secondary')).width('100%')
                Text(row.movie.media.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
                Text(row.movie.localOnly ? '仅本机明确标记' : row.movie.cloudWatched && row.movie.cloudWatchlist ?
                  '云端已看 · 云端待看' : row.movie.cloudWatched ? '云端已看' : '云端待看')
                  .fontSize(12).width('100%')
                Row({ space: 8 }) {
                  Button('查看详情').fontSize(12).layoutWeight(1).enabled(!this.detailBusy && !this.localBusy && !this.syncBusy)
                    .onClick(() => { this.openDetail(row.movie.media); })
                  if (!row.movie.released) {
                    Button('补查日期').fontSize(12).layoutWeight(1).enabled(!this.calendarBusy && !this.syncBusy)
                      .onClick(() => { this.lookupMovieDate(row.movie); })
                  }
                }.width('100%')
              }.padding(12).width('100%').borderRadius(10).backgroundColor($r('app.color.showly_surface'))
            }.width('100%')
          }, (row: MovieCalendarItem) => row.movie.media.id + ':' + row.movie.released + ':' + row.group + ':' + row.heading)
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.calendarPage > 1).onClick(() => { this.calendarPage--; })
            Text(this.calendarPage + ' / ' + this.moviePages()).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.calendarPage < this.moviePages()).onClick(() => { this.calendarPage++; })
          }.width('100%')
        }
      }
    }.width('100%')
  }

  @Builder
  calendarView() {
    Column({ space: 10 }) {
      Text('个人更新与上映日历').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
      Text('剧集使用 Trakt 个人日历，电影使用个人已看与待看电影库的上映日期。均不是全站上映表。')
        .fontSize(12).width('100%')
      Row({ space: 6 }) {
        Button('剧集更新').layoutWeight(1).fontSize(13).enabled(!this.calendarBusy)
          .backgroundColor(this.calendarKind === 'show' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
          .fontColor(this.calendarKind === 'show' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
          .onClick(() => { this.changeCalendar('show', this.calendarWeek); })
        Button('电影上映').layoutWeight(1).fontSize(13).enabled(!this.calendarBusy)
          .backgroundColor(this.calendarKind === 'movie' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
          .fontColor(this.calendarKind === 'movie' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
          .onClick(() => { this.changeCalendar('movie', this.calendarWeek); })
      }.width('100%')
      if (this.calendarKind === 'movie') {
        this.personalMovieCalendarView()
      } else {
        Text(this.calendarRangeLabel()).fontSize(15).width('100%')
        Row({ space: 4 }) {
          Button('前七天').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy && this.calendarWeek > -1)
            .onClick(() => { this.changeCalendar(this.calendarKind, this.calendarWeek - 1); })
          Button('今天起').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy)
            .onClick(() => { this.changeCalendar(this.calendarKind, 0); })
          Button('后七天').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy && this.calendarWeek < 1)
            .onClick(() => { this.changeCalendar(this.calendarKind, this.calendarWeek + 1); })
        }.width('100%')
        if (!this.signedIn) {
          Text('登录 Trakt 后读取个人日历。').fontSize(13).width('100%')
          Button('连接 Trakt').onClick(() => { this.navigate('account'); })
        } else {
          Button(this.calendarBusy ? '读取中…' : '刷新日历').enabled(!this.calendarBusy && !this.authBusy && !this.syncBusy && !this.setupBusy)
            .onClick(() => { this.loadCalendar(); })
          if (this.calendarStatus) { Text(this.calendarStatus).fontSize(13).width('100%') }
          if (this.calendarCurrent()) {
            ForEach(this.calendarSlice(), (row: CalendarEntry) => {
              Column({ space: 6 }) {
                Text(row.day + (row.time ? ' · ' + row.time : ' · 上映日期')).fontSize(13)
                  .fontColor($r('app.color.showly_secondary')).width('100%')
                Text(row.media.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
                if (row.media.kind === 'show') {
                  Text('S' + row.season + 'E' + row.number + (row.episodeTitle ? ' · ' + row.episodeTitle : ''))
                    .fontSize(14).width('100%')
                }
                Button('查看详情').fontSize(12).enabled(!this.detailBusy && !this.localBusy && !this.syncBusy)
                  .onClick(() => { this.openDetail(row.media, false, row.season); })
              }.padding(12).width('100%').borderRadius(10).backgroundColor($r('app.color.showly_surface'))
            }, (row: CalendarEntry) => row.key)
            Row({ space: 8 }) {
              Button('上一页').layoutWeight(1).enabled(this.calendarPage > 1).onClick(() => { this.calendarPage--; })
              Text(this.calendarPage + ' / ' + this.calendarPages()).fontSize(13)
              Button('下一页').layoutWeight(1).enabled(this.calendarPage < this.calendarPages()).onClick(() => { this.calendarPage++; })
            }.width('100%')
          } else if (this.calendarData) {
            Text('会话或当地日期已变化，请刷新日历。').fontSize(12).width('100%')
          }
        }
      }
    }.width('100%')
  }

  @Builder
  progressView() {
    Column({ space: 12 }) {
      Text('观看进度').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 6 }) {
        this.progressModeButton('下一集', 'next')
        this.progressModeButton('日历', 'calendar')
        this.progressModeButton('云端记录', 'cloud')
      }.width('100%')
      if (this.progressMode === 'next') { this.nextShowsView() }
      else if (this.progressMode === 'calendar') { this.calendarView() }
      else { this.legacyProgressView() }
    }.width('100%')
  }

  @Builder
  legacyProgressView() {
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
      Text('待看 ' + this.mediaRecords.filter((record: MediaRecord) => inLocalWatchlist(record)).length + ' 部影视').width('100%')
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
      } else if (this.tab === 'progress') {
        if (this.progressMode === 'next') { await this.loadNextShows(); }
        else if (this.progressMode === 'calendar') { await this.loadCalendar(); }
        else if (this.signedIn) { await this.loadCloud(); }
      } else if (this.tab === 'cloud') {
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
    if (this.collectionFilter === 'all') { return this.items; }
    if (this.collectionFilter === 'queue') {
      return this.mediaRecords.filter((record: MediaRecord) => inLocalWatchlist(record))
        .map((record: MediaRecord) => record.media);
    }
    return this.items.filter((item: Media) => item.watched);
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
      Text(this.migrationStatus).fontSize(12).width('100%')
      Text('旧收藏分类保留；明确设置的待看状态独立于已看。').fontSize(12).width('100%')
      Row({ space: 6 }) {
        this.collectionFilterButton('全部', 'all')
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
      if (this.tab === 'progress' && this.progressMode === 'next' && !this.nextShows.length) { this.loadNextShows(); }
      return true;
    }
    if (this.tab === 'search' || this.tab === 'cloud' || this.tab === 'account') {
      this.navigate('progress');
      return true;
    }
    return false;
  }

  private async openDetail(item: Media, reload: boolean = false, preferredSeason: number = 0): Promise<void> {
    if (this.detailBusy || this.localBusy || this.setupBusy || !canReadDetails(item) || (!this.clientId && item.kind !== 'show')) {
      return;
    }
    this.closeDetail();
    if (preferredSeason > 0 && item.kind === 'show') { this.localSeason = preferredSeason; }
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
    if (value === 'progress' && this.progressMode === 'next' && !this.nextShows.length) { this.loadNextShows(); }
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
      Button('返回').onClick(() => { this.closeDetail(); if (this.tab === 'progress' && this.progressMode === 'next' && !this.nextShows.length) { this.loadNextShows(); } })
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
      if (isTraktMedia(item)) { this.mediaStateView(item) }
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
            this.mediaPreviewView()
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
            this.backupView()
            this.updateView()
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
