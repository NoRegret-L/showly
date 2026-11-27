import { common } from '@kit.AbilityKit';
import { LazyRows } from '../model/LazyRows';
import { DisplayRevisions, LatestDisplayJobs } from '../model/DisplayJobs';
import { ProgressSortInput, MovieSortInput, CollectionSortInput } from '../model/DisplaySort';
import { diffDisplay, showDisplay, movieDisplay, collectionDisplay } from '../data/DisplayTasks';
import { ViewportTasks, addPresentationTask } from '../model/ViewportTasks';
import { CollectionCandidate, CollectionOptions, CollectionState, HiddenEntry, defaultCollection, emptyCollectionState, collectionMembers, recentCollection, recordCollectionDate, transitionCollectionDates, hideMedia } from '../model/CollectionRules';
import { PresentationRepository } from '../data/PresentationRepository';
import { TitlePresentation, PresentationTask, matchesText } from '../model/MediaPresentation';
import { Media, CollectionDate, mediaLabel, setWatched } from '../model/Media';
import { LibraryStore } from '../data/LibraryStore';
import { MediaStore } from '../data/MediaStore';
import { TitleConsent, TitleChange, TitleIntent, titleEdit } from '../model/TitleQuickState';
import { runTitleQuick, reconcileTitleObservation } from '../data/TitleQuickSync';
import { BackupData, RestorePlan, createBackup, exportBackup, selectBackup, planRestore, restoreBackup } from '../data/LocalBackup';
import { MediaRecord, migrateLegacy, isTraktMedia, applyLegacyEdit, setMediaIntent, inLocalWatchlist, followShow } from '../model/MediaState';
import { PersonalLibraryRow, LibraryShowEvidence, buildPersonalLibrary, filterPersonalLibrary, businessLibraryLabel, isPersonalMember } from '../model/PersonalLibrary';
import { MediaPreview, MediaDifference, buildMediaPreview } from '../data/TraktMediaPreview';
import { syncSelectedMedia, reconcilePendingMedia } from '../data/TraktMediaSync';
import { checkpointEpisodes, checkpointMedia, adoptEpisodeCloud, adoptMediaCloud } from '../data/ThreeWaySync';
import { threeWayLabel } from '../model/ThreeWay';
import { NextShow } from '../data/NextShows';
import { RevisionMemo, projectionKey, progressExpiry } from '../model/ReadModelCache';
import { ShowProjectionCache } from '../model/ProjectionCompute';
import { MovieProgressOptions, MovieProgressSource, defaultMovieProgress, validMovieProgress, movieProgressRows as projectMovieProgress, clearMoviePin } from '../model/MovieProgressRules';
import { ProgressSource, ProgressPreferences, ProgressFlag, ProgressRow, defaultProgress, validProgress, toggleProgressFlag, selectProgress, sortProgressCandidates, ProgressEntry, progressSections, progressEntries, progressPage, effectiveProgressFilter } from '../model/ProgressRules';
import { CalendarSnapshot, CalendarEntry, readCalendar, calendarWindow, localDay } from '../data/TraktCalendar';
import { PersonalMovie, PersonalMovieSnapshot, readPersonalMovieDate, CollectionRating, readCollectionRatings } from '../data/TraktLibrary';
import { MovieCalendarItem, filterMovies, moviePage } from '../data/MovieCalendar';
import { searchTrakt } from '../data/TraktSearch';
import { TRAKT_APPS_URL, TRAKT_REDIRECT_URI } from '../config/TraktConfig';
import { ClientSettings, validateClientId } from '../data/ClientSettings';
import { pasteboard } from '@kit.BasicServicesKit';
import { traktAuth } from '../data/TraktAuth';
import { CloudLibrary, ShowProgress, readCloudLibrary, mergeNewTitles, readActivity } from '../data/TraktLibrary';
import { LibraryProjection, projectLibrary, projectDetail } from '../data/LibraryProjection';
import { allowLocalScope } from '../model/EffectiveState';
import { hasTrackingEvidence } from '../model/PersonalLibrary';
import { CollectionGroup, GroupEntry, normalizeMode, progressTabs, collectionRows, pageGroups } from '../model/NavigationModel';
import { MediaDetail, canReadDetails, readDetails, cachePoster, clearDetailMemory } from '../data/TraktDetails';
import { DiscoverItem, DiscoverOptions, DiscoverFeed, DiscoverPage, defaultDiscover, validDiscoverOptions, discoverRequest, discoverKey, discoverFresh, filterDiscover, discoverPage, DISCOVER_GENRES, DISCOVER_NETWORKS } from '../model/DiscoverRules';
import { DiscoverRead } from '../model/DiscoverRead';
import { openDiscover } from '../data/DiscoverRepository';
import { EpisodeProgress, SeasonProgress, SeriesProgress, ChineseText, readSeriesProgress, readChinese } from '../data/TraktProgress';
import { AppearanceStore, applyAppearance } from '../data/AppearanceStore';
import { EpisodeStore, LocalEpisode, LocalSeriesState, LocalSeasonState, LocalEpisodeState, AutoConsent, QueueEntry, fetchFullEpisodeCatalog, eligibleCatalog } from '../data/EpisodeStore';
import { FullEpisodeCatalog, ScheduledEpisode, scheduleEpisodes, scheduleLabel } from '../model/ShowCatalog';
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

interface DisplaySummary { key: string; total: number; page: number; pages: number; }
interface CollectionIndexes {
  times: Map<string,number>;
  recent: Map<string,number>;
  ratings: Map<string,number>;
  movies: Map<string,PersonalMovie>;
}
@Entry
@Component
struct Index {
  @State title: string = '';
  @State presentationLanguage: string = 'zh';
  @State presentationRevision: number = 0;
  private seasonKeys: Map<string, string[]> = new Map<string, string[]>();
  @State presentationStatus: string = '';
  @State languageBusy: boolean = false;
  private presentation?: PresentationRepository;
  private presentationRunning: boolean = false;
  private presentationPending: boolean = false;
  private presentationBlocked: boolean = false;
  private presentationEpoch: number = 0;
  private presentationRoute: string = '';
  private presentationPublished: number = -1;
  private titleIndex: Map<string, TitlePresentation> = new Map<string, TitlePresentation>();
  private episodeNameIndex: Map<string, string> = new Map<string, string>();
  private libraryRevision: number = 0;
  private displayRevisions: DisplayRevisions = new DisplayRevisions();
  private sortJobs: LatestDisplayJobs = new LatestDisplayJobs();
  @State sortedViewRevision: number = 0;
  @State showSummary: DisplaySummary = {key:'',total:0,page:1,pages:1};
  @State movieSummary: DisplaySummary = {key:'',total:0,page:1,pages:1};
  @State collectionSummary: DisplaySummary = {key:'',total:0,page:1,pages:1};
  private lazyRevision: number = 0;
  private showTitleRevision: number = 0;
  private movieTitleRevision: number = 0;
  private showMetaRevision: number = 0;
  private movieMetaRevision: number = 0;
  private hiddenIndex: Set<string> = new Set<string>();
  private flagIndex: Map<string,ProgressFlag> = new Map<string,ProgressFlag>();
  private libraryIndex: Map<string,PersonalLibraryRow> = new Map<string,PersonalLibraryRow>();
  private hiddenShowKey: string = '';
  private hiddenMovieKey: string = '';
  private showFlagKey: string = '';
  private movieFlagKey: string = '';
  private collectionIndexMemos: Map<string,RevisionMemo<CollectionIndexes>> = new Map<string,RevisionMemo<CollectionIndexes>>();
  private movieMetadataMemo: RevisionMemo<Map<string,PersonalMovie>> = new RevisionMemo<Map<string,PersonalMovie>>();
  private titleSortRevision: number = 0;
  private episodeSearchRevision: number = 0;
  private collectionMetaRevision: number = 0;
  private candidateMemo: RevisionMemo<ProgressRow[]> = new RevisionMemo<ProgressRow[]>();
  private candidateExpiry: number = 0;
  private candidateRuns: number = 0;
  private viewport: ViewportTasks = new ViewportTasks();
  private viewportRouteKey: string = '';
  private discoverRows: LazyRows<DiscoverItem[]> = new LazyRows<DiscoverItem[]>();
  private searchRows: LazyRows<Media> = new LazyRows<Media>();
  private calendarRows: LazyRows<CalendarEntry> = new LazyRows<CalendarEntry>();
  private movieCalendarRows: LazyRows<MovieCalendarItem> = new LazyRows<MovieCalendarItem>();
  private libraryMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  private progressMemo: RevisionMemo<ProgressRow[]> = new RevisionMemo<ProgressRow[]>();
  private progressAllMemo: RevisionMemo<ProgressRow[]> = new RevisionMemo<ProgressRow[]>();
  private movieMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  private movieAllMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  @State updateBusy: boolean = false;
  @State updateStatus: string = '';
  @State availableUpdate?: UpdateInfo = undefined;
  @State upstreamInfo?: UpstreamInfo = undefined;
  @State upstreamStatus: string = '';
  @State @Watch('onPresentationChanged') tab: string = 'progress';
  @State @Watch('onPresentationChanged') mediaMode: string = 'show';
  @State modeBusy: boolean = false;
  @State modeStatus: string = '';
  private returnTab: string = 'progress';
  @State @Watch('onPresentationChanged') movieProgressQuery: string = '';
  @State @Watch('onPresentationChanged') movieProgressOptions: MovieProgressOptions = defaultMovieProgress();
  @State movieRandomSeed: number = Date.now();
  @State @Watch('onPresentationChanged') movieProgressPage: number = 1;
  @State @Watch('onPresentationChanged') collectionQuery: string = '';
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
  private titleQuickPending: boolean = false;
  @State titleConsent?: TitleConsent = undefined;
  @State titleQuickStatus: string = '';
  @State titleConfirm: boolean = false;
  @State movieUndo?: Media = undefined;
  @State movieUndoStatus: string = '';
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
  @State @Watch('onPresentationChanged') localSeries?: LocalSeriesState = undefined;
  @State @Watch('onPresentationChanged') fullSchedule?: FullEpisodeCatalog = undefined;
  @State @Watch('onPresentationChanged') schedulePage: number = 1;
  @State @Watch('onPresentationChanged') localSeason: number = -1;
  @State @Watch('onRecoveryGateChanged') localBusy: boolean = false;
  @State localStatus: string = '';
  @State localRecent: Media[] = [];
  @State @Watch('onPresentationChanged') progressMode: string = 'next';
  @State @Watch('onShowsChanged') nextShows: NextShow[] = [];
  @State nextStatus: string = '';
  @State @Watch('onPresentationChanged') progressPrefs: ProgressPreferences = defaultProgress();
  @State @Watch('onFlagsChanged') progressFlags: ProgressFlag[] = [];
  @State progressFlagScope: string = '';
  @State progressPrefsBusy: boolean = false;
  @State progressOptions: boolean = false;
  @State progressDaysInput: string = '30';
  @State progressOptionStatus: string = '';
  @State @Watch('onPresentationChanged') nextFilter: string = 'all';
  @State progressMenuId: string = '';
  @State @Watch('onPresentationChanged') collectionStatusFilter: string = 'all';
  @State @Watch('onPresentationChanged') nextQuery: string = '';
  @State @Watch('onPresentationChanged') nextPage: number = 1;
  @State calendarWeek: number = 0;
  @State @Watch('onPresentationChanged') calendarPage: number = 1;
  @State calendarBusy: boolean = false;
  @State calendarStatus: string = '';
  @State @Watch('onPresentationChanged') calendarData?: CalendarSnapshot = undefined;
  @State @Watch('onMoviesChanged') movieCalendarData?: PersonalMovieSnapshot = undefined;
  private movieRatingKey: string = '';
  private movieRatingRows: CollectionRating[] = [];
  private movieRatingBusy: boolean = false;
  @State @Watch('onPresentationChanged') movieCalendarMode: string = 'future';
  @State @Watch('onPresentationChanged') movieCalendarQuery: string = '';
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
  @State @Watch('onPresentationChanged') collectionFilter: string = 'mine';
  @State @Watch('onPresentationChanged') collectionPage: number = 1;
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
  @State discoverMode: string = 'trending';
  @State discoverOptions: DiscoverOptions = defaultDiscover();
  @State discoverGenreDraft: string = '';
  @State discoverNetworkDraft: string = '';
  @State discoverTotal: number = 0;
  @State discoverShownPage: number = 1;
  private discoverRepo?: Promise<DiscoverRead>;
  private discoverFeed?: DiscoverFeed;
  private discoverFeedKey: string = '';
  private discoverMemo: RevisionMemo<DiscoverItem[]> = new RevisionMemo<DiscoverItem[]>();
  @State @Watch('onPresentationChanged') discoverItems: DiscoverItem[] = [];
  @State discoverPage: number = 1;
  @State discoverPages: number = 0;
  @State discoverBusy: boolean = false;
  @State discoverStatus: string = '';
  private discoverRevision: number = 0;
  @State @Watch('onPresentationChanged') selectedMedia?: Media = undefined;
  @State detail?: MediaDetail = undefined;
  @State detailBusy: boolean = false;
  @State detailStatus: string = '';
  @State posterUri: string = '';
  private detailRevision: number = 0;
  @State @Watch('onPresentationChanged') clientId: string = '';
  @State draftId: string = '';
  @State configuring: boolean = false;
  @State @Watch('onRecoveryGateChanged') setupBusy: boolean = false;
  @State settingsReady: boolean = false;
  @State setupStatus: string = '';
  @State @Watch('onLibraryInputChanged') cloud?: CloudLibrary = undefined;
  @State @Watch('onLibraryInputChanged') libraryEvidence: LibraryShowEvidence[] = [];
  private cloudUuid: string = '';
  private cloudFresh: boolean = false;
  @State @Watch('onLibraryInputChanged') cloudLocalAllowed: boolean = false;
  @State effectiveEditable: boolean = false;
  private observationPending: boolean = false;
  private startupScheduled: boolean = false;
  private projectionMemo: RevisionMemo<LibraryProjection> = new RevisionMemo<LibraryProjection>();
  private showProjectionCache: ShowProjectionCache = new ShowProjectionCache();
  private projectionRuns: number = 0;
  private projectionHits: number = 0;
  private startupAt: number = Date.now();
  @State performanceStatus: string = '等待首次个人库计算';
  private projectionPending: boolean = false;
  private repairTargets: Media[] = [];
  private repairRunning: boolean = false;
  private repairEpoch: number = 0;
  @State repairStatus: string = '';
  private lazyPending: boolean = false;
  private showRows: LazyRows<ProgressEntry> = new LazyRows<ProgressEntry>();
  private movieRowsSource: LazyRows<PersonalLibraryRow> = new LazyRows<PersonalLibraryRow>();
  private collectionRowsSource: LazyRows<CollectionGroup> = new LazyRows<CollectionGroup>();
  @State @Watch('onCollectionStateChanged') collectionState: CollectionState = emptyCollectionState();
  @State collectionScope: string = '';
  @State @Watch('onPresentationChanged') collectionOptions: CollectionOptions = defaultCollection();
  @State collectionOptionsOpen: boolean = false;
  @State collectionGenreDraft: string = '';
  @State collectionNetworkDraft: string = '';
  @State collectionEditBusy: boolean = false;
  @State collectionRuleStatus: string = '';
  private collectionOptionKey: string = '';
  private collectionRandomKeys: Map<string, number> = new Map<string, number>();
  private collectionItemsMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  private recentCollectionMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  @State @Watch('onCollectionRatingsChanged') collectionRatings: CollectionRating[] = [];
  private collectionRatingKey: string = '';
  private collectionRatingBusy: boolean = false;
  @State collectionRatingStatus: string = '';
  @State @Watch('onRecoveryGateChanged') cloudBusy: boolean = false;
  @State cloudStatus: string = '';
  @State advancedSync: boolean = false;
  @State libraryNotice: string = '';
  private settings?: ClientSettings;
  @StorageLink('traktAuthStatus') authStatus: string = '尚未登录 Trakt';
  @StorageLink('traktAuthBusy') @Watch('onRecoveryGateChanged') authBusy: boolean = false;
  @StorageLink('traktSignedIn') @Watch('onObservationAuthChanged') signedIn: boolean = false;
  @State items: Media[] = [];
  @State @Watch('onPresentationChanged') results: Media[] = [];
  @State ready: boolean = false;
  @State @Watch('onRecoveryGateChanged') saving: boolean = false;
  @State searching: boolean = false;
  @State libraryStatus: string = '';
  @State searchStatus: string = '';
  private mediaStore?: MediaStore;
  @State @Watch('onLibraryInputChanged') mediaRecords: MediaRecord[] = [];
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
      this.mediaMode = normalizeMode(this.settings.loadMode());
      this.restoreDiscoverOptions();
      this.presentationLanguage = this.settings.loadLanguage();
      this.progressPrefs = this.settings.loadProgress();
      this.movieProgressOptions = this.settings.loadMovieProgress();
      this.progressDaysInput = this.progressPrefs.days.toString();
      this.nextFilter = effectiveProgressFilter(this.progressPrefs);
      this.reloadProgressFlags();
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
    this.initializePresentation(context);
    this.discoverRepo = openDiscover(context);
  }

  onPageShow(): void {
    this.pageVisible = true;
    if (this.tab === 'discover' && !this.selectedMedia) { this.loadDiscover(this.discoverPage); }
    this.presentationBlocked = false;
    this.requestPresentation();
    this.startNetworkListener();
    if (this.backupBusy) { return; }
    this.requestMediaRecovery();
    const initialized = this.startupScheduled;
    this.requestObservation(true);
    this.scheduleInitialRead();
    if (initialized && !this.signedIn) { this.requestProjection(); }
    if (this.autoActive()) { this.requestRecovery(); }
    else if (this.clientId && !this.setupBusy && !this.cloudBusy && !this.syncBusy) {
      traktAuth.restore(this.clientId);
    }
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.discoverRevision++;
    this.discoverBusy = false;
    this.sortJobs.clear();
    this.lazyRevision++;
    this.viewport.clear();
    this.cancelCatalogRepair();
    this.presentationPending = false;
    this.presentationEpoch++;
    this.recoveryPending = false;
    this.mediaRecoveryPending = false;
    this.titleQuickPending = false;
    this.observationPending = false;
    this.projectionPending = false;
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.discoverRevision++;
    this.discoverBusy = false;
    this.sortJobs.clear();
    this.lazyRevision++;
    this.viewport.clear();
    this.cancelCatalogRepair();
    this.presentationPending = false;
    this.presentationEpoch++;
    this.recoveryPending = false;
    this.mediaRecoveryPending = false;
    this.titleQuickPending = false;
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
          this.requestObservation();
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
  private onObservationAuthChanged(): void {
    this.viewport.clear();
    this.calendarRows.replace([],[],[]);
    this.movieCalendarRows.replace([],[],[]);
    this.collectionScope = '';
    this.collectionRatingKey = '';
    this.collectionRatings = [];
    this.collectionState = emptyCollectionState();
    this.collectionRowsSource.replace([], [], []);
    this.cancelCatalogRepair();
    this.showRows.replace([], [], []);
    this.movieRowsSource.replace([], [], []);
    this.showSummary = {key:'',total:0,page:1,pages:1};
    this.movieSummary = {key:'',total:0,page:1,pages:1};
    this.collectionSummary = {key:'',total:0,page:1,pages:1};
    this.discoverRows.replace([],[],[]);
    this.discoverTotal = 0;
    this.discoverPages = 0;
    this.discoverShownPage = 1;
    this.discoverMemo.clear();
    this.projectionMemo.clear();
    this.showProjectionCache.clear();
    this.libraryRevision++;
    this.displayRevisions.reset();
    this.collectionIndexMemos.clear();
    this.movieMetadataMemo.clear();
    this.libraryIndex.clear();
    this.libraryMemo.clear();
    this.sortJobs.clear();
    this.lazyRevision++;
    this.presentationEpoch++;
    this.presentationBlocked = false;
    this.progressFlags = [];
    this.progressFlagScope = '';
    this.progressMenuId = '';
    this.nextShows = [];
    this.titleConsent = undefined;
    this.titleQuickPending = false;
    this.titleConfirm = false;
    this.movieUndo = undefined;
    this.movieUndoStatus = '';
    if (!this.signedIn) {
      this.cloudLocalAllowed = false;
      this.libraryEvidence = [];
      this.localSeries = undefined;
      this.effectiveEditable = false;
      this.observationPending = false;
      this.projectionPending = false;
      return;
    }
    this.cloudLocalAllowed = false;
    this.libraryEvidence = [];
    this.nextShows = [];
    this.localSeries = undefined;
    this.effectiveEditable = false;
    this.requestObservation();
  }

  private scheduleInitialRead(): void {
    if (this.startupScheduled || !this.ready || !this.episodeReady || !this.pageVisible) { return; }
    this.startupScheduled = true;
    if (this.signedIn) { this.requestObservation(true); }
    else { this.requestProjection(); }
  }

  private requestObservation(passive: boolean = false): void {
    if (!this.pageVisible || !this.signedIn || !this.clientId || (passive && this.cloudBusy)) { return; }
    this.observationPending = true;
    this.onRecoveryGateChanged();
  }

  private requestProjection(): void {
    if (!this.pageVisible) { return; }
    this.projectionPending = true;
    this.onRecoveryGateChanged();
  }

  private onRecoveryGateChanged(): void {
    if (this.backupBusy || !this.pageVisible || this.syncBusy || this.localBusy || this.cloudBusy || this.saving ||
        this.authBusy || this.setupBusy) { return; }
    if (this.recoveryPending && this.autoActive() && this.episodeReady) {
      this.recoveryPending = false;
      this.resumeQueued();
      return;
    }
    if (this.mediaRecoveryPending && !this.saving) {
      this.mediaRecoveryPending = false;
      this.recoverMediaPending();
      return;
    }
    if (!this.ready || !this.episodeReady || this.saving) { return; }
    if (this.observationPending && this.signedIn) {
      this.observationPending = false;
      this.projectionPending = false;
      this.loadCloud(false);
      return;
    }
    if (this.titleQuickPending && this.titleQuickActive()) {
      this.titleQuickPending = false;
      this.resumeTitleQuick();
      return;
    }
    if (this.projectionPending) {
      this.projectionPending = false;
      this.loadNextShows();
      return;
    }
    if (this.repairTargets.length && !this.repairRunning && this.cloudFresh && this.activeCloud()) {
      this.repairCatalogs();
    }
  }

  private cancelCatalogRepair(): void {
    this.repairEpoch++;
    this.repairTargets = [];
    this.repairStatus = '';
  }

  private async repairCatalogs(): Promise<void> {
    const store = this.episodeStore;
    const snapshot = this.activeCloud();
    const uuid = this.cloudUuid;
    const client = this.clientId;
    if (!store || !snapshot || !this.cloudFresh || this.repairRunning || !this.pageVisible) { return; }
    const epoch = this.repairEpoch;
    const targets = this.repairTargets;
    this.repairTargets = [];
    this.repairRunning = true;
    let saved = 0;
    const current = (): boolean => this.pageVisible && this.repairEpoch === epoch &&
      this.activeCloud() === snapshot && this.cloudUuid === uuid && this.clientId === client && this.cloudFresh;
    const idle = (): boolean => !this.localBusy && !this.cloudBusy && !this.syncBusy && !this.saving &&
      !this.authBusy && !this.setupBusy && !this.backupBusy;
    try {
      for (const media of targets) {
        if (!current() || !idle()) { break; }
        this.repairStatus = '正在补齐剧集资料 ' + (saved + 1) + '/' + targets.length + '；可继续浏览';
        const revision = store.readModelRevision();
        const full = await fetchFullEpisodeCatalog(media, client);
        if (!current() || !idle() || store.readModelRevision() !== revision) { break; }
        this.localBusy = true;
        try {
          if (!current()) { break; }
          await store.saveObservedSchedule(full);
          saved++;
        } finally { this.localBusy = false; }
      }
      if (current()) { this.repairStatus = saved === targets.length ? '' : '部分目录待补齐；下次刷新继续。'; }
    } catch (error) {
      if (current()) { this.repairStatus = '目录补齐暂停；已有观看记录保留，下次刷新重试。'; }
    } finally {
      this.repairRunning = false;
      if (current() && saved) { this.requestProjection(); }
      this.onRecoveryGateChanged();
    }
  }

  private titleQuickActive(): boolean {
    const consent = this.titleConsent;
    return !!consent && this.signedIn && this.cloudLocalAllowed && !!this.activeCloud() &&
      consent.uuid === this.cloudUuid && consent.clientId === this.clientId;
  }

  private async setTitleQuick(enabled: boolean): Promise<void> {
    const media = this.mediaStore;
    const binding = this.episodeStore;
    const session = traktAuth.session(this.clientId);
    const uuid = this.cloudUuid;
    if (!media || !binding || this.syncBusy || this.saving || this.cloudBusy || this.localBusy ||
        this.authBusy || this.setupBusy || this.backupBusy) { return; }
    this.syncBusy = true;
    this.titleConfirm = false;
    try {
      if (!enabled) {
        this.titleQuickPending = false;
        this.titleConsent = undefined;
        await media.setTitleConsent('', '', false);
        this.titleQuickStatus = '电影及待看快捷同步已关闭，未发送记录保留。';
      } else {
        if (!session || !this.cloudLocalAllowed || !uuid || await binding.boundAccount() !== uuid ||
            (await readSyncAccount(session)).uuid !== uuid ||
            !traktAuth.isCurrent(this.clientId, session.generation)) { throw new Error('Account changed'); }
        this.titleConsent = await media.setTitleConsent(uuid, this.clientId, true);
        this.titleQuickStatus = '已开启，仅处理此后明确执行的电影新增及待看操作。';
      }
    } catch (error) { this.titleQuickStatus = '同步授权保存失败，请重试。'; }
    finally { this.syncBusy = false; }
  }

  private async resumeTitleQuick(): Promise<void> {
    const media = this.mediaStore;
    const binding = this.episodeStore;
    const consent = this.titleConsent;
    const clientId = this.clientId;
    const session = traktAuth.session(clientId);
    if (!media || !binding || !consent || !session || !this.titleQuickActive() ||
        !this.pageVisible || this.syncBusy || this.saving || this.localBusy || this.cloudBusy ||
        this.authBusy || this.setupBusy || this.backupBusy) { return; }
    this.syncBusy = true;
    this.titleQuickStatus = '正在同步影视操作…';
    try {
      const current = (): boolean => this.pageVisible && this.titleQuickActive() &&
        this.titleConsent?.epoch === consent.epoch && this.clientId === clientId &&
        traktAuth.isCurrent(clientId, session.generation);
      const result = await runTitleQuick(media, binding, session, consent, current);
      this.titleQuickStatus = result.message;
      if (result.review || result.remaining) { this.libraryNotice = '部分操作尚未同步，可在设置中核对。'; }
      if (result.attempted && current()) {
        this.invalidateMovieCalendar();
        this.observationPending = true;
      }
    } catch (error) {
      this.titleQuickStatus = '快捷同步暂未完成，已保留操作。' + safeSyncError(error as Error);
      this.libraryNotice = '同步暂未完成，观看记录已保留。';
    } finally { this.syncBusy = false; }
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
        if (result.confirmed > 0) { this.observationPending = true; }
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
      this.scheduleInitialRead();
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
      this.requestRecovery();
      this.scheduleInitialRead();
    } catch (error) {
      this.episodeInitStatus = '分集数据库打开失败，已停止分集写入；旧收藏不受影响。';
    }
  }

  private async loadLocalEpisodes(item: Media, refresh: boolean = false): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.cloudBusy || this.syncBusy || item.kind !== 'show') { return; }
    const revision = this.detailRevision;
    const clientId = this.clientId;
    this.localBusy = true;
    this.localStatus = '正在读取分集…';
    try {
      let full = await store.fullCatalog(item.id);
      if (revision !== this.detailRevision) { return; }
      this.fullSchedule = full;
      this.schedulePage = 1;
      if ((refresh || !full) && clientId) {
        full = await fetchFullEpisodeCatalog(item, clientId);
        if (revision !== this.detailRevision || this.clientId !== clientId) { return; }
        if (refresh && this.canEditLibrary()) {
          this.invalidateSync();
          await store.saveFullCatalog(full);
        } else {
          await store.saveObservedSchedule(full);
        }
        this.fullSchedule = full;
        this.invalidateNextShows();
        this.requestProjection();
      }
      await this.refreshEffectiveDetail();
    } catch (error) {
      if (revision === this.detailRevision) {
        try { await this.refreshEffectiveDetail(); } catch (failure) {}
        this.localStatus = '资料更新失败，已有记录保留。';
      }
    } finally {
      this.localBusy = false;
    }
  }

  private activeCloud(): CloudLibrary | undefined {
    const snapshot = this.cloud;
    return snapshot && this.signedIn && traktAuth.isCurrent(this.clientId, snapshot.generation) ? snapshot : undefined;
  }

  private canEditLibrary(): boolean {
    return !this.signedIn || (!!this.activeCloud() && this.cloudLocalAllowed);
  }

  private async refreshEffectiveDetail(): Promise<void> {
    const store = this.episodeStore;
    const item = this.selectedMedia;
    if (!store || !item || item.kind !== 'show') { return; }
    const revision = this.detailRevision;
    const snapshot = this.activeCloud();
    const uuid = this.cloudUuid;
    if (this.signedIn && !snapshot) {
      this.localSeries = undefined;
      this.effectiveEditable = false;
      this.localStatus = '正在等待账户验证；暂不读取本机私有记录。';
      return;
    }
    const full = await store.fullCatalog(item.id);
    const result = await projectDetail(store, full, item.id, snapshot, uuid);
    if (revision !== this.detailRevision || snapshot !== this.activeCloud() || uuid !== this.cloudUuid) { return; }
    this.fullSchedule = full;
    this.localSeries = result.state;
    this.localCatalogNeedsVerification = result.localAllowed ? await store.needsCatalogVerification(item.id) : false;
    if (revision !== this.detailRevision || snapshot !== this.activeCloud() || uuid !== this.cloudUuid) {
      this.localSeries = undefined;
      this.effectiveEditable = false;
      return;
    }
    this.effectiveEditable = result.complete && result.localAllowed && this.canEditLibrary();
    if (result.state && result.state.seasons.length > 0 &&
        !result.state.seasons.some((season: LocalSeasonState) => season.number === this.localSeason)) {
      this.localSeason = result.state.seasons[0].number;
    }
    this.localStatus = !result.complete ? '分集资料未齐，暂不允许修改；请刷新个人库或目录。' :
      !this.effectiveEditable ? '当前账户仅供浏览；本机库需明确绑定，不能跨账户修改。' :
      result.state ? '有效观看状态 · 本机操作仍使用原有同步保护' : '请联网获取分集目录';
  }

  private async markLocal(item: Media, ids: number[], watched: boolean): Promise<void> {
    if (this.isHidden(item) || this.collectionEditBusy) { return; }
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.cloudBusy || this.syncBusy || ids.length === 0 ||
        !this.effectiveEditable || !this.canEditLibrary()) { return; }
    if (this.localCatalogNeedsVerification) {
      this.localStatus = '备份恢复的目录需要联网更新后才能修改分集状态。';
      return;
    }
    const revision = this.detailRevision;
    const dateScope = this.currentProgressScope();
    const previous = this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id);
    this.localBusy = true;
    this.confirmSeason = -1;
    const auto = this.autoActive() ? this.autoConsent : undefined;
    let saved = false;
    try {
      this.invalidateSync();
      const existing = await store.catalog(item.id);
      if (ids.some((id: number) => !existing?.episodes.some((episode: LocalEpisode) => episode.id === id))) {
        // A user action may verify missing write-eligible metadata. Read-only
        // bulk catalog repair alone never grants this eligibility.
        const fresh = await fetchFullEpisodeCatalog(item, this.clientId);
        const eligible = eligibleCatalog(fresh, fresh.fetchedAt);
        if (revision !== this.detailRevision || !this.canEditLibrary() ||
            ids.some((id: number) => !eligible.episodes.some((episode: LocalEpisode) => episode.id === id))) {
          throw new Error('Episode not eligible');
        }
        await store.saveFullCatalog(fresh);
      }
      if (revision !== this.detailRevision || !this.canEditLibrary()) { return; }
      await store.mark(item.id, ids, watched, watched && auto ? auto.uuid : '');
      if (watched && (!previous || !hasTrackingEvidence(previous)) && previous?.localRecord?.followState !== 'no') {
        await this.recordFirstEpisodeDate(dateScope,item.id);
      }
      this.invalidateNextShows();
      saved = true;
      this.requestProjection();
      this.localRecent = await store.recent();
      await this.reloadQueue();
      if (revision === this.detailRevision) {
        await this.refreshEffectiveDetail();
        this.localStatus = '观看状态已更新。';
      }
    } catch (error) {
      if (revision === this.detailRevision) {
        this.localStatus = '观看状态更新失败，请刷新后确认。';
      }
    } finally {
      this.localBusy = false;
    }
    if (saved && watched && auto && this.autoActive()) { this.requestRecovery(); }
  }

  private extraSchedule(): ScheduledEpisode[] {
    const catalog = this.fullSchedule;
    if (!catalog) { return []; }
    const eligible: Set<number> = new Set<number>((this.localSeries?.catalog.episodes ?? [])
      .map((episode: LocalEpisode) => episode.id));
    return scheduleEpisodes(catalog).filter((episode: ScheduledEpisode) => !eligible.has(episode.id));
  }

  @Builder
  scheduleView() {
    Column({ space: 8 }) {
      if (this.fullSchedule) {
        Text('其他分集 · ' + this.extraSchedule().length + ' 集')
          .fontSize(14).width('100%')
        Text('待播或播出日期未确认的分集暂不可标记。').fontSize(12).width('100%')
        ForEach(this.extraSchedule().slice((this.schedulePage - 1) * this.collectionPageSize,
          this.schedulePage * this.collectionPageSize), (episode: ScheduledEpisode) => {
          Text('S' + episode.season + 'E' + episode.number + ' · ' + (this.selectedMedia ? this.displayEpisode(this.selectedMedia, episode.season, episode.id, episode.title) : episode.title) +
            ' · ' + scheduleLabel(episode, Date.now())).fontSize(13).width('100%')
        }, (episode: ScheduledEpisode) => episode.id.toString() + ':' + (this.selectedMedia ? this.displayEpisode(this.selectedMedia, episode.season, episode.id, episode.title) : episode.title))
        if (this.extraSchedule().length > this.collectionPageSize) {
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.schedulePage > 1).onClick(() => { this.schedulePage--; })
            Text(this.schedulePage + ' / ' + Math.ceil(this.extraSchedule().length / this.collectionPageSize)).fontSize(12)
            Button('下一页').layoutWeight(1)
              .enabled(this.schedulePage * this.collectionPageSize < this.extraSchedule().length)
              .onClick(() => { this.schedulePage++; })
          }.width('100%')
        }
      } else {
        Text('旧版仅保存已播目录；联网更新后可查看完整播出资料。').fontSize(12).width('100%')
      }
    }.width('100%')
  }

  @Builder
  localEpisodesView(item: Media) {
    Column({ space: 10 }) {
      Text('分集观看状态').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Text('仅统计已播普通集。').fontSize(12).width('100%')
      if (!this.episodeReady) {
        Text(this.episodeInitStatus || '正在打开分集数据库…').fontSize(13).width('100%')
      } else {
        Button(this.localBusy ? '更新中…' : '刷新分集')
          .enabled(!this.localBusy && !this.cloudBusy && !this.syncBusy && !!this.clientId)
          .onClick(() => { this.loadLocalEpisodes(item, true); })
        if (this.localBusy) { Text('正在更新分集…').fontSize(12).width('100%') }
        else if (!this.localSeries) { Text('暂无完整分集资料，请刷新。').fontSize(12).width('100%') }
        else if (!this.effectiveEditable) { Text('暂不可编辑，请检查同步设置。').fontSize(12).width('100%') }
        if (!this.localBusy && this.localStatus.includes('失败')) { Text(this.localStatus).fontSize(12).width('100%') }
        if (this.localSeries) {
          if (this.localCatalogNeedsVerification) { Text('恢复的资料需刷新后才能编辑。').fontSize(12).width('100%') }
          Text('已看 ' + this.localSeries.completed + ' / ' + this.localSeries.catalog.episodes.length + ' 集')
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
                  Button('整季已看').layoutWeight(1).enabled(this.effectiveEditable && !this.cloudBusy && !this.localCatalogNeedsVerification && !this.localBusy && !this.syncBusy && season.completed < season.episodes.length)
                    .onClick(() => { this.confirmSeason = season.number; this.confirmWatched = true; })
                  Button('整季撤销').layoutWeight(1).enabled(this.effectiveEditable && !this.cloudBusy && !this.localCatalogNeedsVerification && !this.localBusy && !this.syncBusy && season.completed > 0)
                    .onClick(() => { this.confirmSeason = season.number; this.confirmWatched = false; })
                }.width('100%')
                if (this.confirmSeason === season.number) {
                  Text(this.confirmWatched ? '确认将本季已播集全部标记已看？' : '确认撤销本季已看状态？同步删除需单独确认。').fontSize(13)
                  Row({ space: 8 }) {
                    Button('取消').layoutWeight(1).onClick(() => { this.confirmSeason = -1; })
                    Button('确认').layoutWeight(1).enabled(this.effectiveEditable && !this.cloudBusy && !this.localBusy && !this.syncBusy)
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
                      if (this.displayEpisode(item, season.number, entry.episode.id, entry.episode.title)) {
                        Text(this.displayEpisode(item, season.number, entry.episode.id, entry.episode.title)).fontSize(12).maxLines(2).width('100%')
                          .fontColor($r('app.color.showly_secondary'))
                      }
                    }.layoutWeight(1)
                    Button(entry.watched ? '撤销已看' : '标记已看').fontSize(12).enabled(this.effectiveEditable && !this.cloudBusy && !this.localCatalogNeedsVerification && !this.localBusy && !this.syncBusy)
                      .onClick(() => { this.markLocal(item, [entry.episode.id], !entry.watched); })
                  }.width('100%')
                }, (entry: LocalEpisodeState) => entry.episode.id + ':' + entry.watched + ':' + this.displayEpisode(item, season.number, entry.episode.id, entry.episode.title))
              }
            }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
          }, (season: LocalSeasonState) => season.number + ':' + season.completed)
        }
        if (this.extraSchedule().length > 0) { this.scheduleView() }
      }
    }.width('100%')
  }

  private async initializePresentation(context: common.UIAbilityContext): Promise<void> {
    try {
      this.presentation = await PresentationRepository.open(context);
      this.publishPresentation();
      this.requestPresentation();
    } catch (error) { this.presentationStatus = '影视资料缓存暂不可用，仍可管理观看记录。'; }
  }

  private onLibraryInputChanged(): void {
    this.libraryRevision++;
    this.onPresentationChanged();
  }

  private onShowsChanged(): void {
    this.displayRevisions.showsChanged();
    this.onPresentationChanged();
  }
  private onMoviesChanged(): void {
    this.displayRevisions.moviesChanged();
    this.onPresentationChanged();
  }
  private onCollectionRatingsChanged(): void {
    this.displayRevisions.collectionChanged();
    this.onPresentationChanged();
  }
  private onCollectionStateChanged(): void {
    this.displayRevisions.collectionChanged();
    this.hiddenIndex = new Set<string>(this.collectionState.hidden.map((row: HiddenEntry) => row.media.id));
    this.hiddenShowKey = JSON.stringify(Array.from(this.hiddenIndex).filter((id: string) => id.startsWith('show:')).sort());
    this.hiddenMovieKey = JSON.stringify(Array.from(this.hiddenIndex).filter((id: string) => id.startsWith('movie:')).sort());
    this.onPresentationChanged();
  }
  private onFlagsChanged(): void {
    this.flagIndex.clear();
    for (const flag of this.progressFlags) { this.flagIndex.set(flag.id,flag); }
    this.showFlagKey = JSON.stringify(this.progressFlags.filter((flag: ProgressFlag) => flag.id.startsWith('show:')));
    this.movieFlagKey = JSON.stringify(this.progressFlags.filter((flag: ProgressFlag) => flag.id.startsWith('movie:')));
    this.onPresentationChanged();
  }
  private titleVersion(kind: string): number { return kind === 'movie' ? this.movieTitleRevision : this.showTitleRevision; }
  private metaVersion(kind: string): number { return kind === 'movie' ? this.movieMetaRevision : this.showMetaRevision; }
  private hiddenVersion(kind: string): string {
    if (this.collectionScope !== this.currentProgressScope()) { return ''; }
    return kind === 'movie' ? this.hiddenMovieKey : this.hiddenShowKey;
  }
  private flagVersion(kind: string): string {
    if (this.progressFlagScope !== this.currentProgressScope()) { return ''; }
    return kind === 'movie' ? this.movieFlagKey : this.showFlagKey;
  }

  private publishPresentation(): void {
    if (!this.presentation) { return; }
    const revision = this.presentation.revision();
    if (revision === this.presentationPublished) { return; }
    this.presentationPublished = revision;
    const changes = this.presentation.takeChanges();
    for (const row of changes.titles) {
      const prior = this.titleIndex.get(row.id);
      if ((prior?.text.title ?? '') !== row.text.title) {
        this.titleSortRevision++;
        if (row.id.startsWith('movie:')) { this.movieTitleRevision++; } else { this.showTitleRevision++; }
      }
      if (JSON.stringify(prior?.collection ?? null) !== JSON.stringify(row.collection ?? null)) {
        this.collectionMetaRevision++;
        if (row.id.startsWith('movie:')) { this.movieMetaRevision++; } else { this.showMetaRevision++; }
      }
      this.titleIndex.set(row.id,row);
    }
    for (const row of changes.seasons) {
      const seasonKey = row.showId + ':' + row.season;
      const previous = this.seasonKeys.get(seasonKey) ?? [];
      const keys: Set<string> = new Set<string>();
      for (const ep of row.episodes) {
        const key = seasonKey + ':' + ep.id;
        keys.add(key);
        if ((this.episodeNameIndex.get(key) ?? '') !== ep.text.title) { this.episodeSearchRevision++; }
        this.episodeNameIndex.set(key,ep.text.title);
      }
      for (const key of previous) {
        if (!keys.has(key)) { this.episodeNameIndex.delete(key); this.episodeSearchRevision++; }
      }
      this.seasonKeys.set(seasonKey,Array.from(keys));
    }
    this.presentationRevision = revision;
    // A localized sort or query can reveal a different page. One more pass
    // only after real cache changes converges to the newly visible artwork.
    if (this.presentationRunning) { this.presentationPending = true; }
    this.scheduleLazyRows();
  }

  private displayTitle(item: Media): string {
    return this.presentationLanguage === 'zh' && this.presentationRevision > 0 ?
      this.titleIndex.get(item.id)?.text.title || item.title : item.title;
  }

  private displayLabel(item: Media): string {
    const title = this.displayTitle(item);
    const year = item.year > 0 ? ' (' + item.year + ')' : '';
    const kind = item.kind === 'movie' ? '电影' : item.kind === 'show' ? '剧集' : '手动';
    return title + year + ' · ' + kind;
  }

  private displayEpisode(item: Media, season: number, id: number, original: string): string {
    return this.presentationLanguage === 'zh' && this.presentationRevision > 0 ?
      this.episodeNameIndex.get(item.id + ':' + season + ':' + id) || original : original;
  }

  private displayOverview(item: Media, original: string): string {
    return this.presentationLanguage === 'zh' ?
      (this.presentationRevision > 0 ? this.titleIndex.get(item.id)?.text.overview : '') || original : original;
  }

  private artwork(item: Media): string {
    return this.presentationRevision > 0 ? this.titleIndex.get(item.id)?.posterUri ?? '' : '';
  }

  private matchesMedia(item: Media, query: string): boolean {
    return matchesText(query, item.title, this.displayTitle(item));
  }

  private viewScope(): string { return this.tab + ':' + this.mediaMode + ':' + this.progressMode + ':' + (this.selectedMedia?.id ?? ''); }
  private viewportChanged(item: Media, season: number, urls: string[], visible: boolean, tab: string, mode: string, slot: string = ''): void {
    if (!this.pageVisible || this.selectedMedia || tab !== this.tab || (mode && mode !== this.progressMode) || !canReadDetails(item)) { return; }
    if (this.viewport.update(item,season,urls,visible,slot)) { this.requestPresentation(); }
  }
  private onPresentationChanged(): void {
    const scope = this.viewScope();
    if (scope !== this.viewportRouteKey) { this.viewport.clear(); this.sortJobs.clear(); this.viewportRouteKey = scope; }
    this.reloadCollectionOptions();
    const route = JSON.stringify([this.clientId, this.tab, this.mediaMode, this.progressMode, this.selectedMedia?.id ?? '',
      this.nextPage, this.nextQuery, this.movieProgressPage, this.movieProgressQuery, this.collectionPage,
      this.collectionQuery, this.collectionFilter, this.collectionStatusFilter, this.calendarPage, this.movieCalendarQuery,
      this.movieCalendarMode, this.schedulePage, this.localSeason, this.presentationLanguage, this.collectionOptions]);
    if (route !== this.presentationRoute) {
      this.presentationRoute = route;
      this.presentationEpoch++;
      this.presentationBlocked = false;
      this.presentationStatus = '';
    }
    this.requestPresentation();
  }

  private scheduleLazyRows(): void {
    this.lazyRevision++;
    if (this.lazyPending) { return; }
    this.lazyPending = true;
    this.updateLazyRows();
  }

  private async updateLazyRows(): Promise<void> {
    await Promise.resolve();
    this.lazyPending = false;
    if (!this.pageVisible || this.selectedMedia) { return; }
    const revision = this.lazyRevision;
    const scope = this.viewScope();
    const account = this.currentProgressScope();
    const current = (): boolean => this.pageVisible && revision === this.lazyRevision && scope === this.viewScope() && account === this.currentProgressScope() && !this.selectedMedia;
    if (this.tab === 'discover') {
      const items = this.visibleDiscover();
      const result = this.discoverPageResult();
      const rows: DiscoverItem[][] = [];
      for (let i=0;i<items.length;i+=2) { rows.push(items.slice(i,i+2)); }
      const committed = await this.discoverRows.submit(rows,rows.map((row: DiscoverItem[]) => row.map((item: DiscoverItem) => item.media.id).join(',')),
        rows.map((row: DiscoverItem[]) => this.discoverRowKey(row)),diffDisplay,current);
      if (committed && current()) { this.discoverTotal = result.total; this.discoverShownPage = result.page; this.discoverPages = result.pages; }
      return;
    }
    if (this.tab === 'search') {
      await this.searchRows.submit(this.results,this.results.map((item: Media) => item.id),this.results.map((item: Media) => this.searchRowKey(item)),diffDisplay,current);
      return;
    }
    if (this.tab === 'progress' && this.progressMode === 'calendar') {
      if (this.mediaMode === 'movie') {
        const rows = this.movieCalendarCurrent() ? this.movieSlice() : [];
        await this.movieCalendarRows.submit(rows,rows.map((row: MovieCalendarItem) => row.movie.media.id),rows.map((row: MovieCalendarItem) => this.movieCalendarKey(row)),diffDisplay,current);
      } else {
        const rows = this.calendarSlice();
        await this.calendarRows.submit(rows,rows.map((row: CalendarEntry) => row.key),rows.map((row: CalendarEntry) => this.calendarRowKey(row)),diffDisplay,current);
      }
      return;
    }
    if (this.tab === 'library') {
      if (this.collectionOptions.sort === 'userRating') { this.loadCollectionRatings(); }
      const prepared = this.collectionItems(true);
      if (this.sortJobs.pending('collection')) { return; }
      const summary: DisplaySummary = {key:this.collectionDisplayKey(),total:prepared.length,page:this.collectionPage,pages:Math.max(1,Math.ceil(prepared.length/this.collectionPageSize))};
      const rows: CollectionGroup[] = [];
      if (!this.signedIn || this.activeCloud()) {
        for (const group of this.collectionPageGroups()) {
          const step = this.collectionGrid ? 2 : 1;
          for (let i = 0; i < group.rows.length; i += step) {
            rows.push({ key: group.key + ':' + group.rows[i].media.id, label: group.label, rows: group.rows.slice(i,i+step) });
          }
        }
      }
      const committed = await this.collectionRowsSource.submit(rows, rows.map((group: CollectionGroup) => group.key),
        rows.map((group: CollectionGroup) => this.collectionGroupKey(group)),diffDisplay,current);
      if (committed && current()) { this.collectionSummary = summary; }
      return;
    }
    if (this.tab !== 'progress' || this.progressMode !== 'next') { return; }
    if (this.mediaMode === 'movie') {
      if (this.movieProgressOptions.sort === 'userRating') { this.loadMovieRatings(); }
      const prepared = this.movieProgressRows(this.movieProgressQuery,false,true);
      if (this.movieProgressQuery && this.presentationLanguage === 'zh') { this.movieProgressRows('',false,true); }
      if (this.sortJobs.pending(this.movieProgressQuery ? 'movie-query' : 'movie-all')) { return; }
      const rows = prepared.slice((this.movieProgressPage - 1) * this.collectionPageSize,this.movieProgressPage * this.collectionPageSize);
      const summary: DisplaySummary = {key:this.movieDisplayKey(),total:prepared.length,page:this.movieProgressPage,pages:Math.max(1,Math.ceil(prepared.length/this.collectionPageSize))};
      const committed = await this.movieRowsSource.submit(rows, rows.map((row: PersonalLibraryRow) => row.media.id),
        rows.map((row: PersonalLibraryRow) => this.movieRowKey(row)),diffDisplay,current);
      if (committed && current()) { this.movieSummary = summary; }
    } else {
      this.progressData(this.nextQuery,false,true);
      if (this.nextQuery && this.presentationLanguage === 'zh') { this.progressData('',false,true); }
      if (this.sortJobs.pending(this.nextQuery ? 'show-query' : 'show-all')) { return; }
      const rows = this.nextSlice();
      const pages = this.nextPages();
      const summary: DisplaySummary = {key:this.showDisplayKey(),total:this.nextFiltered().length,page:Math.min(this.nextPage,pages),pages:pages};
      const committed = await this.showRows.submit(rows, rows.map((entry: ProgressEntry) => entry.key),
        rows.map((entry: ProgressEntry) => this.showRowKey(entry)),diffDisplay,current);
      if (committed && current()) { this.showSummary = summary; }
    }
  }

  private showRowKey(entry: ProgressEntry): string {
    const row = entry.row;
    return JSON.stringify([entry.key,entry.group,entry.label,entry.collapsed,entry.count,row?.episode.id ?? 0,
      row?.episode.season ?? 0,row?.episode.number ?? 0,row?.episode.firstAired ?? '',row?.total ?? 0,
      row?.completed ?? 0,row?.upcoming ?? false,row?.fresh ?? false,row?.pinned ?? false,row?.held ?? false,
      row?.dateUnknown ?? false,row ? this.artwork(row.media) : '',row ? this.displayTitle(row.media) : '',
      row ? this.displayEpisode(row.media,row.episode.season,row.episode.id,row.episode.title) : '']);
  }

  private collectionGroupKey(group: CollectionGroup): string {
    return group.key + ':' + this.collectionGrid + ':' + group.rows.map((row: PersonalLibraryRow) => this.movieRowKey(row) + ':' + this.isHidden(row.media)).join(',');
  }

  private movieRowKey(row: PersonalLibraryRow): string {
    return JSON.stringify([row.media.id,this.displayLabel(row.media),businessLibraryLabel(row),row.watched,row.queued,
      this.artwork(row.media),this.progressFlag(row.media)?.pinned ?? false,this.progressFlag(row.media)?.held ?? false]);
  }

  private discoverRowKey(row: DiscoverItem[]): string {
    return JSON.stringify(row.map((item: DiscoverItem) => [item.media.id,this.displayLabel(item.media),item.rating,
      this.artwork(item.media),this.isHidden(item.media),this.progressFlag(item.media)?.pinned ?? false,this.progressFlag(item.media)?.held ?? false]));
  }
  private searchRowKey(item: Media): string {
    return JSON.stringify([item.id,this.displayLabel(item),this.artwork(item),this.isInLibrary(item),this.isHidden(item)]);
  }
  private movieCalendarKey(row: MovieCalendarItem): string {
    return JSON.stringify([row.movie.media.id,row.movie.released,row.group,row.heading,row.movie.cloudWatched,row.movie.cloudWatchlist,
      this.artwork(row.movie.media),this.displayTitle(row.movie.media)]);
  }
  private calendarRowKey(row: CalendarEntry): string {
    return JSON.stringify([row.key,row.day,row.time,row.season,row.number,this.artwork(row.media),this.displayTitle(row.media),
      this.displayEpisode(row.media,row.season,Number(row.key.substring(8)),row.episodeTitle)]);
  }
  private requestPresentation(): void {
    this.scheduleLazyRows();
    if (!this.pageVisible || !this.presentation || this.presentationBlocked) { return; }
    this.presentationPending = true;
    if (!this.presentationRunning) { this.loadPresentation(); }
  }

  private addPresentationTask(tasks: Map<string,PresentationTask>, item: Media, artwork: boolean, season: number = 0,
    urls: string[] = []): void {
    if (!canReadDetails(item)) { return; }
    if (artwork && !this.selectedMedia && !this.viewport.has(item,season)) { return; }
    addPresentationTask(tasks,item,artwork,season,urls);
  }

  private presentationTasks(): PresentationTask[] {
    const tasks = new Map<string,PresentationTask>();
    const detail = this.selectedMedia;
    if (detail) {
      this.addPresentationTask(tasks, detail, true, this.localSeason > 0 ? this.localSeason : 0, this.detail?.posterUrls ?? []);
      if (this.fullSchedule && detail.kind === 'show') {
        for (const episode of this.extraSchedule().slice((this.schedulePage - 1) * this.collectionPageSize, this.schedulePage * this.collectionPageSize)) {
          this.addPresentationTask(tasks, detail, false, episode.season);
        }
      }
    } else if (this.tab === 'discover') {
      for (const item of this.visibleDiscover()) { this.addPresentationTask(tasks, item.media, true, 0, item.posterUrls); }
    } else if (this.tab === 'search') {
      for (const item of this.results) { this.addPresentationTask(tasks, item, true); }
    } else if (this.tab === 'library') {
      for (const row of this.collectionSlice()) { this.addPresentationTask(tasks, row.media, true); }
      // A Chinese query must also check translations of candidates not yet visible.
      if (this.collectionPage === 1 && this.collectionFilter === 'mine') {
        for (const row of this.recentCollectionRows()) { this.addPresentationTask(tasks, row.media, true); }
      }
      if (this.collectionNeedsMetadata() || (this.presentationLanguage === 'zh' && (this.collectionQuery.trim() || this.collectionOptions.sort === 'title'))) {
        for (const row of this.collectionBase()) {
          this.addPresentationTask(tasks, row.media, false);
        }
      }
    } else if (this.tab === 'progress' && this.progressMode === 'next' && this.mediaMode === 'show') {
      for (const entry of this.nextSlice()) {
        if (entry.row) { this.addPresentationTask(tasks, entry.row.media, true, entry.row.episode.season); }
      }
      if (this.presentationLanguage === 'zh' && (this.nextQuery.trim() || this.progressPrefs.sort === 'title')) {
        for (const row of this.progressData('')) {
          this.addPresentationTask(tasks, row.media, false, this.nextQuery.trim() ? row.episode.season : 0);
        }
      }
    } else if (this.tab === 'progress' && this.progressMode === 'next' && this.mediaMode === 'movie') {
      for (const row of this.movieProgressRows().slice((this.movieProgressPage - 1) * this.collectionPageSize,
        this.movieProgressPage * this.collectionPageSize)) { this.addPresentationTask(tasks, row.media, true); }
      if (this.presentationLanguage === 'zh' && (this.movieProgressQuery.trim() || this.movieProgressOptions.sort === 'title' || this.movieProgressOptions.sort === 'userRating')) {
        for (const row of this.movieProgressRows('')) { this.addPresentationTask(tasks, row.media, false); }
      }
    } else if (this.tab === 'progress' && this.progressMode === 'calendar') {
      if (this.mediaMode === 'show') {
        for (const row of this.calendarSlice()) { this.addPresentationTask(tasks, row.media, true, row.season); }
      } else {
        for (const row of this.movieSlice()) { this.addPresentationTask(tasks, row.movie.media, true); }
        if (this.movieCalendarQuery.trim() && this.presentationLanguage === 'zh') {
          for (const row of this.movieRows(this.movieCalendarMode, '')) { this.addPresentationTask(tasks, row.media, false); }
        }
      }
    }
    return Array.from(tasks.values());
  }

  private async presentationLane(repo: PresentationRepository, tasks: PresentationTask[], client: string, language: string,
    collection: boolean, text: boolean, current: () => boolean): Promise<boolean> {
    let pagePublished = false;
    if (text && language === 'zh') {
      // Publish already cached visible translations before any remote wait.
      try {
        for (const task of tasks) {
          if (!current()) { break; }
          if (task.artwork && !this.selectedMedia && !this.viewport.has(task.media,task.season)) { continue; }
          if (task.artwork && task.season > 0) { await repo.hydrateSeason(task.media,task.season); }
        }
        this.publishPresentation();
      } catch (error) { this.publishPresentation(); return true; }
    }
    for (const task of tasks) {
      if (!current()) { break; }
      if (task.artwork && !this.selectedMedia && !this.viewport.has(task.media,task.season)) { continue; }
      if (!pagePublished && !task.artwork) { this.publishPresentation(); pagePublished = true; }
      try {
        if (text) {
          // Local season translation does not depend on the title or artwork request.
          if (task.season > 0) { await repo.season(task.media,task.season,client,language); }
          if (current()) { await repo.translation(task.media,client,language); }
        } else {
          await repo.artwork(task.media,client,task.artwork,task.posterUrls,collection);
        }
      } catch (error) {
        this.publishPresentation();
        return true;
      }
    }
    this.publishPresentation();
    return false;
  }

  private async loadPresentation(): Promise<void> {
    const repo = this.presentation;
    if (!repo || this.presentationRunning) { return; }
    // Let state setters finish before collecting current-page tasks.
    await Promise.resolve();
    if (this.presentationRunning || !this.pageVisible || this.presentationBlocked) { return; }
    this.presentationRunning = true;
    try {
      while (this.presentationPending && this.pageVisible && !this.presentationBlocked) {
        this.presentationPending = false;
        const client = this.clientId;
        const language = this.presentationLanguage;
        const tab = this.tab;
        const mode = this.mediaMode;
        const progress = this.progressMode;
        const selected = this.selectedMedia?.id ?? '';
        const epoch = this.presentationEpoch;
        const current = (): boolean => this.pageVisible && this.presentationEpoch === epoch &&
          this.clientId === client && this.presentationLanguage === language && this.tab === tab &&
          this.mediaMode === mode && this.progressMode === progress && (this.selectedMedia?.id ?? '') === selected;
        // Two independent resource lanes, one sequential producer per lane.
        // No arbitrary concurrency multiplier; neither waits on the other's I/O.
        const tasks = this.presentationTasks();
        const failed = await Promise.all([
          this.presentationLane(repo,tasks,client,language,tab === 'library' && !selected,false,current),
          this.presentationLane(repo,tasks,client,language,false,true,current)
        ]);
        if (current() && failed.some((value: boolean) => value)) {
          this.presentationStatus = '部分海报或译名暂不可用；下拉刷新可重试。';
          this.presentationBlocked = true;
        }
      }
    } finally { this.presentationRunning = false; }
  }

  private async changePresentationLanguage(language: string): Promise<void> {
    if (!this.settings || this.languageBusy || this.presentationLanguage === language) { return; }
    this.languageBusy = true;
    try {
      await this.settings.saveLanguage(language);
      this.presentationLanguage = language;
      this.presentationEpoch++;
      this.presentationBlocked = false;
      this.presentationStatus = '';
      this.nextPage = 1;
      this.collectionPage = 1;
      this.movieProgressPage = 1;
      this.calendarPage = 1;
      this.requestPresentation();
    } catch (error) { this.presentationStatus = '影视资料语言保存失败。'; }
    finally { this.languageBusy = false; }
  }

  @Builder
  posterImage(item: Media, width: number, height: number) {
    if (this.artwork(item)) {
      Image(this.artwork(item)).width(width).height(height).objectFit(ImageFit.Cover).borderRadius(6)
    } else {
      Column() {
        Text('海报').fontSize(11).fontColor($r('app.color.showly_secondary'))
      }.width(width).height(height).justifyContent(FlexAlign.Center).borderRadius(6)
        .backgroundColor($r('app.color.showly_placeholder'))
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
    this.titleQuickPending = false;
    this.observationPending = false;
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
      this.requestObservation();
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
    this.titleConsent = undefined;
    this.titleQuickPending = false;
    this.titleConfirm = false;
    if (this.mediaStore) { await this.mediaStore.setTitleConsent('', '', false); }
    else if (this.signedIn) { throw new Error('Media store unavailable'); }
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
    this.viewport.clear();
    this.calendarRows.replace([],[],[]);
    this.movieCalendarRows.replace([],[],[]);
    this.collectionScope = '';
    this.collectionRatingKey = '';
    this.collectionRatings = [];
    this.collectionState = emptyCollectionState();
    this.collectionRowsSource.replace([], [], []);
    this.cancelCatalogRepair();
    this.showRows.replace([], [], []);
    this.movieRowsSource.replace([], [], []);
    this.showSummary = {key:'',total:0,page:1,pages:1};
    this.movieSummary = {key:'',total:0,page:1,pages:1};
    this.collectionSummary = {key:'',total:0,page:1,pages:1};
    this.discoverRows.replace([],[],[]);
    this.discoverTotal = 0;
    this.discoverPages = 0;
    this.discoverShownPage = 1;
    this.discoverMemo.clear();
    this.projectionMemo.clear();
    this.showProjectionCache.clear();
    this.libraryRevision++;
    this.displayRevisions.reset();
    this.collectionIndexMemos.clear();
    this.movieMetadataMemo.clear();
    this.libraryIndex.clear();
    this.libraryMemo.clear();
    this.sortJobs.clear();
    this.lazyRevision++;
    this.resetCalendar();
    this.invalidateSync();
    this.cloud = undefined;
    this.cloudUuid = '';
    this.cloudFresh = false;
    this.progressFlags = [];
    this.progressFlagScope = '';
    this.titleConsent = undefined;
    this.titleQuickPending = false;
    this.titleConfirm = false;
    this.movieUndo = undefined;
    this.movieUndoStatus = '';
    this.cloudLocalAllowed = false;
    this.localSeries = undefined;
    this.effectiveEditable = false;
    this.nextShows = [];
    this.libraryEvidence = [];
    this.cloudStatus = '';
    this.trackingPage = 1;
    this.trackingQuery = '';
    this.resetCollection();
  }

  private async readLibraryProjection(store: EpisodeStore, snapshot: CloudLibrary | undefined, uuid: string,
    clientId: string, fill: boolean, force: boolean, current: () => boolean): Promise<LibraryProjection> {
    const records = this.mediaRecords;
    const recordKey = JSON.stringify(records);
    const key = projectionKey(clientId, uuid, snapshot?.generation ?? -1, snapshot?.activity ?? '',
      store.readModelRevision(), recordKey);
    const cached = force ? undefined : this.projectionMemo.get(key, Date.now());
    if (cached && current()) {
      this.projectionHits++;
      this.performanceStatus = '全库计算 ' + this.projectionRuns + ' 次 · 缓存命中 ' + this.projectionHits + ' 次';
      return cached;
    }
    this.projectionRuns++;
    const started = Date.now();
    const queryStart = store.readQueryCount();
    const result = await projectLibrary(store, records, snapshot, uuid, clientId, fill, current,
      (done: number, total: number): void => {
        if (fill) { this.cloudStatus = '计算个人库及补齐目录 ' + done + '/' + total; }
      }, this.showProjectionCache);
    if (!current()) { throw new Error('Observation session changed'); }
    const finalKey = projectionKey(clientId, uuid, snapshot?.generation ?? -1, snapshot?.activity ?? '',
      store.readModelRevision(), JSON.stringify(this.mediaRecords));
    // The caller serializes edits with cloudBusy/localBusy. A missing or
    // failed catalog must be retried, not memoized as complete.
    if (result.cacheable && recordKey === JSON.stringify(this.mediaRecords) && !result.matches.length) {
      this.projectionMemo.put(finalKey, result, result.computedAt, result.validUntil);
    }
    this.performanceStatus = '全库计算 ' + this.projectionRuns + ' 次 · 缓存命中 ' + this.projectionHits +
      ' 次 · 本轮重算 ' + result.computedShows + ' 部 / 复用 ' + result.reusedShows + ' 部（磁盘 ' + result.diskHits + ' 部） · 目录解析 ' + result.scheduleParses + ' / 缓存解析 ' + result.diskParses + ' / 缓存行更新 ' + result.diskWrites + ' / 后台批次 ' + result.workerBatches + ' · 计算 ' +
      (Date.now() - started) + ' ms · EpisodeStore SELECT ' + (store.readQueryCount() - queryStart) + ' 次' + (this.projectionRuns === 1 ? ' · 启动至首轮计算完成 ' + (Date.now() - this.startupAt) + ' ms' : '');
    return result;
  }

  private async loadCloud(force: boolean = true): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.ready || !this.episodeReady || this.cloudBusy || this.localBusy || this.saving ||
        this.backupBusy || this.syncBusy || this.setupBusy || this.authBusy || !this.clientId) { return; }
    this.cancelCatalogRepair();
    this.cloudBusy = true;
    this.cloudFresh = false;
    this.cloudStatus = '正在验证账户并读取个人库…';
    const clientId = this.clientId;
    try {
      await traktAuth.restore(clientId, true);
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('请先完成 Trakt 登录'); }
      const account = await readSyncAccount(session);
      const current = (): boolean => this.clientId === clientId && traktAuth.isCurrent(clientId, session.generation);
      if (!current()) { throw new Error('Session changed'); }
      if (this.cloudUuid !== account.uuid || this.cloud?.generation !== session.generation) {
        this.clearCloud();
      }
      const bound = await store.boundAccount();
      if (!current()) { throw new Error('Session changed'); }
      this.cloudLocalAllowed = allowLocalScope(true, bound, account.uuid);
      const cached = this.activeCloud() && this.cloudUuid === account.uuid ? undefined : await store.readRemoteObservation(account.uuid);
      if (!current()) { throw new Error('Session changed'); }
      let initialProjection: LibraryProjection | undefined;
      let initialSnapshot: CloudLibrary | undefined;
      let initialRevision = -1;
      let initialRecords = '';
      if (cached) {
        const restored: CloudLibrary = { generation: session.generation, activity: cached.activity,
          observedAt: cached.observedAt, watchlist: cached.watchlist, watchedMovies: cached.watchedMovies,
          shows: cached.shows, moviePlays: cached.moviePlays, queueDates: cached.queueDates, movieDetails: cached.movieDetails };
        this.cloud = restored;
        this.cloudUuid = account.uuid;
        this.publishMovieSource(restored);
        this.reloadProgressFlags();
        this.resetCollection();
        this.cloudStatus = '已读取本账户缓存，正在核对云端版本…';
        this.libraryNotice = '显示已验证账户的上次缓存；正在核对云端版本。';
        // Local-first render, no network catalog fill and no checkpoint writes.
        // The existing cloudBusy gate remains active until fresh verification.
        try {
          const initial = await this.readLibraryProjection(store, restored, account.uuid, clientId, false, false, current);
          if (!current()) { throw new Error('Session changed'); }
          initialProjection = initial;
          initialSnapshot = restored;
          initialRevision = store.readModelRevision();
          initialRecords = JSON.stringify(this.mediaRecords);
          this.nextShows = initial.next;
          this.libraryEvidence = initial.evidence;
          this.reloadProgressFlags();
        } catch (error) {
          if (!current()) { throw new Error('Session changed'); }
        }
      }
      let snapshot = this.cloud;
      try {
        const revision = await readActivity(session);
        const changed = !snapshot || snapshot.activity !== revision || snapshot.queueDates === undefined || snapshot.movieDetails === undefined;
        if (changed) { snapshot = await readCloudLibrary(session); }
        if (!snapshot) { throw new Error('Observation unavailable'); }
        const verified = await readSyncAccount(session);
        if (!current() || verified.uuid !== account.uuid || await readActivity(session) !== snapshot.activity) {
          throw new Error('Account or activity changed');
        }
        if (!current()) { throw new Error('Session changed'); }
        if (changed) { await store.saveRemoteObservation(account.uuid, snapshot); }
        if (!current()) { throw new Error('Session changed'); }
        this.cloud = snapshot;
        this.cloudUuid = account.uuid;
        this.publishMovieSource(snapshot);
        if (changed) { this.libraryEvidence = []; }
        this.cloudFresh = true;
      } catch (error) {
        if (!current() || !this.cloud || this.cloudUuid !== account.uuid) { throw new Error('读取云端失败'); }
        snapshot = this.cloud;
      }
      if (!snapshot || !current()) { throw new Error('Observation unavailable'); }
      const mediaStore = this.mediaStore;
      if (this.cloudFresh && this.cloudLocalAllowed && mediaStore) {
        try {
          const records = await reconcileTitleObservation(mediaStore, store, session, account.uuid, snapshot, current);
          if (!current()) { throw new Error('Session changed'); }
          if (JSON.stringify(records) !== JSON.stringify(this.mediaRecords)) {
            this.mediaRecords = records;
            this.items = records.map((record: MediaRecord) => record.media);
          }
          const consent = await mediaStore.titleConsent();
          if (!current()) { throw new Error('Session changed'); }
          this.titleConsent = consent?.uuid === account.uuid && consent.clientId === clientId ? consent : undefined;
          this.syncAccount = account;
          this.syncBound = true;
          if ((await mediaStore.pendingTargets(account.uuid)).length > 0) { this.mediaRecoveryPending = true; }
          if (this.titleQuickActive()) {
            const intents = await mediaStore.titleIntents(account.uuid);
            this.titleQuickPending = intents.some((intent: TitleIntent) => intent.state === 'open' && intent.epoch === this.titleConsent?.epoch);
          }
        } catch (error) {
          if (!current()) { throw new Error('Session changed'); }
          // Partial read coordination must not publish stale title records.
          const retained = await mediaStore.load();
          if (!current()) { throw new Error('Session changed'); }
          this.mediaRecords = retained;
          this.items = this.mediaRecords.map((record: MediaRecord) => record.media);
          this.titleQuickPending = false;
          this.titleQuickStatus = '影视状态协调未完成，请刷新。';
        }
      }
      // The cached first pass already performed live resolution. When fresh
      // verification and title reconciliation leave every input unchanged,
      // reuse even an incomplete first pass; repair is scheduled separately.
      const now = Date.now();
      const reuseInitial = initialProjection && initialSnapshot === snapshot &&
        initialRevision === store.readModelRevision() && initialRecords === JSON.stringify(this.mediaRecords) &&
        now >= initialProjection.computedAt && now < initialProjection.validUntil;
      const result = reuseInitial && initialProjection ? initialProjection :
        await this.readLibraryProjection(store, snapshot, account.uuid, clientId, false, force, current);
      if (reuseInitial) { this.performanceStatus += ' · 首轮投影复用'; }
      let checkpointChanged = false;
      if (!current()) { throw new Error('Session changed'); }
      if (this.cloudFresh && result.localAllowed && result.matches.length &&
          await readActivity(session) === snapshot.activity && current()) {
        await store.saveReadCheckpoints(account.uuid, result.matches);
        checkpointChanged = true;
      }
      if (!current()) { throw new Error('Session changed'); }
      this.cloudLocalAllowed = result.localAllowed;
      this.nextShows = result.next;
      this.reloadProgressFlags();
      this.nextPage = 1;
      this.movieProgressPage = 1;
      this.nextStatus = result.missing ? '部分剧集资料尚未补齐。' : '';
      this.libraryEvidence = result.evidence;
      this.resetCollection();
      await this.refreshEffectiveDetail();
      // A newly acknowledged watch time can alter LAST_WATCHED. Only that
      // real input change requires a follow-up projection.
      if (checkpointChanged) { this.projectionPending = true; }
      if (this.cloudFresh) { this.repairTargets = result.repairTargets; }
      this.libraryNotice = !this.cloudFresh ? '更新未完成，显示上次记录。' : result.missing || result.failed ? '部分剧集资料尚未补齐。' : '';
      this.cloudStatus = (this.cloudFresh ? '云端版本已核对' : '使用上次缓存（非实时）') +
        ' · 缺少目录 ' + result.missing + ' 部 · 下载失败 ' + result.failed + ' 部；未写入 Trakt。' + (result.localAllowed ? '' : ' 当前账户只读；本机库未绑定或属于另一账户。');
      if (this.tab === 'library' && this.collectionGrid && !this.selectedMedia) { this.loadCollectionPosters(); }
      // Movie progress and calendar consume the already verified observation.
      // Optional rating reads run outside the cloudBusy gate.
    } catch (error) {
      if (!this.cloud || !traktAuth.isCurrent(clientId, this.cloud.generation)) { this.clearCloud(); }
      this.libraryNotice = '更新未完成，请重试。';
      this.cloudStatus = '读取未完成：' + safeSyncError(error as Error) + '；保留原记录。';
    } finally { this.cloudBusy = false; this.scheduleLazyRows(); }
  }

  private async importCloud(): Promise<void> {
    const snapshot = this.cloud;
    if (!snapshot || !this.cloudFresh || !this.cloudLocalAllowed || this.cloudBusy || this.saving || !this.ready || this.authBusy || this.setupBusy) {
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

  private async persistMedia(records: MediaRecord[], changes: TitleChange[] = []): Promise<boolean> {
    const store = this.mediaStore;
    if (!this.ready || this.saving || this.syncBusy || !store || !this.canEditLibrary()) { return false; }
    const dateScope = this.currentProgressScope();
    const beforeDates = changes.length ? this.personalLibrary() : [];
    this.saving = true;
    this.clearThreeWayReview();
    this.mediaSelected = undefined;
    this.mediaWatchTime = '';
    this.mediaPreview = undefined;
    this.mediaPreviewStatus = '';
    this.mediaPage = 1;
    try {
      const snapshot = this.activeCloud();
      const uuid = this.cloudUuid;
      const scoped = changes.length > 0 && !!snapshot && this.cloudLocalAllowed && !!uuid;
      if (scoped && await this.episodeStore?.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
      if (!this.canEditLibrary() || snapshot !== this.activeCloud() || uuid !== this.cloudUuid) { throw new Error('Session changed'); }
      const verified = scoped ? await store.saveTitleEdit(records, changes, uuid, this.clientId,
        new Date().toISOString(), this.titleQuickActive()) : await store.save(records);
      this.invalidateMovieCalendar();
      this.mediaRecords = verified;
      this.items = verified.map((record: MediaRecord) => record.media);
      try { await this.recordTitleDates(dateScope, beforeDates, changes); }
      catch (error) { this.collectionRuleStatus = '收藏已保存，但添加时间未能保存。'; }
      this.resetCollection();
      if (this.collectionGrid && this.tab === 'library' && !this.selectedMedia) { this.loadCollectionPosters(); }
      this.libraryStatus = '已保存到本机；未修改 Trakt';
      this.libraryNotice = '';
      this.requestProjection();
      if (scoped && this.titleQuickActive()) { this.titleQuickPending = true; }
      this.migrationStatus = '收藏数据库已就绪 · ' + verified.length + ' 部；旧版 Preferences 保留。';
      return true;
    } catch (error) {
      this.libraryStatus = '保存或回读失败，已停止写入；请重启应用检查记录，不要清除数据。';
      this.libraryNotice = '保存失败，请重启应用检查记录。不要清除数据。';
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
    if (!this.ready || this.saving || this.cloudBusy || this.syncBusy || !this.canEditLibrary() ||
        this.items.some((value: Media) => value.id === item.id)) { return; }
    this.save([...this.items, item], 'add');
  }

  private isInLibrary(item: Media): boolean {
    const row = this.personalLibrary().length ? this.libraryIndex.get(item.id) : undefined;
    return !!row && isPersonalMember(row);
  }

  private isFollowed(item: Media): boolean {
    const row = this.personalLibrary().length ? this.libraryIndex.get(item.id) : undefined;
    return !!row && hasTrackingEvidence(row);
  }

  private mediaIntent(item: Media, domain: string): string {
    const record = this.mediaRecords.find((row: MediaRecord) => row.media.id === item.id);
    return domain === 'movie' ? record?.movieState ?? 'unknown' : record?.watchlistState ?? 'unknown';
  }

  private localIntentLabel(value: string): string {
    return value === 'yes' ? '明确标记' : value === 'no' ? '明确撤销/移出' : '未明确设置（旧记录保留）';
  }

  private async changeMediaIntent(item: Media, domain: string, value: string): Promise<void> {
    if (this.isHidden(item) || this.collectionEditBusy || !this.ready || this.saving || this.cloudBusy || this.syncBusy || !this.canEditLibrary() ||
        (domain === 'movie' && this.progressPrefsBusy)) { return; }
    const pinScope = this.currentProgressScope();
    const movieEdit = domain === 'movie' && item.kind === 'movie';
    if (movieEdit) { this.progressPrefsBusy = true; }
    try {
      const edit = titleEdit(this.mediaRecords, item, domain, value);
      const saved = await this.persistMedia(edit.records, edit.changes);
      if (saved && domain === 'movie') {
        await this.clearWatchedMoviePin(item, pinScope);
        this.movieProgressPage = 1;
        this.movieUndo = value === 'no' && this.signedIn ? item : undefined;
        this.movieUndoStatus = '';
        if (this.movieUndo) { this.libraryNotice = '观看标记已撤销；同步历史移除需单独核对。'; }
      }
    } catch (error) {
      this.libraryStatus = '本机状态校验失败，未保存。';
    } finally {
      if (movieEdit) { this.progressPrefsBusy = false; this.reloadProgressFlags(); }
    }
  }

  private async clearWatchedMoviePin(item: Media, scope: string): Promise<void> {
    const settings = this.settings;
    if (!settings || !scope || scope !== this.currentProgressScope() || scope !== this.progressFlagScope ||
        !this.progressFlag(item)?.pinned) { return; }
    try {
      const flags = clearMoviePin(this.progressFlags, item.id);
      await settings.saveProgressFlags(scope, flags);
      if (scope === this.currentProgressScope()) { this.progressFlags = flags; }
    } catch (error) { this.progressOptionStatus = '观看状态已保存，但取消置顶失败，请重试。'; }
  }

  private async joinFollowed(item: Media): Promise<void> {
    if (this.isHidden(item) || this.collectionEditBusy || !this.ready || this.saving || this.cloudBusy || this.syncBusy || !this.canEditLibrary()) { return; }
    try {
      const edit = titleEdit(this.mediaRecords, item, 'follow', 'yes');
      await this.persistMedia(edit.records, edit.changes);
    }
    catch (error) { this.libraryStatus = '追剧状态保存失败。'; }
  }

  private async reviewMovieUndo(): Promise<void> {
    const item = this.movieUndo;
    const media = this.mediaStore;
    const binding = this.episodeStore;
    const clientId = this.clientId;
    const session = traktAuth.session(clientId);
    const uuid = this.cloudUuid;
    if (!item || !media || !binding || !session || !this.canEditLibrary() || !this.pageVisible ||
        this.syncBusy || this.saving || this.localBusy || this.cloudBusy || this.authBusy || this.setupBusy ||
        this.backupBusy) { return; }
    this.syncBusy = true;
    this.mediaSelected = undefined;
    this.mediaPreview = undefined;
    this.movieUndoStatus = '正在核对单次观看历史…';
    try {
      const preview = await buildMediaPreview(binding, session, await media.load(), uuid, media);
      if (this.movieUndo?.id !== item.id || this.cloudUuid !== uuid || !this.canEditLibrary() ||
          !traktAuth.isCurrent(clientId, session.generation)) { throw new Error('Account changed'); }
      const row = preview.rows.find((value: MediaDifference) => value.id === item.id && value.domain === 'movie');
      if (!row?.remote) {
        this.movieUndoStatus = '无需移除历史。';
        return;
      }
      if (row.operation !== 'remove') {
        this.movieUndoStatus = '无法确认属于本应用的单次历史，未删除。';
        return;
      }
      this.syncAccount = preview.account;
      this.syncBound = true;
      this.mediaPreview = preview;
      this.selectMediaOperationForUndo(row);
      this.movieUndoStatus = '确认后仅移除已核实的单次观看历史。';
    } catch (error) { this.movieUndoStatus = '核对失败，未删除任何历史。'; }
    finally { this.syncBusy = false; }
  }

  private selectMediaOperationForUndo(row: MediaDifference): void {
    this.mediaSelected = row;
    this.mediaWatchTime = new Date().toISOString();
  }

  @Builder
  movieUndoView() {
    if (this.movieUndo && this.canEditLibrary() && this.signedIn) {
      Column({ space: 6 }) {
        Text('撤销观看 · ' + this.movieUndo.title).fontSize(14).width('100%')
        if (this.movieUndoStatus) { Text(this.movieUndoStatus).fontSize(12).width('100%') }
        if (this.mediaSelected?.id === this.movieUndo.id && this.mediaSelected?.domain === 'movie' &&
            this.mediaSelected?.operation === 'remove' && this.mediaPreview) {
          Button('确认移除单次观看历史').enabled(!this.syncBusy && !this.saving && !this.cloudBusy && !this.localBusy)
            .onClick(() => { this.confirmMediaOperation(); this.movieUndo = undefined; })
        } else {
          Button('核对是否可同步撤销').enabled(!this.syncBusy && !this.saving && !this.cloudBusy && !this.localBusy)
            .onClick(() => { this.reviewMovieUndo(); })
        }
        Button('关闭').enabled(!this.syncBusy).onClick(() => {
          this.movieUndo = undefined; this.movieUndoStatus = ''; this.mediaSelected = undefined;
        })
      }.width('100%').padding(8)
    }
  }

  @Builder
  mediaStateView(item: Media) {
    Column({ space: 8 }) {
      Text('收藏与观看状态').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      this.librarySyncNotice()
      if (this.movieUndo?.id === item.id) { this.movieUndoView() }
      if (item.kind === 'movie') {
        Text(this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id)?.watched ? '已看' : '未看或未确认').fontSize(14).width('100%')
        Button(this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id)?.watched ? '撤销已看' : '标记已看')
          .width('100%').enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
          .onClick(() => { this.changeMediaIntent(item, 'movie',
            this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id)?.watched ? 'no' : 'yes'); })
      }
      if (item.kind === 'movie') { this.showProgressActions(item) }
      if (item.kind === 'show') {
        Text(this.isFollowed(item) ? '追剧中' : '未加入追剧').fontSize(14).width('100%')
        this.showProgressActions(item)
        if (!this.isFollowed(item)) {
          Button('加入追剧').width('100%')
            .enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
            .onClick(() => { this.joinFollowed(item); })
        }
      }
      Button(this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id)?.queued ?
        '移出待看' : this.isFollowed(item) ? '移回待看' : '加入待看')
        .width('100%').enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
        .onClick(() => { this.changeMediaIntent(item, 'watchlist',
          this.personalLibrary().find((row: PersonalLibraryRow) => row.media.id === item.id)?.queued ? 'no' : 'yes'); })
      if (!this.ready) { Text('收藏暂不可编辑，请检查设置。').fontSize(12).width('100%') }
      if (this.libraryStatus.includes('失败')) { Text('操作未完成，请检查设置后重试。').fontSize(12).width('100%') }
      if (this.libraryNotice) { Text(this.libraryNotice).fontSize(12).width('100%') }
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
      this.cloudLocalAllowed = false;
      this.libraryEvidence = [];
      this.cloudFresh = false;
      this.requestObservation();
      this.cloudStatus = '电影/待看操作已结束；正在重新读取云端清单。';
      this.resetCollection();
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
      Text('性能诊断：' + this.performanceStatus).fontSize(12).width('100%')
      Text('高级管理用于未授权操作、异常及历史撤销。已有保护凭证只读核对，不会重发。')
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
      const client = this.clientId;
      const query = this.title.trim();
      const rows = await searchTrakt(query, client);
      if (this.clientId !== client || this.title.trim() !== query) { return; }
      const ids: Set<string> = new Set<string>(rows.map((item: Media) => item.id));
      for (const row of this.personalLibrary()) {
        if (isTraktMedia(row.media) && !ids.has(row.media.id) && this.matchesMedia(row.media, query)) {
          rows.push(row.media);
          ids.add(row.media.id);
        }
      }
      this.results = rows;
      this.searchStatus = this.results.length === 0 ? '没有搜索结果' : '搜索完成';
    } catch (error) {
      this.searchStatus = '搜索失败：请检查网络、Client ID 或 Trakt API 权限与限额。';
    } finally {
      this.searching = false;
    }
  }

  private resetDiscover(): void {
    ++this.discoverRevision;
    this.discoverFeed = undefined;
    this.discoverFeedKey = '';
    this.discoverMemo.clear();
    this.discoverRows.replace([],[],[]);
    this.discoverItems = [];
    this.discoverPage = 1;
    this.discoverShownPage = 1;
    this.discoverPages = 0;
    this.discoverTotal = 0;
    this.discoverBusy = false;
    this.discoverStatus = '';
  }
  private restoreDiscoverOptions(): void {
    this.discoverOptions = this.settings?.loadDiscoverOptions(this.mediaMode) ?? defaultDiscover();
    this.discoverMode = this.discoverOptions.mode;
    this.discoverGenreDraft = this.discoverOptions.genres.join(',');
    this.discoverNetworkDraft = this.discoverOptions.networks.join(',');
  }
  private discoverCollectionSize(): number {
    let count = 0;
    for (const row of this.personalLibrary()) {
      if (row.media.kind !== this.mediaMode) { continue; }
      if (row.queued) { count++; }
      if (row.watched || hasTrackingEvidence(row)) { count++; }
    }
    return count + this.currentCollectionState().hidden.filter((row: HiddenEntry) => row.media.kind === this.mediaMode).length;
  }
  private async loadDiscover(page: number = 1, force: boolean = false): Promise<void> {
    if (this.setupBusy || !this.clientId || page < 1 || !this.pageVisible || this.tab !== 'discover') { return; }
    const revision = ++this.discoverRevision;
    const clientId = this.clientId;
    const kind = this.mediaMode;
    const options = this.discoverOptions;
    const request = discoverRequest(kind,options,this.discoverCollectionSize());
    const key = discoverKey(clientId,request);
    const current = (): boolean => revision === this.discoverRevision && clientId === this.clientId &&
      kind === this.mediaMode && this.pageVisible && this.tab === 'discover' && this.discoverOptions === options;
    const publish = (feed: DiscoverFeed, fresh: boolean): void => {
      if (!current()) { return; }
      this.discoverFeed = feed;
      this.discoverFeedKey = key;
      this.discoverMemo.clear();
      this.discoverItems = feed.items;
      this.discoverPage = page;
      this.discoverStatus = fresh ? '本地榜单已就绪' : '显示本地旧榜单，正在更新…';
      this.requestPresentation();
    };
    if (this.discoverFeed && this.discoverFeedKey === key) {
      if (!force && discoverFresh(this.discoverFeed,Date.now())) {
        this.discoverPage = page;
        this.discoverStatus = '本地榜单已就绪';
        this.discoverBusy = false;
        this.requestPresentation();
        return;
      }
      publish(this.discoverFeed,false);
    } else {
      this.discoverFeed = undefined; this.discoverFeedKey = ''; this.discoverMemo.clear();
      this.discoverRows.replace([],[],[]);
      this.discoverItems = []; this.discoverTotal = 0; this.discoverPages = 0; this.discoverShownPage = 1;
    }
    this.discoverBusy = true;
    if (!this.discoverFeed) { this.discoverStatus = '正在读取本地榜单…'; }
    try {
      if (!this.discoverRepo) { this.discoverRepo = openDiscover(this.context()); }
      const repo = await this.discoverRepo;
      if (!current()) { return; }
      const feed = await repo.load(clientId,request,force,publish);
      if (!current()) { return; }
      publish(feed,true);
    } catch (error) {
      if (current()) { this.discoverStatus = this.discoverFeed ? '网络更新失败，保留本地榜单。' : '榜单不可用，请检查网络或 Trakt 权限后重试。'; }
    } finally {
      if (current()) { this.discoverBusy = false; this.requestPresentation(); }
    }
  }
  private async applyDiscover(options: DiscoverOptions): Promise<void> {
    if (!validDiscoverOptions(options)) { this.discoverStatus = '筛选无效，请使用下方列出的类型或电视网代码。'; return; }
    const kind = this.mediaMode;
    this.resetDiscover();
    this.discoverOptions = options;
    this.discoverMode = options.mode;
    this.discoverGenreDraft = options.genres.join(',');
    this.discoverNetworkDraft = options.networks.join(',');
    this.loadDiscover();
    try { await this.settings?.saveDiscoverOptions(kind,options); }
    catch (error) { if (kind === this.mediaMode && this.discoverOptions === options) { this.discoverStatus = '筛选已应用，但设置未保存。'; } }
  }
  private changeDiscover(mode: string): void {
    if (mode === this.discoverMode) { return; }
    this.applyDiscover({mode:mode,genres:this.discoverOptions.genres,networks:this.discoverOptions.networks,hideCollection:this.discoverOptions.hideCollection});
  }
  private applyDiscoverDraft(): void {
    const genres = this.discoverGenreDraft.split(',').map((x: string) => x.trim().toLowerCase()).filter((x: string) => !!x);
    const networks = this.mediaMode === 'show' ? this.discoverNetworkDraft.split(',').map((x: string) => x.trim().toUpperCase()).filter((x: string) => !!x) : [];
    this.applyDiscover({mode:this.discoverMode,genres:genres,networks:networks,hideCollection:this.discoverOptions.hideCollection});
  }
  private discoverPageResult(): DiscoverPage {
    // Public feed storage contains no personal membership or watch state.
    // Do not interpret an unverified account as an empty collection.
    if (this.discoverOptions.hideCollection && (!this.ready || (this.signedIn && !this.activeCloud()))) { return discoverPage([],1); }
    const now = Date.now();
    const day = new Date(now).toISOString().substring(0,10);
    const key = JSON.stringify([this.discoverFeedKey,this.discoverFeed?.fetchedAt ?? 0,this.discoverMode,this.discoverOptions.hideCollection,
      this.libraryRevision,this.displayRevisions.collection,this.currentProgressScope(),day]);
    let rows = this.discoverMemo.get(key,now);
    if (!rows) {
      const hidden = new Set<string>(this.currentCollectionState().hidden.map((x: HiddenEntry) => x.media.id));
      const members = new Set<string>();
      if (this.discoverOptions.hideCollection) {
        for (const row of this.personalLibrary()) { if (isPersonalMember(row)) { members.add(row.media.id); } }
      }
      rows = filterDiscover(this.discoverItems,this.discoverOptions,hidden,members,now);
      this.discoverMemo.put(key,rows,now,Date.parse(day+'T00:00:00Z')+86400000);
    }
    return discoverPage(rows,this.discoverPage);
  }
  private visibleDiscover(): DiscoverItem[] { return this.discoverPageResult().items; }

  @Builder
  discoverCard(item: DiscoverItem) {
    Column({ space: 6 }) {
      if (this.artwork(item.media)) {
        Image(this.artwork(item.media)).width('100%').aspectRatio(0.667)
          .objectFit(ImageFit.Cover).borderRadius(10)
      } else {
        Column() {
          Text('海报').fontColor($r('app.color.showly_secondary')).fontSize(14)
        }.width('100%').aspectRatio(0.667)
          .justifyContent(FlexAlign.Center).backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
      }
      Text(this.displayTitle(item.media)).fontSize(15).fontWeight(FontWeight.Medium)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text((item.media.year > 0 ? item.media.year.toString() : '年份未知') +
        (item.rating > 0 ? ' · ★ ' + item.rating.toFixed(1) : ''))
        .fontSize(12).fontColor($r('app.color.showly_secondary')).width('100%')
      this.showProgressActions(item.media)
    }.width('48%').padding({ bottom: 12 })
      .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(item.media,0,item.posterUrls,visible && ratio > 0,'discover',''); })
      .onClick(() => { this.openDetail(item.media); })
  }

  @Builder
  discoverView() {
    List({ space: 12 }) {
      ListItem() {
        Column({ space: 12 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
      Text(this.mediaMode === 'show' ? '发现剧集' : '发现电影').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      if (!this.clientId) {
        Text('请先在账户页配置自己的 Trakt Client ID。').fontSize(14)
        Button('前往账户').onClick(() => { this.tab = 'account'; })
      } else {
        Row({ space: 6 }) {
          this.discoverModeButton('趋势', 'trending')
          this.discoverModeButton('热门', 'popular')
          this.discoverModeButton('最近播出', 'recent')
          this.discoverModeButton(this.mediaMode === 'movie' ? '即将上映' : '即将播出', 'anticipated')
        }.width('100%')
        TextInput({placeholder:'类型代码，逗号分隔',text:this.discoverGenreDraft})
          .onChange((value: string) => { this.discoverGenreDraft = value; })
        Text(DISCOVER_GENRES.join(', ')).fontSize(11).width('100%')
        if (this.mediaMode === 'show') {
          TextInput({placeholder:'电视网代码，逗号分隔',text:this.discoverNetworkDraft})
            .onChange((value: string) => { this.discoverNetworkDraft = value; })
          Text(DISCOVER_NETWORKS.join(', ')).fontSize(11).width('100%')
        }
        Row({space:8}) {
          Button('应用筛选').layoutWeight(1).onClick(() => { this.applyDiscoverDraft(); })
          Button(this.discoverOptions.hideCollection ? '显示已收藏' : '隐藏已收藏').layoutWeight(1)
            .onClick(() => { this.applyDiscover({mode:this.discoverMode,genres:this.discoverOptions.genres,networks:this.discoverOptions.networks,hideCollection:!this.discoverOptions.hideCollection}); })
        }.width('100%')
        Text(this.discoverStatus).fontSize(12).width('100%')
        if (this.discoverOptions.hideCollection && (!this.ready || (this.signedIn && !this.activeCloud()))) {
          Text('正在核对个人库，暂不显示未验证的收藏筛选结果。').fontSize(12).width('100%')
        } else { Text('共 '+this.discoverTotal+' 部').fontSize(12).width('100%') }
        Button(this.discoverBusy ? '加载中…' : '刷新榜单')
          .enabled(!this.discoverBusy && !this.setupBusy)
          .onClick(() => { this.loadDiscover(this.discoverPage,true); })
      }
        }.width('100%')
      }
      if (this.clientId) {
        LazyForEach(this.discoverRows, (row: DiscoverItem[]) => {
          ListItem() {
            Row({ space: 8 }) {
              ForEach(row,(item: DiscoverItem) => { this.discoverCard(item) },(item: DiscoverItem) => item.media.id + ':' + this.artwork(item.media) + ':' + this.displayTitle(item.media))
            }.width('100%').justifyContent(FlexAlign.SpaceBetween)
          }
        }, (row: DiscoverItem[]) => this.discoverRows.keyFor(row.map((item: DiscoverItem) => item.media.id).join(',')))
        ListItem() {
        Row({ space: 8 }) {
          Button('上一页').layoutWeight(1)
             .enabled(!this.discoverBusy && this.discoverShownPage > 1)
            .onClick(() => { this.loadDiscover(this.discoverShownPage - 1); })
          Text(this.discoverShownPage + ' / ' + (this.discoverPages || 1)).fontSize(13)
          Button('下一页').layoutWeight(1)
            .enabled(!this.discoverBusy && this.discoverShownPage < this.discoverPages)
            .onClick(() => { this.loadDiscover(this.discoverShownPage + 1); })
        }.width('100%')
        }
      }
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  discoverModeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .backgroundColor(this.discoverMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.discoverMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.changeDiscover(mode); })
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
    this.projectionMemo.clear();
    this.nextShows = [];
    this.libraryEvidence = [];
    this.projectionPending = true;
    this.resetCollection();
    this.nextPage = 1;
    this.nextStatus = '观看记录已变化，正在更新进度。';
  }

  private async loadNextShows(): Promise<void> {
    const store = this.episodeStore;
    if (!store || !this.episodeReady || this.localBusy || this.cloudBusy || this.syncBusy || this.backupBusy) { return; }
    this.localBusy = true;
    this.nextStatus = '正在更新追剧进度…';
    try {
      const snapshot = this.cloud;
      const uuid = this.cloudUuid;
      const clientId = this.clientId;
      const signedIn = this.signedIn;
      const active = snapshot && signedIn && traktAuth.isCurrent(clientId, snapshot.generation) ? snapshot : undefined;
      if (signedIn && !active) { this.nextShows = []; this.libraryEvidence = []; return; }
      const result = await this.readLibraryProjection(store, active, uuid, clientId, false, false,
        (): boolean => this.signedIn === signedIn && this.activeCloud() === active && this.cloudUuid === uuid && this.clientId === clientId);
      if (this.activeCloud() !== active || this.cloudUuid !== uuid || (this.signedIn && !active)) { return; }
      this.nextShows = result.next;
      this.reloadProgressFlags();
      this.cloudLocalAllowed = result.localAllowed && !!active;
      this.libraryEvidence = result.evidence;
      this.resetCollection();
      await this.refreshEffectiveDetail();
      if (this.tab === 'library' && this.collectionGrid && !this.selectedMedia) { this.loadCollectionPosters(); }
      this.nextPage = 1;
      this.nextStatus = result.missing ? '部分剧集资料尚未补齐。' : '';
      if (this.cloudFresh && active) { this.libraryNotice = result.repairTargets.length ? '部分剧集资料尚未补齐。' : ''; }
    } catch (error) {
      this.invalidateNextShows();
      this.projectionPending = false;
      this.nextStatus = '进度更新失败，请重试。';
    } finally { this.localBusy = false; }
  }

  private currentProgressScope(): string {
    if (!this.signedIn) { return 'device'; }
    return this.activeCloud() && this.cloudUuid ? 'account:' + this.cloudUuid : '';
  }

  private reloadProgressFlags(): void {
    this.reloadCollectionState();
    const scope = this.currentProgressScope();
    if (scope === this.progressFlagScope || this.progressPrefsBusy) { return; }
    this.progressFlags = [];
    this.progressFlagScope = '';
    if (!scope || !this.settings) { return; }
    try {
      this.progressFlags = this.settings.loadProgressFlags(scope);
      this.progressFlagScope = scope;
    } catch (error) { this.progressOptionStatus = '置顶与暂缓设置无法读取，未覆盖原记录。'; }
  }

  private async editProgressFlag(item: Media, kind: string): Promise<void> {
    if (this.isHidden(item) || this.collectionEditBusy) { return; }
    const id = item.id;
    const settings = this.settings;
    const scope = this.currentProgressScope();
    if (!settings || !scope || scope !== this.progressFlagScope || this.progressPrefsBusy ||
        !this.canEditLibrary() || this.localBusy || this.cloudBusy || this.syncBusy || this.saving ||
        this.authBusy || this.setupBusy || this.backupBusy || !this.pageVisible ||
        !isTraktMedia(item) || (kind !== 'pin' && kind !== 'hold') || (item.kind === 'movie' && kind !== 'pin')) { return; }
    this.progressPrefsBusy = true;
    try {
      const flags = toggleProgressFlag(this.progressFlags, id, kind);
      await settings.saveProgressFlags(scope, flags);
      if (this.currentProgressScope() !== scope) { return; }
      this.progressFlags = flags;
      this.nextPage = 1;
      this.movieProgressPage = 1;
      this.progressOptionStatus = '';
    } catch (error) { this.progressOptionStatus = '设置保存失败，请重试。'; }
    finally { this.progressPrefsBusy = false; this.reloadProgressFlags(); }
  }

  private async editProgressOption(key: string, value: string): Promise<void> {
    const settings = this.settings;
    if (!settings || this.progressPrefsBusy) { return; }
    const old = this.progressPrefs;
    const next: ProgressPreferences = {
      strategy: key === 'strategy' ? value : old.strategy,
      count: key === 'count' ? value : old.count,
      days: key === 'days' ? Number(value) : old.days,
      sort: key === 'sort' ? value : old.sort,
      descending: key === 'direction' ? !old.descending : old.descending,
      newAtTop: key === 'new' ? !old.newAtTop : old.newAtTop,
      upcomingCollapsed: key === 'upcoming' ? !old.upcomingCollapsed : old.upcomingCollapsed,
      holdCollapsed: key === 'hold' ? !old.holdCollapsed : old.holdCollapsed,
      filter: key === 'filter' ? value : this.nextFilter
    };
    if ((key === 'days' && !/^\d+$/.test(value.trim())) || !validProgress(next)) {
      this.progressOptionStatus = '请输入有效的非负整数天数。'; return;
    }
    this.progressPrefsBusy = true;
    try {
      await settings.saveProgress(next);
      this.progressPrefs = next;
      this.progressDaysInput = next.days.toString();
      this.progressOptionStatus = '';
      this.nextFilter = effectiveProgressFilter(next);
      this.nextPage = 1;
    } catch (error) { this.progressOptionStatus = '设置保存失败，请重试。'; }
    finally { this.progressPrefsBusy = false; this.reloadProgressFlags(); }
  }

  private showDisplayKey(): string { return JSON.stringify([this.progressSortKey(this.nextQuery),this.nextPage,this.progressPrefs.upcomingCollapsed,this.progressPrefs.holdCollapsed]); }
  private movieDisplayKey(): string { return JSON.stringify([this.movieSortKey(this.movieProgressQuery,new Date().toISOString().substring(0,10)),this.movieProgressPage]); }
  private collectionDisplayKey(): string { return JSON.stringify([this.collectionSortKey(),this.collectionPage,this.collectionGrid]); }
  private progressBusinessKey(): string {
    const prefs = this.progressPrefs;
    return JSON.stringify([this.displayRevisions.show,this.currentProgressScope(),this.activeCloud()?.generation ?? -1,
      this.progressFlagScope,this.flagVersion('show'),this.hiddenVersion('show'),prefs.strategy,prefs.count,prefs.days,prefs.newAtTop]);
  }
  private progressSortKey(query: string): string {
    return JSON.stringify([this.progressBusinessKey(),this.presentationLanguage,this.titleVersion('show'),
      query ? this.episodeSearchRevision : 0,this.progressPrefs.sort,this.progressPrefs.descending,this.nextFilter,query]);
  }
  private progressData(query: string, live: boolean = false, prepare: boolean = false): ProgressRow[] {
    if (this.signedIn && !this.activeCloud()) { return []; }
    const now = Date.now();
    const businessKey = this.progressBusinessKey();
    const key = this.progressSortKey(query);
    const memo = query ? this.progressMemo : this.progressAllMemo;
    const cached = this.sortedViewRevision >= 0 ? memo.get(key,now) : undefined;
    if (cached) { return cached; }
    if (!live && !prepare) { return []; }
    if (!live && this.sortJobs.matches(query ? 'show-query' : 'show-all',JSON.stringify([this.presentationEpoch,key]))) { return []; }
    let candidates = this.candidateMemo.get(businessKey,now);
    if (!candidates) {
      this.candidateRuns++;
      const sources: ProgressSource[] = [];
      for (const row of this.nextShows) {
        const source = row.source;
        if (source && !this.isHidden(source.media)) { sources.push(source); }
      }
      this.candidateExpiry = progressExpiry(sources,this.progressPrefs,now);
      candidates = [];
      const flags = this.progressFlagScope === this.currentProgressScope() ? this.progressFlags : [];
      for (const source of sources) {
        const row = selectProgress(source,this.progressPrefs,flags,now);
        if (row) { candidates.push(row); }
      }
      this.candidateMemo.put(businessKey,candidates,now,this.candidateExpiry);
    }
    const localized = candidates.map((row: ProgressRow): ProgressRow => ({
      media: row.media, episode: row.episode, total: row.total, completed: row.completed, upcoming: row.upcoming,
      fresh: row.fresh, pinned: row.pinned, held: row.held, group: row.group, recentAt: row.recentAt,
      rating: row.rating, randomOrder: row.randomOrder, dateUnknown: row.dateUnknown,
      localizedTitle: this.presentationLanguage === 'zh' ? this.displayTitle(row.media) : undefined,
      localizedEpisode: this.presentationLanguage === 'zh' ? this.displayEpisode(row.media,row.episode.season,row.episode.id,row.episode.title) : undefined
    }));
    if (live) {
      // Explicit mark validation remains synchronous against current inputs.
      const rows = sortProgressCandidates(localized,this.progressPrefs,this.nextFilter,query);
      memo.put(key,rows,now,this.candidateExpiry);
      return rows;
    }
    const input: ProgressSortInput = {rows:localized,prefs:this.progressPrefs,filter:this.nextFilter,query:query};
    this.runShowSort(input,key,now,this.candidateExpiry);
    return [];
  }
  private async runShowSort(input: ProgressSortInput, key: string, now: number, expiry: number): Promise<void> {
    const slot = input.query ? 'show-query' : 'show-all';
    const epoch = this.presentationEpoch;
    const token = this.sortJobs.begin(slot,JSON.stringify([epoch,key]));
    if (!token) { return; }
    try {
      const rows = await showDisplay(input);
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'progress' ||
          this.mediaMode !== 'show' || this.progressMode !== 'next' || epoch !== this.presentationEpoch ||
          (input.query && input.query !== this.nextQuery) || key !== this.progressSortKey(input.query) ||
          Date.now() < now || Date.now() >= expiry) { return; }
      const memo = input.query ? this.progressMemo : this.progressAllMemo;
      memo.put(key,rows,now,expiry);
    } finally {
      if (this.sortJobs.finish(slot,token) && this.pageVisible) { this.sortedViewRevision++; this.requestPresentation(); }
    }
  }
  private nextFiltered(): ProgressRow[] { return this.progressData(this.nextQuery); }

  private nextEntries(): ProgressEntry[] {
    return progressEntries(progressSections(this.nextFiltered(), this.progressPrefs));
  }

  private nextPages(): number { return Math.max(1, Math.ceil(this.nextEntries().length / this.collectionPageSize)); }
  private nextSlice(): ProgressEntry[] {
    const entries = this.nextEntries();
    return progressPage(entries, Math.min(this.nextPage, Math.max(1, Math.ceil(entries.length / this.collectionPageSize))), this.collectionPageSize);
  }

  private async markNext(row: ProgressRow): Promise<void> {
    const store = this.episodeStore;
    const snapshot = this.activeCloud();
    const uuid = this.cloudUuid;
    const clientId = this.clientId;
    const signedIn = this.signedIn;
    const revision = this.detailRevision;
    const current = (): boolean => this.pageVisible && this.tab === 'progress' &&
      this.mediaMode === 'show' && this.progressMode === 'next' && !this.selectedMedia &&
      this.detailRevision === revision && this.clientId === clientId && this.signedIn === signedIn &&
      this.activeCloud() === snapshot && this.cloudUuid === uuid && this.canEditLibrary() && !this.isHidden(row.media) && !this.collectionEditBusy;
    if (!store || !current() || !this.episodeReady || this.localBusy || this.cloudBusy || this.syncBusy ||
        this.saving || this.backupBusy || this.authBusy || this.setupBusy || row.upcoming ||
        !this.progressData(this.nextQuery,true).some((item: ProgressRow) => item.media.id === row.media.id && item.episode.id === row.episode.id)) { return; }
    this.localBusy = true;
    let saved = false;
    const auto = this.autoActive() ? this.autoConsent : undefined;
    try {
      if (signedIn && (!uuid || await store.boundAccount() !== uuid)) { throw new Error('Account mismatch'); }
      let full = await store.fullCatalog(row.media.id);
      if (!full || !current()) { throw new Error('Missing progress metadata'); }
      let allowed = eligibleCatalog(full, Date.now());
      if (!allowed.episodes.some((ep: LocalEpisode) => ep.id === row.episode.id)) { throw new Error('Episode not aired'); }
      const existing = await store.catalog(row.media.id);
      if (await store.needsCatalogVerification(row.media.id) ||
          !existing?.episodes.some((ep: LocalEpisode) => ep.id === row.episode.id)) {
        // Explicit user mark is allowed to verify metadata; mere recommendation never grants eligibility.
        full = await fetchFullEpisodeCatalog(row.media, clientId);
        allowed = eligibleCatalog(full, full.fetchedAt);
        if (!current() || !allowed.episodes.some((ep: LocalEpisode) => ep.id === row.episode.id)) {
          throw new Error('Episode no longer eligible');
        }
        await store.saveFullCatalog(full);
      }
      const effective = await projectDetail(store, full, row.media.id, snapshot, uuid);
      if (!current() || !effective.complete || !effective.localAllowed || !effective.state) { throw new Error('State changed'); }
      let unwatched = false;
      for (const season of effective.state.seasons) {
        if (season.episodes.some((ep: LocalEpisodeState) => ep.episode.id === row.episode.id && !ep.watched)) { unwatched = true; }
      }
      if (!unwatched) { this.nextStatus = '该集已看，正在更新推荐。'; this.requestProjection(); return; }
      if (signedIn && await store.boundAccount() !== uuid) { throw new Error('Account mismatch'); }
      if (!current()) { return; }
      this.invalidateSync();
      // Same guarded write path as detail. No direct remote request.
      await store.mark(row.media.id, [row.episode.id], true, auto && this.autoActive() ? auto.uuid : '');
      saved = true;
      this.invalidateNextShows();
      this.requestProjection();
      this.localRecent = await store.recent();
      await this.reloadQueue();
      this.nextStatus = '观看状态已更新。';
    } catch (error) {
      this.nextStatus = '未能完成观看操作，请刷新后核对。';
      this.requestProjection();
    } finally { this.localBusy = false; }
    if (saved && auto && this.autoActive()) { this.requestRecovery(); }
  }

  private invalidateMovieCalendar(): void {
    // Release dates are metadata; membership always comes from the current effective library.
    // Session changes still invalidate the snapshot via resetCalendar/current generation.
    if (!this.movieCalendarCurrent()) { this.movieCalendarData = undefined; }
    if (this.mediaMode === 'movie') {
      ++this.calendarRevision;
      this.calendarBusy = false;
      this.calendarPage = 1;
      this.movieProgressPage = 1;
      this.calendarStatus = '收藏已更新；新电影的上映日期可通过刷新补齐。';
    }
  }

  private resetCalendar(): void {
    ++this.calendarRevision;
    this.movieCalendarData = undefined;
    this.movieRatingKey = '';
    this.movieRatingRows = [];
    this.calendarData = undefined;
    this.calendarBusy = false;
    this.calendarPage = 1;
    this.calendarStatus = '';
  }

  private publishMovieSource(snapshot: CloudLibrary): void {
    if (this.activeCloud() !== snapshot || !snapshot.movieDetails) { return; }
    if (this.movieCalendarCurrent()) { return; }
    this.movieRatingKey = '';
    this.movieRatingRows = [];
    this.movieCalendarData = { generation: snapshot.generation, activity: snapshot.activity,
      movies: snapshot.movieDetails, ratingsComplete: false };
    this.calendarStatus = '已读取本账户电影资料，共 ' + snapshot.movieDetails.length + ' 部。';
    this.movieProgressPage = 1;
  }

  private async loadMovieRatings(): Promise<void> {
    const source = this.activeCloud();
    const snapshot = this.movieCalendarData;
    const session = traktAuth.session(this.clientId);
    const scope = this.currentProgressScope();
    if (!source || !snapshot || !session || !scope || !this.movieCalendarCurrent() || !this.cloudFresh ||
        this.cloudBusy || this.movieRatingBusy || this.authBusy || this.syncBusy || this.setupBusy) { return; }
    const key = JSON.stringify([scope,session.clientId,session.generation,source.activity]);
    if (this.movieRatingKey === key) { return; }
    this.movieRatingKey = key;
    this.movieRatingBusy = true;
    const current = (): boolean => this.activeCloud() === source && this.movieCalendarData === snapshot &&
      this.currentProgressScope() === scope && traktAuth.isCurrent(session.clientId,session.generation);
    try {
      const ratings = await readCollectionRatings(session,'movie',source.activity);
      if (!current()) { return; }
      const values = new Map<string,number>();
      for (const rating of ratings) { values.set(rating.id,rating.value); }
      this.movieRatingRows = ratings;
      this.collectionRatingStatus = '';
      const movies = snapshot.movies.map((row: PersonalMovie): PersonalMovie => ({
        media: row.media, released: row.released, cloudWatched: row.cloudWatched, cloudWatchlist: row.cloudWatchlist,
        localOnly: row.localOnly, runtime: row.runtime, rating: row.rating, addedAt: row.addedAt,
        dateUncertain: row.dateUncertain, userRating: values.get(row.media.id) }));
      this.movieCalendarData = { generation: snapshot.generation, activity: snapshot.activity, movies: movies, ratingsComplete: true };
    } catch (error) {
      if (current()) { this.collectionRatingStatus = '电影个人评分读取失败；下拉刷新后重试。'; }
    } finally {
      this.movieRatingBusy = false;
      if (this.activeCloud() !== source || this.currentProgressScope() !== scope ||
          (this.movieCalendarData !== snapshot && this.movieCalendarData?.ratingsComplete !== true)) {
        if (this.movieRatingKey === key) { this.movieRatingKey = ''; }
        this.scheduleLazyRows();
      }
    }
  }

  private async loadCalendar(): Promise<void> {
    if (this.calendarBusy || this.authBusy || this.setupBusy || this.syncBusy || !this.signedIn || !this.clientId) { return; }
    const session = traktAuth.session(this.clientId);
    if (!session) { this.calendarStatus = '登录会话尚不可用，请恢复 Trakt 登录后重试。'; return; }
    const revision = ++this.calendarRevision;
    const kind = this.mediaMode;
    const week = this.calendarWeek;
    this.calendarBusy = true;
    this.calendarData = undefined;
    this.calendarPage = 1;
    this.calendarStatus = '正在更新日历…';
    try {
      if (kind === 'movie') {
        const source = this.activeCloud();
        if (source?.movieDetails) {
          this.publishMovieSource(source);
          this.calendarStatus = '使用已验证账户的个人电影资料，共 ' + (this.movieCalendarData?.movies.length ?? 0) + ' 部。';
        } else {
          this.calendarStatus = '等待个人库核对及电影资料读取。';
          this.requestObservation();
        }
        return;
      }
      const result = await readCalendar(session, kind, week);
      if (revision !== this.calendarRevision || this.mediaMode !== kind || this.calendarWeek !== week ||
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
    if (this.mediaMode === 'movie') { return this.movieCalendarCurrent(); }
    return !!this.calendarData && this.signedIn &&
      traktAuth.isCurrent(this.clientId, this.calendarData.generation) &&
      this.calendarData.window.from === calendarWindow(new Date(), this.calendarWeek).from &&
      this.calendarData.window.startMs === calendarWindow(new Date(), this.calendarWeek).startMs;
  }

  private calendarSlice(): CalendarEntry[] {
    if (!this.calendarCurrent()) { return []; }
    return this.personalCalendarEntries().slice((this.calendarPage - 1) * this.collectionPageSize,
      this.calendarPage * this.collectionPageSize);
  }

  private personalCalendarEntries(): CalendarEntry[] {
    const members: Set<string> = new Set<string>(this.personalLibrary()
      .filter((row: PersonalLibraryRow) => !this.isHidden(row.media) && (row.queued || hasTrackingEvidence(row)))
      .map((row: PersonalLibraryRow) => row.media.id));
    return (this.calendarData?.entries ?? []).filter((row: CalendarEntry) => members.has(row.media.id) && row.season > 0);
  }

  private calendarPages(): number {
    return Math.max(1, Math.ceil(this.personalCalendarEntries().length / this.collectionPageSize));
  }

  private changeCalendar(week: number): void {
    const kind = this.mediaMode;
    if (this.calendarBusy) { return; }
    ++this.calendarRevision;
    this.calendarData = undefined;
    this.calendarPage = 1;
    this.calendarStatus = '';
    this.calendarWeek = week;
    if (kind === 'movie' && this.movieCalendarCurrent()) {
      this.calendarStatus = '已读取个人电影库，共 ' + (this.movieCalendarData?.movies.length ?? 0) + ' 部。';
    } else { this.loadCalendar(); }
  }

  private chooseProgressMode(mode: string): void {
    if (!progressTabs(this.mediaMode).includes(mode)) { return; }
    this.progressMode = mode;
    if (mode === 'next') {
      if (this.signedIn) { this.requestObservation(); } else { this.loadNextShows(); }
      if (this.mediaMode === 'movie' && !this.movieCalendarCurrent()) { this.loadCalendar(); }
    }
    if (mode === 'calendar' && !this.calendarCurrent()) { this.loadCalendar(); }
  }

  @Builder
  progressModeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).fontSize(13)
      .backgroundColor(this.progressMode === mode ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.progressMode === mode ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.chooseProgressMode(mode); })
  }

  private progressFilterSelected(filter: string): boolean {
    return this.nextFilter === filter || (this.nextFilter === 'both' && filter !== 'all');
  }

  private changeProgressFilter(filter: string): void {
    let value = 'all';
    if (filter !== 'all') {
      const upcoming = filter === 'upcoming' ? !this.progressFilterSelected('upcoming') : this.progressFilterSelected('upcoming');
      const hold = filter === 'hold' ? !this.progressFilterSelected('hold') : this.progressFilterSelected('hold');
      value = upcoming && hold ? 'both' : upcoming ? 'upcoming' : hold ? 'hold' : 'all';
    }
    this.editProgressOption('filter', value);
  }

  @Builder
  nextFilterButton(label: string, filter: string) {
    Button(label).layoutWeight(1).fontSize(12).enabled(!this.progressPrefsBusy)
      .backgroundColor(this.progressFilterSelected(filter) ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.progressFilterSelected(filter) ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.changeProgressFilter(filter); })
  }

  @Builder
  progressOptionButton(label: string, key: string, value: string, selected: boolean) {
    Button(label).layoutWeight(1).fontSize(12).enabled(!this.progressPrefsBusy)
      .backgroundColor(selected ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(selected ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.editProgressOption(key, value); })
  }

  @Builder
  progressOptionsView() {
    Column({ space: 7 }) {
      Text('下一集策略').fontSize(14).width('100%')
      Row({ space: 6 }) {
        this.progressOptionButton('最后观看之后', 'strategy', 'last', this.progressPrefs.strategy === 'last')
        this.progressOptionButton('最早未看', 'strategy', 'oldest', this.progressPrefs.strategy === 'oldest')
      }.width('100%')
      Text('进度统计').fontSize(14).width('100%')
      Row({ space: 6 }) {
        this.progressOptionButton('已播集数', 'count', 'aired', this.progressPrefs.count === 'aired')
        this.progressOptionButton('全部集数', 'count', 'all', this.progressPrefs.count === 'all')
      }.width('100%')
      Text('待播预告天数（0 = 关闭）').fontSize(14).width('100%')
      Row({ space: 6 }) {
        TextInput({ placeholder: '天数', text: this.progressDaysInput }).layoutWeight(1)
          .type(InputType.Number).onChange((value: string) => { this.progressDaysInput = value; })
        Button('保存').enabled(!this.progressPrefsBusy).onClick(() => { this.editProgressOption('days', this.progressDaysInput); })
      }.width('100%')
      Text('排序').fontSize(14).width('100%')
      Row({ space: 4 }) {
        this.progressOptionButton('最近观看', 'sort', 'recent', this.progressPrefs.sort === 'recent')
        this.progressOptionButton('剩余集数', 'sort', 'remaining', this.progressPrefs.sort === 'remaining')
        this.progressOptionButton('片名', 'sort', 'title', this.progressPrefs.sort === 'title')
      }.width('100%')
      Row({ space: 4 }) {
        this.progressOptionButton('播出日期', 'sort', 'newest', this.progressPrefs.sort === 'newest')
        this.progressOptionButton('评分', 'sort', 'rating', this.progressPrefs.sort === 'rating')
        this.progressOptionButton('随机', 'sort', 'random', this.progressPrefs.sort === 'random')
      }.width('100%')
      Row({ space: 6 }) {
        this.progressOptionButton(this.progressPrefs.descending ? '降序' : '升序', 'direction', '', false)
        this.progressOptionButton(this.progressPrefs.newAtTop ? '新集优先：开' : '新集优先：关', 'new', '', this.progressPrefs.newAtTop)
      }.width('100%')
      Text('个人评分排序尚未接入；未知评分不参与数值比较。').fontSize(12).width('100%')
    }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
  }

  private progressFlag(item: Media): ProgressFlag | undefined {
    if (this.progressFlagScope !== this.currentProgressScope()) { return undefined; }
    return this.progressFlags.length ? this.flagIndex.get(item.id) : undefined;
  }

  @Builder
  showProgressActions(item: Media) {
    if (isTraktMedia(item)) {
      Column({ space: 4 }) {
        Button(this.progressMenuId === item.id ? '收起操作' :
          this.isHidden(item) ? '更多 · 已隐藏' : this.progressFlag(item)?.held ? '更多 · 暂缓中' : this.progressFlag(item)?.pinned ? '更多 · 置顶' : '更多')
          .fontSize(12).onClick(() => { this.progressMenuId = this.progressMenuId === item.id ? '' : item.id; })
        if (this.progressMenuId === item.id) {
          Row({ space: 4 }) {
            if (!this.isHidden(item)) {
            Button(this.progressFlag(item)?.pinned ? '取消置顶' : '置顶').layoutWeight(1).fontSize(12)
              .enabled(this.canEditLibrary() && !this.progressPrefsBusy && !!this.progressFlagScope && !this.localBusy && !this.cloudBusy && !this.syncBusy)
              .onClick(() => { this.editProgressFlag(item, 'pin'); })
            if (item.kind === 'show') {
              Button(this.progressFlag(item)?.held ? '取消「暂缓」' : '设为「暂缓中」').layoutWeight(1).fontSize(12)
                .enabled(this.canEditLibrary() && !this.progressPrefsBusy && !!this.progressFlagScope && !this.localBusy && !this.cloudBusy && !this.syncBusy)
                .onClick(() => { this.editProgressFlag(item, 'hold'); })
            }
            }
            Button(this.isHidden(item) ? '取消隐藏' : '隐藏').layoutWeight(1).fontSize(12)
              .enabled(!!this.collectionScope && !this.collectionEditBusy && !this.progressPrefsBusy && !this.cloudBusy && !this.localBusy && !this.syncBusy && !this.saving && this.canEditLibrary())
              .onClick(() => { this.editHidden(item); })
          }.width('100%')
        }
      }.width('100%')
    }
  }

  @Builder
  nextProgressCard(row: ProgressRow) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        this.posterImage(row.media, 74, 111)
        Column({ space: 6 }) {
      Text(this.displayTitle(row.media)).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
      Text((row.pinned ? '置顶 · ' : row.held ? '暂缓 · ' : '') +
        (row.fresh ? '新集 · ' : '') + 'S' + row.episode.season + 'E' + row.episode.number +
        (this.displayEpisode(row.media, row.episode.season, row.episode.id, row.episode.title) ? ' · ' + this.displayEpisode(row.media, row.episode.season, row.episode.id, row.episode.title) : '')).fontSize(14).width('100%')
      Text((row.upcoming ? '待播 · ' : '播出 · ') + row.episode.firstAired.substring(0,10)).fontSize(12).width('100%')
      Text('已看 ' + row.completed + ' / ' + row.total + ' 集 · 剩余 ' + (row.total - row.completed) + ' 集')
        .fontSize(12).width('100%')
      if (row.total > 0) {
        Progress({ value: row.completed, total: row.total, type: ProgressType.Linear }).width('100%').color($r('app.color.showly_accent'))
      }
      if (row.dateUnknown) { Text('部分观看时间未知，按可验证记录推荐。').fontSize(12).width('100%') }
        }.layoutWeight(1)
      }.width('100%')
      Row({ space: 6 }) {
        Button('详情').layoutWeight(1).fontSize(12).enabled(!this.detailBusy)
          .onClick(() => { this.openDetail(row.media, false, row.episode.season); })
        Button(row.upcoming ? '尚未播出' : '标记已看').layoutWeight(1).fontSize(12)
          .enabled(!row.upcoming && this.canEditLibrary() && !this.localBusy && !this.cloudBusy && !this.syncBusy && !this.saving)
          .onClick(() => { this.markNext(row); })
      }.width('100%')
      this.showProgressActions(row.media)
    }.padding(12).borderRadius(10).width('100%').backgroundColor($r('app.color.showly_surface'))
      .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,row.episode.season,[],visible && ratio > 0,'progress','next'); })
  }

  @Builder
  nextShowsView() {
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 10 }) {
          this.progressHeader()
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          if (this.repairStatus) { Text(this.repairStatus).fontSize(12).width('100%') }
      Row({ space: 6 }) {
        Text('下一集').fontSize(21).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button(this.progressOptions ? '收起筛选设置' : '筛选与排序').fontSize(12)
          .onClick(() => { this.progressOptions = !this.progressOptions; })
      }.width('100%')
      this.librarySyncNotice()
      if (this.progressOptions) { this.progressOptionsView() }
      if (this.progressOptionStatus) { Text(this.progressOptionStatus).fontSize(12).width('100%') }
      Button(this.localBusy || this.cloudBusy ? '更新中…' : '刷新进度')
        .enabled(this.episodeReady && !this.localBusy && !this.cloudBusy && !this.syncBusy && !this.backupBusy)
        .onClick(() => { if (this.signedIn) { this.requestObservation(); } else { this.loadNextShows(); } })
      if (this.nextStatus) { Text(this.nextStatus).fontSize(12).width('100%') }
      Row({ space: 4 }) {
        this.nextFilterButton('全部', 'all')
        if (this.progressPrefs.days > 0) { this.nextFilterButton('待播', 'upcoming') }
        this.nextFilterButton('暂缓观看', 'hold')
      }.width('100%')
      TextInput({ placeholder: '搜索剧集或分集标题', text: this.nextQuery })
        .onChange((value: string) => { this.nextQuery = value; this.nextPage = 1; })
      if (this.nextShows.some((row: NextShow) => !row.source)) {
        Text('部分剧集缺少完整播出目录，暂不推荐。').fontSize(12).width('100%')
      }
      if (this.showSummary.key === this.showDisplayKey()) {
        Text('符合条件 ' + this.showSummary.total + ' 部').fontSize(13).width('100%')
        if (!this.showSummary.total && !this.cloudBusy && !this.localBusy) { Text('暂无符合条件的下一集。').fontSize(14).width('100%') }
      } else { Text('正在更新列表…').fontSize(13).width('100%') }
        }.width('100%')
      }
      if (!this.signedIn || this.activeCloud()) {
        LazyForEach(this.showRows, (entry: ProgressEntry) => {
          ListItem() {
        if (entry.row) {
          this.nextProgressCard(entry.row)
        } else {
          Row({ space: 8 }) {
            Text(entry.label + ' · ' + entry.count + ' 部').fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
            Button(entry.collapsed ? '展开' : '折叠').fontSize(12).enabled(!this.progressPrefsBusy)
              .onClick(() => { this.editProgressOption(entry.group === 'hold' ? 'hold' : 'upcoming', ''); })
          }.width('100%')
        }
          }
        }, (entry: ProgressEntry) => this.showRows.keyFor(entry.key))
      }
      ListItem() {
      Row({ space: 8 }) {
        Button('上一页').layoutWeight(1).enabled(this.showSummary.key === this.showDisplayKey() && this.showSummary.page > 1).onClick(() => { this.nextPage = this.showSummary.page - 1; })
        Text(this.showSummary.page + ' / ' + this.showSummary.pages).fontSize(13)
        Button('下一页').layoutWeight(1).enabled(this.showSummary.key === this.showDisplayKey() && this.showSummary.page < this.showSummary.pages).onClick(() => { this.nextPage = this.showSummary.page + 1; })
      }.width('100%')
      }
    }.width('100%').height('100%').padding(16)
  }

  private movieCalendarCurrent(): boolean {
    const active = this.activeCloud();
    return !!this.movieCalendarData && !!active && this.movieCalendarData.activity === active.activity &&
      this.movieCalendarData.generation === active.generation &&
      traktAuth.isCurrent(this.clientId, this.movieCalendarData.generation);
  }

  private movieRows(mode: string = this.movieCalendarMode, query: string = this.movieCalendarQuery): PersonalMovie[] {
    if (!this.movieCalendarCurrent()) { return []; }
    const metadata = new Map<string,PersonalMovie>();
    for (const movie of this.movieCalendarData?.movies ?? []) { metadata.set(movie.media.id,movie); }
    const rows: PersonalMovie[] = [];
    for (const row of this.personalLibrary()) {
      if (this.isHidden(row.media) || row.media.kind !== 'movie' || !isTraktMedia(row.media) || (!row.watched && !row.queued)) { continue; }
      const found = metadata.get(row.media.id);
      rows.push({ media: row.media, released: found?.released ?? '', cloudWatched: row.watched,
        cloudWatchlist: row.queued, localOnly: false });
    }
    return filterMovies(rows, mode, '', new Date()).filter((row: PersonalMovie) => this.matchesMedia(row.media, query) || row.released.includes(query.trim()));
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
        this.authBusy || this.setupBusy || row.released || !this.personalLibrary().some((item: PersonalLibraryRow) =>
          item.media.id === row.media.id && (item.queued || item.watched))) { return; }
    const revision = ++this.calendarRevision;
    this.calendarBusy = true;
    this.calendarStatus = '正在补查电影上映日期…';
    try {
      const date = await readPersonalMovieDate(session, row.media);
      if (revision !== this.calendarRevision || !this.movieCalendarCurrent() || this.movieCalendarData !== snapshot) { return; }
      const movies = snapshot.movies.filter((item: PersonalMovie) => item.media.id !== row.media.id);
      const prior = snapshot.movies.find((item: PersonalMovie) => item.media.id === row.media.id);
      movies.push({ media: row.media, released: date, cloudWatched: row.cloudWatched,
        cloudWatchlist: row.cloudWatchlist, localOnly: !date && (prior?.localOnly ?? true), runtime: prior?.runtime,
        rating: prior?.rating, addedAt: prior?.addedAt, userRating: prior?.userRating, dateUncertain: !date && prior?.dateUncertain === true });
      this.movieCalendarData = { generation: snapshot.generation, activity: snapshot.activity, movies: movies,
        ratingsComplete: snapshot.ratingsComplete };
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
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 10 }) {
          this.progressHeader()
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          Text('电影上映日历').fontSize(21).fontWeight(FontWeight.Medium).width('100%')

      Text('个人已看及待看电影的上映日期，不代表当地影院排期。')
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
        }
      }
        }.width('100%')
      }
      if (this.signedIn && this.movieCalendarCurrent()) {
          LazyForEach(this.movieCalendarRows, (row: MovieCalendarItem) => {
            ListItem() {
            Column({ space: 6 }) {
              if (row.heading) { Text(row.group).fontSize(18).fontWeight(FontWeight.Bold).width('100%') }
              Column({ space: 6 }) {
                Text(row.movie.released || '上映日期待确认').fontSize(13)
                  .fontColor($r('app.color.showly_secondary')).width('100%')
                Row({ space: 8 }) {
                  this.posterImage(row.movie.media, 54, 81)
                  Text(this.displayTitle(row.movie.media)).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
                }.width('100%')
                Text(row.movie.cloudWatched && row.movie.cloudWatchlist ?
                  '已看 · 待看' : row.movie.cloudWatched ? '已看' : '待看')
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
              .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.movie.media,0,[],visible && ratio > 0,'progress','calendar'); })
            }
          }, (row: MovieCalendarItem) => this.movieCalendarRows.keyFor(row.movie.media.id))
        ListItem() {
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.calendarPage > 1).onClick(() => { this.calendarPage--; })
            Text(this.calendarPage + ' / ' + this.moviePages()).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.calendarPage < this.moviePages()).onClick(() => { this.calendarPage++; })
          }.width('100%')
        }
      }
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  calendarView() {
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 10 }) {
          this.progressHeader()
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          Text('剧集播出日历').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
          Text('个人收藏中的剧集播出安排。').fontSize(12).width('100%')
        Text(this.calendarRangeLabel()).fontSize(15).width('100%')
        Row({ space: 4 }) {
          Button('前七天').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy && this.calendarWeek > -1)
            .onClick(() => { this.changeCalendar(this.calendarWeek - 1); })
          Button('今天起').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy)
            .onClick(() => { this.changeCalendar(0); })
          Button('后七天').layoutWeight(1).fontSize(12).enabled(!this.calendarBusy && this.calendarWeek < 1)
            .onClick(() => { this.changeCalendar(this.calendarWeek + 1); })
        }.width('100%')
        if (!this.signedIn) {
          Text('登录 Trakt 后读取个人日历。').fontSize(13).width('100%')
          Button('连接 Trakt').onClick(() => { this.navigate('account'); })
        } else {
          Button(this.calendarBusy ? '读取中…' : '刷新日历').enabled(!this.calendarBusy && !this.authBusy && !this.syncBusy && !this.setupBusy)
            .onClick(() => { this.loadCalendar(); })
          if (this.calendarStatus) { Text(this.calendarStatus).fontSize(13).width('100%') }
          if (!this.calendarCurrent() && this.calendarData) {
            Text('会话或当地日期已变化，请刷新日历。').fontSize(12).width('100%')
          }
        }
        }.width('100%')
      }
      if (this.signedIn && this.calendarCurrent()) {
            LazyForEach(this.calendarRows, (row: CalendarEntry) => {
              ListItem() {
              Column({ space: 6 }) {
                Text(row.day + (row.time ? ' · ' + row.time : ' · 上映日期')).fontSize(13)
                  .fontColor($r('app.color.showly_secondary')).width('100%')
                Row({ space: 8 }) {
                  this.posterImage(row.media, 54, 81)
                  Text(this.displayTitle(row.media)).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
                }.width('100%')
                if (row.media.kind === 'show') {
                  Text('S' + row.season + 'E' + row.number + (this.displayEpisode(row.media, row.season, Number(row.key.substring(8)), row.episodeTitle) ? ' · ' + this.displayEpisode(row.media, row.season, Number(row.key.substring(8)), row.episodeTitle) : ''))
                    .fontSize(14).width('100%')
                }
                Button('查看详情').fontSize(12).enabled(!this.detailBusy && !this.localBusy && !this.syncBusy)
                  .onClick(() => { this.openDetail(row.media, false, row.season); })
              }.padding(12).width('100%').borderRadius(10).backgroundColor($r('app.color.showly_surface'))
                .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,row.season,[],visible && ratio > 0,'progress','calendar',row.key); })
              }
            }, (row: CalendarEntry) => this.calendarRows.keyFor(row.key))
        ListItem() {
            Row({ space: 8 }) {
              Button('上一页').layoutWeight(1).enabled(this.calendarPage > 1).onClick(() => { this.calendarPage--; })
              Text(this.calendarPage + ' / ' + this.calendarPages()).fontSize(13)
              Button('下一页').layoutWeight(1).enabled(this.calendarPage < this.calendarPages()).onClick(() => { this.calendarPage++; })
            }.width('100%')
        }
      }
    }.width('100%').height('100%').padding(16)
  }

  private movieSortKey(query: string, utc: string): string {
    return JSON.stringify([this.displayRevisions.movie,this.libraryRevision,this.currentProgressScope(),this.activeCloud()?.generation ?? -1,
      this.presentationLanguage,this.titleVersion('movie'),this.progressFlagScope,this.flagVersion('movie'),this.hiddenVersion('movie'),
      this.movieProgressOptions,this.movieRandomSeed,utc,query]);
  }
  private movieProgressRows(query: string = this.movieProgressQuery, live: boolean = false, prepare: boolean = false): PersonalLibraryRow[] {
    // Missing snapshot is not evidence of a missing release date.
    if (!this.movieCalendarCurrent()) { return []; }
    const now = Date.now();
    const utc = new Date(now).toISOString().substring(0, 10);
    const key = this.movieSortKey(query,utc);
    const memo = query ? this.movieMemo : this.movieAllMemo;
    const cached = this.sortedViewRevision >= 0 ? memo.get(key,now) : undefined;
    if (cached) { return cached; }
    if (!live && !prepare) { return []; }
    if (!live && this.sortJobs.matches(query ? 'movie-query' : 'movie-all',JSON.stringify([this.presentationEpoch,key]))) { return []; }
    const metadata = this.movieMetadataIndex();
    const sources: MovieProgressSource[] = [];
    for (const row of this.personalLibrary()) {
      const movie = metadata.get(row.media.id);
      if (this.isHidden(row.media) || !movie || movie.localOnly || movie.dateUncertain || row.media.kind !== 'movie') { continue; }
      const translation = this.presentationLanguage === 'zh' ?
        (this.presentationRevision > 0 ? this.titleIndex.get(row.media.id)?.text.title ?? '' : '') : '';
      sources.push({ row: row, translation: translation,
        metadata: { id: row.media.id, released: movie.released, year: movie.media.year,
          runtime: movie.runtime, rating: movie.rating, addedAt: movie.addedAt, userRating: movie.userRating } });
    }
    const flags = this.progressFlagScope === this.currentProgressScope() ? this.progressFlags : [];
    const expiry = Date.parse(utc + 'T00:00:00Z') + 86400000;
    if (live) {
      const rows = projectMovieProgress(sources,flags,this.movieProgressOptions,utc,query,this.movieRandomSeed);
      memo.put(key,rows,now,expiry);
      return rows;
    }
    const input: MovieSortInput = {sources:sources,flags:flags,options:this.movieProgressOptions,utc:utc,query:query,seed:this.movieRandomSeed};
    this.runMovieSort(input,key,now,expiry);
    return [];
  }
  private async runMovieSort(input: MovieSortInput, key: string, now: number, expiry: number): Promise<void> {
    const slot = input.query ? 'movie-query' : 'movie-all';
    const epoch = this.presentationEpoch;
    const token = this.sortJobs.begin(slot,JSON.stringify([epoch,key]));
    if (!token) { return; }
    try {
      const rows = await movieDisplay(input);
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'progress' ||
          this.mediaMode !== 'movie' || this.progressMode !== 'next' || epoch !== this.presentationEpoch || !this.movieCalendarCurrent() ||
          (input.query && input.query !== this.movieProgressQuery) || key !== this.movieSortKey(input.query,input.utc) ||
          Date.now() < now || Date.now() >= expiry) { return; }
      const memo = input.query ? this.movieMemo : this.movieAllMemo;
      memo.put(key,rows,now,expiry);
    } finally {
      if (this.sortJobs.finish(slot,token) && this.pageVisible) { this.sortedViewRevision++; this.requestPresentation(); }
    }
  }

  private async setMovieProgressSort(sort: string, descending: boolean): Promise<void> {
    const settings = this.settings;
    const options: MovieProgressOptions = { sort: sort, descending: descending };
    if (!settings || this.progressPrefsBusy || !validMovieProgress(options)) { return; }
    this.progressPrefsBusy = true;
    try {
      await settings.saveMovieProgress(options);
      this.movieProgressOptions = options;
      this.movieRandomSeed = Date.now();
      this.movieProgressPage = 1;
      this.progressOptionStatus = '';
      this.requestPresentation();
    } catch (error) { this.progressOptionStatus = '电影排序保存失败。'; }
    finally { this.progressPrefsBusy = false; this.reloadProgressFlags(); }
  }

  private async markMovieProgress(item: Media): Promise<void> {
    if (!this.pageVisible || this.tab !== 'progress' || this.mediaMode !== 'movie' ||
        this.progressMode !== 'next' || this.selectedMedia || this.authBusy || this.setupBusy ||
        this.backupBusy || this.localBusy || this.calendarBusy || this.progressPrefsBusy ||
        !this.canEditLibrary() || !this.activeCloud()) { return; }
    const row = this.movieProgressRows('',true).find((candidate: PersonalLibraryRow) => candidate.media.id === item.id);
    if (!row) { return; }
    await this.changeMediaIntent(row.media, 'movie', 'yes');
  }

  @Builder
  movieSortButton(label: string, sort: string) {
    Button(label).fontSize(12).layoutWeight(1)
      .backgroundColor(this.movieProgressOptions.sort === sort ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.movieProgressOptions.sort === sort ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .enabled(!this.progressPrefsBusy)
      .onClick(() => { this.setMovieProgressSort(sort, this.movieProgressOptions.descending); })
  }

  @Builder
  movieProgressView() {
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 10 }) {
          this.progressHeader()
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          if (this.repairStatus) { Text(this.repairStatus).fontSize(12).width('100%') }
      this.librarySyncNotice()
      Text('已上映或仅有年份、尚未观看的待看电影').fontSize(13).width('100%')
      if (!this.signedIn) {
        Text('连接 Trakt 后可获取电影上映日期。待看电影仍可在收藏中管理。').fontSize(13).width('100%')
        Button('连接 Trakt').onClick(() => { this.navigate('account'); })
      } else {
        Button(this.calendarBusy || this.cloudBusy ? '更新中…' : '刷新电影进度')
          .enabled(!this.calendarBusy && !this.cloudBusy && !this.syncBusy && !this.saving)
          .onClick(() => { this.refreshPage(); })
        if (this.calendarStatus) { Text(this.calendarStatus).fontSize(12).width('100%') }
        TextInput({ placeholder: '筛选电影', text: this.movieProgressQuery })
          .onChange((value: string) => { this.movieProgressQuery = value; this.movieProgressPage = 1; })
        Row({ space: 4 }) {
          this.movieSortButton('添加时间', 'added')
          this.movieSortButton('片名', 'title')
          this.movieSortButton('上映日期', 'newest')
        }.width('100%')
        Row({ space: 4 }) {
          this.movieSortButton('时长', 'runtime')
          this.movieSortButton('公众评分', 'rating')
          this.movieSortButton('个人评分', 'userRating')
          this.movieSortButton('随机', 'random')
        }.width('100%')
        Button(this.movieProgressOptions.descending ? '降序' : '升序').fontSize(12)
          .enabled(!this.progressPrefsBusy)
          .onClick(() => { this.setMovieProgressSort(this.movieProgressOptions.sort, !this.movieProgressOptions.descending); })
        if (this.progressOptionStatus) { Text(this.progressOptionStatus).fontSize(12).width('100%') }
        if (!this.movieCalendarCurrent()) {
          Text('上映资料尚未就绪，请刷新。').fontSize(13).width('100%')
        } else {
          if (this.movieProgressOptions.sort === 'userRating' && this.movieCalendarData?.ratingsComplete !== true) {
            Text('个人评分按需读取中或暂不可用；保留其他排序及观看功能。').fontSize(12).width('100%')
          }
          if (this.movieSummary.key !== this.movieDisplayKey()) { Text('正在更新列表…').fontSize(13).width('100%') }
          else if (!this.movieSummary.total) { Text('暂无符合上映日期或年份条件的待看电影。').fontSize(13).width('100%') }
        }
      }
        }.width('100%')
      }
      if (this.signedIn && this.movieCalendarCurrent()) {
        LazyForEach(this.movieRowsSource, (row: PersonalLibraryRow) => {
          ListItem() {
            Row({ space: 8 }) {
              this.posterImage(row.media, 54, 81)
              Column({ space: 4 }) {
                Text(this.displayTitle(row.media)).width('100%').onClick(() => { this.openDetail(row.media); })
                this.showProgressActions(row.media)
              }.layoutWeight(1)
              Button('标记已看').fontSize(12)
                .enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy &&
                  !this.calendarBusy && !this.progressPrefsBusy)
                .onClick(() => { this.markMovieProgress(row.media); })
            }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
          }
          .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'progress','next'); })
        }, (row: PersonalLibraryRow) => this.movieRowsSource.keyFor(row.media.id))
        ListItem() {
          Row({ space: 8 }) {
            Button('上一页').layoutWeight(1).enabled(this.movieSummary.key === this.movieDisplayKey() && this.movieSummary.page > 1).onClick(() => { this.movieProgressPage--; })
            Text(this.movieSummary.page + ' / ' + this.movieSummary.pages).fontSize(13)
            Button('下一页').layoutWeight(1).enabled(this.movieSummary.key === this.movieDisplayKey() && this.movieSummary.page < this.movieSummary.pages)
              .onClick(() => { this.movieProgressPage++; })
          }.width('100%')
        }
      }
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  progressHeader() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.mediaMode === 'show' ? '剧集进度' : '电影进度').fontSize(25).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('同步').fontSize(12).onClick(() => { this.navigate('account'); })
      }.width('100%')
      Row({ space: 6 }) {
        this.progressModeButton(this.mediaMode === 'show' ? '下一集' : '待看进度', 'next')
        this.progressModeButton(this.mediaMode === 'show' ? '日历' : '上映日历', 'calendar')
        if (this.mediaMode === 'show') { this.progressModeButton('历史', 'history') }
      }.width('100%')
    }.width('100%')
  }

  @Builder
  progressView() {
    Column({ space: 12 }) {
      this.progressHeader()
      if (this.progressMode === 'history' && this.mediaMode === 'show') {
        Text('逐集观看历史尚未实现。现有观看记录不受影响。').fontSize(14).width('100%')
      }
    }.width('100%')
  }

  @Builder
  legacyProgressView() {
    Column({ space: 12 }) {
      Text('观看进度').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
      if (this.canEditLibrary() && this.localRecent.length > 0) {
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
    if (this.tab === 'library') { this.collectionRatingKey = ''; this.collectionRatings = []; }
    if (this.mediaMode === 'movie') {
      this.movieRatingKey = '';
      this.movieRatingRows = [];
    }
    this.presentation?.retryArtwork();
    this.presentationBlocked = false;
    this.presentationStatus = '';
    try {
      if (this.selectedMedia) {
        await this.openDetail(this.selectedMedia, true);
      } else if (this.tab === 'discover') {
        await this.loadDiscover(this.discoverPage,true);
      } else if (this.tab === 'library') {
        if (this.signedIn) { await this.loadCloud(); } else { await this.loadNextShows(); }
        if (this.collectionGrid) { await this.loadCollectionPosters(); }
      } else if (this.tab === 'progress') {
        if (this.progressMode === 'next') {
          if (this.signedIn) { await this.loadCloud(); } else { await this.loadNextShows(); }
          // Movie source is published by loadCloud; no second network read.
        }
        else if (this.progressMode === 'calendar') { if (this.signedIn) { await this.loadCloud(); } if (this.mediaMode === 'show') { await this.loadCalendar(); } }
        else if (this.signedIn) { await this.loadCloud(); }
      } else if (this.tab === 'cloud') {
        if (this.signedIn) { await this.loadCloud(); }
      } else if (this.tab === 'search' && this.title.trim()) {
        await this.search();
      }
    } finally {
      this.refreshing = false;
      this.requestPresentation();
    }
  }

  private resetCollection(): void {
    ++this.collectionRevision;
    this.collectionPage = 1;
    this.collectionCards = [];
    this.collectionBusy = false;
    this.collectionStatus = '';
  }

  private personalLibrary(): PersonalLibraryRow[] {
    const snapshot = this.cloud;
    const cloud = snapshot && this.signedIn && traktAuth.isCurrent(this.clientId, snapshot.generation) ?
      snapshot : undefined;
    if (this.signedIn && !cloud) { return []; }
    const key = JSON.stringify([this.libraryRevision, this.signedIn, this.cloudLocalAllowed, this.clientId,
      this.cloudUuid, cloud?.generation ?? -1, cloud?.activity ?? '']);
    const now = Date.now();
    const cached = this.libraryMemo.get(key, now);
    if (cached) { return cached; }
    const cloudShows = (cloud?.shows ?? []).map((show: ShowProgress): LibraryShowEvidence => {
      const media: Media = { id: show.id, title: show.title, kind: 'show', year: show.year ?? 0, watched: false };
      return { media: media, watchedEpisodes: show.watchedEpisodes };
    });
    const localShows = this.libraryEvidence.filter((show: LibraryShowEvidence) => cloud ? show.merged === true : !show.merged);
    const rows = buildPersonalLibrary(cloud && !this.cloudLocalAllowed ? [] : this.mediaRecords,
      cloud?.watchedMovies ?? [], cloud?.watchlist ?? [], cloudShows, localShows);
    this.libraryIndex.clear();
    for (const row of rows) { this.libraryIndex.set(row.media.id,row); }
    this.libraryMemo.put(key, rows, now, Number.MAX_SAFE_INTEGER);
    return rows;
  }

  private currentCollectionState(): CollectionState {
    return this.collectionScope && this.collectionScope === this.currentProgressScope() ? this.collectionState : emptyCollectionState();
  }
  private isHidden(media: Media): boolean {
    return this.currentCollectionState().hidden.length > 0 && this.hiddenIndex.has(media.id);
  }
  private reloadCollectionState(): void {
    const scope = this.currentProgressScope();
    if (this.collectionScope === scope || this.collectionEditBusy) { return; }
    this.collectionScope = '';
    this.collectionState = emptyCollectionState();
    if (!scope || !this.settings) { return; }
    try {
      this.collectionState = this.settings.loadCollectionState(scope);
      this.collectionScope = scope;
      this.onCollectionStateChanged();
    } catch (error) { this.collectionRuleStatus = '隐藏及添加记录读取失败；未覆盖原记录。'; }
  }
  private async editHidden(media: Media): Promise<void> {
    const scope = this.currentProgressScope();
    const settings = this.settings;
    if (!settings || !scope || scope !== this.collectionScope || !this.canEditLibrary() || !this.pageVisible ||
        this.collectionEditBusy || this.progressPrefsBusy || this.saving || this.syncBusy || this.localBusy ||
        this.cloudBusy || this.authBusy || this.setupBusy || this.backupBusy || !isTraktMedia(media)) { return; }
    const hidden = !this.isHidden(media);
    this.collectionEditBusy = true;
    this.progressPrefsBusy = true;
    try {
      const next = hideMedia(this.collectionState, media, hidden, Date.now());
      await settings.saveCollectionState(scope, next);
      if (scope !== this.currentProgressScope()) { return; }
      this.collectionState = next;
      if (hidden && this.progressFlagScope === scope && this.progressFlag(media)?.pinned) {
        const flags = this.progressFlags.map((flag: ProgressFlag): ProgressFlag =>
          flag.id === media.id ? { id: flag.id, pinned: false, held: flag.held } : flag)
          .filter((flag: ProgressFlag) => flag.pinned || flag.held);
        await settings.saveProgressFlags(scope, flags);
        if (scope === this.currentProgressScope()) { this.progressFlags = flags; }
      }
      this.collectionRuleStatus = hidden ? '已在本机隐藏；不会删除观看记录或写入 Trakt。' : '已取消本机隐藏；原记录保留。';
      this.nextPage = 1; this.movieProgressPage = 1; this.calendarPage = 1;
      this.resetCollection();
      this.onCollectionStateChanged();
    } catch (error) { this.collectionRuleStatus = '隐藏或置顶设置未全部保存，请核对。'; }
    finally { this.collectionEditBusy = false; this.progressPrefsBusy = false; this.reloadProgressFlags(); }
  }
  private async recordTitleDates(scope: string, before: PersonalLibraryRow[], changes: TitleChange[]): Promise<void> {
    const settings = this.settings;
    if (!settings || !scope || scope !== this.collectionScope || scope !== this.currentProgressScope() || !changes.length) { return; }
    const state = transitionCollectionDates(this.collectionState,before,this.personalLibrary(),
      changes.map((change: TitleChange) => change.id),Date.now());
    if (state === this.collectionState) { return; }
    try {
      await settings.saveCollectionState(scope,state);
      if (scope === this.currentProgressScope()) { this.collectionState = state; }
    } catch (error) { this.collectionRuleStatus = '收藏已保存，但添加时间未能保存。'; }
  }
  private async recordFirstEpisodeDate(scope: string,id: string): Promise<void> {
    const settings = this.settings;
    if (!settings || !scope || scope !== this.collectionScope || scope !== this.currentProgressScope()) { return; }
    if (this.collectionState.mine.some((date: CollectionDate) => date.id === id)) { return; }
    try {
      const next = recordCollectionDate(this.collectionState,id,'mine',true,Date.now());
      await settings.saveCollectionState(scope,next);
      if (scope === this.currentProgressScope()) { this.collectionState = next; }
    } catch (error) { this.collectionRuleStatus = '观看已保存，但添加时间未能保存。'; }
  }
  private reloadCollectionOptions(): void {
    const key = this.mediaMode + ':' + this.collectionFilter;
    if (!this.settings || this.collectionOptionKey === key || !['mine','queue','hidden'].includes(this.collectionFilter)) { return; }
    this.collectionOptionKey = key;
    this.collectionOptions = this.settings.loadCollectionOptions(this.mediaMode,this.collectionFilter);
    this.collectionGenreDraft = this.collectionOptions.genres.join(',');
    this.collectionNetworkDraft = this.collectionOptions.networks.join(',');
  }
  private async editCollectionOptions(key: string,value: string): Promise<void> {
    const settings = this.settings; const kind = this.mediaMode; const section = this.collectionFilter;
    if (!settings || this.collectionEditBusy || !['mine','queue','hidden'].includes(section)) { return; }
    const old = this.collectionOptions;
    const values = value.split(',').map((g: string) => g.trim()).filter((g: string) => !!g);
    const options: CollectionOptions = { sort: key === 'sort' ? value : old.sort,
      descending: key === 'direction' ? !old.descending : old.descending,
      genres: key === 'genre' ? values.map((g: string) => g.toLowerCase()) : old.genres,
      networks: key === 'network' ? values : old.networks,
      upcoming: key === 'upcoming' ? value : old.upcoming };
    this.collectionEditBusy = true;
    try {
      await settings.saveCollectionOptions(kind,section,options);
      if (kind === this.mediaMode && section === this.collectionFilter) {
        this.collectionOptions = options;
        this.collectionGenreDraft = options.genres.join(',');
        this.collectionNetworkDraft = options.networks.join(',');
        this.resetCollection();
        this.presentationBlocked = false;
        this.onPresentationChanged();
      }
    } catch (error) { this.collectionRuleStatus = '收藏排序或筛选保存失败。'; }
    finally { this.collectionEditBusy = false; }
  }
  private async loadCollectionRatings(): Promise<void> {
    if (this.mediaMode === 'movie') { await this.loadMovieRatings(); return; }
    const snapshot = this.activeCloud();
    const session = traktAuth.session(this.clientId);
    const scope = this.currentProgressScope();
    const kind = this.mediaMode;
    if (!snapshot || !session || !scope || !this.cloudFresh || this.collectionRatingBusy || this.cloudBusy || this.syncBusy || this.authBusy) { return; }
    const key = JSON.stringify([scope,session.clientId,session.generation,snapshot.activity,kind]);
    if (this.collectionRatingKey === key) { return; }
    this.collectionRatingBusy = true;
    this.collectionRatingKey = key;
    this.collectionRatings = [];
    const current = (): boolean => this.currentProgressScope() === scope && this.activeCloud() === snapshot &&
      this.mediaMode === kind && this.clientId === session.clientId && traktAuth.isCurrent(session.clientId,session.generation);
    try {
      this.collectionRatingStatus = '正在读取个人评分…';
      const ratings = await readCollectionRatings(session,kind,snapshot.activity);
      if (current()) { this.collectionRatings = ratings; this.collectionRatingStatus = ''; }
    } catch (error) { if (current()) { this.collectionRatingStatus = '个人评分读取失败；刷新后重试。'; } }
    finally {
      this.collectionRatingBusy = false;
      if (!current() && this.collectionRatingKey === key) {
        this.collectionRatingKey = '';
        this.scheduleLazyRows();
      }
    }
  }
  private collectionNeedsMetadata(): boolean {
    const options = this.collectionOptions;
    return !!options.genres.length || !!options.networks.length || options.upcoming !== 'all' ||
      ['rating','runtime','newest'].includes(options.sort);
  }
  private collectionBase(): PersonalLibraryRow[] {
    if (this.signedIn && !this.activeCloud()) { return []; }
    return collectionMembers(this.personalLibrary(),this.currentCollectionState(),this.mediaMode,this.collectionFilter,this.collectionStatusFilter);
  }
  private movieMetadataIndex(): Map<string,PersonalMovie> {
    const now = Date.now();
    const key = JSON.stringify([this.displayRevisions.movie,this.currentProgressScope(),this.movieCalendarCurrent(),this.activeCloud()?.activity ?? '']);
    const cached = this.movieMetadataMemo.get(key,now);
    if (cached) { return cached; }
    const movies = new Map<string,PersonalMovie>();
    if (this.movieCalendarCurrent()) {
      for (const row of this.movieCalendarData?.movies ?? []) { movies.set(row.media.id,row); }
    }
    this.movieMetadataMemo.put(key,movies,now,Number.MAX_SAFE_INTEGER);
    return movies;
  }
  private collectionIndexes(section: string): CollectionIndexes {
    const now = Date.now();
    const key = JSON.stringify([this.displayRevisions.collection,this.libraryRevision,this.currentProgressScope(),
      this.collectionScope,this.mediaMode,section,this.collectionRatingKey,this.movieRatingKey,this.movieCalendarCurrent()]);
    const slot = this.mediaMode + ':' + section;
    let memo = this.collectionIndexMemos.get(slot);
    if (!memo) { memo = new RevisionMemo<CollectionIndexes>(); this.collectionIndexMemos.set(slot,memo); }
    const cached = memo.get(key,now);
    if (cached) { return cached; }
    const state = this.currentCollectionState();
    const dates = section === 'mine' ? state.mine : section === 'queue' ? state.queue :
      state.hidden.map((h: HiddenEntry): CollectionDate => ({ id: h.media.id, at: h.at }));
    const times = new Map<string,number>();
    if (section === 'queue') { for (const date of this.activeCloud()?.queueDates ?? []) { times.set(date.id,date.at); } }
    for (const date of dates) { times.set(date.id,date.at); }
    const recent = new Map<string,number>();
    for (const row of this.nextShows) { if (row.source?.recentAt) { recent.set(row.media.id,row.source.recentAt); } }
    const personalRatings = new Map<string,number>();
    const active = this.activeCloud();
    const session = traktAuth.session(this.clientId);
    if (active && session && this.collectionRatingKey === JSON.stringify([this.currentProgressScope(),session.clientId,session.generation,active.activity,this.mediaMode])) {
      for (const rating of this.collectionRatings) { personalRatings.set(rating.id,rating.value); }
    }
    const movies = this.movieMetadataIndex();
    if (this.movieCalendarCurrent()) {
      if (this.mediaMode === 'movie' && active && session && this.movieRatingKey === JSON.stringify([this.currentProgressScope(),session.clientId,session.generation,active.activity])) {
        for (const rating of this.movieRatingRows) { personalRatings.set(rating.id,rating.value); }
      }
    }
    const indexes: CollectionIndexes = {times:times,recent:recent,ratings:personalRatings,movies:movies};
    memo.put(key,indexes,now,Number.MAX_SAFE_INTEGER);
    return indexes;
  }
  private collectionCandidates(rows: PersonalLibraryRow[], section: string): CollectionCandidate[] {
    const indexes = this.collectionIndexes(section);
    return rows.map((row: PersonalLibraryRow): CollectionCandidate => {
      const metadata = this.titleIndex.get(row.media.id);
      const movie = indexes.movies.get(row.media.id);
      if (!this.collectionRandomKeys.has(row.media.id)) { this.collectionRandomKeys.set(row.media.id,Math.random()); }
      return { row: row, translation: this.presentationLanguage === 'zh' ? metadata?.text.title ?? '' : '',
        meta: metadata?.collection, added: indexes.times.get(row.media.id), recent: indexes.recent.get(row.media.id),
        userRating: indexes.ratings.get(row.media.id) ?? movie?.userRating, randomOrder: this.collectionRandomKeys.get(row.media.id) ?? 0 };
    });
  }
  private recentCollectionRows(): PersonalLibraryRow[] {
    const now = Date.now();
    const key = JSON.stringify([this.displayRevisions.collection,this.libraryRevision,this.collectionScope,this.currentProgressScope(),this.mediaMode]);
    const cached = this.recentCollectionMemo.get(key,now);
    if (cached) { return cached; }
    const members = collectionMembers(this.personalLibrary(),this.currentCollectionState(),this.mediaMode,'mine','all');
    const rows = recentCollection(this.collectionCandidates(members,'mine'),4);
    this.recentCollectionMemo.put(key,rows,now,Number.MAX_SAFE_INTEGER);
    return rows;
  }
  private collectionSource(): PersonalLibraryRow[] { return this.collectionBase(); }
  private collectionSortKey(): string {
    const options = this.collectionFilter === 'other' ? defaultCollection() : this.collectionOptions;
    return JSON.stringify([this.displayRevisions.collection,this.libraryRevision,this.collectionScope,this.currentProgressScope(),
      this.mediaMode,this.collectionFilter,this.collectionStatusFilter,this.collectionQuery,options,this.presentationLanguage,
      this.titleVersion(this.mediaMode),this.metaVersion(this.mediaMode)]);
  }
  private collectionItems(prepare: boolean = false): PersonalLibraryRow[] {
    if (this.signedIn && !this.activeCloud()) { return []; }
    const now = Date.now();
    const options = this.collectionFilter === 'other' ? defaultCollection() : this.collectionOptions;
    const key = this.collectionSortKey();
    const cached = this.sortedViewRevision >= 0 ? this.collectionItemsMemo.get(key,now) : undefined;
    if (cached) { return cached; }
    if (!prepare || this.sortJobs.matches('collection',JSON.stringify([this.presentationEpoch,key]))) { return []; }
    const candidates = this.collectionCandidates(this.collectionSource(),this.collectionFilter);
    let expiry = Number.MAX_SAFE_INTEGER;
    if (this.collectionFilter === 'queue' && options.upcoming !== 'all') {
      expiry = Date.parse(new Date(now).toISOString().substring(0,10)+'T00:00:00Z') + 86400000;
      for (const candidate of candidates) {
        const date = Date.parse(candidate.meta?.release ?? '');
        if (date >= now) { expiry = Math.min(expiry,date === now ? date + 1 : date); }
      }
    }
    const input: CollectionSortInput = {candidates:candidates,options:options,section:this.collectionFilter,query:this.collectionQuery,now:now};
    this.runCollectionSort(input,key,expiry);
    return [];
  }
  private async runCollectionSort(input: CollectionSortInput, key: string, expiry: number): Promise<void> {
    const slot = 'collection';
    const epoch = this.presentationEpoch;
    const token = this.sortJobs.begin(slot,JSON.stringify([epoch,key]));
    if (!token) { return; }
    try {
      const rows = await collectionDisplay(input);
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'library' ||
          epoch !== this.presentationEpoch || key !== this.collectionSortKey() ||
          (this.signedIn && !this.activeCloud()) || Date.now() < input.now || Date.now() >= expiry) { return; }
      this.collectionItemsMemo.put(key,rows,input.now,expiry);
    } finally {
      if (this.sortJobs.finish(slot,token) && this.pageVisible) { this.sortedViewRevision++; this.requestPresentation(); }
    }
  }

  private collectionEntries(): GroupEntry[] {
    const label = this.collectionFilter === 'hidden' ? '隐藏影视' : this.collectionFilter === 'queue' ? '待看清单' : '全部';
    return this.collectionItems().map((row: PersonalLibraryRow): GroupEntry => ({ key: this.collectionFilter, label: label, row: row }));
  }

  private collectionPageGroups(): CollectionGroup[] {
    return pageGroups(this.collectionEntries(), this.collectionPage, this.collectionPageSize);
  }

  private collectionSlice(): PersonalLibraryRow[] {
    const result: PersonalLibraryRow[] = [];
    const seen: Set<string> = new Set<string>();
    for (const group of this.collectionPageGroups()) {
      for (const row of group.rows) {
        if (!seen.has(row.media.id)) { result.push(row); seen.add(row.media.id); }
      }
    }
    return result;
  }

  private toggleCollectionLocal(id: string): void {
    if (!this.canEditLibrary() || !this.ready || this.saving || this.cloudBusy || this.syncBusy) { return; }
    const row = this.personalLibrary().find((value: PersonalLibraryRow) => value.media.id === id);
    if (!row || this.isHidden(row.media) || row.media.kind === 'show') { return; }
    if (isTraktMedia(row.media)) { this.changeMediaIntent(row.media, 'movie', row.watched ? 'no' : 'yes'); }
    else { this.save(setWatched(this.items, id, !row.watched)); }
  }

  private collectionPages(): number {
    return Math.max(1, Math.ceil(this.collectionEntries().length / this.collectionPageSize));
  }

  private chooseCollection(filter: string): void {
    if (this.collectionFilter !== filter) {
      this.collectionOptionsOpen = false;
      this.resetCollection();
      this.collectionFilter = filter;
      this.collectionQuery = '';
      this.collectionStatusFilter = 'all';
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
    this.requestPresentation();
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
    List({ space: 12 }) {
      ListItem() {
        Column({ space: 12 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
      Row({ space: 8 }) {
        Text('收藏').fontSize(25).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('列表').fontSize(12).onClick(() => { this.chooseCollection('lists'); })
      }.width('100%')
      this.librarySyncNotice()
      this.movieUndoView()
      if (this.cloudBusy || this.localBusy) { Text('正在更新收藏…').fontSize(12).width('100%') }
      else if (this.libraryNotice) { Text(this.libraryNotice).fontSize(12).width('100%') }
      Row({ space: 6 }) {
        this.collectionFilterButton(this.mediaMode === 'show' ? '我的剧集' : '我的电影', 'mine')
        this.collectionFilterButton('待看', 'queue')
        this.collectionFilterButton('隐藏', 'hidden')
        if (collectionRows(this.personalLibrary(), this.mediaMode, 'other').length > 0) {
          this.collectionFilterButton('其他', 'other')
        }
      }.width('100%')
      if (this.collectionFilter === 'lists') {
        Text('自定义列表尚未实现。')
          .fontSize(14).width('100%')
      } else {
      if (this.mediaMode === 'show' && this.collectionFilter === 'mine') {
        Row({ space: 4 }) {
          this.collectionStatusButton('全部', 'all')
          this.collectionStatusButton('正在追', 'watching')
          this.collectionStatusButton('已完结', 'finished')
        }.width('100%')
        Row({ space: 4 }) {
          this.collectionStatusButton('等待更新', 'upcoming')
          this.collectionStatusButton('待核实', 'unclassified')
        }.width('100%')
      }
      TextInput({ placeholder: this.mediaMode === 'show' ? '搜索收藏剧集' : '搜索收藏电影', text: this.collectionQuery })
        .onChange((value: string) => {
          this.collectionQuery = value;
          this.resetCollection();
        }).onSubmit(() => { if (this.collectionGrid) { this.loadCollectionPosters(); } })
      if (this.collectionFilter !== 'other') { this.collectionRuleControls() }
      if (this.collectionRuleStatus) { Text(this.collectionRuleStatus).fontSize(12).width('100%') }
      if (this.collectionFilter === 'hidden') { Text('仅本机隐藏，不删除历史、不写入 Trakt。').fontSize(12).width('100%') }
      if (this.collectionFilter === 'mine' && this.collectionPage === 1 && !this.collectionQuery.trim() && this.recentCollectionRows().length) {
        Text('最近添加（已记录时间）').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
        ForEach(this.recentCollectionRows(), (row: PersonalLibraryRow) => {
          Text(this.displayTitle(row.media)).fontSize(13).width('100%').onClick(() => { this.openDetail(row.media); })
            .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'library','','recent:' + row.media.id); })
        }, (row: PersonalLibraryRow) => 'recent:' + row.media.id + ':' + this.displayTitle(row.media))
      }
      if (this.collectionSummary.key === this.collectionDisplayKey()) {
        if (!this.collectionSummary.total && !this.cloudBusy && !this.localBusy) { Text('此分类暂无影视。').fontSize(13).width('100%') }
        Text('共 ' + this.collectionSummary.total + ' 部').fontSize(14)
      } else { Text('正在更新列表…').fontSize(13).width('100%') }
      Row({ space: 8 }) {
        Button(this.collectionGrid ? '切换文字列表' : '切换海报网格').layoutWeight(1)
          .onClick(() => {
            this.collectionGrid = !this.collectionGrid;
            this.scheduleLazyRows();
            if (this.collectionGrid) { this.loadCollectionPosters(); }
          })
        if (this.collectionGrid) {
          Button(this.collectionBusy ? '加载中…' : '加载本页海报').layoutWeight(1)
            .enabled(!this.collectionBusy && !this.setupBusy && !!this.clientId)
            .onClick(() => { this.loadCollectionPosters(); })
        }
      }.width('100%')
      if (this.collectionGrid && this.collectionStatus) { Text(this.collectionStatus).fontSize(12) }
      }
        }.width('100%')
      }
      if ((!this.signedIn || this.activeCloud()) && this.collectionFilter !== 'lists') {
        LazyForEach(this.collectionRowsSource, (group: CollectionGroup) => {
          ListItem() { this.collectionGroupView(group) }
        }, (group: CollectionGroup) => this.collectionRowsSource.keyFor(group.key))
        ListItem() {
      Row({ space: 8 }) {
        Button('上一页').layoutWeight(1).enabled(!this.collectionBusy && this.collectionSummary.key === this.collectionDisplayKey() && this.collectionSummary.page > 1)
          .onClick(() => { this.goCollectionPage(this.collectionPage - 1); })
        Text(this.collectionSummary.page + ' / ' + this.collectionSummary.pages).fontSize(13)
        Button('下一页').layoutWeight(1).enabled(!this.collectionBusy && this.collectionSummary.key === this.collectionDisplayKey() && this.collectionSummary.page < this.collectionSummary.pages)
          .onClick(() => { this.goCollectionPage(this.collectionPage + 1); })
      }.width('100%')
        }
      }
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  collectionSortButton(label: string, sort: string) {
    Button(label).layoutWeight(1).fontSize(12).enabled(!this.collectionEditBusy)
      .backgroundColor(this.collectionOptions.sort === sort ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.collectionOptions.sort === sort ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.editCollectionOptions('sort',sort); })
  }

  @Builder
  collectionRuleControls() {
    Button(this.collectionOptionsOpen ? '收起排序与筛选' : '排序与筛选').fontSize(12)
      .onClick(() => { this.collectionOptionsOpen = !this.collectionOptionsOpen; this.requestPresentation(); })
    if (this.collectionOptionsOpen) {
      Row({ space: 4 }) {
        this.collectionSortButton('添加时间','added')
        this.collectionSortButton('名称','title')
        this.collectionSortButton('公众评分','rating')
        this.collectionSortButton('最新','newest')
      }.width('100%')
      Row({ space: 4 }) {
        this.collectionSortButton('随机','random')
        if (this.mediaMode === 'movie') {
          this.collectionSortButton('时长','runtime')
        } else if (this.collectionFilter === 'mine') { this.collectionSortButton('最近观看','recent') }
        this.collectionSortButton('个人评分','userRating')
        Button(this.collectionOptions.descending ? '降序' : '升序').layoutWeight(1).fontSize(12)
          .onClick(() => { this.editCollectionOptions('direction',''); })
      }.width('100%')
      Text('类型（英文分类 slug，逗号分隔，回车保存；留空清除）').fontSize(12).width('100%')
      TextInput({ text: this.collectionGenreDraft, placeholder: '如 drama,comedy' })
        .onChange((value: string) => { this.collectionGenreDraft = value; })
        .onSubmit(() => { this.editCollectionOptions('genre',this.collectionGenreDraft); })
      if (this.mediaMode === 'show') {
        Text('播出平台（Trakt 平台原名，逗号分隔，回车保存）').fontSize(12).width('100%')
        TextInput({ text: this.collectionNetworkDraft, placeholder: '如 Netflix,HBO' })
          .onChange((value: string) => { this.collectionNetworkDraft = value; })
          .onSubmit(() => { this.editCollectionOptions('network',this.collectionNetworkDraft); })
      }
      if (this.collectionFilter === 'queue') {
        Row({ space: 4 }) {
          Button('全部').layoutWeight(1).fontSize(12).onClick(() => { this.editCollectionOptions('upcoming','all'); })
          Button('已播/上映').layoutWeight(1).fontSize(12).onClick(() => { this.editCollectionOptions('upcoming','released'); })
          Button('待播/上映').layoutWeight(1).fontSize(12).onClick(() => { this.editCollectionOptions('upcoming','upcoming'); })
        }.width('100%')
      }
      if (this.collectionOptions.sort === 'userRating' && this.collectionRatingStatus) { Text(this.collectionRatingStatus).fontSize(12).width('100%') }
      Text('未知添加时间、评分和分类不会被猜测；资料未齐时筛选结果可能不完整。').fontSize(12).width('100%')
    }
  }

  @Builder
  collectionStatusButton(label: string, status: string) {
    Button(label).layoutWeight(1).fontSize(12)
      .backgroundColor(this.collectionStatusFilter === status ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.collectionStatusFilter === status ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => {
        this.collectionStatusFilter = status;
        this.resetCollection();
        if (this.collectionGrid) { this.loadCollectionPosters(); }
      })
  }

  @Builder
  collectionGroupView(group: CollectionGroup) {
    Column({ space: 8 }) {
      if (this.collectionGrid) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(group.rows, (row: PersonalLibraryRow) => {
            Column({ space: 6 }) {
              if (this.artwork(row.media)) {
                Image(this.artwork(row.media))
                  .width('100%').aspectRatio(0.667).objectFit(ImageFit.Cover).borderRadius(10)
              } else {
                Column() {
                  Text('海报').fontSize(13).fontColor($r('app.color.showly_secondary'))
                }.width('100%').aspectRatio(0.667).justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
              }
              Text(this.displayLabel(row.media)).fontSize(14).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(businessLibraryLabel(row)).fontSize(11).width('100%')
              this.showProgressActions(row.media)
              if (!this.isHidden(row.media) && row.media.kind !== 'show' && this.canEditLibrary()) {
                Button(row.watched ? '撤销已看' : '标记已看').fontSize(12)
                  .enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
                  .onClick(() => { this.toggleCollectionLocal(row.media.id); })
              }
            }.width('48%').padding({ bottom: 12 })
              .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'library',''); })
              .onClick(() => { this.openDetail(row.media); })
          }, (row: PersonalLibraryRow) => row.media.id + ':' + businessLibraryLabel(row) + ':' +
            this.artwork(row.media) + ':' + this.displayTitle(row.media))
        }.width('100%')
      } else {
        ForEach(group.rows, (row: PersonalLibraryRow) => {
          Row({ space: 8 }) {
            this.posterImage(row.media, 54, 81)
            Column({ space: 4 }) {
              Text(this.displayLabel(row.media)).width('100%')
              Text(businessLibraryLabel(row)).fontSize(12).width('100%')
              this.showProgressActions(row.media)
            }.layoutWeight(1).onClick(() => { this.openDetail(row.media); })
            Button('详情').fontSize(12).onClick(() => { this.openDetail(row.media); })
            if (!this.isHidden(row.media) && row.media.kind !== 'show' && this.canEditLibrary()) {
              Button(row.watched ? '撤销已看' : '标记已看').fontSize(12)
                .enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
                .onClick(() => { this.toggleCollectionLocal(row.media.id); })
            }
          }.width('100%')
            .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'library',''); })
        }, (row: PersonalLibraryRow) => row.media.id + ':' + businessLibraryLabel(row) + ':' +
          (row.watched ? 'yes' : 'no') + ':' + this.artwork(row.media) + ':' + this.displayTitle(row.media))
      }
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
    if (this.selectedMedia?.id !== item.id) { return; }
    this.presentation?.retryArtwork();
    this.presentationBlocked = false;
    this.presentationStatus = '';
    this.requestPresentation();
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
    this.effectiveEditable = false;
    this.fullSchedule = undefined;
    this.schedulePage = 1;
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
      if ((this.tab === 'library' || (this.tab === 'progress' && this.progressMode === 'next')) && !this.nextShows.length) { this.loadNextShows(); }
      return true;
    }
    if (this.tab === 'search' || this.tab === 'cloud' || this.tab === 'account') {
      this.navigate(this.returnTab);
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
      this.requestPresentation();
    } catch (error) {
      if (revision === this.detailRevision) {
        this.detailStatus = '详情读取失败，请检查网络或 Trakt API 权限后重试。';
      }
    } finally {
      this.detailBusy = false;
    }
  }

  private async changeMediaMode(mode: string): Promise<void> {
    if (this.modeBusy || this.selectedMedia || (mode !== 'show' && mode !== 'movie') || mode === this.mediaMode) { return; }
    this.modeBusy = true;
    try {
      this.mediaMode = normalizeMode(mode);
      this.restoreDiscoverOptions();
      this.progressMode = 'next';
      this.collectionFilter = 'mine';
      this.collectionQuery = '';
      this.collectionStatusFilter = 'all';
      this.nextPage = 1;
      this.movieProgressPage = 1;
      this.calendarWeek = 0;
      this.resetDiscover();
      // Calendar range changes do not discard account movie metadata.
      ++this.calendarRevision;
      this.calendarData = undefined;
      this.calendarBusy = false;
      this.calendarPage = 1;
      this.calendarStatus = '';
      const source = this.activeCloud();
      if (source) { this.publishMovieSource(source); }
      this.resetCollection();
      if (this.settings) { await this.settings.saveMode(this.mediaMode); }
      this.modeStatus = '';
    } catch (error) { this.modeStatus = '影视模式暂未保存，下次启动可能恢复原模式。'; }
    finally { this.modeBusy = false; }
    if (this.tab === 'discover') { this.loadDiscover(); }
    if (this.tab === 'library' && this.collectionGrid) { this.loadCollectionPosters(); }
    if (this.tab === 'progress') { this.chooseProgressMode('next'); }
  }

  @Builder
  mediaModeTabs() {
    Row({ space: 8 }) {
      Button('剧集').layoutWeight(1).fontSize(14).enabled(!this.modeBusy)
        .backgroundColor(this.mediaMode === 'show' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
        .fontColor(this.mediaMode === 'show' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
        .onClick(() => { this.changeMediaMode('show'); })
      Button('电影').layoutWeight(1).fontSize(14).enabled(!this.modeBusy)
        .backgroundColor(this.mediaMode === 'movie' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
        .fontColor(this.mediaMode === 'movie' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
        .onClick(() => { this.changeMediaMode('movie'); })
    }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  private navigate(value: string): void {
    if (this.tab === 'progress' || this.tab === 'discover' || this.tab === 'library') { this.returnTab = this.tab; }
    this.closeDetail();
    if (this.tab === 'discover' && value !== 'discover') { this.discoverRevision++; this.discoverBusy = false; }
    if (this.tab === 'library' && value !== 'library' && this.collectionBusy) { this.resetCollection(); }
    this.tab = value === 'cloud' ? 'account' : value;
    if (value === 'cloud') { this.advancedSync = true; }
    if (value === 'progress') { this.chooseProgressMode(this.progressMode); }
    if (value === 'discover' && !this.discoverBusy) { this.loadDiscover(this.discoverPage); }
    if (value === 'library' && this.episodeReady && this.ready) {
      if (this.signedIn) { this.requestObservation(); }
      else if (!this.libraryEvidence.length) { this.loadNextShows(); }
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
      Button('返回').onClick(() => { this.closeDetail(); if ((this.tab === 'library' || (this.tab === 'progress' && this.progressMode === 'next')) && !this.nextShows.length) { this.loadNextShows(); } })
      Text(this.displayTitle(item))
        .fontSize(26).fontWeight(FontWeight.Bold).width('100%')
      if (this.artwork(item)) {
        Image(this.artwork(item))
          .width(180).height(270).objectFit(ImageFit.Contain).borderRadius(10)
          .onError(() => {
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
        Text(this.displayOverview(item, this.detail.overview) || '暂无简介').fontSize(15).width('100%')
        if (this.presentationLanguage === 'zh') {
          Button('重试中文资料').onClick(() => { this.translateDetail(item); })
        }
      }
      if (isTraktMedia(item)) { this.mediaStateView(item) }
      if (item.kind === 'show') {
        this.localEpisodesView(item)
      }
      if (this.detailBusy) { Text('正在更新详情…').fontSize(12).width('100%') }
      Button('刷新详情').enabled(!this.detailBusy && !this.setupBusy)
        .onClick(() => { this.openDetail(item, true); })
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

  @Builder
  librarySyncNotice() {
    if (this.signedIn && !this.activeCloud()) {
      Text('正在验证账户，暂不可编辑。').fontSize(12).width('100%')
    } else if (this.signedIn && !this.cloudLocalAllowed) {
      Button('完成账户设置以编辑收藏').fontSize(12).onClick(() => { this.navigate('account'); })
    }
  }

  @Builder
  syncSettingsView() {
    Column({ space: 10 }) {
      Text('Trakt 同步').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      Text(this.signedIn ? '已连接' : '未连接').fontSize(14).width('100%')
      if (this.signedIn) {
        Text(this.autoActive() ? '快捷同步已开启；仅限已授权的新观看记录。' : '快捷同步未开启；需要上传的操作请在高级同步管理确认。').fontSize(12).width('100%')
        Button(this.cloudBusy ? '更新中…' : '更新个人库').width('100%')
          .enabled(!this.cloudBusy && !this.syncBusy && !this.authBusy && !this.localBusy && !this.saving)
          .onClick(() => { this.requestObservation(); })
        if (this.libraryNotice) { Text(this.libraryNotice).fontSize(12).width('100%') }
        if (!this.cloudLocalAllowed) {
          Button('验证并绑定账户').enabled(!this.cloudBusy && !this.syncBusy && !this.authBusy && !this.localBusy)
            .onClick(() => { this.advancedSync = true; this.verifySync(); })
        }
        if (this.syncBound && this.syncAccount && traktAuth.isCurrent(this.clientId, this.syncAccount.generation)) {
          Button(this.autoActive() ? '关闭快捷同步' : '开启快捷同步')
            .enabled(!this.syncBusy && !this.cloudBusy && !this.localBusy && !this.authBusy)
            .onClick(() => { this.setAuto(!this.autoActive()); })
          Text('分集快捷同步仅上传已授权的新观看标记。电影及待看使用下方独立授权。').fontSize(12).width('100%')
        } else {
          Button('同步设置').enabled(!this.cloudBusy && !this.syncBusy && !this.authBusy && !this.localBusy)
            .onClick(() => { this.advancedSync = true; this.verifySync(); })
        }
      }
      if (this.signedIn && this.cloudLocalAllowed) {
        Text('电影及待看快捷同步').fontSize(16).width('100%')
        Button(this.titleQuickActive() ? '关闭电影及待看快捷同步' : '开启电影及待看快捷同步')
          .enabled(!this.syncBusy && !this.cloudBusy && !this.localBusy && !this.authBusy && !this.saving)
          .onClick(() => {
            if (this.titleQuickActive()) { this.setTitleQuick(false); }
            else { this.titleConfirm = true; }
          })
        if (this.titleConfirm) {
          Text('授权此后标记电影已看（可能移出待看）以及加入／移出待看自动同步。不会自动删除观看历史，不会上传旧记录。')
            .fontSize(12).width('100%')
          Row({ space: 8 }) {
            Button('取消').layoutWeight(1).onClick(() => { this.titleConfirm = false; })
            Button('确认授权').layoutWeight(1).enabled(!this.syncBusy && !this.cloudBusy && !this.localBusy && !this.saving)
              .onClick(() => { this.setTitleQuick(true); })
          }.width('100%')
        }
        if (this.titleQuickStatus) { Text(this.titleQuickStatus).fontSize(12).width('100%') }
        Button('核对待处理操作').enabled(this.titleQuickActive() && !this.syncBusy && !this.cloudBusy && !this.localBusy && !this.saving)
          .onClick(() => { this.titleQuickPending = true; this.onRecoveryGateChanged(); })
      }
      Button(this.advancedSync ? '收起高级同步管理' : '高级同步管理')
        .onClick(() => { this.advancedSync = !this.advancedSync; })
      if (this.advancedSync) {
        this.syncPreviewView()
        this.mediaPreviewView()
        Text(this.cloudStatus).fontSize(12).width('100%')
        Text(this.migrationStatus).fontSize(12).width('100%')
        Text(this.libraryStatus).fontSize(12).width('100%')
        Text(this.localStatus).fontSize(12).width('100%')
        if (this.cloud && this.signedIn) {
          Button('仅导入新待看与已看电影到本机')
            .enabled(this.ready && this.cloudLocalAllowed && !this.saving && !this.cloudBusy && !this.authBusy)
            .onClick(() => { this.importCloud(); })
          Button('清除云端预览').enabled(!this.cloudBusy).onClick(() => { this.clearCloud(); })
        }
      }
    }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
  }

  @Builder
  searchView() {
    List({ space: 10 }) {
      ListItem() {
        Column({ space: 12 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
        Text('影视搜索').fontSize(20).fontWeight(FontWeight.Medium)
        TextInput({ placeholder: '电影或剧集名称', text: this.title })
          .onChange((value: string) => { this.title = value; })
        Row({ space: 8 }) {
          Button('搜索').layoutWeight(1)
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
        }.width('100%')
      }
        LazyForEach(this.searchRows, (item: Media) => {
          ListItem() {
          Row({ space: 8 }) {
            this.posterImage(item, 54, 81)
            Text(this.displayLabel(item)).layoutWeight(1)
              .onClick(() => { this.openDetail(item); })
            if (this.isHidden(item)) { Text('已隐藏').fontSize(12) }
            Button('详情').fontSize(12).enabled(!this.detailBusy && !this.setupBusy)
              .onClick(() => { this.openDetail(item); })
            Button(this.isInLibrary(item) ? '已收藏' : '添加')
              .enabled(this.ready && !this.saving && !this.cloudBusy && this.canEditLibrary() && !this.isInLibrary(item))
              .onClick(() => { this.changeMediaIntent(item, 'watchlist', 'yes'); })
          }.width('100%')
            .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(item,0,[],visible && ratio > 0,'search',''); })
          }
        }, (item: Media) => this.searchRows.keyFor(item.id))
    }.width('100%').height('100%').padding(16)
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('Showly').fontSize(27).fontWeight(FontWeight.Bold).layoutWeight(1)
        this.headerAction('搜索', 'search')
        this.headerAction('设置', 'account')
      }.width('100%').padding(12).backgroundColor($r('app.color.showly_surface'))
      Divider().color($r('app.color.showly_line'))
      if (!this.selectedMedia && (this.tab === 'progress' || this.tab === 'discover' || this.tab === 'library')) {
        this.mediaModeTabs()
        if (this.modeStatus) { Text(this.modeStatus).fontSize(12).width('100%') }
      }
      Refresh({ refreshing: $$this.refreshing }) {
        if (!this.selectedMedia && this.tab === 'progress' && this.progressMode === 'next') {
          if (this.mediaMode === 'movie') { this.movieProgressView() }
          else { this.nextShowsView() }
        } else if (!this.selectedMedia && this.tab === 'library') {
          this.collectionView()
        } else if (!this.selectedMedia && this.tab === 'discover') {
          this.discoverView()
        } else if (!this.selectedMedia && this.tab === 'search') {
          this.searchView()
        } else if (!this.selectedMedia && this.tab === 'progress' && this.progressMode === 'calendar') {
          if (this.mediaMode === 'movie') { this.personalMovieCalendarView() } else { this.calendarView() }
        } else {
        Scroll() {
        Column({ space: 14 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          if (this.selectedMedia) {
            this.detailPage(this.selectedMedia)
          } else if (this.tab === 'progress') {
            this.progressView()
          } else {
            Text('账户与设置').fontSize(23).fontWeight(FontWeight.Bold)
            Text('影视资料语言').fontSize(19).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 6 }) {
              Button(this.presentationLanguage === 'zh' ? '简体中文 ✓' : '简体中文').layoutWeight(1).enabled(!this.languageBusy)
                .onClick(() => { this.changePresentationLanguage('zh'); })
              Button(this.presentationLanguage === 'original' ? '原文 ✓' : '原文').layoutWeight(1).enabled(!this.languageBusy)
                .onClick(() => { this.changePresentationLanguage('original'); })
            }.width('100%')
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
          Text('登录使用 Trakt 官方浏览器页面。').fontSize(12)

        }
            this.syncSettingsView()
          }
        }.width('100%').padding(16)
        }.width('100%').height('100%').align(Alignment.TopStart)
        }
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
