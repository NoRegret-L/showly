import { SyncStatusPanel } from './SyncStatusPanel';
import { lastScheduleWake } from '../data/SyncSchedule';
import { executeEpisodeQueue } from '../data/EpisodeQueueExecutor';
import { SyncCoordinator, syncService } from '../model/SyncCoordinator';
import { GalleryTarget } from '../model/GalleryRules';
import { GalleryPage } from './GalleryPage';
import { CommentTarget } from '../model/CommentRules';
import { CommentsPage } from './CommentsPage';
import { WatchOptions } from '../model/AvailabilityRules';
import { WatchSettings } from './WatchSettings';
import { StreamingSection } from './StreamingSection';
import { MovieSeriesSection } from './MovieSeriesSection';
import { RatingEditor } from './RatingEditor';
import { RatingTarget,RatingState,RatingRecord } from '../model/RatingRules';
import { openRatings } from '../data/RatingsRepository';
import { StatisticsPage } from './StatisticsPage';
import { StatisticsInput, StatisticsRating } from '../model/StatisticsOwner';
import { CustomListsPage } from './CustomListsPage';
import { SeasonExtrasCoordinator } from '../data/SeasonExtrasCoordinator';
import { SearchController, SearchSnapshot } from '../model/SearchController';
import { SeasonDetailOwner, SeasonDetailSnapshot, emptySeasonDetail, VerifiedEpisode, DetailEpisodeEntry, DetailSeasonRow } from '../model/SeasonDetailOwner';
import { DetailSeasons } from './DetailSeasons';
import { DetailSummarySection } from './DetailSummarySection';
import { DetailPeopleSection } from './DetailPeopleSection';
import { DetailRelatedSection } from './DetailRelatedSection';
import { DetailViewOwner, DetailSnapshot, emptyDetail } from '../model/DetailViewOwner';
import { DetailHeader } from './DetailHeader';
import { CollectionViewOwner, CollectionNetworkGroup, CollectionGenreOption, COLLECTION_NETWORK_GROUPS, COLLECTION_GENRES, toggleCollectionSelection, COLLECTION_RECENT_AMOUNTS, CollectionDependencyVersions, CollectionMetadataVersions, CollectionRatingRequest, CollectionRecoveryOwner, CollectionUiSnapshot, emptyCollectionUi, collectionUiNext, CollectionSpoilers, defaultCollectionSpoilers, collectionSpoilerText, progressRatingSpoilerText, collectionEmptyText } from '../model/CollectionViewOwner';
import { StableDisplayOrder, StableOrderChange } from '../model/StableDisplayOrder';
import { PageStateOwner, PageWork, PageWorkSet, PageSortJobs, PageSummary } from '../model/PageStateOwner';
import { ProgressTitleOrder } from '../model/ProgressTitleOrder';
import { PresentationQueues, FramePublication } from '../model/PresentationQueue';
import { ArtworkImage } from './ArtworkImage';
import { MediaInputVersion } from '../model/MediaInputVersion';
import { DetailSession, SeasonSummary, summarizeSeasons } from '../model/DetailSession';
import { DetailEpisodeList } from './DetailEpisodeList';
import { EpisodeRowsOwner, EpisodeDisplayRow } from '../model/EpisodeRowsOwner';
import { ListDiffInput } from '../model/ListDiff';
import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { ScrollRows, ScrollAnchor, ScrollAnchors, captureAnchor, resolveAnchor } from '../model/ScrollAnchor';
import { ReadCancel, ReadCancelled } from '../model/ReadFlight';
import { common } from '@kit.AbilityKit';
import { LazyRows } from '../model/LazyRows';
import { DisplayRevisions } from '../model/DisplayJobs';
import { ProgressSortInput, MovieSortInput, CollectionSortInput } from '../model/DisplaySort';
import { diffDisplay, showDisplay, movieDisplay, collectionDisplay } from '../data/DisplayTasks';
import { ViewportTasks, addPresentationTask } from '../model/ViewportTasks';
import { CollectionCandidate, CollectionOptions, CollectionState, HiddenEntry, defaultCollection, emptyCollectionState, collectionMembers, recentCollection, projectCollection, recordCollectionDate, transitionCollectionDates, hideMedia, collectionSortEligible, compareCollectionCandidates, sameCollectionCandidate } from '../model/CollectionRules';
import { PresentationAttempts, PresentationFailure, presentationFailure } from '../model/PresentationPolicy';
import { presentationGate } from '../data/PresentationHttp';
import { PresentationRepository } from '../data/PresentationRepository';
import { TitlePresentation, SeasonPresentation, PresentationTask, matchesText } from '../model/MediaPresentation';
import { Media, CollectionDate, mediaLabel, setWatched } from '../model/Media';
import { LibraryStore } from '../data/LibraryStore';
import { MediaStore } from '../data/MediaStore';
import { TitleConsent, TitleChange, TitleIntent, titleEdit } from '../model/TitleQuickState';
import { runTitleQuick, reconcileTitleObservation } from '../data/TitleQuickSync';
import { BackupData, RestorePlan, createBackup, exportBackup, selectBackup, planRestore, restoreBackup } from '../data/LocalBackup';
import { MediaRecord, migrateLegacy, isTraktMedia, applyLegacyEdit, setMediaIntent, inLocalWatchlist, followShow } from '../model/MediaState';
import { PersonalLibraryRow, LibraryShowEvidence, PersonalLibraryIndex, PersonalLibraryChange, buildPersonalLibrary, filterPersonalLibrary, businessLibraryLabel, isPersonalMember } from '../model/PersonalLibrary';
import { MediaPreview, MediaDifference, buildMediaPreview } from '../data/TraktMediaPreview';
import { syncSelectedMedia, reconcilePendingMedia } from '../data/TraktMediaSync';
import { checkpointEpisodes, checkpointMedia, adoptEpisodeCloud, adoptMediaCloud } from '../data/ThreeWaySync';
import { threeWayLabel } from '../model/ThreeWay';
import { NextShow } from '../data/NextShows';
import { HistoryOwner, HistoryEntry, HistoryEpisode, HistorySnapshot, HistoryPeriodOption, HISTORY_PERIODS, initialHistory, validHistoryPeriod } from '../model/HistoryOwner';
import { RevisionMemo, projectionKey } from '../model/ReadModelCache';
import { CandidateInput, CandidateBatch, CandidateResult, ProgressCandidateIndex } from '../model/ProgressCandidates';
import { CacheLifecycle, cacheResidency, memoryEvents } from '../model/CacheLifecycle';
import { computeCandidateDisplay } from '../data/ProgressCandidateTask';
import { ShowProjectionCache } from '../model/ProjectionCompute';
import { MovieProgressOptions, MovieProgressSource, defaultMovieProgress, validMovieProgress, movieProgressRows as projectMovieProgress, clearMoviePin, movieSortEligible, compareMovieSources, sameMovieSource } from '../model/MovieProgressRules';
import { ProgressSource, ProgressPreferences, ProgressFlag, ProgressRow, defaultProgress, validProgress, toggleProgressFlag, selectProgress, sortProgressCandidates, ProgressEntry, progressSections, progressEntries, progressPage, effectiveProgressFilter, validWatchTime, releaseWatchTime, ProgressWatchSelection } from '../model/ProgressRules';
import { CalendarSource, CalendarInput, CalendarEntry, CalendarIndex, CalendarText, CalendarJobInput, calendarClockKey, calendarExpiry, calendarPageRows, calendarTitleHidden } from '../model/CalendarRules';
import { calendarDisplay } from '../data/CalendarTask';
import { PersonalMovie, PersonalMovieSnapshot, readPersonalMovieDate, CollectionRating, readCollectionRatings } from '../data/TraktLibrary';
import { MovieCalendarItem, filterMovies, moviePage } from '../data/MovieCalendar';
import { SearchRecord, SearchCandidate, SearchInput, SearchOptions, SearchGeneration, defaultSearch, publicSearchRecord, searchScope, validSearchRecord, SearchCandidateTitles } from '../model/SearchRules';
import { SearchRead } from '../model/SearchRead';
import { openSearch } from '../data/SearchRepository';
import { searchDisplay } from '../data/SearchTask';
import { TRAKT_APPS_URL, TRAKT_REDIRECT_URI } from '../config/TraktConfig';
import { ClientSettings, validateClientId } from '../data/ClientSettings';
import { pasteboard } from '@kit.BasicServicesKit';
import { traktAuth } from '../data/TraktAuth';
import { CloudLibrary, ShowProgress, readCloudLibraryIncremental, mergeNewTitles, readActivity } from '../data/TraktLibrary';
import { LibraryProjection, LibraryProjectionSession, projectDetail } from '../data/LibraryProjection';
import { allowLocalScope } from '../model/EffectiveState';
import { hasTrackingEvidence } from '../model/PersonalLibrary';
import { CollectionGroup, GroupEntry, normalizeMode, progressTabs, collectionRows, pageGroups } from '../model/NavigationModel';
import { MediaDetail, canReadDetails, readDetails, clearDetailMemory } from '../data/TraktDetails';
import { CollectionFanartOwner } from '../data/CollectionFanart';
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
import { safeSyncError } from '../data/SyncDiagnostics';
import { APP_VERSION, RELEASES_URL } from '../config/BuildInfo';
import { UpdateInfo, UpstreamInfo, checkRelease, checkUpstream } from '../data/ReleaseUpdates';

interface CollectionIndexes {
  times: Map<string,number>;
  recent: Map<string,number>;
  ratings: Map<string,number>;
  movies: Map<string,PersonalMovie>;
}
interface PendingMediaDelta {
  changes?:PersonalLibraryChange[];
  movieQueryScope:string;
  movieAllScope:string;
  collectionScope:string;
  now:number;
  utc:string;
  version:string;
  account:string;
  cloud?:CloudLibrary;
  evidence:LibraryShowEvidence[];
  localAllowed:boolean;
}
class RestoreScrollFrame extends FrameCallback {
  private action: ()=>void;
  constructor(action: ()=>void) { super(); this.action=action; }
  onFrame(frameTimeInNano: number): void {}
  onIdle(timeLeftInNano: number): void { this.action(); }
}
@Entry
@Component
struct Index {
  private scrollAnchors: ScrollAnchors=new ScrollAnchors();
  private scrollIndices: Map<string,number>=new Map<string,number>();
  private scrollAccount: string='';
  private scrollScheduled?: ScrollAnchor=undefined;
  private discoverScroller: Scroller=new Scroller();
  private searchScroller: Scroller=new Scroller();
  private showScroller: Scroller=new Scroller();
  private movieScroller: Scroller=new Scroller();
  private calendarScroller: Scroller=new Scroller();
  private movieCalendarScroller: Scroller=new Scroller();
  private collectionScroller: Scroller=new Scroller();
  @State title: string = '';
  @State presentationLanguage: string = 'zh';
  @State presentationRevision: number = 0;
  private seasonKeys: Map<string, string[]> = new Map<string, string[]>();
  @State presentationStatus: string = '';
  @State languageBusy: boolean = false;
  private presentation?: PresentationRepository;
  private presentationLanes: Set<string> = new Set<string>();
  private presentationQueues=new PresentationQueues();
  private presentationFrame=new FramePublication();
  private viewportFrame=new FramePublication();
  private emptyBusinessTasks=new Map<string,PresentationTask>();
  private presentationAttempts: PresentationAttempts = new PresentationAttempts();
  private presentationWorkVersion: number = 0;
  private presentationEpoch: number = 0;
  private presentationRoute: string = '';
  private presentationPublished: number = -1;
  private titleIndex: Map<string, TitlePresentation> = new Map<string, TitlePresentation>();
  private episodeNameIndex: Map<string, string> = new Map<string, string>();
  private discoverRows: PageStateOwner<DiscoverItem[],DiscoverItem[]> = new PageStateOwner<DiscoverItem[],DiscoverItem[]>((row: DiscoverItem[])=>row.map((item: DiscoverItem)=>item.media.id));
  private searchRows: PageStateOwner<Media,Media[]> = new PageStateOwner<Media,Media[]>((row: Media)=>[row.id]);
  private calendarRows: PageStateOwner<CalendarEntry,CalendarEntry[]> = new PageStateOwner<CalendarEntry,CalendarEntry[]>((row: CalendarEntry)=>[row.media.id]);
  private movieCalendarRows: PageStateOwner<MovieCalendarItem,MovieCalendarItem[]> = new PageStateOwner<MovieCalendarItem,MovieCalendarItem[]>((row: MovieCalendarItem)=>[row.movie.media.id]);
  private showRows: PageStateOwner<ProgressEntry,ProgressRow[]> = new PageStateOwner<ProgressEntry,ProgressRow[]>((entry: ProgressEntry)=>entry.row?[entry.row.media.id]:[]);
  private movieRowsSource: PageStateOwner<PersonalLibraryRow,PersonalLibraryRow[]> = new PageStateOwner<PersonalLibraryRow,PersonalLibraryRow[]>((row: PersonalLibraryRow)=>[row.media.id]);
  private showCollectionRowsSource: PageStateOwner<CollectionGroup,PersonalLibraryRow[]> = new PageStateOwner<CollectionGroup,PersonalLibraryRow[]>((group: CollectionGroup)=>group.rows.map((row: PersonalLibraryRow)=>row.media.id));
  private movieCollectionRowsSource: PageStateOwner<CollectionGroup,PersonalLibraryRow[]> = new PageStateOwner<CollectionGroup,PersonalLibraryRow[]>((group: CollectionGroup)=>group.rows.map((row: PersonalLibraryRow)=>row.media.id));
  private collectionRowsSource():PageStateOwner<CollectionGroup,PersonalLibraryRow[]>{return this.mediaMode==='movie'?this.movieCollectionRowsSource:this.showCollectionRowsSource;}
  private collectionOwnerSlot():string{return this.mediaMode==='movie'?'libraryMovie':'libraryShow';}
  private collectionSortSlot():string{return this.mediaMode==='movie'?'collection-movie':'collection-show';}
  private historyRows:PageStateOwner<HistoryEntry,HistoryEntry[]>=new PageStateOwner<HistoryEntry,HistoryEntry[]>((row:HistoryEntry)=>row.episode?[row.episode.media.id]:[]);
  private historyScroller:Scroller=new Scroller();
  private historyOwner:HistoryOwner=new HistoryOwner();
  @State historyUi:HistorySnapshot=initialHistory();
  private pageWorks:PageWorkSet=this.createPageWorks();
  private sortJobs:PageSortJobs=new PageSortJobs(this.pageWorks);
  private createPageWorks():PageWorkSet{
    const pages=new PageWorkSet();
    pages.register('discover',this.discoverRows.work);pages.register('search',this.searchRows.work);
    pages.register('calendar',this.calendarRows.work);pages.register('movieCalendar',this.movieCalendarRows.work);
    pages.register('show',this.showRows.work);pages.register('movie',this.movieRowsSource.work);
    pages.register('libraryShow',this.showCollectionRowsSource.work);
    pages.register('libraryMovie',this.movieCollectionRowsSource.work);
    pages.register('history',this.historyRows.work);
    return pages;
  }
  private pageOwnerSlot():string{const slot=this.scrollSlot();return slot==='library'?this.collectionOwnerSlot():slot;}
  private activePageWork():PageWork|undefined{return this.pageWorks.get(this.pageOwnerSlot());}
  private libraryRevision: number = 0;
  private collectionDependencies:CollectionDependencyVersions=new CollectionDependencyVersions();
  private collectionMetadata:CollectionMetadataVersions=new CollectionMetadataVersions();
  private mediaInput: MediaInputVersion=new MediaInputVersion();
  private displayRevisions: DisplayRevisions = new DisplayRevisions();
  @State sortedViewRevision: number = 0;
  @State showSummary: PageSummary = {key:'',total:0,page:1,pages:1};
  @State movieSummary: PageSummary = {key:'',total:0,page:1,pages:1};
  @State collectionSummary: PageSummary = {key:'',total:0,page:1,pages:1};
  @State collectionUi:CollectionUiSnapshot=emptyCollectionUi();
  @State collectionSpoilers:CollectionSpoilers=defaultCollectionSpoilers();
  @State collectionRevealed:string[]=[];
  @State collectionFanart:Map<string,string>=new Map<string,string>();
  private fanartOwner:CollectionFanartOwner=new CollectionFanartOwner();
  private watchSelection:ProgressWatchSelection=new ProgressWatchSelection();
  @State progressWatchMode:string='ask';
  @State progressEpisodeHidden:boolean=false;
  @State progressRatingHidden:boolean=false;
  @State progressTapReveal:boolean=false;
  private progressRevealed:Set<string>=new Set<string>();
  private showCollectionRecovery:CollectionRecoveryOwner=new CollectionRecoveryOwner();
  private movieCollectionRecovery:CollectionRecoveryOwner=new CollectionRecoveryOwner();
  private collectionStage:string='初始化';
  private collectionRecovery():CollectionRecoveryOwner{return this.mediaMode==='movie'?this.movieCollectionRecovery:this.showCollectionRecovery;}
  private clearCollectionFanart():void{
    this.fanartOwner.clear();if(this.collectionFanart.size){this.collectionFanart=new Map<string,string>();}
  }
  private recentFanartVisible(item:Media,visible:boolean):void{
    if(!visible){this.fanartOwner.hide(item.id);return;}
    const scope=this.collectionRecoveryScope(),client=this.clientId;
    const current=():boolean=>this.pageVisible&&this.tab==='library'&&!this.selectedMedia&&item.kind===this.mediaMode&&this.collectionRecoveryScope()===scope&&this.clientId===client;
    if(current()){this.fanartOwner.visible(item,client,this.context().cacheDir,this.settings,current,(rows:Map<string,string>)=>{this.collectionFanart=rows;});}
  }
  private recentFanartFailed(item:Media,uri:string):void{
    if(this.fanartOwner.failed(item.id,uri)){this.collectionFanart=this.fanartOwner.snapshot();}
  }
  private collectionRecoveryScope():string{return JSON.stringify([this.currentProgressScope(),this.viewScope()]);}
  private publishCollectionUi(recent:PersonalLibraryRow[],other:boolean,error:string,retrying:boolean):void{
    const next=collectionUiNext(this.collectionUi,recent,other,error,retrying);
    if(next!==this.collectionUi){this.collectionUi=next;}
  }
  private showTitleRevision: number = 0;
  private movieTitleRevision: number = 0;
  private showMetaRevision: number = 0;
  private movieMetaRevision: number = 0;
  private hiddenIndex: Set<string> = new Set<string>();
  private flagIndex: Map<string,ProgressFlag> = new Map<string,ProgressFlag>();
  private libraryIndex: Map<string,PersonalLibraryRow> = new Map<string,PersonalLibraryRow>();
  private personalLibraryIndex:PersonalLibraryIndex=new PersonalLibraryIndex();
  private pendingMediaDelta?:PendingMediaDelta;
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
  private cacheLifecycle: CacheLifecycle=new CacheLifecycle();
  private detailSession: DetailSession<FullEpisodeCatalog>=new DetailSession<FullEpisodeCatalog>();
  private detailConsumer: ReadCancel=this.detailSession.consumer();
  private detailResumePending: boolean=false;
  private detailScroller: Scroller=new Scroller();
  private detailScrollOffset: number=0;
  private relatedBack:Media[]=[];
  private relatedOffsets:number[]=[];
  @State episodePage: boolean=false;
  private episodeRowOwner=new EpisodeRowsOwner();
  private seasonDetailOwner:SeasonDetailOwner=new SeasonDetailOwner();
  @State seasonDetail:SeasonDetailSnapshot=emptySeasonDetail();
  private seasonExtras:SeasonExtrasCoordinator=new SeasonExtrasCoordinator();
  private clearSeasonDetail():void{this.seasonExtras.clear();this.seasonDetailOwner.clear();this.seasonDetail=this.seasonDetailOwner.snapshot();this.episodeRowOwner.clear();}
  private seasonScope(item:Media):string{return JSON.stringify([this.currentSearchAccount(),item.id]);}
  @State ratingSheetOpen:boolean=false;
  @State ratingTarget:RatingTarget={kind:'show',id:0,label:''};
  private ratingTicket:number=0;
  private ratingScopeCaptured:string='';
  private ratingDetailCaptured:number=0;
  private ratingCurrent(ticket:number,scope:string):boolean{return this.ratingSheetOpen&&ticket===this.ratingTicket&&this.pageVisible&&this.currentProgressScope()===scope&&this.detailRevision===this.ratingDetailCaptured;}
  private closeRating():void{this.ratingTicket++;this.ratingSheetOpen=false;}
  private openRating(kind:string,id:number,label:string):void{
    const scope=this.currentProgressScope();if(!scope||!Number.isSafeInteger(id)||id<=0||!this.selectedMedia||this.setupBusy||this.authBusy||this.syncBusy||this.cloudBusy){return;}
    this.ratingTicket++;this.ratingScopeCaptured=scope;this.ratingDetailCaptured=this.detailRevision;this.ratingTarget={kind:kind,id:id,label:label};this.ratingSheetOpen=true;
  }
  private async ratingRead():Promise<RatingState>{
    const ticket=this.ratingTicket,scope=this.ratingScopeCaptured,target=this.ratingTarget,session=scope==='device'?undefined:traktAuth.session(this.clientId);
    const current=():boolean=>this.ratingCurrent(ticket,scope)&&(!session||traktAuth.isCurrent(session.clientId,session.generation));
    const repo=await openRatings(this.context());return repo.inspect(scope,target,session,current);
  }
  private async ratingSave(expected:RatingState,value:number):Promise<RatingState>{
    const ticket=this.ratingTicket,scope=this.ratingScopeCaptured,target=this.ratingTarget,session=scope==='device'?undefined:traktAuth.session(this.clientId);
    const current=():boolean=>this.ratingCurrent(ticket,scope)&&!this.setupBusy&&!this.authBusy&&!this.syncBusy&&!this.cloudBusy&&(!session||traktAuth.isCurrent(session.clientId,session.generation));
    const repo=await openRatings(this.context()),state=await repo.change(scope,target,expected,value,session,current);
    if(current()&&!state.pending){
      const item=this.selectedMedia;
      if(item&&(target.kind==='show'||target.kind==='movie')){
        this.detailOwner.personalRating(this.detailOwner.token(),state.value||undefined,false,state.value?'':'尚未评分');this.publishDetail();
        this.showRatingRequest.reset();this.movieRatingRequest.reset();this.collectionRatingKey='';this.movieRatingKey='';this.collectionDependencies.sourceChanged(target.kind);
      }else if(item){await this.reloadPartRatingRows(item);}
      if(scope!=='device'){this.requestObservation();}else{this.scheduleLazyRows();}
    }
    return state;
  }
  @Builder ratingSheet(){
    RatingEditor({target:this.ratingTarget,read:()=>this.ratingRead(),save:(state:RatingState,value:number)=>this.ratingSave(state,value),onClose:()=>{this.closeRating();}})
  }
  private async sharedRatings(kind:string,scope:string):Promise<RatingRecord[]>{
    if(!scope||scope!==this.currentProgressScope()){throw new Error('Rating scope changed');}
    const session=scope==='device'?undefined:traktAuth.session(this.clientId),source=this.activeCloud();
    const current=():boolean=>this.pageVisible&&scope===this.currentProgressScope()&&(!session||traktAuth.isCurrent(session.clientId,session.generation));
    const repo=await openRatings(this.context()),snapshot=await repo.list(scope,kind,session,this.cloudFresh?source?.activity??'':'',current);
    if(!current()||!snapshot.known){throw new Error('Rating data unavailable');}return snapshot.rows;
  }
  private async sharedTitleRatings(kind:string,scope:string):Promise<CollectionRating[]>{
    return (await this.sharedRatings(kind,scope)).map((row:RatingRecord):CollectionRating=>({id:kind+':'+row.id,value:row.value,ratedAt:row.ratedAt}));
  }
  private async reloadPartRatingRows(item:Media):Promise<void>{
    const scope=this.currentProgressScope(),revision=this.detailRevision,seasonScope=this.seasonScope(item),ratingScope=this.partRatingScope();
    try{const rows=await Promise.all([this.sharedRatings('season',scope),this.sharedRatings('episode',scope)]);
      if(this.pageVisible&&revision===this.detailRevision&&this.selectedMedia?.id===item.id&&scope===this.currentProgressScope()&&ratingScope===this.partRatingScope()){
        this.seasonExtras.presentation.setRatings(seasonScope,ratingScope,rows[0],rows[1]);this.publishSeasonPresentation();
      }
    }catch(error){}
  }
  @State commentSheetOpen:boolean=false;
  @State commentTarget:CommentTarget={kind:'show',id:0,label:''};
  private commentScope:string='';
  private commentRevision:number=0;
  private commentClient:string='';
  private commentCurrent():boolean{return this.commentSheetOpen&&this.pageVisible&&this.commentScope===this.currentProgressScope()&&this.commentRevision===this.detailRevision&&this.commentClient===this.clientId;}
  private openComments(t:CommentTarget):void{if(!this.clientId||!this.selectedMedia){return;}this.commentScope=this.currentProgressScope();this.commentRevision=this.detailRevision;this.commentClient=this.clientId;this.commentTarget=t;this.commentSheetOpen=true;}
  @Builder commentSheet(){CommentsPage({target:this.commentTarget,client:this.commentClient,scope:this.commentScope,session:()=>this.commentScope.startsWith('account:')?traktAuth.session(this.commentClient):undefined,current:()=>this.commentCurrent()&&!this.setupBusy&&!this.authBusy,onClose:()=>{this.commentSheetOpen=false;}})}
  @State gallerySheetOpen:boolean=false;
  @State galleryTarget:GalleryTarget={item:{id:'',kind:'show',title:'',year:0,watched:false},type:'poster',hints:[],initialUri:''};
  private galleryRevision:number=0;
  private galleryScope:string='';
  private openMediaGallery(item:Media,type:string):void{this.galleryRevision=this.detailRevision;this.galleryScope=this.currentSearchAccount();this.galleryTarget={item:item,type:type,hints:type==='poster'?this.detailUi.summary?.posterUrls??[]:this.detailUi.summary?.fanartUrls??[],initialUri:type==='poster'?this.artwork(item):this.detailUi.fanart};this.gallerySheetOpen=true;}
  private galleryCurrent():boolean{return this.gallerySheetOpen&&this.pageVisible&&this.galleryRevision===this.detailRevision&&this.galleryScope===this.currentSearchAccount();}
  @Builder gallerySheet(){GalleryPage({target:this.galleryTarget,client:this.clientId,current:()=>this.galleryCurrent(),onClose:()=>{this.gallerySheetOpen=false;}})}
  private partRatingScope():string{return JSON.stringify([this.currentProgressScope(),this.activeCloud()?.generation??-1,this.activeCloud()?.activity??'',this.cloudFresh]);}
  private publishSeasonPresentation():void{this.seasonDetail=this.seasonDetailOwner.touch();this.updateEpisodePageRows();}
  private displaySeasonRows():DetailSeasonRow[]{
    const rows=this.seasonDetail.seasons;
    const special=this.seasonExtras.presentation.season(0);
    if(!this.settings?.loadSpecialSeasons()||!special){return rows;}
    const extra:DetailSeasonRow={number:0,count:0,completed:0,total:special.episodes.length};return rows.concat([extra]);
  }
  private async toggleSpecialSeasons():Promise<void>{
    if(!this.settings){return;}try{await this.settings.saveSpecialSeasons(!this.settings.loadSpecialSeasons());this.publishSeasonPresentation();}catch(error){this.localStatus='特别篇设置保存失败';}
  }
  private async loadSeasonExtras(item:Media,refresh:boolean=false):Promise<void>{
    if(item.kind!=='show'||!this.pageVisible||this.selectedMedia?.id!==item.id){return;}
    const revision=this.detailRevision,scope=this.seasonScope(item),client=this.clientId,consumer=this.detailConsumer;
    await this.seasonExtras.load(item,client,scope,consumer,this.presentation,refresh,()=>this.activeCloud(),()=>this.partRatingScope(),
      ()=>this.cloudFresh&&!!this.currentProgressScope(),()=>this.pageVisible&&this.selectedMedia?.id===item.id&&revision===this.detailRevision&&scope===this.seasonScope(item)&&client===this.clientId,
      ()=>{this.publishSeasonPresentation();});
    await this.reloadPartRatingRows(item);
  }
  private presentationReaders: Map<string, ReadCancel>=new Map<string, ReadCancel>();
  private presentationReaderTasks: Map<string, PresentationTask>=new Map<string, PresentationTask>();
  private businessPresentationTasks?: Map<string,PresentationTask>;
  private memoryListener: ()=>void=()=>{ this.handleMemoryPressure(); };
  private memorySubscribed: boolean=false;
  private memoryPending: boolean=false;
  private memoryTimer: number=-1;
  private candidateIndex: ProgressCandidateIndex = new ProgressCandidateIndex();
  private candidateWake: number = -1;
  private candidateWakeAt: number = 0;
  private candidateFailureKey: string = '';
  private showRatingVersion: number = 0;
  private viewport: ViewportTasks = new ViewportTasks();
  private viewportRouteKey: string = '';
  private libraryMemo: RevisionMemo<PersonalLibraryRow[]> = new RevisionMemo<PersonalLibraryRow[]>();
  private progressTitleOrder=new ProgressTitleOrder();
  private progressAllTitleOrder=new ProgressTitleOrder();
  private progressMemo: RevisionMemo<ProgressRow[]> = this.showRows.memo;
  private progressAllMemo: RevisionMemo<ProgressRow[]> = this.showRows.allMemo;
  private movieMemo: RevisionMemo<PersonalLibraryRow[]> = this.movieRowsSource.memo;
  private movieAllMemo: RevisionMemo<PersonalLibraryRow[]> = this.movieRowsSource.allMemo;
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
  @State @Watch('onMovieViewChanged') movieProgressQuery: string = '';
  @State @Watch('onMovieViewChanged') movieProgressOptions: MovieProgressOptions = defaultMovieProgress();
  @State movieRandomSeed: number = Date.now();
  @State @Watch('onMovieViewChanged') movieProgressPage: number = 1;
  @State @Watch('onCollectionViewChanged') collectionQuery: string = '';
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
  private syncCoordinator: SyncCoordinator = syncService.coordinator;
  private seenScheduleWake: number = 0;
  private get recoveryPending(): boolean { return this.syncCoordinator.has('episodes'); }
  private set recoveryPending(value: boolean) { this.syncCoordinator.mark('episodes', value); }
  private get mediaRecoveryPending(): boolean { return this.syncCoordinator.has('media'); }
  private set mediaRecoveryPending(value: boolean) { this.syncCoordinator.mark('media', value); }
  private get titleQuickPending(): boolean { return this.syncCoordinator.has('titles'); }
  private set titleQuickPending(value: boolean) { this.syncCoordinator.mark('titles', value); }
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
  @State lastEpisodeUpload: number = 0;
  @State uploadStatus: string = '';
  @State episodeReady: boolean = false;
  @State episodeInitStatus: string = '';
  @State @Watch('onDetailViewChanged') localSeries?: LocalSeriesState = undefined;
  @State @Watch('onDetailViewChanged') fullSchedule?: FullEpisodeCatalog = undefined;
  @State @Watch('onDetailViewChanged') schedulePage: number = 1;
  @State @Watch('onDetailViewChanged') localSeason: number = -1;
  @State @Watch('onRecoveryGateChanged') localBusy: boolean = false;
  @State localStatus: string = '';
  @State @Watch('onPresentationChanged') progressMode: string = 'next';
  @State @Watch('onShowsChanged') nextShows: NextShow[] = [];
  @State nextStatus: string = '';
  @State @Watch('onShowViewChanged') progressPrefs: ProgressPreferences = defaultProgress();
  @State @Watch('onFlagsChanged') progressFlags: ProgressFlag[] = [];
  @State progressFlagScope: string = '';
  @State progressPrefsBusy: boolean = false;
  @State progressOptions: boolean = false;
  @State progressDaysInput: string = '30';
  @State progressOptionStatus: string = '';
  @State @Watch('onShowViewChanged') nextFilter: string = 'all';
  @State progressMenuId: string = '';
  @State @Watch('onCollectionViewChanged') collectionStatusFilter: string = 'all';
  @State @Watch('onShowViewChanged') nextQuery: string = '';
  @State @Watch('onShowViewChanged') nextPage: number = 1;
  @State @Watch('onCalendarViewChanged') showCalendarMode: string = 'future';
  @State @Watch('onCalendarViewChanged') calendarPremieres: boolean = false;
  @State @Watch('onCalendarViewChanged') calendarQuery: string = '';
  @State @Watch('onCalendarViewChanged') calendarProtect: boolean = true;
  @State @Watch('onPresentationChanged') calendarPage: number = 1;
  @State calendarBusy: boolean = false;
  @State calendarStatus: string = '';
  @State calendarSourceVersion: number = 0;
  @State calendarViewRevision: number = 0;
  @State calendarSummary: PageSummary = {key:'',total:0,page:1,pages:1};
  private calendarSourceScope: string = '';
  private calendarSources: CalendarSource[] = [];
  private calendarRepairTargets: Media[] = [];
  private calendarIndex: CalendarIndex = new CalendarIndex();
  private calendarMemo: RevisionMemo<CalendarEntry[]> = this.calendarRows.memo;
  private calendarHydrationKey: string = '';
  @State @Watch('onMoviesChanged') movieCalendarData?: PersonalMovieSnapshot = undefined;
  private movieRatingKey: string = '';
  private movieRatingRows: CollectionRating[] = [];
  private movieRatingRequest:CollectionRatingRequest=new CollectionRatingRequest();
  @State movieCollectionRatingStatus:string='';
  @State @Watch('onMovieCalendarViewChanged') movieCalendarMode: string = 'future';
  @State @Watch('onMovieCalendarViewChanged') movieCalendarQuery: string = '';
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
  private translationCache: Map<string, ChineseText> = new Map<string, ChineseText>();
  @State @Watch('onCollectionViewChanged') collectionFilter: string = 'mine';
  @State @Watch('onCollectionViewChanged') collectionPage: number = 1;
  @State collectionGrid: boolean = true;
  @State collectionBusy: boolean = false;
  @State collectionStatus: string = '';
  private collectionRevision: number = 0;
  private readonly collectionPageSize: number = 12;
  @State progress?: SeriesProgress = undefined;
  @State progressBusy: boolean = false;
  @State progressStatus: string = '';
  @State seasonNumber: number = -1;
  @State discoverMode: string = 'trending';
  @State discoverOptions: DiscoverOptions = defaultDiscover();
  @State discoverGenreDraft: string = '';
  @State discoverNetworkDraft: string = '';
  @State discoverTotal: number = 0;
  @State discoverShownPage: number = 1;
  private discoverRepo?: Promise<DiscoverRead>;
  private discoverFeed?: DiscoverFeed;
  private discoverFeedKey: string = '';
  private discoverMemo: RevisionMemo<DiscoverItem[]> = this.discoverRows.memo;
  @State @Watch('onDiscoverViewChanged') discoverItems: DiscoverItem[] = [];
  @State discoverPage: number = 1;
  @State discoverPages: number = 0;
  @State discoverBusy: boolean = false;
  @State discoverStatus: string = '';
  @State @Watch('onPresentationChanged') selectedMedia?: Media = undefined;
  @State detailUi:DetailSnapshot<MediaDetail>=emptyDetail<MediaDetail>();
  private detailOwner:DetailViewOwner<MediaDetail>=new DetailViewOwner<MediaDetail>();
  private detailFanart:CollectionFanartOwner=new CollectionFanartOwner();
  private publishDetail():void{const next=this.detailOwner.snapshot();if(next!==this.detailUi){this.detailUi=next;}}
  private resetDetailUi():void{this.detailFanart.clear();this.detailOwner.clear();this.publishDetail();}
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
  private get observationPending(): boolean { return this.syncCoordinator.has('observation'); }
  private set observationPending(value: boolean) { this.syncCoordinator.mark('observation', value); }
  private startupScheduled: boolean = false;
  private projectionMemo: RevisionMemo<LibraryProjection> = new RevisionMemo<LibraryProjection>();
  private showProjectionCache: ShowProjectionCache = new ShowProjectionCache();
  private libraryProjectionSession:LibraryProjectionSession=new LibraryProjectionSession();
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
  @State @Watch('onCollectionStateChanged') collectionState: CollectionState = emptyCollectionState();
  @State collectionScope: string = '';
  @State @Watch('onCollectionViewChanged') collectionOptions: CollectionOptions = defaultCollection();
  @State collectionOptionsOpen: boolean = false;
  @State collectionSearchOpen: boolean = false;
  private showCollectionView:CollectionViewOwner=new CollectionViewOwner();
  private movieCollectionView:CollectionViewOwner=new CollectionViewOwner();
  private collectionViewOwner():CollectionViewOwner{return this.mediaMode==='movie'?this.movieCollectionView:this.showCollectionView;}
  private captureCollectionView():void{this.collectionViewOwner().update(this.collectionFilter,this.collectionQuery,this.collectionStatusFilter,this.collectionGrid,this.collectionSearchOpen);}
  private restoreCollectionView():void{
    const view=this.collectionViewOwner().snapshot();
    this.collectionOptionsOpen=false;this.collectionFilter=view.section;this.collectionQuery=view.query;
    this.collectionStatusFilter=view.status;this.collectionGrid=view.grid;this.collectionSearchOpen=view.searchOpen;
    this.collectionOptionKey='';this.reloadCollectionOptions();
  }
  private clearCollectionViews():void{
    this.showCollectionView.clear();this.movieCollectionView.clear();this.restoreCollectionView();
  }
  @State collectionGenreDraft: string = '';
  @State collectionNetworkDraft: string = '';
  @State collectionEditBusy: boolean = false;
  @State collectionRuleStatus: string = '';
  private collectionOptionKey: string = '';
  private collectionRandomKeys: Map<string, number> = new Map<string, number>();
  private collectionItemsMemo():RevisionMemo<PersonalLibraryRow[]>{return this.collectionRowsSource().memo;}
  private recentCollectionMemo():RevisionMemo<PersonalLibraryRow[]>{return this.collectionRowsSource().allMemo;}
  @State @Watch('onCollectionRatingsChanged') collectionRatings: CollectionRating[] = [];
  private collectionRatingKey: string = '';
  private showRatingRequest:CollectionRatingRequest=new CollectionRatingRequest();
  @State collectionRecentAmount:number=4;
  @State collectionRecentSaving:boolean=false;
  @State collectionRatingStatus: string = '';
  @State @Watch('onRecoveryGateChanged') cloudBusy: boolean = false;
  @State cloudStatus: string = '';
  @State advancedSync: boolean = false;
  @State libraryNotice: string = '';
  private settings?: ClientSettings;
  @State watchOptions:WatchOptions={enabled:false,region:'us'};
  @State watchCredentialVersion:number=0;
  @StorageLink('traktAuthStatus') authStatus: string = '尚未登录 Trakt';
  @StorageLink('traktAuthBusy') @Watch('onRecoveryGateChanged') authBusy: boolean = false;
  @StorageLink('traktSignedIn') @Watch('onObservationAuthChanged') signedIn: boolean = false;
  @State items: Media[] = [];
  @State @Watch('onSearchViewChanged') results: Media[] = [];
  @State ready: boolean = false;
  @State @Watch('onRecoveryGateChanged') saving: boolean = false;
  @State searching: boolean = false;
  @State searchOptions: SearchOptions = defaultSearch();
  @State searchRecents: string[] = [];
  @State searchSubmitted: boolean = false;
  private searchRepo?: Promise<SearchRead>;
  private searchGeneration: SearchGeneration = new SearchGeneration();
  private searchAccount: string = '';
  private searchRoute: boolean = false;
  private searchLanguage: string = '';
  private searchController:SearchController=new SearchController();
  @State searchSnapshot:SearchSnapshot=this.searchController.snapshot();
  private publishSearch():void{const next=this.searchController.snapshot();if(next!==this.searchSnapshot){this.searchSnapshot=next;}}
  private resetSearchRemote():void{this.searchController.resetRemote();this.publishSearch();}
  private chooseSearchSource(offline:boolean):void{this.searchController.chooseOffline(offline);this.publishSearch();this.refreshSearchLocal();}
  private searchLocalRunning: boolean = false;

  private movieTitleOrder=new StableDisplayOrder<MovieProgressSource>((x:MovieProgressSource)=>x.row);
  private movieAllTitleOrder=new StableDisplayOrder<MovieProgressSource>((x:MovieProgressSource)=>x.row);
  private showCollectionTitleOrder=new StableDisplayOrder<CollectionCandidate>((x:CollectionCandidate)=>x.row);
  private movieCollectionTitleOrder=new StableDisplayOrder<CollectionCandidate>((x:CollectionCandidate)=>x.row);
  private collectionTitleOrder():StableDisplayOrder<CollectionCandidate>{return this.mediaMode==='movie'?this.movieCollectionTitleOrder:this.showCollectionTitleOrder;}
  private releaseCollectionOwner(kind:string):void{
    const owner=kind==='movie'?this.movieCollectionRowsSource:this.showCollectionRowsSource;
    owner.memo.clear();owner.allMemo.clear();owner.replace([],[],[]);
    if(kind==='movie'){this.movieCollectionTitleOrder.clear();}else{this.showCollectionTitleOrder.clear();}
  }
  private clearCollectionOwners():void{this.releaseCollectionOwner('show');this.releaseCollectionOwner('movie');this.clearCollectionHeader();}
  private clearCollectionHeader():void{
    this.showCollectionRecovery.clear();this.movieCollectionRecovery.clear();
    this.collectionUi=emptyCollectionUi();this.collectionRevealed=[];this.clearCollectionFanart();
  }
  private publishCollectionHeader():void{
    const key=JSON.stringify([this.currentProgressScope(),this.mediaMode,this.collectionDependencies.source(this.mediaMode),this.collectionDependencies.business(this.mediaMode),this.collectionRecentAmount,this.collectionScope]);
    const owner=this.collectionRecovery();
    if(owner.headerCurrent(key)){return;}
    const rows=this.personalLibrary();
    const recent=this.recentCollectionRows();
    const other=collectionRows(rows,this.mediaMode,'other').length>0;
    owner.publishHeader(key);
    this.publishCollectionUi(recent,other,this.collectionUi.error,this.collectionUi.retrying);
  }
  private reportCollectionFailure(key:string,stage:string,error?:Error):void{
    const detail=error?.message??'';
    const message='收藏加载失败（'+stage+'）'+(detail?'：'+detail:'')+'；观看记录未修改。';
    this.collectionRecovery().fail(key,message);
    this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,message,this.collectionUi.retrying);
  }
  private async retryCollectionDisplay():Promise<void>{
    if(this.collectionUi.retrying||this.tab!=='library'){return;}
    const owner=this.collectionRecovery(),scope=this.collectionRecoveryScope();
    owner.activate(scope);
    const token=owner.beginRetry(scope);if(!token){return;}
    this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,this.collectionUi.error,true);
    try{
      await Promise.resolve();
      if(this.tab!=='library'||!this.pageVisible||this.collectionRecovery()!==owner||
        this.collectionRecoveryScope()!==scope||!owner.current(scope,token)){return;}
      this.collectionStage='重试缓存清理';
      this.collectionItemsMemo().clear();this.collectionTitleOrder().clear();this.recentCollectionMemo().clear();
      if(!owner.requestFull(scope,token)){return;}
      this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,'',this.collectionUi.retrying);
      this.requestPresentation();
    }catch(error){
      if(owner.current(scope,token)&&this.collectionRecovery()===owner&&this.collectionRecoveryScope()===scope){
        this.reportCollectionFailure(this.collectionSortKey(),this.collectionStage,error as Error);
      }
    }finally{if(owner.finishRetry(scope,token)&&this.collectionRecovery()===owner&&this.collectionRecoveryScope()===scope){this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,this.collectionUi.error,false);}}
  }
  private searchHistoryGeneration: SearchGeneration = new SearchGeneration();
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
    if (!this.memorySubscribed) { memoryEvents.subscribe(this.memoryListener); this.memorySubscribed=true; }
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
      this.collectionRecentAmount=this.settings.loadCollectionRecentAmount();
      this.restoreDiscoverOptions();
      this.presentationLanguage = this.settings.loadLanguage();
      this.watchOptions=this.settings.loadWatchOptions();
      this.progressPrefs = this.settings.loadProgress();
      this.progressWatchMode=this.settings.loadProgressWatchMode();this.progressEpisodeHidden=this.settings.loadProgressEpisodeHidden();
      this.progressRatingHidden=this.settings.loadProgressRatingHidden();this.progressTapReveal=this.settings.loadProgressTapReveal();
      const period=this.settings.loadHistoryPeriod();this.historyUi=initialHistory(validHistoryPeriod(period)?period:'all');
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
    this.searchRepo = openSearch(context);
    this.updateCacheLifecycle();
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.updateCacheLifecycle();
    this.updateSearchContext();
    this.resumeDetail();
    if (this.tab === 'discover' && !this.selectedMedia) { this.loadDiscover(this.discoverPage); }
    this.requestPresentation();
    this.startNetworkListener();
    if (this.backupBusy) { return; }
    this.requestMediaRecovery();
    const initialized = this.startupScheduled;
    this.requestObservation(true);
    const wake = lastScheduleWake(this.context().filesDir);
    if (wake > this.seenScheduleWake && this.ready && this.episodeReady && this.signedIn) {
      this.seenScheduleWake = wake;
      this.requestSyncNow();
    }
    this.scheduleInitialRead();
    if (initialized && !this.signedIn) { this.requestProjection(); }
    if (this.autoActive()) { this.requestRecovery(); }
    else if (this.clientId && !this.setupBusy && !this.cloudBusy && !this.syncBusy) {
      traktAuth.restore(this.clientId);
    }
  }

  onPageHide(): void {
    this.watchSelection.clear();
    this.pageVisible = false;
    this.pauseDetail();
    this.updateCacheLifecycle();
    this.cancelCandidateWake();
    this.updateSearchContext();
    this.cancelDiscoverRead();
    this.discoverBusy = false;
    this.sortJobs.clear();
    this.invalidateLazyWork();
    this.viewport.clear();
    this.cancelCatalogRepair();
    this.presentationWorkVersion++;
    this.presentationEpoch++;
    // Retain pending wakeups; existing foreground write gates stay intact.
    this.projectionPending = false;
  }

  aboutToDisappear(): void {
    this.watchSelection.clear();
    if (this.memorySubscribed) { memoryEvents.unsubscribe(this.memoryListener); this.memorySubscribed=false; }
    if (this.memoryTimer>=0) { clearTimeout(this.memoryTimer); this.memoryTimer=-1; this.memoryPending=false; }
    this.pageVisible = false;
    this.pauseDetail();
    this.updateCacheLifecycle();
    this.cancelCandidateWake();
    this.updateSearchContext();
    this.cancelDiscoverRead();
    this.discoverBusy = false;
    this.sortJobs.clear();
    this.invalidateLazyWork();
    this.viewport.clear();
    this.cancelCatalogRepair();
    this.presentationWorkVersion++;
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
          this.presentationAttempts.retry(); this.presentationQueues.clear();
          this.requestPresentation();
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
    this.syncCoordinator.reset();
    this.lastEpisodeUpload = 0;
    this.clearCollectionViews();
    this.clearProgressCandidates();
    this.resetSearchAccount();
    this.viewport.clear();
    this.clearLocalCalendar(true);
    this.movieCalendarRows.replace([],[],[]);
    this.collectionScope = '';
    this.showRatingRequest.reset();this.collectionRatingStatus='';
    this.collectionRatingKey = '';
    this.collectionRatings = [];
    this.collectionState = emptyCollectionState();
    this.clearCollectionOwners();
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
    this.showProjectionCache.clear(); this.libraryProjectionSession.clear();
    this.episodeStore?.releaseProjectionReadCache();
    this.libraryRevision++;
    this.collectionDependencies.reset();
    this.displayRevisions.reset();
    this.collectionIndexMemos.clear();
    this.movieMetadataMemo.clear();
    this.libraryIndex.clear();this.personalLibraryIndex.clear();this.pendingMediaDelta=undefined;
    this.libraryMemo.clear();
    this.sortJobs.clear();
    this.invalidateLazyWork();
    this.presentationEpoch++;
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
      this.clearLocalCalendar(); this.libraryEvidence = [];
      this.localSeries = undefined;
      this.effectiveEditable = false;
      this.observationPending = false;
      this.projectionPending = false;
      return;
    }
    this.cloudLocalAllowed = false;
    this.clearLocalCalendar(); this.libraryEvidence = [];
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

  private requestSyncNow(): void {
    if (!this.pageVisible || !this.signedIn || !this.clientId || this.backupBusy ||
        !this.ready || !this.episodeReady || this.authBusy || this.setupBusy) { return; }
    this.observationPending = true;
    if (this.syncBound && this.syncAccount &&
        traktAuth.isCurrent(this.clientId, this.syncAccount.generation)) {
      if (this.autoActive()) { this.recoveryPending = true; }
      if (this.titleQuickActive()) { this.titleQuickPending = true; }
      this.mediaRecoveryPending = true;
    }
    this.onRecoveryGateChanged();
  }

  private requestProjection(): void {
    if (!this.pageVisible) { return; }
    this.projectionPending = true;
    this.onRecoveryGateChanged();
  }

  private onRecoveryGateChanged(): void {
    if (syncService.busy() || this.backupBusy || !this.pageVisible || this.syncBusy || this.localBusy || this.cloudBusy || this.saving ||
        this.authBusy || this.setupBusy) { return; }
    if (this.detailResumePending && this.selectedMedia) { this.resumeDetail(); if (this.localBusy) { return; } }
    const lane = this.syncCoordinator.next(this.autoActive() && this.episodeReady,
      !this.saving, this.ready && this.episodeReady && this.signedIn,
      this.ready && this.episodeReady && this.titleQuickActive());
    if (lane === 'episodes') {
      this.recoveryPending = false;
      this.resumeQueued();
      return;
    }
    if (lane === 'media') {
      this.mediaRecoveryPending = false;
      this.recoverMediaPending();
      return;
    }
    if (!this.ready || !this.episodeReady || this.saving) { return; }
    if (lane === 'observation') {
      this.observationPending = false;
      this.projectionPending = false;
      this.loadCloud(false);
      return;
    }
    if (lane === 'titles') {
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
    const ticket = syncService.acquire(JSON.stringify([clientId,consent.uuid,'titles']));
    if (!ticket) { return; }
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
    } finally { syncService.release(ticket); this.syncBusy = false; }
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
    const ticket = syncService.acquire(JSON.stringify([clientId,account.uuid,'media']));
    if (!ticket) { return; }
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
      syncService.release(ticket);
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
      this.publishMediaRecords(migrateLegacy(legacy));
      const store = await MediaStore.open(context, legacy);
      const records = await store.load();
      this.mediaStore = store;
      this.invalidateMovieCalendar();
      this.publishMediaRecords(records);
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
    const scope=this.currentSearchAccount();
    const token=this.detailSession.token();
    const current=(): boolean=>this.pageVisible && revision===this.detailRevision && this.detailSession.current(token,scope,item.id) && this.currentSearchAccount()===scope;
    this.localBusy = true;
    this.localStatus = '正在读取分集…';
    try {
      const readRevision=store.assertProjectionReadable();
      let full = this.detailSession.read(scope,item.id,readRevision);
      if (!full) { full=await store.fullCatalog(item.id); }
      if (!current() || !store.projectionReadable(readRevision)) { return; }
      if (full) { this.detailSession.remember(token,scope,item.id,readRevision,full); }
      this.fullSchedule = full;
      this.schedulePage = 1;
      if ((refresh || !full) && clientId) {
        full = await fetchFullEpisodeCatalog(item, clientId,this.detailConsumer);
        if (!current() || this.clientId !== clientId) { return; }
        if (refresh && this.canEditLibrary()) {
          this.invalidateSync();
          await store.saveFullCatalog(full);
        } else {
          await store.saveObservedSchedule(full);
        }
        if (!current() || this.clientId !== clientId) { return; }
        this.detailSession.remember(token,scope,item.id,store.readModelRevision(),full);
        this.fullSchedule = full;
        this.invalidateNextShows();
        this.requestProjection();
      }
      await this.refreshEffectiveDetail();
      if(current()){this.loadSeasonExtras(item,refresh);}
    } catch (error) {
      if (current()) {
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
    if (!store || !item || item.kind !== 'show' || !this.pageVisible) { return; }
    const revision = this.detailRevision;
    const scope=this.currentSearchAccount();
    if (!this.detailSession.current(this.detailSession.token(),scope,item.id)) { this.detailSession.begin(scope,item.id); this.detailConsumer=this.detailSession.consumer(); }
    const token=this.detailSession.token();
    const snapshot = this.activeCloud();
    const uuid = this.cloudUuid;
    if (this.signedIn && !snapshot) {
      this.localSeries = undefined;
      this.clearSeasonDetail();
      this.effectiveEditable = false;
      this.localStatus = '正在等待账户验证；暂不读取本机私有记录。';
      return;
    }
    this.effectiveEditable=false;
    const readRevision=store.assertProjectionReadable();
    const current=(): boolean=>this.pageVisible && revision===this.detailRevision && this.detailSession.current(token,scope,item.id) && scope===this.currentSearchAccount() && snapshot===this.activeCloud() && uuid===this.cloudUuid && store.projectionReadable(readRevision);
    let full=this.detailSession.read(scope,item.id,readRevision);
    if (!full) { full=await store.fullCatalog(item.id); }
    if (!current()) { return; }
    if (full) { this.detailSession.remember(token,scope,item.id,readRevision,full); }
    const result=await projectDetail(store,full,item.id,snapshot,uuid,true);
    const verify=result.localAllowed ? await store.needsCatalogVerification(item.id) : false;
    if (!current()) { return; }
    this.fullSchedule=full;
    this.localSeries=result.state;
    this.localCatalogNeedsVerification=verify;
    this.effectiveEditable = result.complete && result.localAllowed && this.canEditLibrary();
    if (!this.episodePage && result.state && result.state.seasons.length > 0 &&
        !result.state.seasons.some((season: LocalSeasonState) => season.number === this.localSeason)) {
      this.localSeason = result.state.seasons[0].number;
    }
    const verified:VerifiedEpisode[]=[];
    for(const season of result.state?.seasons??[]){for(const row of season.episodes){verified.push({id:row.episode.id,season:row.episode.season,number:row.episode.number,title:row.episode.title,watched:row.watched});}}
    if(this.seasonDetailOwner.reconcile(JSON.stringify([scope,item.id]),full,verified)){this.seasonDetail=this.seasonDetailOwner.snapshot();}
    else{this.seasonDetail=this.seasonDetailOwner.update(JSON.stringify([scope,item.id]),full,verified);}
    this.updateEpisodePageRows();
    this.localStatus = !result.complete ? '分集资料未齐，暂不允许修改；请刷新个人库或目录。' :
      !this.effectiveEditable ? '当前账户仅供浏览；本机库需明确绑定，不能跨账户修改。' :
      result.state ? '有效观看状态 · 本机操作仍使用原有同步保护' : '请联网获取分集目录';
  }

  private async markLocal(item: Media, ids: number[], watched: boolean,watchedAt:number=Date.now()): Promise<void> {
    if(!validWatchTime(watchedAt,Date.now())||this.selectedMedia?.id!==item.id){return;}
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
      const editSnapshot=this.activeCloud();
      const editUuid=this.cloudUuid;
      const editRevision=store.readModelRevision();
      const evidence=await projectDetail(store,await store.fullCatalog(item.id),item.id,editSnapshot,editUuid);
      if (revision !== this.detailRevision || !this.canEditLibrary() || editSnapshot!==this.activeCloud() || editUuid!==this.cloudUuid || !store.projectionReadable(editRevision) || !evidence.complete || !evidence.localAllowed) { return; }
      await store.mark(item.id, ids, watched, watched && auto && this.autoActive() ? auto.uuid : '',watchedAt);
      if (watched && (!previous || !hasTrackingEvidence(previous)) && previous?.localRecord?.followState !== 'no') {
        await this.recordFirstEpisodeDate(dateScope,item.id);
      }
      this.invalidateNextShows(item.id);
      saved = true;
      this.requestProjection();
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
    DetailSeasons({rows:this.displaySeasonRows(),item:item,cacheDir:this.context().cacheDir,presentation:this.seasonExtras.presentation,metadataRevision:this.seasonDetail.revision,special:this.settings?.loadSpecialSeasons()??false,publicStatus:this.seasonExtras.publicStatus,ratingStatus:this.seasonExtras.ratingStatus,ratingScope:this.partRatingScope(),hideRating:this.progressRatingHidden,tapReveal:this.progressTapReveal,onSpecial:()=>{this.toggleSpecialSeasons();},onMetadata:()=>{this.loadSeasonExtras(item,true);},ready:this.episodeReady,busy:this.localBusy,editable:this.effectiveEditable,
      verify:this.localCatalogNeedsVerification,refreshable:!this.cloudBusy&&!this.syncBusy&&!!this.clientId,
      status:this.episodeReady?this.localStatus:this.episodeInitStatus,completed:this.localSeries?.completed??0,count:this.localSeries?.catalog.episodes.length??0,next:this.localSeries?.next??'',
      onRefresh:()=>{this.loadLocalEpisodes(item,true);},onOpen:(season:number)=>{this.openSeasonPage(season);},onRate:(id:number,label:string)=>{this.openRating('season',id,label);}})
  }

  private currentSeason(): LocalSeasonState | undefined {
    return this.localSeries?.seasons.find((season: LocalSeasonState)=>season.number===this.localSeason);
  }
  private updateEpisodePageRows(): void {
    if (!this.episodePage || !this.selectedMedia) { this.episodeRowOwner.clear(); this.seasonDetail=this.seasonDetailOwner.count(0); return; }
    const item=this.selectedMedia;
    const entries:DetailEpisodeEntry[]=this.localSeason===0?(this.seasonExtras.presentation.season(0)?.episodes??[]).map((e):DetailEpisodeEntry=>({id:e.id,season:0,number:e.number,title:e.title,watched:false,eligible:false,firstAired:e.firstAired})):this.seasonDetailOwner.season(this.localSeason);
    const rows=entries.map((entry:DetailEpisodeEntry):EpisodeDisplayRow=>{
      const meta=this.seasonExtras.presentation.episode(entry.id);
      const exact=meta&&meta.season===entry.season&&meta.number===entry.number?meta:undefined;
      return {id:entry.id,number:entry.number,watched:entry.watched,originalTitle:entry.title,eligible:entry.eligible,firstAired:entry.firstAired,
        title:this.displayEpisode(item,entry.season,entry.id,entry.title),rating:exact?.rating,myRating:this.seasonExtras.presentation.episodeRating(entry.id,this.partRatingScope()),runtime:exact?.runtime,overview:exact?.overview,images:exact?.images};
    });
    this.episodeRowOwner.replace(this.episodeRowsScope(),rows);this.seasonDetail=this.seasonDetailOwner.count(rows.length);
  }
  private episodeRowsScope(): string { return JSON.stringify([this.currentSearchAccount(),this.selectedMedia?.id??'',this.localSeason,this.presentationLanguage]); }
  private openSeasonPage(season: number): void {
    if (!this.selectedMedia || !this.displaySeasonRows().some((row:SeasonSummary)=>row.number===season)) { return; }
    try { this.detailScrollOffset=this.detailScroller.currentOffset().yOffset; } catch (error) { this.detailScrollOffset=0; }
    this.localSeason=season;
    this.episodePage=true;
    this.updateEpisodePageRows();
    this.requestPresentation();
  }
  private closeSeasonPage(): void {
    this.episodePage=false; this.episodeRowOwner.clear(); this.seasonDetail=this.seasonDetailOwner.count(0);
    const revision=this.detailRevision;
    const offset=this.detailScrollOffset;
    this.getUIContext().postFrameCallback(new RestoreScrollFrame(()=>{
      if (revision===this.detailRevision && this.selectedMedia && !this.episodePage) {
        try { this.detailScroller.scrollTo({xOffset:0,yOffset:offset,animation:false}); } catch (error) {}
      }
    }));
    this.requestPresentation();
  }
  private markSeasonPage(item: Media,watched: boolean,id: number=0): void {
    if (!this.episodePage || this.selectedMedia?.id!==item.id || !this.pageVisible) { return; }
    const ids=(this.currentSeason()?.episodes??[]).filter((entry: LocalEpisodeState)=>entry.watched!==watched && (!id || entry.episode.id===id))
      .map((entry: LocalEpisodeState)=>entry.episode.id);
    if(!watched){this.markLocal(item,ids,false);return;}
    const season=this.localSeason,scope=this.episodeRowsScope(),revision=this.detailRevision;
    const release=id?this.seasonDetailOwner.episode(id)?.firstAired??'':'';
    this.chooseWatchTime(release,(at:number)=>{if(this.episodePage&&season===this.localSeason&&scope===this.episodeRowsScope()&&revision===this.detailRevision){this.markLocal(item,ids,true,at);}});
  }
  private quickFillTo(item:Media,id:number):void{
    if(!this.episodePage||this.selectedMedia?.id!==item.id||!this.effectiveEditable){return;}
    const delta=this.seasonDetailOwner.delta(id);if(!delta.valid){return;}
    if(delta.remove.length){this.localStatus='存在后续已看记录；不会自动撤销。请单独核对观看历史。';return;}
    if(!delta.add.length){this.localStatus='截至本集的已播普通集已看完。';return;}
    const revision=this.detailRevision,scope=this.episodeRowsScope(),signature=JSON.stringify(delta.add);
    try{this.getUIContext().showActionSheet({title:'补齐观看进度',message:'确认实际看过这 '+delta.add.length+' 集？保留已有历史，不自动删除。',alignment:DialogAlignment.Bottom,autoCancel:true,sheets:[
      {title:'确认并选择观看时间',action:()=>{this.chooseWatchTime('',(at:number)=>{
        if(revision!==this.detailRevision||scope!==this.episodeRowsScope()||!this.episodePage){return;}
        const fresh=this.seasonDetailOwner.delta(id);if(!fresh.valid||fresh.remove.length||JSON.stringify(fresh.add)!==signature){this.localStatus='进度已变化，请重新选择。';return;}
        this.markLocal(item,fresh.add,true,at);
      });}}
    ]});}catch(error){this.localStatus='无法打开进度确认，未修改记录。';}
  }
  @Builder
  episodeDetailPage(item: Media) {
    DetailEpisodeList({source:this.episodeRowOwner.source,count:this.seasonDetail.count,title:this.displayTitle(item),season:this.localSeason,item:item,cacheDir:this.context().cacheDir,hideRating:this.progressRatingHidden,hideTitle:this.progressEpisodeHidden,tapReveal:this.progressTapReveal,
      eligibleCount:this.currentSeason()?.episodes.length??0,
      completed:this.currentSeason()?.completed??0,
      editable:this.localSeason!==0 && this.effectiveEditable && !this.localCatalogNeedsVerification && !this.cloudBusy && !this.syncBusy,
      busy:this.localBusy,status:this.localStatus,onBack:()=>{this.closeSeasonPage();},
      onToggle:(id: number,watched: boolean)=>{this.markSeasonPage(item,watched,id);},
      onMarkSeason:(watched: boolean)=>{this.markSeasonPage(item,watched);},onQuickProgress:(id:number)=>{this.quickFillTo(item,id);},onRate:(id:number,label:string)=>{this.openRating('episode',id,label);},onComments:(id:number,episode:number)=>{this.openComments({kind:'episode',id:id,showId:Number(item.id.substring(5)),season:this.localSeason,episode:episode,label:'第 '+this.localSeason+' 季 · 第 '+episode+' 集'});}
    })
  }
  private async initializePresentation(context: common.UIAbilityContext): Promise<void> {
    try {
      this.presentation = await PresentationRepository.open(context);
      this.publishPresentation();
      this.requestPresentation();
    } catch (error) { this.presentationStatus = '影视资料缓存暂不可用，仍可管理观看记录。'; }
  }

  private publishMediaRecords(records: MediaRecord[],submitted?:MediaRecord[],expected?:string,ids:string[]=[]): boolean {
    const prior=this.pendingMediaDelta,now=Date.now(),utc=new Date(now).toISOString().substring(0,10);
    const movieQueryScope=prior?.movieQueryScope??this.movieSortKey(this.movieProgressQuery,utc,false);
    const movieAllScope=prior?.movieAllScope??this.movieSortKey('',utc,false);
    const collectionScope=prior?.collectionScope??this.collectionSortKey(false);
    const changed=submitted&&expected!==undefined?this.mediaInput.replaceVerifiedEdit(expected,submitted,records,ids):this.mediaInput.replace(records);
    if (!changed) { return false; }
    const changes=prior||this.signedIn&&!this.activeCloud()?undefined:this.personalLibraryIndex.updateRecords(this.mediaInput.recordsById(),this.mediaInput.libraryChangedIds(),
      this.mediaInput.canApplyIncremental()&&!this.mediaInput.libraryOrderChanged(),this.activeCloud(),this.libraryEvidence,this.cloudLocalAllowed);
    if(changes){
      for(const change of changes){if(change.row){this.libraryIndex.set(change.id,change.row);}else{this.libraryIndex.delete(change.id);}}
    }else{this.personalLibraryIndex.clear();this.libraryIndex.clear();}
    this.pendingMediaDelta={changes:changes,movieQueryScope:movieQueryScope,movieAllScope:movieAllScope,
      collectionScope:collectionScope,now:now,utc:utc,version:this.mediaInput.version(),account:this.currentProgressScope(),
      cloud:this.activeCloud(),evidence:this.libraryEvidence,localAllowed:this.cloudLocalAllowed};
    this.mediaRecords=records;
    return true;
  }
  private onLibraryInputChanged(): void {
    this.libraryRevision++;this.libraryMemo.clear();
    const pending=this.pendingMediaDelta;this.pendingMediaDelta=undefined;
    let handled=false;
    const scoped=!!pending?.changes&&pending.version===this.mediaInput.version()&&pending.account===this.currentProgressScope()&&
      pending.cloud===this.activeCloud()&&pending.evidence===this.libraryEvidence&&pending.localAllowed===this.cloudLocalAllowed&&
      (!this.signedIn||!!this.activeCloud());
    this.collectionDependencies.observe(scoped&&pending?.changes?pending.changes.map((change:PersonalLibraryChange)=>change.id):[],!scoped);
    this.pageWorks.observe(JSON.stringify([this.currentProgressScope(),this.libraryRevision]),
      scoped&&pending?.changes?pending.changes.map((change:PersonalLibraryChange)=>change.id):[],!scoped);
    if(scoped&&pending?.changes){
      this.updateSearchCandidatesForLibraryChanges(pending.changes);
      handled=this.applyMediaRecordDisplayDelta(pending);
      this.mediaInput.acknowledgeLibrary(pending.version);
    }else if(pending){this.personalLibraryIndex.clear();this.libraryIndex.clear();}
    if(!handled){this.onPresentationChanged();}
    this.refreshSearchLocal();
  }
  private updateSearchCandidatesForLibraryChanges(changes:PersonalLibraryChange[]):void{
    if(!this.searchController.source){return;}
    const scope=this.currentSearchAccount();
    const priorKey=JSON.stringify([scope,this.libraryRevision-1,this.cloudLocalAllowed,this.activeCloud()?.generation??-1,
      this.activeCloud()?.activity??'',this.presentationLanguage]);
    if(this.searchController.key!==priorKey){return;}
    for(const change of changes){
      if(this.searchController.stored.has(change.id)){continue;}
      if(change.row&&isTraktMedia(change.row.media)){
        const old=this.searchController.titles.get(change.id);
        this.searchController.titles.upsert({media:publicSearchRecord(change.row.media).media,votes:old?.votes??0,
          localized:this.presentationLanguage==='zh'?this.titleIndex.get(change.id)?.text.title??'':''});
      }else{this.searchController.titles.remove(change.id);}
    }
    this.searchController.key=JSON.stringify([scope,this.libraryRevision,this.cloudLocalAllowed,this.activeCloud()?.generation??-1,
      this.activeCloud()?.activity??'',this.presentationLanguage]);
  }
  private applyMediaRecordDisplayDelta(pending:PendingMediaDelta):boolean{
    const changes=pending.changes??[],metadata=this.movieCalendarCurrent()?this.movieMetadataIndex():new Map<string,PersonalMovie>();
    const movieChanges:StableOrderChange<MovieProgressSource>[]=[];
    for(const change of changes){
      const row=change.row;let item:MovieProgressSource|undefined;
      if(row&&row.media.kind==='movie'&&!this.isHidden(row.media)){
        const movie=metadata.get(change.id);
        if(movie&&!movie.localOnly&&!movie.dateUncertain){
          item={row:row,metadata:{id:row.media.id,released:movie.released,year:movie.media.year,runtime:movie.runtime,
            rating:movie.rating,addedAt:movie.addedAt,userRating:movie.userRating},
            translation:this.presentationLanguage==='zh'?this.titleIndex.get(row.media.id)?.text.title??'':''};
        }
      }
      movieChanges.push({id:change.id,item:item,ordinal:change.ordinal});
    }
    const flags=this.progressFlagScope===this.currentProgressScope()?this.progressFlags:[];
    const pins=new Set<string>(flags.filter((flag:ProgressFlag)=>flag.pinned).map((flag:ProgressFlag)=>flag.id));
    let movieHandled=false,collectionHandled=false,needsFull=false;
    if(this.movieCalendarCurrent()){
      const movieCases:[StableDisplayOrder<MovieProgressSource>,string,string,string,RevisionMemo<PersonalLibraryRow[]>][]=[
        [this.movieTitleOrder,pending.movieQueryScope,this.movieSortKey(this.movieProgressQuery,pending.utc,false),
          this.movieSortKey(this.movieProgressQuery,pending.utc,false,false),this.movieMemo],
        [this.movieAllTitleOrder,pending.movieAllScope,this.movieSortKey('',pending.utc,false),
          this.movieSortKey('',pending.utc,false,false),this.movieAllMemo]
      ];
      for(let i=0;i<movieCases.length;i++){
        const order=movieCases[i][0];
        const before=movieCases[i][1];
        const after=movieCases[i][2];
        const basis=movieCases[i][3];
        const memo=movieCases[i][4];
        const query=i===0?this.movieProgressQuery:'';
        if(order.hasDirty()){order.clear();needsFull=true;continue;}
        const result=order.applyChanges(before,after,basis,pending.now,order.validUntil(),movieChanges,
          (value:MovieProgressSource)=>movieSortEligible(value,pending.utc,query),
          (a:MovieProgressSource,b:MovieProgressSource)=>compareMovieSources(a,b,this.movieProgressOptions,pins,this.movieRandomSeed));
        if(!result){continue;}
        memo.put(this.movieSortKey(query,pending.utc),result.rows,pending.now,order.validUntil());
        if(query===this.movieProgressQuery&&this.pageVisible&&this.tab==='progress'&&this.progressMode==='next'&&this.mediaMode==='movie'&&!this.selectedMedia){
          if(result.structural){needsFull=true;}
          else{
            let patched=true;
            for(const patch of result.patches){if(patch.kind==='update'&&patch.row&&!this.movieRowsSource.patchRow(patch.id,patch.row,this.movieRowKey(patch.row))){patched=false;}}
            movieHandled=patched;if(!patched){needsFull=true;}
          }
        }
      }
    }
    if(this.collectionTitleOrder().hasDirty()||(this.collectionFilter==='queue'&&this.collectionOptions.upcoming!=='all')){
      // A changed release can introduce an earlier expiry; the complete
      // candidate path recomputes it. Pending translations also invalidate.
      this.collectionTitleOrder().clear();needsFull=true;
    }else if(this.collectionFilter==='mine'||this.collectionFilter==='queue'){
      const before=pending.collectionScope,after=this.collectionSortKey(false),basis=this.collectionSortKey(false,false);
      const collectionChanges:StableOrderChange<CollectionCandidate>[]=[];
      for(const change of changes){
        let candidate:CollectionCandidate|undefined;
        if(change.row){
          const members=collectionMembers([change.row],this.currentCollectionState(),this.mediaMode,this.collectionFilter,this.collectionStatusFilter);
          if(members.length){candidate=this.collectionCandidateForRow(members[0],this.collectionFilter);}
        }
        collectionChanges.push({id:change.id,item:candidate,ordinal:change.ordinal});
      }
      const options=this.collectionOptions;
      const result=this.collectionTitleOrder().applyChanges(before,after,basis,pending.now,this.collectionTitleOrder().validUntil(),collectionChanges,
        (value:CollectionCandidate)=>collectionSortEligible(value,options,this.collectionFilter,this.collectionQuery,pending.now),
        (a:CollectionCandidate,b:CollectionCandidate)=>compareCollectionCandidates(a,b,options,this.collectionFilter));
      if(result){
        this.collectionItemsMemo().put(this.collectionSortKey(),result.rows,pending.now,this.collectionTitleOrder().validUntil());
        if(this.pageVisible&&this.tab==='library'&&!this.selectedMedia){
          if(result.structural){needsFull=true;}
          else{
            let patched=true;
            for(const patch of result.patches){if(patch.kind==='update'&&patch.row&&!this.patchCollectionDisplayRow(patch.row)){patched=false;}}
            collectionHandled=patched;if(!patched){needsFull=true;}
          }
        }
      }
    }
    if(this.pageVisible&&this.tab==='progress'&&this.mediaMode==='movie'&&this.progressMode==='next'&&!this.selectedMedia){return movieHandled&&!needsFull;}
    if(this.pageVisible&&this.tab==='library'&&!this.selectedMedia&&(this.collectionFilter==='mine'||this.collectionFilter==='queue')){return collectionHandled&&!needsFull;}
    return false;
  }
  private patchCollectionDisplayRow(row:PersonalLibraryRow):boolean{
    const index=this.collectionRowsSource().indexOfId(row.media.id);if(index<0){return false;}
    const group=this.collectionRowsSource().getData(index);
    const rows=group.rows.map((item:PersonalLibraryRow)=>item.media.id===row.media.id?row:item);
    const next:CollectionGroup={key:group.key,label:group.label,rows:rows};
    return this.collectionRowsSource().patchRow(group.key,next,this.collectionGroupKey(next));
  }

  private onShowsChanged(): void {
    this.displayRevisions.showsChanged();this.collectionDependencies.sourceChanged('show');
    const slot=this.scrollSlot();
    if(!slot||slot==='show'||slot==='history'||slot==='calendar'||slot==='library'||slot==='discover'||slot==='search'){this.onPresentationChanged();}
  }
  private onMoviesChanged(): void {
    this.displayRevisions.moviesChanged();this.collectionDependencies.sourceChanged('movie');
    const slot=this.scrollSlot();
    if(!slot||slot==='movie'||slot==='movieCalendar'||slot==='library'||slot==='discover'||slot==='search'){this.onPresentationChanged();}
  }
  private onCollectionRatingsChanged(): void {
    this.showRatingVersion++;
    this.displayRevisions.collectionChanged();this.collectionDependencies.sourceChanged('show');
    const slot=this.scrollSlot();
    if(!slot||slot==='show'||slot==='library'){this.onPresentationChanged();}
  }
  private onCollectionStateChanged(): void {
    this.displayRevisions.collectionChanged();this.collectionDependencies.sourceChanged('');
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
    const priorTitles=this.titleSortRevision;
    const priorCollectionMeta=this.collectionMetadataKey();
    const priorShow=this.showTitleRevision,priorMovie=this.movieTitleRevision;
    const priorShowMeta=this.showMetaRevision,priorMovieMeta=this.movieMetaRevision;
    const priorEpisodes=this.episodeSearchRevision;
    const dirty=new Set<string>();
    const episodeDirty=new Set<number>();
    const sortDirty=new Set<string>();
    for (const row of changes.titles) {
      const prior = this.titleIndex.get(row.id);
      if ((prior?.text.title ?? '') !== row.text.title) {
        this.titleSortRevision++; sortDirty.add(row.id);
        if(this.presentationLanguage==='zh'){
          this.searchController.titles.patch(row.id,row.text.title);
          this.movieTitleOrder.dirty(row.id);this.movieAllTitleOrder.dirty(row.id);
          if(row.id.startsWith('movie:')){this.movieCollectionTitleOrder.dirty(row.id);}else{this.showCollectionTitleOrder.dirty(row.id);}
        }
        if (row.id.startsWith('movie:')) { this.movieTitleRevision++; } else { this.showTitleRevision++; }
      }
      if (JSON.stringify(prior?.collection ?? null) !== JSON.stringify(row.collection ?? null)) {
        this.collectionMetaRevision++;
        this.collectionMetadata.changed(row.id,prior?.collection,row.collection);
        if (row.id.startsWith('movie:')) { this.movieMetaRevision++; } else { this.showMetaRevision++; }
      }
      if ((prior?.text.title??'')!==row.text.title || (prior?.posterUri??'')!==row.posterUri) { dirty.add(row.id); }
      this.titleIndex.set(row.id,row);
    }
    for (const row of changes.seasons) {
      const seasonKey = row.showId + ':' + row.season;
      const previous = this.seasonKeys.get(seasonKey) ?? [];
      const keys: Set<string> = new Set<string>();
      for (const ep of row.episodes) {
        const key = seasonKey + ':' + ep.id;
        keys.add(key);
        if ((this.episodeNameIndex.get(key) ?? '') !== ep.text.title) {
          this.episodeSearchRevision++; sortDirty.add(row.showId);
          if (row.showId===this.selectedMedia?.id && row.season===this.localSeason) { episodeDirty.add(ep.id); }
        }
        this.episodeNameIndex.set(key,ep.text.title);
      }
      for (const key of previous) {
        if (!keys.has(key)) { this.episodeNameIndex.delete(key); this.episodeSearchRevision++; sortDirty.add(row.showId);
          if (row.showId===this.selectedMedia?.id && row.season===this.localSeason) { episodeDirty.add(Number(key.substring(key.lastIndexOf(':')+1))); }
        }
      }
      this.seasonKeys.set(seasonKey,Array.from(keys));
      dirty.add(row.showId);
    }
    this.progressTitleOrder.dirty(Array.from(sortDirty)); this.progressAllTitleOrder.dirty(Array.from(sortDirty));
    // This state is only observed by the detail and the small recent-title header.
    if (this.selectedMedia) {
      if (changes.titles.some((row: TitlePresentation)=>row.id===this.selectedMedia?.id) ||
          dirty.has(this.selectedMedia.id)) { this.presentationRevision=revision; }
      if (this.episodePage && episodeDirty.size) {
        const item=this.selectedMedia;
        for (const id of episodeDirty) {
          const title=this.presentationLanguage==='zh'?this.episodeNameIndex.get(item.id+':'+this.localSeason+':'+id)??'':'';
          this.episodeRowOwner.updateTitle(this.episodeRowsScope(),id,title);
        }
      }
      return;
    }
    const titleChanged=this.presentationLanguage==='zh' && (this.mediaMode==='show'?priorShow!==this.showTitleRevision:priorMovie!==this.movieTitleRevision);
    const metaChanged=this.mediaMode==='show'?priorShowMeta!==this.showMetaRevision:priorMovieMeta!==this.movieMetaRevision;
    const episodeChanged=this.presentationLanguage==='zh' && priorEpisodes!==this.episodeSearchRevision;
    if (this.tab==='search' && this.presentationLanguage==='zh' && priorTitles!==this.titleSortRevision) { this.refreshSearchLocal(); }
    if ((this.tab==='library' && titleChanged) || !this.scrollSlot()) { this.presentationRevision=revision; }
    const structural=(this.tab==='library' && ((titleChanged && this.businessTitlesNeeded()) || (priorCollectionMeta!==this.collectionMetadataKey()))) ||
      (this.tab==='progress' && this.progressMode==='next' && ((titleChanged && (this.mediaMode==='show' || this.businessTitlesNeeded())) || (episodeChanged && this.mediaMode==='show' && !!this.nextQuery.trim()))) ||
      (this.tab==='progress' && this.progressMode==='calendar' && (this.mediaMode==='show' ?
        metaChanged || (!!this.calendarQuery.trim() && (titleChanged || episodeChanged)) : titleChanged && !!this.movieCalendarQuery.trim()));
    if (structural || !this.refreshPresentationRows(Array.from(dirty))) { this.scheduleLazyRows(); }
  }

  private refreshPresentationRows(ids: string[]): boolean {
    if (!ids.length || !this.pageVisible) { return true; }
    switch (this.scrollSlot()) {
      case 'discover': return this.discoverRows.refreshDependencies(ids,(row: DiscoverItem[])=>this.discoverRowKey(row));
      case 'search': return this.searchRows.refreshDependencies(ids,(row: Media)=>this.searchRowKey(row));
      case 'show': return this.showRows.refreshDependencies(ids,(row: ProgressEntry)=>this.showRowKey(row));
      case 'movie': return this.movieRowsSource.refreshDependencies(ids,(row: PersonalLibraryRow)=>this.movieRowKey(row));
      case 'history': return this.historyRows.refreshDependencies(ids,(row:HistoryEntry)=>this.historyRowKey(row));
      case 'calendar': return this.calendarRows.refreshDependencies(ids,(row: CalendarEntry)=>this.calendarRowKey(row));
      case 'movieCalendar': return this.movieCalendarRows.refreshDependencies(ids,(row: MovieCalendarItem)=>this.movieCalendarKey(row));
      case 'library': return this.collectionRowsSource().refreshDependencies(ids,(row: CollectionGroup)=>this.collectionGroupKey(row));
      default: return true;
    }
  }

  private presentationReady(item: Media): boolean {
    return this.selectedMedia?.id===item.id || !this.scrollSlot() ? (this.presentationRevision>=0 && this.presentationPublished>=0) : this.presentationPublished>=0;
  }
  private displayTitle(item: Media): string {
    return this.presentationLanguage === 'zh' && this.presentationReady(item) ?
      this.titleIndex.get(item.id)?.text.title || item.title : item.title;
  }

  private displayLabel(item: Media): string {
    const title = this.displayTitle(item);
    const year = item.year > 0 ? ' (' + item.year + ')' : '';
    const kind = item.kind === 'movie' ? '电影' : item.kind === 'show' ? '剧集' : '手动';
    return title + year + ' · ' + kind;
  }

  private displayEpisode(item: Media, season: number, id: number, original: string): string {
    return this.presentationLanguage === 'zh' && this.presentationReady(item) ?
      this.episodeNameIndex.get(item.id + ':' + season + ':' + id) || original : original;
  }

  private displayOverview(item: Media, original: string): string {
    return this.presentationLanguage === 'zh' ?
      (this.presentationReady(item) ? this.presentation?.overview(item.id) : '') || original : original;
  }

  private artwork(item: Media): string {
    return this.presentationReady(item) ? this.titleIndex.get(item.id)?.posterUri ?? '' : '';
  }

  private matchesMedia(item: Media, query: string): boolean {
    return matchesText(query, item.title, this.displayTitle(item));
  }

  private scrollSlot(): string {
    if (!this.pageVisible || this.selectedMedia) { return ''; }
    if (this.tab==='discover' || this.tab==='search' || this.tab==='library') { return this.tab; }
    if (this.tab==='progress' && this.progressMode==='next') { return this.mediaMode==='movie'?'movie':'show'; }
    if (this.tab==='progress' && this.progressMode==='calendar') { return this.mediaMode==='movie'?'movieCalendar':'calendar'; }
    if(this.tab==='progress'&&this.progressMode==='history'&&this.mediaMode==='show'){return 'history';}
    return '';
  }
  private scrollSource(slot: string): ScrollRows | undefined {
    switch (slot) {
      case 'discover': return this.discoverRows;
      case 'search': return this.searchRows;
      case 'show': return this.showRows;
      case 'movie': return this.movieRowsSource;
      case 'history': return this.historyRows;
      case 'calendar': return this.calendarRows;
      case 'movieCalendar': return this.movieCalendarRows;
      case 'library': return this.collectionRowsSource();
      default: return undefined;
    }
  }
  private scrollController(slot: string): Scroller | undefined {
    switch (slot) {
      case 'discover': return this.discoverScroller;
      case 'search': return this.searchScroller;
      case 'show': return this.showScroller;
      case 'movie': return this.movieScroller;
      case 'history': return this.historyScroller;
      case 'calendar': return this.calendarScroller;
      case 'movieCalendar': return this.movieCalendarScroller;
      case 'library': return this.collectionScroller;
      default: return undefined;
    }
  }
  private scrollContext(slot: string): string {
    const scope=this.currentSearchAccount();
    if (slot==='discover') { return JSON.stringify([scope,slot,this.mediaMode,this.discoverOptions]); }
    if (slot==='search') { return JSON.stringify([scope,slot,this.title,this.searchOptions,this.searchSubmitted]); }
    if (slot==='show') { return JSON.stringify([scope,slot,this.nextQuery,this.nextFilter,this.progressPrefs]); }
    if (slot==='movie') { return JSON.stringify([scope,slot,this.movieProgressQuery,this.movieProgressOptions]); }
    if (slot==='calendar') { return JSON.stringify([scope,slot,this.calendarQuery,this.showCalendarMode,this.calendarPremieres,this.calendarProtect]); }
    if (slot==='movieCalendar') { return JSON.stringify([scope,slot,this.movieCalendarQuery,this.movieCalendarMode]); }
    return JSON.stringify([scope,slot,this.mediaMode,this.collectionFilter,this.collectionStatusFilter,this.collectionQuery,this.collectionOptions,this.collectionGrid]);
  }
  private rememberScroll(): void {
    const slot=this.scrollSlot(), rows=this.scrollSource(slot), scroller=this.scrollController(slot);
    if (!slot || !rows || !scroller) { return; }
    const context=this.scrollContext(slot);
    if (this.scrollAnchors.pending(slot,context)) { return; }
    const index=this.scrollIndices.get(slot) ?? 0;
    let offset=0;
    try { offset=-scroller.getItemRect(index).y; } catch (error) {}
    this.scrollAnchors.save(slot,captureAnchor(context,rows,index,offset));
  }
  private onListScroll(slot: string,index: number): void {
    if (this.scrollSlot()!==slot) { return; }
    this.scrollIndices.set(slot,index);
    this.restoreScroll(slot);
  }
  private restoreScroll(slot: string): void {
    if (!this.scrollAnchors.has(slot) || this.scrollSlot()!==slot) { return; }
    const context=this.scrollContext(slot), anchor=this.scrollAnchors.pending(slot,context);
    const rows=this.scrollSource(slot), scroller=this.scrollController(slot);
    if (!anchor || !rows || !scroller || this.scrollScheduled===anchor || !resolveAnchor(anchor,context,rows)) { return; }
    this.scrollScheduled=anchor;
    // Run after the native data source notifications have been laid out.
    // No guessed delay, retained page or repeated scroll timer.
    this.getUIContext().postFrameCallback(new RestoreScrollFrame(()=>{
      if (this.scrollScheduled===anchor) { this.scrollScheduled=undefined; }
      if (this.scrollSlot()!==slot || this.scrollContext(slot)!==context || this.scrollAnchors.pending(slot,context)!==anchor) { return; }
      const target=resolveAnchor(anchor,context,rows);
      if (!target) { return; }
      try {
        scroller.scrollToIndex(target.index,false,ScrollAlign.START,{extraOffset:LengthMetrics.vp(target.offset)});
        this.scrollIndices.set(slot,target.index);
        this.scrollAnchors.consume(slot,anchor);
      } catch (error) {
        // A detached controller is retried only by the next native layout/data event.
      }
    }));
  }
  private viewScope(): string { return this.tab + ':' + this.mediaMode + ':' + this.progressMode + ':' + (this.selectedMedia?.id ?? ''); }
  private viewportChanged(item: Media, season: number, urls: string[], visible: boolean, tab: string, mode: string, slot: string = ''): void {
    if (!this.pageVisible || this.selectedMedia || tab !== this.tab || (mode && mode !== this.progressMode) || (tab!=='search' && item.kind!==this.mediaMode) || !canReadDetails(item)) { return; }
    if (this.viewport.update(item,season,urls,visible,slot)) { this.requestViewportPresentation(); }
  }
  private onShowViewChanged(): void { if (this.pageVisible && !this.selectedMedia && this.tab==='progress' && this.mediaMode==='show' && this.progressMode==='next') { this.onPresentationChanged(); } }
  private onMovieViewChanged(): void { if (this.pageVisible && !this.selectedMedia && this.tab==='progress' && this.mediaMode==='movie' && this.progressMode==='next') { this.onPresentationChanged(); } }
  private onCalendarViewChanged(): void { if (this.pageVisible && !this.selectedMedia && this.tab==='progress' && this.mediaMode==='show' && this.progressMode==='calendar') { this.onPresentationChanged(); } }
  private onMovieCalendarViewChanged(): void { if (this.pageVisible && !this.selectedMedia && this.tab==='progress' && this.mediaMode==='movie' && this.progressMode==='calendar') { this.onPresentationChanged(); } }
  private onCollectionViewChanged(): void { if (!this.modeBusy) { this.captureCollectionView(); } if (this.pageVisible && !this.selectedMedia && this.tab==='library') { this.onPresentationChanged(); } }
  private onDetailViewChanged(): void { if (this.pageVisible && this.selectedMedia) { this.onPresentationChanged(); } }
  private onDiscoverViewChanged(): void { if (this.pageVisible && !this.selectedMedia && this.tab==='discover') { this.onPresentationChanged(); } }
  private onSearchViewChanged(): void { if (this.searchActive()) { this.onPresentationChanged(); } }
  private activePresentationRoute():string{
    const common=JSON.stringify([this.currentSearchAccount(),this.clientId,this.tab,this.mediaMode,this.progressMode,this.selectedMedia?.id??'',this.presentationLanguage]);
    if(this.selectedMedia){return JSON.stringify([common,this.schedulePage,this.localSeason]);}
    switch(this.scrollSlot()){
      case 'show':return JSON.stringify([common,this.nextPage,this.nextQuery]);
      case 'movie':return JSON.stringify([common,this.movieProgressPage,this.movieProgressQuery]);
      case 'library':return JSON.stringify([common,this.collectionPage,this.collectionQuery,this.collectionFilter,this.collectionStatusFilter,this.collectionOptions]);
      case 'calendar':return JSON.stringify([common,this.calendarPage,this.showCalendarMode,this.calendarPremieres,this.calendarQuery,this.calendarProtect]);
      case 'movieCalendar':return JSON.stringify([common,this.movieCalendarQuery,this.movieCalendarMode]);
      default:return common;
    }
  }
  private onPresentationChanged(): void {
    this.updateCacheLifecycle();
    this.updateSearchContext();
    const scope = this.viewScope();
    if (!this.progressCandidateActive()) { this.cancelCandidateWake(); }
    if (scope !== this.viewportRouteKey) { this.viewport.clear(); this.viewportRouteKey = scope; }
    this.reloadCollectionOptions();
    const route = this.activePresentationRoute();
    if (route !== this.presentationRoute) {
      this.presentationRoute = route;
      this.cancelPresentationReads();
      this.activePageWork()?.changePresentation(route);
      this.presentationEpoch++;
        this.presentationStatus = '';
    }
    this.requestPresentation();
  }

  private updateCacheLifecycle(): void {
    const route=this.pageVisible ? this.viewScope() : '';
    const account=this.currentSearchAccount();
    if (this.scrollAccount!==account) { this.scrollAccount=account; this.scrollAnchors.clear(); this.scrollIndices.clear(); this.scrollScheduled=undefined; }
    if (!this.cacheLifecycle.transition(route,account)) { return; }
    this.pageWorks.transition(this.pageOwnerSlot(),route,account);
    this.cancelPresentationReads();
    this.businessPresentationTasks=undefined;
    if (!this.pageVisible || this.selectedMedia || this.tab!=='discover' || !this.discoverRows.work.remote.snapshot().loading) { this.discoverBusy=false; }
    this.releaseInactiveCaches(false);
  }
  private handleMemoryPressure(): void {
    if (this.memoryPending) { return; }
    this.memoryPending=true;
    // Defer cache work out of the native memory callback; no periodic timer.
    this.memoryTimer=setTimeout(()=>{
      this.memoryTimer=-1; this.memoryPending=false;
      if (!this.memorySubscribed) { return; }
      this.cacheLifecycle.invalidate();
      this.cancelPresentationReads();
      this.businessPresentationTasks=undefined;
      this.releaseInactiveCaches(true);
      if (this.pageVisible) { this.requestPresentation(); }
    },0);
  }
  private releaseInactiveCaches(pressure: boolean): void {
    if(pressure||!this.pageVisible||this.tab!=='library'||this.selectedMedia){this.clearCollectionFanart();}
    if(pressure||this.scrollSlot()!=='history'){this.historyOwner.clear();this.historyRows.replace([],[],[]);}
    if(this.scrollSlot()!=='show'){this.progressRevealed.clear();}
    const residency=cacheResidency(this.pageVisible,this.tab,this.mediaMode,this.progressMode,!!this.selectedMedia);
    const generation=this.cacheLifecycle.generation();
    const scope=residency.search ? this.currentSearchAccount() : '';
    const promise=this.searchRepo;
    if (promise) {
      promise.then((repo: SearchRead)=>{
        if (!this.cacheLifecycle.current(generation)) { return; }
        repo.setResidentScope(scope);
        if (pressure) { repo.releaseCatalogs(); }
      }).catch(()=>{});
    }
    if (!residency.search || pressure) {
      if(pressure){this.invalidateSearchLocal();}
      this.searchController.clearCandidates();
      if (!residency.search) { this.searchRows.replace([],[],[]); }
      else { this.refreshSearchLocal(); }
    }
    // Only derived models are released. In-flight observation / journal writes,
    // authoritative snapshots and synchronization evidence are untouched.
    if (!residency.progress) {
      this.clearProgressCandidates();
      this.showRows.replace([],[],[]);
    }
    if (!residency.calendar) { this.calendarIndex.clear(); this.calendarMemo.clear(); this.calendarRows.replace([],[],[]); }
    if (!residency.movieProgress) { this.movieMemo.clear(); this.movieAllMemo.clear(); this.movieTitleOrder.clear(); this.movieAllTitleOrder.clear(); this.movieRowsSource.replace([],[],[]); }
    if (!residency.movieCalendar) { this.movieCalendarRows.replace([],[],[]); }
    if (!residency.movieProgress && !residency.movieCalendar && !residency.collection) { this.movieMetadataMemo.clear(); }
    if (!residency.collection) { this.collectionIndexMemos.clear(); this.clearCollectionOwners(); }
    else { this.releaseCollectionOwner(this.mediaMode==='movie'?'show':'movie'); }
    if (!residency.discover) { this.discoverMemo.clear(); this.discoverRows.replace([],[],[]); }
    // Keep active detail/season data during foreground pressure; route changes
    // evict full payloads, but keep lightweight title/sort metadata.
    if (!pressure || !this.pageVisible) {
      this.presentationWorkVersion++; this.presentationEpoch++;
      this.presentation?.releaseTransient();
      this.episodeNameIndex.clear(); this.seasonKeys.clear(); this.episodeSearchRevision++;
      this.presentationAttempts.retry(); this.presentationQueues.clear();
    }
    if (pressure || !this.pageVisible) { this.libraryProjectionSession.clear(); this.episodeStore?.releaseProjectionReadCache(); }
    if (pressure) {
      // Pressure revokes display work, not the still-visible remote search or
      // discovery request. Their original lifecycle and loading flags stay valid.
      this.pageWorks.resetDisplay();
      this.movieMetadataMemo.clear(); this.movieMemo.clear(); this.movieAllMemo.clear(); this.movieTitleOrder.clear(); this.movieAllTitleOrder.clear();
      // The existing projection may be in use by verified observation. Do not
      // clear its shared cache mid-flight; derived module caches above suffice.
    }
  }

  private scheduleLazyRows(): void {
    const work=this.activePageWork();
    if(!work){return;}
    work.invalidate();
    if (this.lazyPending) { return; }
    this.lazyPending = true;
    const scope=this.viewScope(),account=this.currentProgressScope();
    this.updateLazyRows().catch((error:Error)=>{
      if(this.pageVisible&&this.tab==='library'&&scope===this.viewScope()&&account===this.currentProgressScope()){
        this.reportCollectionFailure(this.collectionSortKey(),this.collectionStage,error);
      }
    });
  }

  private activateDisplayOwner(scope:string):void {
    switch(this.scrollSlot()) {
      case 'discover': this.discoverRows.activate(scope); break;
      case 'search': this.searchRows.activate(scope); break;
      case 'show': this.showRows.activate(scope); break;
      case 'movie': this.movieRowsSource.activate(scope); break;
      case 'history': this.historyRows.activate(scope); break;
      case 'calendar': this.calendarRows.activate(scope); break;
      case 'movieCalendar': this.movieCalendarRows.activate(scope); break;
      case 'library': this.collectionRowsSource().activate(scope); break;
    }
  }
  private async updateLazyRows(): Promise<void> {
    await Promise.resolve();
    this.lazyPending = false;
    if (!this.pageVisible || this.selectedMedia) { return; }
    const work=this.activePageWork();
    if(!work){return;}
    const ticket=work.begin();
    const consumer=ticket.consumer;
    const differ=(input: ListDiffInput)=>diffDisplay(input,consumer);
    const scope = this.viewScope();
    const account = this.currentProgressScope();
    if(this.tab==='library'){this.collectionStage='数据源初始化';}
    this.activateDisplayOwner(JSON.stringify([account,scope]));
    const current = (): boolean => this.pageVisible && work.current(ticket) && this.activePageWork()===work && scope === this.viewScope() && account === this.currentProgressScope() && !this.selectedMedia;
    if(this.scrollSlot()==='history'){
      try{
        const ui=this.historyUi;
        this.historyOwner.update(account,account?this.nextShows:[]);
        const rows=this.historyOwner.rows(ui.period,ui.query,Date.now(),(r:HistoryEpisode)=>this.displayTitle(r.media),(r:HistoryEpisode)=>this.displayEpisode(r.media,r.season,r.id,r.title));
        const committed=await this.historyRows.submit(rows,rows.map((r:HistoryEntry)=>r.key),rows.map((r:HistoryEntry)=>this.historyRowKey(r)),differ,current);
        if(committed&&current()&&ui.period===this.historyUi.period&&ui.query===this.historyUi.query){this.historyUi={period:ui.period,query:ui.query,loading:false,error:'',count:rows.filter((r:HistoryEntry)=>!!r.episode).length};this.restoreScroll('history');}
      }catch(error){if(current()){this.historyUi={period:this.historyUi.period,query:this.historyUi.query,loading:false,error:'历史读取失败，点击重试。',count:0};}}
      return;
    }
    if (this.tab === 'discover') {
      const items = this.visibleDiscover();
      const result = this.discoverPageResult();
      const rows: DiscoverItem[][] = [];
      for (let i=0;i<items.length;i+=2) { rows.push(items.slice(i,i+2)); }
      const committed = await this.discoverRows.submit(rows,rows.map((row: DiscoverItem[]) => row.map((item: DiscoverItem) => item.media.id).join(',')),
        rows.map((row: DiscoverItem[]) => this.discoverRowKey(row)),differ,current);
      if (committed && current()) { if(this.discoverTotal!==result.total){this.discoverTotal=result.total;} if(this.discoverShownPage!==result.page){this.discoverShownPage=result.page;} if(this.discoverPages!==result.pages){this.discoverPages=result.pages;} this.restoreScroll('discover'); }
      return;
    }
    if (this.tab === 'search') {
      const committed=await this.searchRows.submit(this.results,this.results.map((item: Media) => item.id),this.results.map((item: Media) => this.searchRowKey(item)),differ,current);
      if (committed && current()) { this.restoreScroll('search'); }
      return;
    }
    if (this.tab === 'progress' && this.progressMode === 'calendar') {
      if (this.mediaMode === 'movie') {
        const rows = this.movieCalendarCurrent() ? this.movieSlice() : [];
        const committed=await this.movieCalendarRows.submit(rows,rows.map((row: MovieCalendarItem) => row.movie.media.id),rows.map((row: MovieCalendarItem) => this.movieCalendarKey(row)),differ,current);
        if (committed && current()) { this.restoreScroll('movieCalendar'); }
      } else {
        const prepared = this.prepareCalendar();
        if (!prepared) { return; }
        const pages = Math.max(1,Math.ceil(prepared.length/this.collectionPageSize));
        const summary: PageSummary = {key:this.calendarDisplayKey(),total:prepared.length,page:Math.min(this.calendarPage,pages),pages:pages};
        const rows = prepared;
        const committed = await this.calendarRows.submit(rows,rows.map((row: CalendarEntry) => row.key),rows.map((row: CalendarEntry) => this.calendarRowKey(row)),differ,current);
        if (committed && current() && this.calendarRows.work.publishSummary(summary,this.calendarSummary)) { this.calendarSummary = summary; }
      if (committed && current()) { this.restoreScroll('calendar'); }
      }
      return;
    }
    if (this.tab === 'library') {
      const recovery=this.collectionRecovery();recovery.activate(this.collectionRecoveryScope());
      if(recovery.blocked(this.collectionSortKey())){return;}
      this.collectionStage='最近添加';this.publishCollectionHeader();
      this.collectionStage='评分读取';if (this.collectionOptions.sort === 'userRating') { this.loadCollectionRatings(); }
      this.collectionStage='收藏计算';
      const prepared = this.collectionItems(true);
      if (this.sortJobs.pending(this.collectionSortSlot())) { return; }
      const summary: PageSummary = {key:this.collectionDisplayKey(),total:prepared.length,page:this.collectionPage,pages:Math.max(1,Math.ceil(prepared.length/this.collectionPageSize))};
      const rows: CollectionGroup[] = [];
      if (!this.signedIn || this.activeCloud()) {
        const label=this.collectionFilter==='hidden'?'隐藏影视':this.collectionFilter==='queue'?'待看清单':'全部';
        const step=this.collectionGrid?2:1;
        for(let i=0;i<prepared.length;i+=step){
          rows.push({key:this.collectionFilter+':'+prepared[i].media.id,label:label,rows:prepared.slice(i,i+step)});
        }
      }
      this.collectionStage='列表发布';
      const committed = await this.collectionRowsSource().submit(rows, rows.map((group: CollectionGroup) => group.key),
        rows.map((group: CollectionGroup) => this.collectionGroupKey(group)),differ,current);
      if (committed && current() && this.collectionRowsSource().work.publishSummary(summary,this.collectionSummary)) { this.collectionSummary = summary; }
      if (committed && current()) { recovery.published();this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,'',this.collectionUi.retrying);this.restoreScroll('library'); }
      return;
    }
    if (this.tab !== 'progress' || this.progressMode !== 'next') { return; }
    if (this.mediaMode === 'movie') {
      if (this.movieProgressOptions.sort === 'userRating') { this.loadMovieRatings(); }
      const prepared = this.movieProgressRows(this.movieProgressQuery,false,true);
      if (this.movieProgressQuery && this.presentationLanguage === 'zh') { this.movieProgressRows('',false,true); }
      if (this.sortJobs.pending(this.movieProgressQuery ? 'movie-query' : 'movie-all')) { return; }
      const rows = prepared;
      const summary: PageSummary = {key:this.movieDisplayKey(),total:prepared.length,page:this.movieProgressPage,pages:Math.max(1,Math.ceil(prepared.length/this.collectionPageSize))};
      const committed = await this.movieRowsSource.submit(rows, rows.map((row: PersonalLibraryRow) => row.media.id),
        rows.map((row: PersonalLibraryRow) => this.movieRowKey(row)),differ,current);
      if (committed && current() && this.movieRowsSource.work.publishSummary(summary,this.movieSummary)) { this.movieSummary = summary; }
      if (committed && current()) { this.restoreScroll('movie'); }
    } else {
      if (this.progressPrefs.sort==='userRating') { this.loadCollectionRatings(); }
      this.progressData(this.nextQuery,false,true);
      if (this.nextQuery && this.presentationLanguage === 'zh') { this.progressData('',false,true); }
      if (this.sortJobs.pending('show-candidates') || this.sortJobs.pending(this.nextQuery ? 'show-query' : 'show-all')) { return; }
      const rows = this.nextSlice();
      const pages = this.nextPages();
      const summary: PageSummary = {key:this.showDisplayKey(),total:this.nextFiltered().length,page:Math.min(this.nextPage,pages),pages:pages};
      const committed = await this.showRows.submit(rows, rows.map((entry: ProgressEntry) => entry.key),
        rows.map((entry: ProgressEntry) => this.showRowKey(entry)),differ,current);
      if (committed && current() && this.showRows.work.publishSummary(summary,this.showSummary)) { this.showSummary = summary; }
      if (committed && current()) { this.restoreScroll('show'); }
    }
  }

  private showRowKey(entry: ProgressEntry): string {
    const row = entry.row;
    return JSON.stringify([entry.key,entry.group,entry.label,entry.collapsed,entry.count,row?.episode.id ?? 0,
      row?.episode.season ?? 0,row?.episode.number ?? 0,row?.episode.firstAired ?? '',row?.total ?? 0,
      row?.completed ?? 0,row?.upcoming ?? false,row?.fresh ?? false,row?.pinned ?? false,row?.held ?? false,
      row?.dateUnknown ?? false,row ? this.artwork(row.media) : '',row ? this.displayTitle(row.media) : '',
      row ? this.progressEpisodeLabel(row) : '',row?this.progressRatingLabel(row):'']);
  }

  private collectionGroupKey(group: CollectionGroup): string {
    return group.key + ':' + this.collectionGrid + ':' + group.rows.map((row: PersonalLibraryRow) => this.movieRowKey(row) + ':' + this.isHidden(row.media)+':'+this.collectionDescription(row.media)+':'+this.collectionRatingText(row.media)).join(',');
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
    return JSON.stringify([row.key,row.day,row.time,row.season,row.number,row.group,row.header,row.state,row.queued,row.synthetic,this.calendarProtect,this.artwork(row.media),this.displayTitle(row.media),this.calendarEpisodeTitle(row)]);
  }
  private requestPresentation(invalidateBusiness:boolean=true): void {
    if (!this.pageVisible) { return; }
    if (invalidateBusiness) { this.businessPresentationTasks=undefined; }
    this.scheduleLazyRows();
    this.requestViewportPresentation();
  }
  private requestViewportPresentation(): void {
    if (!this.pageVisible || !this.presentation) { return; }
    const token=this.viewportFrame.request();
    if (token<0) { return; }
    this.getUIContext().postFrameCallback(new RestoreScrollFrame(()=>{
      if (!this.viewportFrame.consume(token) || !this.pageVisible || !this.presentation) { return; }
      this.updatePresentationQueues();
      this.requestPresentationPublication();
      this.cancelInvisiblePresentationReads();
      this.presentationWorkVersion++;
      this.loadPresentation();
    }));
  }
  private requestPresentationPublication(): void {
    if (!this.pageVisible) { return; }
    const token=this.presentationFrame.request();
    if (token<0) { return; }
    this.getUIContext().postFrameCallback(new RestoreScrollFrame(()=>{
      if (this.presentationFrame.consume(token) && this.pageVisible) { this.publishPresentation(); }
    }));
  }

  private addPresentationTask(tasks: Map<string,PresentationTask>, item: Media, artwork: boolean, season: number = 0,
    urls: string[] = []): void {
    if (!canReadDetails(item)) { return; }
    if (artwork && !this.selectedMedia && !this.viewport.has(item,season)) { return; }
    addPresentationTask(tasks,item,artwork,season,urls);
  }

  private businessTasks(): Map<string,PresentationTask> {
    if (this.businessPresentationTasks) { return this.businessPresentationTasks; }
    const tasks=new Map<string,PresentationTask>();
    if (this.tab==='library' && !this.selectedMedia) {
      if (this.collectionNeedsMetadata() || this.businessTitlesNeeded()) {
        for (const row of this.collectionBase()) { this.addPresentationTask(tasks,row.media,false); }
      }
    } else if (this.tab==='progress' && !this.selectedMedia && this.progressMode==='next') {
      if (this.mediaMode==='show' && this.businessTitlesNeeded()) {
        const candidates=this.candidateMemo.get(this.progressBusinessKey(),Date.now())??[];
        for (const row of candidates) {
          if (this.nextFilter==='all'||this.nextFilter===row.group||(this.nextFilter==='both'&&(row.group==='upcoming'||row.group==='hold'))) {
            this.addPresentationTask(tasks,row.media,false,this.nextQuery.trim()?row.episode.season:0);
          }
        }
      } else if (this.mediaMode==='movie' && this.businessTitlesNeeded()) {
        for (const row of this.movieProgressRows('')) { this.addPresentationTask(tasks,row.media,false); }
      }
    } else if (this.tab==='progress' && !this.selectedMedia && this.progressMode==='calendar' && this.mediaMode==='movie' && this.businessTitlesNeeded()) {
      for (const row of this.movieRows(this.movieCalendarMode,'')) { this.addPresentationTask(tasks,row.media,false); }
    }
    this.businessPresentationTasks=tasks;
    return tasks;
  }

  private businessTitlesNeeded(): boolean {
    if (this.presentationLanguage!=='zh') { return false; }
    if (this.tab==='library') { const options=this.collectionFilter==='other'?defaultCollection():this.collectionOptions; return !!this.collectionQuery.trim() || options.sort==='title' || options.sort==='userRating'; }
    if (this.tab!=='progress') { return false; }
    if (this.progressMode==='next') {
      // Every show-progress comparator uses localized title for ties.
      return this.mediaMode==='show' ? true :
        !!this.movieProgressQuery.trim() || this.movieProgressOptions.sort==='title' || this.movieProgressOptions.sort==='userRating';
    }
    return this.progressMode==='calendar' && this.mediaMode==='movie' && !!this.movieCalendarQuery.trim();
  }

  private presentationTasks(): PresentationTask[] {
    const tasks = new Map<string,PresentationTask>();
    const detail=this.selectedMedia;
    if (detail) {
      this.addPresentationTask(tasks,detail,true,this.localSeason>0?this.localSeason:0,this.detailUi.summary?.posterUrls??[]);
      if (this.fullSchedule && detail.kind==='show') {
        for (const episode of this.extraSchedule().slice((this.schedulePage-1)*this.collectionPageSize,this.schedulePage*this.collectionPageSize)) {
          this.addPresentationTask(tasks,detail,false,episode.season);
        }
      }
    } else { return this.viewport.rows(); }
    return Array.from(tasks.values());
  }
  private cancelPresentationReads(): void {
    this.presentationQueues.clear(); this.viewportFrame.clear(); this.presentationFrame.clear();
    for (const consumer of this.presentationReaders.values()) { consumer.cancel(); }
    this.presentationReaders.clear(); this.presentationReaderTasks.clear();
    if(this.calendarHydrationKey){this.calendarRows.work.hydrate.cancel();this.calendarHydrationKey='';}
  }
  private updatePresentationQueues(): void {
    const visible=this.presentationTasks();
    const business=this.selectedMedia?this.emptyBusinessTasks:this.businessTasks();
    const language=this.presentationLanguage;
    const selected=!!this.selectedMedia;
    const collection=this.tab==='library' && !selected;
    for (const lane of ['local','title','season','artwork']) {
      const eligible=(task: PresentationTask): boolean=>{
        if (task.artwork && !this.selectedMedia && !this.viewport.has(task.media,task.season)) { return false; }
        if (lane==='local') { return language==='zh' && task.season>0; }
        if (lane==='title') { return language==='zh' && (task.artwork || selected || this.businessTitlesNeeded()); }
        if (lane==='season') { return language==='zh' && task.season>0 && (task.artwork || selected || this.businessTitlesNeeded()); }
        return task.artwork || (collection && this.collectionNeedsMetadata());
      };
      this.presentationQueues.lane(lane).update(visible,business,eligible,Date.now());
    }
  }
  private cancelInvisiblePresentationReads(): void {
    for (const lane of this.presentationReaderTasks.keys()) {
      const task=this.presentationReaderTasks.get(lane);
      if (!task || this.selectedMedia) { continue; }
      if (task.artwork && !this.viewport.has(task.media,task.season)) {
        // A title/season can remain required as business metadata.
        if (lane==='artwork' || !this.businessTasks().has(ViewportTasks.key(task.media,task.season))) {
          this.presentationReaders.get(lane)?.cancel();
        }
      } else if (!task.artwork && !this.businessTasks().has(ViewportTasks.key(task.media,task.season))) {
        this.presentationReaders.get(lane)?.cancel();
      }
    }
  }

  private async presentationLane(lane: string): Promise<void> {
    if (this.presentationLanes.has(lane)) { return; }
    this.presentationLanes.add(lane);
    try {
      while (this.pageVisible && this.presentation) {
        const repo=this.presentation;
        const queue=this.presentationQueues.lane(lane);
        const row=queue.next();
        if (!row) { break; }
        const task=row.task;
        const epoch=this.presentationEpoch;
        const client=this.clientId;
        const language=this.presentationLanguage;
        const account=this.currentProgressScope();
        const route=this.viewScope();
        const collection=this.tab==='library' && !this.selectedMedia;
        const current=(): boolean=>this.pageVisible && this.presentation===repo && this.presentationEpoch===epoch &&
          this.clientId===client && this.presentationLanguage===language && account===this.currentProgressScope() && route===this.viewScope();
        const key=JSON.stringify([JSON.stringify([client,language,account]),lane,row.key]);
        const generation=this.presentationAttempts.generation();
        const consumer=new ReadCancel();
        let success=false;
        let until=Number.MAX_SAFE_INTEGER;
        this.presentationReaders.set(lane,consumer); this.presentationReaderTasks.set(lane,task);
        try {
          if (!this.presentationAttempts.allowed(key,Date.now())) {
            until=this.presentationAttempts.nextAttempt(key); success=true;
          } else {
            if (lane==='local') { await repo.hydrateSeason(task.media,task.season,consumer); }
            else if (lane==='title') { await repo.translation(task.media,client,language,consumer); }
            else if (lane==='season') { await repo.season(task.media,task.season,client,language,consumer); }
            else {
              await repo.artwork(task.media,'',task.artwork,task.posterUrls,false,consumer);
              if (current()) { this.requestPresentationPublication(); }
              if (current() && queue.relevant(row) && !consumer.cancelled()) { await repo.artwork(task.media,client,task.artwork,task.posterUrls,collection,consumer); }
            }
            consumer.check();
            success=current() && queue.relevant(row);
            until=repo.taskValidUntil(task,lane,Date.now());
          }
        } catch (error) {
          if (!(error instanceof ReadCancelled) && !consumer.cancelled()) {
            const failure=presentationFailure(error as Error);
            this.presentationAttempts.fail(key,failure,generation);
            success=true; until=this.presentationAttempts.nextAttempt(key);
            if (current()) {
              if (failure.category==='limited') { this.presentationStatus='资料服务限流；遵守服务端重试时间，已缓存资料仍可用。'; }
              else if (failure.category==='authorization') { this.presentationStatus='资料服务授权失败；请检查 Client ID 或图片来源。'; }
              else if (failure.category!=='missing' && !this.presentationStatus) { this.presentationStatus='部分影视资料暂不可用；其他资料继续加载。'; }
            }
          }
        } finally {
          if (this.presentationReaders.get(lane)===consumer) { this.presentationReaders.delete(lane); this.presentationReaderTasks.delete(lane); }
          queue.finish(row,success,until);
        }
        if (current()) { this.requestPresentationPublication(); }
        if (!current()) { break; }
      }
    } finally {
      this.presentationLanes.delete(lane);
      // A scope reset may have queued new work while the old flight was unwinding.
      if (this.pageVisible && this.presentationQueues.lane(lane).hasPending()) { this.presentationLane(lane); }
    }
  }

  private async loadPresentation(): Promise<void> {
    if (!this.presentation || !this.pageVisible) { return; }
    // Independent resource lanes, not a configurable concurrency multiplier.
    // A slow season never holds the title, local hydration or artwork lane.
    await Promise.all([
      this.presentationLane('local'),this.presentationLane('title'),
      this.presentationLane('season'),this.presentationLane('artwork')
    ]);
  }

  private async changePresentationLanguage(language: string): Promise<void> {
    if (!this.settings || this.languageBusy || this.presentationLanguage === language) { return; }
    this.languageBusy = true;
    try {
      await this.settings.saveLanguage(language);
      this.presentationLanguage = language;
      this.updateEpisodePageRows();
      this.presentationEpoch++;
      this.presentationQueues.clear();
        this.presentationStatus = '';
      this.nextPage = 1;
      this.collectionPage = 1;
      this.movieProgressPage = 1;
      this.calendarPage = 1;
      this.requestPresentation();
    } catch (error) { this.presentationStatus = '影视资料语言保存失败。'; }
    finally { this.languageBusy = false; }
  }

  private async artworkFailed(item: Media,uri: string): Promise<void> {
    const repo=this.presentation;
    if (!repo || !this.pageVisible || this.artwork(item)!==uri) { return; }
    try {
      const retry=await repo.repairArtwork(item,uri);
      if (this.presentation!==repo || !this.pageVisible) { return; }
      this.publishPresentation();
      if (retry) { this.presentationQueues.lane('artwork').invalidateMedia(item.id); this.requestViewportPresentation(); }
    } catch (error) {}
  }

  @Builder
  posterImage(item: Media, width: number, height: number) {
    if (this.artwork(item)) {
      ArtworkImage({uri:this.artwork(item),widthValue:width,ratio:width/height,corner:6,onFailure:(uri: string)=>{this.artworkFailed(item,uri);}})
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

  private async openReleasePage(upstream: boolean = false,direct:boolean=false): Promise<void> {
    const target = upstream ? this.upstreamInfo?.url : (direct?this.availableUpdate?.directUrl:this.availableUpdate?.url) ?? RELEASES_URL;
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
        this.publishMediaRecords(records);
        this.items = records.map((record: MediaRecord) => record.media);
        this.migrationStatus = '收藏数据库已就绪 · ' + records.length + ' 部；旧版 Preferences 保留。';
        this.resetCollection();
        this.invalidateNextShows();
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
      Text('当前版本 ' + APP_VERSION + ' · 未签名个人预览版').fontSize(13)
        .fontColor($r('app.color.showly_secondary')).width('100%')
      Text('下载更新使用 tvv.tw GitHub 加速；请核对 SHA-256。').fontSize(12).width('100%')
      Button('查看功能审计与验收计划').onClick(() => { this.openFeatureAudit(); })
      Button(this.updateBusy ? '检查中…' : '检查更新').enabled(!this.updateBusy)
        .onClick(() => { this.checkAppUpdate(); })
      if (this.updateStatus) { Text(this.updateStatus).fontSize(13).width('100%') }
      if (this.availableUpdate) {
        Text('新版本 ' + this.availableUpdate.version + ' · SHA-256 ' + this.availableUpdate.digest.substring(7))
          .fontSize(12).width('100%')
      }
      Button(this.availableUpdate ? '直接下载新版本 HAP（加速）' : '打开鸿蒙发布页')
        .onClick(() => { this.openReleasePage(); })
      if(this.availableUpdate){Button('GitHub 原始下载链接').fontSize(12).onClick(()=>{this.openReleasePage(false,true);})}
      Text('仅检查公开 GitHub 发布信息，不发送 Trakt 凭据或观看记录。浏览器下载，不自动安装或卸载；请核对官方哈希并用原安装方式覆盖安装。')
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
    const rows = uuid ? await store.queueEntries(uuid) : [];
    const confirmed = uuid ? await store.lastConfirmedEpisodeUpload(uuid) : 0;
    if (await store.boundAccount() !== uuid) { return; }
    this.queueRows = rows;
    this.lastEpisodeUpload = confirmed;
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
    const ticket = syncService.acquire(JSON.stringify([clientId,expected,'episodes']));
    if (!ticket) { return; }
    this.syncBusy = true;
    this.queueConfirm = false;
    this.autoStatus = '正在读取待同步队列…';
    try {
      this.autoStatus = await executeEpisodeQueue(store, expected, clientId, manual,
        ()=>this.clientId===clientId, ()=>this.pageVisible && (manual || (this.autoActive() && this.autoConsent?.uuid===expected)),
        ()=>this.pageVisible, ()=>this.revokeAuto(),
        (account: SyncAccount)=>{ this.syncAccount=account; this.syncBound=true; },
        ()=>{ this.queueRows=[]; }, (status: string)=>{ this.autoStatus=status; });
    } finally {
      try {
        await this.reloadQueue();
        this.syncLogs = await store.syncLogs(expected);
      } catch (error) {
        this.autoStatus += '；本机队列或日志刷新失败：' + safeSyncError(error as Error);
      }
      this.syncPreview = undefined;
      syncService.release(ticket);
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
    const selected=preview.rows.find((row:SyncDifference)=>row.episodeId===episodeId);
    if(!selected?.watchedAt){this.uploadStatus='观看时间未知，未发送。';return;}
    const watchedAt=selected.watchedAt;
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
      this.publishMediaRecords(records);
      this.items = records.map((record: MediaRecord) => record.media);
      this.resetCollection();
      this.threeWayStatus = '已采用云端状态并保存共同基线；仅修改所选本机状态域，未写入 Trakt。';
    } catch (error) {
      this.threeWayStatus = '采用云端状态未确认：' + safeSyncError(error as Error) + '；请重新生成预览。';
      try {
        const records = await store.load();
        this.invalidateMovieCalendar();
        this.publishMediaRecords(records);
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
                  Text('确认将 ' + row.label + ' 的一次观看记录新增至当前已绑定 Trakt 账户？观看时间为本机记录时间：' + (row.watchedAt??'未知，禁止上传') + '。')
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
    this.clearCollectionViews();
    this.movieTitleOrder.clear();this.movieAllTitleOrder.clear();this.showCollectionTitleOrder.clear();this.movieCollectionTitleOrder.clear();
    this.clearProgressCandidates();
    this.resetSearchAccount();
    this.viewport.clear();
    this.clearLocalCalendar(true);
    this.movieCalendarRows.replace([],[],[]);
    this.collectionScope = '';
    this.showRatingRequest.reset();this.collectionRatingStatus='';
    this.collectionRatingKey = '';
    this.collectionRatings = [];
    this.collectionState = emptyCollectionState();
    this.clearCollectionOwners();
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
    this.showProjectionCache.clear(); this.libraryProjectionSession.clear();
    this.episodeStore?.releaseProjectionReadCache();
    this.libraryRevision++;
    this.collectionDependencies.reset();
    this.displayRevisions.reset();
    this.collectionIndexMemos.clear();
    this.movieMetadataMemo.clear();
    this.libraryIndex.clear();this.personalLibraryIndex.clear();this.pendingMediaDelta=undefined;
    this.libraryMemo.clear();
    this.sortJobs.clear();
    this.invalidateLazyWork();
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
    this.detailSession.clear(); this.detailConsumer=this.detailSession.consumer();
    this.detailRevision++; this.detailResumePending=!!this.selectedMedia; this.relatedBack=[];this.relatedOffsets=[];this.resetDetailUi();
    this.clearSeasonDetail();
    this.localSeries = undefined;
    this.effectiveEditable = false;
    this.nextShows = [];
    this.clearLocalCalendar(); this.libraryEvidence = [];
    this.cloudStatus = '';
    this.resetCollection();
  }

  private async readLibraryProjection(store: EpisodeStore, snapshot: CloudLibrary | undefined, uuid: string,
    clientId: string, fill: boolean, force: boolean, current: () => boolean): Promise<LibraryProjection> {
    const records = this.mediaRecords;
    const recordKey = this.mediaInput.version();
    const readRevision=store.assertProjectionReadable();
    const durableKey=store.committedProjectionKey();
    const key = projectionKey(clientId, uuid, snapshot?.generation ?? -1, snapshot?.activity ?? '',
      0,JSON.stringify([durableKey,recordKey]));
    const cached = force ? undefined : this.projectionMemo.get(key, Date.now());
    if (cached && current() && store.projectionReadable(readRevision)) {
      this.projectionHits++;
      this.performanceStatus = '全库计算 ' + this.projectionRuns + ' 次 · 缓存命中 ' + this.projectionHits + ' 次';
      return cached;
    }
    this.projectionRuns++;
    const started = Date.now();
    const queryStart = store.readQueryCount();
    const result = await this.libraryProjectionSession.read(store, records, snapshot, uuid, clientId, fill, force,
      ():boolean=>current()&&recordKey===this.mediaInput.version(),
      (done: number, total: number): void => {
        if (fill) { this.cloudStatus = '计算个人库及补齐目录 ' + done + '/' + total; }
      }, this.showProjectionCache,this.mediaInput);
    if (!current() || recordKey!==this.mediaInput.version() || (!fill && !store.projectionReadable(readRevision))) { throw new Error('Observation session changed'); }
    const finalKey=key;
    // The caller serializes edits with cloudBusy/localBusy. A missing or
    // failed catalog must be retried, not memoized as complete.
    if (!fill && result.cacheable && store.projectionReadable(readRevision) && recordKey===this.mediaInput.version() && !result.matches.length) {
      this.projectionMemo.put(finalKey, result, result.computedAt, result.validUntil);
    }
    this.performanceStatus = '全库计算 ' + this.projectionRuns + ' 次 · 缓存命中 ' + this.projectionHits +
      ' 次 · 本轮重算 ' + result.computedShows + ' 部 / 复用 ' + result.reusedShows + ' 部（磁盘 ' + result.diskHits + ' 部） · 目录解析 ' + result.scheduleParses + ' / 缓存解析 ' + result.diskParses + ' / 缓存行更新 ' + result.diskWrites + ' / 后台批次 ' + result.workerBatches + ' · 遍历 ' + result.visitedShows + ' 部 / 工作输入 ' + result.workerInputBytes + ' B · 计算 ' +
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
          shows: cached.shows, moviePlays: cached.moviePlays, queueDates: cached.queueDates, movieDetails: cached.movieDetails, movieWatchedDetails: cached.movieWatchedDetails, movieQueuedDetails: cached.movieQueuedDetails, versions: cached.versions, verifiedAt: cached.verifiedAt };
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
          const initialFence=store.assertProjectionReadable();
          const initialMediaVersion=this.mediaInput.version();
          const initial = await this.readLibraryProjection(store, restored, account.uuid, clientId, false, false, current);
          if (!current()) { throw new Error('Session changed'); }
          initialProjection = initial;
          initialSnapshot = restored;
          initialRevision = initialFence;
          initialRecords = initialMediaVersion;
          this.retainProgressCandidates(initial.next);
          this.nextShows = initial.next;
          this.libraryEvidence = initial.evidence;
          this.publishLocalCalendar(initial);
          this.reloadProgressFlags();
        } catch (error) {
          if (!current()) { throw new Error('Session changed'); }
        }
      }
      let snapshot = this.cloud;
      try {
        const revision = await readActivity(session);
        const changed = !snapshot || snapshot.activity !== revision || snapshot.queueDates === undefined || snapshot.movieDetails === undefined || snapshot.versions === undefined;
        if (changed) { snapshot = await readCloudLibraryIncremental(session,snapshot); }
        if (!snapshot) { throw new Error('Observation unavailable'); }
        const verified = await readSyncAccount(session);
        if (!current() || verified.uuid !== account.uuid || await readActivity(session) !== snapshot.activity) {
          throw new Error('Account or activity changed');
        }
        if (!current()) { throw new Error('Session changed'); }
        const verifiedAt = Date.now();
        // Persist only after account/activity fences. Cache metadata is not a receipt.
        const persisted: CloudLibrary = { generation: snapshot.generation, activity: snapshot.activity,
          observedAt: snapshot.observedAt, watchlist: snapshot.watchlist, watchedMovies: snapshot.watchedMovies,
          shows: snapshot.shows, moviePlays: snapshot.moviePlays, queueDates: snapshot.queueDates,
          movieDetails: snapshot.movieDetails, movieWatchedDetails: snapshot.movieWatchedDetails, movieQueuedDetails: snapshot.movieQueuedDetails, versions: snapshot.versions, verifiedAt: verifiedAt };
        await store.saveRemoteObservation(account.uuid, persisted);
        if (!current()) { throw new Error('Session changed'); }
        snapshot = persisted;
        this.cloud = snapshot;
        this.cloudUuid = account.uuid;
        this.publishMovieSource(snapshot);
        if (changed) { this.clearLocalCalendar(); this.libraryEvidence = []; }
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
          if (this.publishMediaRecords(records)) {
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
          this.publishMediaRecords(retained);
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
        store.projectionReadable(initialRevision) && initialRecords === this.mediaInput.version() &&
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
      this.retainProgressCandidates(result.next);
      this.nextShows = result.next;
      this.reloadProgressFlags();
      this.movieProgressPage = 1;
      this.nextStatus = result.missing ? '部分剧集资料尚未补齐。' : '';
      this.libraryEvidence = result.evidence;
      this.publishLocalCalendar(result);
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

  private async persistMedia(records: MediaRecord[], changes: TitleChange[] = [],watchTime:number=Date.now()): Promise<boolean> {
    if(!validWatchTime(watchTime,Date.now())){return false;}
    const store = this.mediaStore;
    if (!this.ready || this.saving || this.syncBusy || !store || !this.canEditLibrary()) { return false; }
    const dateScope = this.currentProgressScope();
    const editVersion=this.mediaInput.version();
    const editIds=new Set<string>(changes.map((change:TitleChange)=>change.id));
    const beforeDates:PersonalLibraryRow[]=changes.length?this.personalLibrary().filter((row:PersonalLibraryRow)=>editIds.has(row.media.id)):[];
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
        new Date(watchTime).toISOString(), this.titleQuickActive()) : await store.save(records);
      this.invalidateMovieCalendar();
      this.publishMediaRecords(verified,records,editVersion,Array.from(editIds));
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

  private async changeMediaIntent(item: Media, domain: string, value: string,watchTime:number=Date.now()): Promise<void> {
    if (this.isHidden(item) || this.collectionEditBusy || !this.ready || this.saving || this.cloudBusy || this.syncBusy || !this.canEditLibrary() ||
        (domain === 'movie' && this.progressPrefsBusy)) { return; }
    const pinScope = this.currentProgressScope();
    const movieEdit = domain === 'movie' && item.kind === 'movie';
    if (movieEdit) { this.progressPrefsBusy = true; }
    try {
      const edit = titleEdit(this.mediaRecords, item, domain, value);
      const saved = await this.persistMedia(edit.records, edit.changes,watchTime);
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

  private detailLibraryRow(item:Media):PersonalLibraryRow|undefined{this.personalLibrary();return this.libraryIndex.get(item.id);}
  @Builder
  mediaStateView(item: Media) {
    Column({ space: 8 }) {
      Text('收藏与观看状态').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      this.librarySyncNotice()
      if (this.movieUndo?.id === item.id) { this.movieUndoView() }
      if (item.kind === 'movie') {
        Text(this.detailLibraryRow(item)?.watched ? '已看' : '未看或未确认').fontSize(14).width('100%')
        Button(this.detailLibraryRow(item)?.watched ? '撤销已看' : '标记已看')
          .width('100%').enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
          .onClick(() => { this.changeMediaIntent(item, 'movie',
            this.detailLibraryRow(item)?.watched ? 'no' : 'yes'); })
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
      Button(this.detailLibraryRow(item)?.queued ?
        '移出待看' : this.isFollowed(item) ? '移回待看' : '加入待看')
        .width('100%').enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
        .onClick(() => { this.changeMediaIntent(item, 'watchlist',
          this.detailLibraryRow(item)?.queued ? 'no' : 'yes'); })
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
    this.mediaWatchTime = row.watchedAt??new Date().toISOString();
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
      this.clearLocalCalendar(); this.libraryEvidence = [];
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
                  Text('仅在确实已观看时确认。本次观看时间：' + new Date(this.mediaWatchTime).toLocaleString() +
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

  private currentSearchAccount(): string { return searchScope(this.clientId,this.currentProgressScope()); }
  private searchActive(): boolean { return this.pageVisible && this.tab==='search' && !this.selectedMedia; }
  private cancelSearchRead(): void {
    this.searchGeneration.cancel(); this.searchRows.work.remote.cancel();
  }
  private resetSearchAccount(): void {
    this.cancelSearchRead(); this.searchHistoryGeneration.cancel(); this.invalidateSearchLocal();
    this.searchAccount=''; this.resetSearchRemote(); this.searchSubmitted=false; this.searching=false;
    this.searchController.clearCandidates();
    this.searchRecents=[]; this.searchStatus=''; this.title=''; this.results=[];
    this.searchRows.replace([],[],[]);
  }
  private updateSearchContext(): void {
    const scope=this.currentSearchAccount();
    const active=this.searchActive();
    const language=this.presentationLanguage;
    const changed=scope!==this.searchAccount;
    const wasActive=this.searchRoute;
    const entered=active && !wasActive;
    const langChanged=language!==this.searchLanguage;
    // Store the context first; @Watch callbacks may run during assignments.
    this.searchRoute=active; this.searchLanguage=language;
    if (changed) {
      const previous=this.searchAccount;
      this.searchAccount=scope;
      this.cancelSearchRead(); this.searchHistoryGeneration.cancel(); this.invalidateSearchLocal();
      this.resetSearchRemote(); this.searchSubmitted=false; this.searching=false; this.searchRecents=[];
      this.searchController.clearCandidates();
      if (previous) { this.title=''; }
      this.searchStatus=''; this.results=[]; this.searchRows.replace([],[],[]);
    }
    if (!active) {
      if (this.searching) { this.cancelSearchRead(); this.searching=false; this.searchStatus='搜索已停止，可重新提交。'; }
      if(wasActive&&!changed){this.invalidateSearchLocal();}
      return;
    }
    if (changed || entered) { this.loadSearchHistory(); }
    if (changed || entered || langChanged) { this.refreshSearchLocal(); }
  }
  private async loadSearchHistory(): Promise<void> {
    const scope=this.currentSearchAccount();
    const token=this.searchHistoryGeneration.begin();
    if (!scope || !this.searchActive()) { return; }
    try {
      const repo=await this.searchRepository();
      const rows=await repo.recents(scope);
      if (this.searchHistoryGeneration.current(token) && this.searchActive() && scope===this.currentSearchAccount()) { this.searchRecents=rows; }
    } catch (error) {}
  }
  private async clearSearchHistory(): Promise<void> {
    const scope=this.currentSearchAccount();
    if (!scope) { return; }
    try { const repo=await this.searchRepository(); await repo.clear(scope); }
    catch (error) { if (scope===this.currentSearchAccount()) { this.searchStatus='历史清除失败。'; } }
    if (scope===this.currentSearchAccount()) { this.loadSearchHistory(); }
  }
  private searchRepository(): Promise<SearchRead> {
    if (!this.searchRepo) { this.searchRepo=openSearch(this.context()); }
    const repo=this.searchRepo;
    const scope=this.searchActive() ? this.currentSearchAccount() : '';
    const generation=this.cacheLifecycle.generation();
    return repo.then((value: SearchRead): SearchRead=>{
      if (this.cacheLifecycle.current(generation)) { value.setResidentScope(scope); }
      return value;
    });
  }
  private changeSearchText(value: string): void {
    if (value===this.title) { return; }
    this.cancelSearchRead(); this.invalidateSearchLocal();
    this.title=value; this.searching=false; this.searchSubmitted=false;
    this.resetSearchRemote(); this.searchOptions=defaultSearch(); this.searchStatus='';
    this.searchRows.replace([],[],[]); this.results=[];
    this.refreshSearchLocal();
  }
  private changeSearchOptions(kind: string,sort: string,descending: boolean): void {
    this.searchOptions={kind:kind,sort:sort,descending:descending};
    this.refreshSearchLocal();
  }
  private refreshSearchLocal(): void {
    if (!this.searchActive()) { return; }
    this.invalidateSearchLocal();
    if (!this.searchLocalRunning) { this.runSearchLocal(); }
  }
  private async runSearchLocal(): Promise<void> {
    if (this.searchLocalRunning) { return; }
    this.searchLocalRunning=true;
    let processed=-1;
    try {
      while (this.searchActive() && processed!==this.searchRows.work.local.version()) {
        processed=this.searchRows.work.local.version();
        const scope=this.currentSearchAccount(), query=this.title.trim(), submitted=this.searchSubmitted;
        const options=this.searchOptions, language=this.presentationLanguage, version=processed;
        const current=(): boolean=>this.searchActive() && version===this.searchRows.work.local.version() &&
          scope===this.currentSearchAccount() && query===this.title.trim() && language===this.presentationLanguage;
        if (!query) { if (current() && this.results.length) { this.results=[]; } continue; }
        let stored: SearchRecord[]=[];
        try { const repo=await this.searchRepository(); stored=await repo.catalog(scope); } catch (error) {}
        if (!current()) { continue; }
        const candidate=(row: SearchRecord): SearchCandidate=>({media:row.media,votes:row.votes,localized:language==='zh' ? this.titleIndex.get(row.media.id)?.text.title ?? '' : ''});
        const key=JSON.stringify([scope,this.libraryRevision,this.cloudLocalAllowed,this.activeCloud()?.generation ?? -1,
          this.activeCloud()?.activity ?? '',language]);
        if (this.searchController.source!==stored || this.searchController.key!==key) {
          const library:Media[]=scope&&scope===this.currentSearchAccount()?this.personalLibrary().filter((row:PersonalLibraryRow)=>isTraktMedia(row.media)).map((row:PersonalLibraryRow)=>row.media):[];
          this.searchController.seed(stored,key,library,candidate);
        }
        const input:SearchInput=this.searchController.input(query,submitted,options,candidate);
        try {
          const local=this.searchRows.work.local;
          const consumer=local.consumer();local.start(consumer,JSON.stringify([key,query,submitted,version]));
          const rows=await searchDisplay(input,consumer);
          local.finish(consumer);
          if (!current()) { continue; }
          this.results=rows;
          if (!submitted) { this.searchStatus='本地建议 · '+rows.length+' 部'; }
          else if (this.searching) { this.searchStatus='本地结果 · '+rows.length+' 部，正在搜索网络…'; }
        } catch (error) { if (current()) { const local=this.searchRows.work.local;local.finish(local.consumer(),'local');this.searchStatus='本地搜索暂不可用。'; } }
      }
    } finally { this.searchLocalRunning=false; }
  }
  private async search(): Promise<void> {
    if (!this.searchActive() || this.setupBusy || !this.title.trim()) { return; }
    const query=this.title.trim(), client=this.clientId, scope=this.currentSearchAccount();
    this.cancelSearchRead();
    const lane=this.searchRows.work.remote;
    const consumer=lane.consumer();
    const token=this.searchGeneration.begin();
    const current=(): boolean=>this.searchGeneration.current(token) && lane.current(consumer) && this.searchActive() &&
      client===this.clientId && scope===this.currentSearchAccount() && query===this.title.trim();
    this.searchSubmitted=true; this.resetSearchRemote(); this.searchOptions=defaultSearch();
    this.searching=!!client; this.searchStatus=client ? '读取本地结果…' : '本地搜索（未配置网络）';
    if(client){lane.start(consumer,JSON.stringify([scope,client,query]));}
    this.refreshSearchLocal();
    try {
      const repo=await this.searchRepository();
      if (!current()) { return; }
      if (!client) { return; }
      const rows=await repo.remote(client,query,consumer);
      if (!current()) { return; }
      this.searchController.acceptRemote(rows);this.publishSearch();
      lane.finish(consumer);this.searching=false;
      this.searchStatus='网络搜索完成';
      this.refreshSearchLocal();
      // Persist only public metadata under the captured verified scope.
      try { await repo.rememberCatalog(scope,rows); } catch (error) {}
      if (current()) {
        try { await repo.remember(scope,query); } catch (error) {}
        if (current()) { this.loadSearchHistory(); }
      }
    } catch (error) {
      if (current()) { lane.finish(consumer,'network');this.searching=false; this.searchStatus='网络搜索失败，保留本地结果。'; }
    } finally {
      if (current()) { if(lane.snapshot().loading){lane.finish(consumer);}this.searching=false; this.refreshSearchLocal(); }
    }
  }
  private async rememberSearchDiscovery(scope: string,rows: DiscoverItem[]): Promise<void> {
    if (!scope) { return; }
    try {
      const repo=await this.searchRepository();
      await repo.rememberCatalog(scope,rows.map((row: DiscoverItem)=>publicSearchRecord(row.media)));
    } catch (error) {}
  }

  private cancelDiscoverRead(): number {
    return this.discoverRows.work.remote.cancel();
  }
  private invalidateSearchLocal(): void {
    this.searchRows.work.local.cancel();
  }
  private invalidateLazyWork(): void {
    this.pageWorks.reset();
  }
  private resetDiscover(): void {
    this.cancelDiscoverRead();
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
    if (this.setupBusy || !this.clientId || page < 1 || !this.pageVisible || this.selectedMedia || this.tab !== 'discover') { return; }
    const lane=this.discoverRows.work.remote;
    const account=this.currentSearchAccount();
    const clientId = this.clientId;
    const kind = this.mediaMode;
    const options = this.discoverOptions;
    const request = discoverRequest(kind,options,this.discoverCollectionSize());
    const key = discoverKey(clientId,request);
    const consumer=lane.begin(JSON.stringify([account,key,page]),force);
    if(!consumer){return;}
    const revision=lane.version();
    const current = (): boolean => revision === lane.version() && lane.current(consumer) && clientId === this.clientId &&
      kind === this.mediaMode && this.pageVisible && !this.selectedMedia && this.tab === 'discover' && this.discoverOptions === options && account===this.currentSearchAccount();
    const publish = (feed: DiscoverFeed, fresh: boolean): void => {
      if (!current()) { return; }
      this.discoverFeed = feed;
      this.discoverFeedKey = key;
      this.discoverMemo.clear();
      this.discoverItems = feed.items;
      this.rememberSearchDiscovery(this.currentSearchAccount(),feed.items);
      this.discoverPage = page;
      this.discoverStatus = fresh ? '本地榜单已就绪' : '显示本地旧榜单，正在更新…';
      this.requestPresentation();
    };
    if (this.discoverFeed && this.discoverFeedKey === key) {
      if (!force && discoverFresh(this.discoverFeed,Date.now())) {
        this.discoverPage = page;
        this.discoverStatus = '本地榜单已就绪';
        lane.finish(consumer);this.discoverBusy = false;
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
      const feed = await repo.load(clientId,request,force,publish,consumer);
      if (!current()) { return; }
      publish(feed,true);
    } catch (error) {
      if (current()) { lane.finish(consumer,'network');this.discoverStatus = this.discoverFeed ? '网络更新失败，保留本地榜单。' : '榜单不可用，请检查网络或 Trakt 权限后重试。'; }
    } finally {
      if (current()) { if(lane.snapshot().loading){lane.finish(consumer);}this.discoverBusy = false; this.requestPresentation(); }
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
    return {items:rows,page:1,pages:1,total:rows.length};
  }
  private visibleDiscover(): DiscoverItem[] { return this.discoverPageResult().items; }

  @Builder
  discoverCard(item: DiscoverItem) {
    Column({ space: 6 }) {
      if (this.artwork(item.media)) {
        ArtworkImage({uri:this.artwork(item.media),widthValue:'100%',ratio:2/3,corner:10,onFailure:(uri: string)=>{this.artworkFailed(item.media,uri);}})
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
    List({ space: 12, scroller: this.discoverScroller }) {
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
        
      }
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('discover',start); })
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

  private invalidateNextShows(showId: string = ''): void {
    this.projectionMemo.clear();
    if (showId) {
      this.candidateIndex.remove(showId);
      this.nextShows = this.nextShows.filter((row: NextShow)=>row.media.id!==showId);
    } else { this.nextShows = []; }
    this.clearLocalCalendar(); this.libraryEvidence = [];
    this.projectionPending = true;
    this.resetCollection();
    if (!showId) { this.nextPage = 1; }
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
      if (signedIn && !active) { this.nextShows = []; this.clearLocalCalendar(); this.libraryEvidence = []; return; }
      const result = await this.readLibraryProjection(store, active, uuid, clientId, false, false,
        (): boolean => this.signedIn === signedIn && this.activeCloud() === active && this.cloudUuid === uuid && this.clientId === clientId);
      if (this.activeCloud() !== active || this.cloudUuid !== uuid || (this.signedIn && !active)) { return; }
      this.retainProgressCandidates(result.next);
      this.nextShows = result.next;
      this.reloadProgressFlags();
      this.cloudLocalAllowed = result.localAllowed && !!active;
      this.libraryEvidence = result.evidence;
      this.publishLocalCalendar(result);
      this.resetCollection();
      await this.refreshEffectiveDetail();
      if (this.tab === 'library' && this.collectionGrid && !this.selectedMedia) { this.loadCollectionPosters(); }
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
    return JSON.stringify([this.displayRevisions.show,this.candidateScope(),
      this.progressFlagScope,this.flagVersion('show'),this.hiddenVersion('show'),prefs.strategy,prefs.count,prefs.days,prefs.newAtTop]);
  }
  private progressTitleScope(query:string):string {
    return JSON.stringify([this.progressBusinessKey(),this.presentationLanguage,this.progressPrefs.sort,this.progressPrefs.descending,this.nextFilter,query,
      this.progressPrefs.sort==='userRating'?this.showRatingVersion:0,this.progressPrefs.sort==='userRating'?this.currentShowRatingKey():'']);
  }
  private progressSortKey(query: string): string {
    return JSON.stringify([this.progressBusinessKey(),this.presentationLanguage,this.presentationLanguage==='zh' ? this.titleVersion('show') : 0,
      query ? this.episodeSearchRevision : 0,this.progressPrefs.sort,this.progressPrefs.descending,this.nextFilter,query,
      this.progressPrefs.sort==='userRating' ? this.showRatingVersion : 0,
      this.progressPrefs.sort==='userRating' ? this.currentShowRatingKey() : '']);
  }
  private candidateScope(): string {
    return JSON.stringify([this.clientId,this.currentProgressScope(),this.activeCloud()?.generation ?? -1,this.cloudLocalAllowed]);
  }
  private progressCandidateActive(): boolean {
    return this.pageVisible && !this.selectedMedia && this.tab==='progress' && this.mediaMode==='show' && this.progressMode==='next';
  }
  private cancelCandidateWake(): void {
    if (this.candidateWake>=0) { clearTimeout(this.candidateWake); }
    this.candidateWake=-1; this.candidateWakeAt=0;
  }
  private scheduleCandidateWake(expiry: number): void {
    if (!this.progressCandidateActive() || expiry===Number.MAX_SAFE_INTEGER) { this.cancelCandidateWake(); return; }
    if (this.candidateWake>=0 && this.candidateWakeAt===expiry) { return; }
    this.cancelCandidateWake();
    this.candidateWakeAt=expiry;
    // Native timer signed 32-bit maximum, not an empirical refresh period.
    this.candidateWake=setTimeout(()=>{
      this.candidateWake=-1; this.candidateWakeAt=0;
      if (!this.progressCandidateActive()) { return; }
      if (Date.now()<expiry) { this.scheduleCandidateWake(expiry); return; }
      this.requestPresentation();
    },Math.min(2147483647,Math.max(0,expiry-Date.now())));
  }
  private clearProgressCandidates(): void {
    this.cancelCandidateWake(); this.candidateIndex.clear(); this.candidateMemo.clear();
    this.progressTitleOrder.clear(); this.progressAllTitleOrder.clear();
    this.progressMemo.clear(); this.progressAllMemo.clear(); this.candidateFailureKey='';
  }
  private retainProgressCandidates(rows: NextShow[]): void {
    this.candidateIndex.begin(this.candidateScope());
    this.candidateIndex.retain(new Set<string>(rows.map((row: NextShow)=>row.media.id)));
  }
  private currentShowRatingKey(): string {
    const active=this.activeCloud(); const session=traktAuth.session(this.clientId); const scope=this.currentProgressScope();
    return active && session && scope ? JSON.stringify([scope,session.clientId,session.generation,active.activity,'show']) : '';
  }
  private showRatingIndex(): Map<string,number> {
    const result=new Map<string,number>();
    const key=this.currentShowRatingKey();
    if (key && this.collectionRatingKey===key) {
      for (const rating of this.collectionRatings) { result.set(rating.id,rating.value); }
    }
    return result;
  }
  private localizedProgress(row: ProgressRow,ratings: Map<string,number>): ProgressRow {
    return {media:row.media,episode:row.episode,total:row.total,completed:row.completed,upcoming:row.upcoming,
      fresh:row.fresh,pinned:row.pinned,held:row.held,group:row.group,recentAt:row.recentAt,
      rating:row.rating,randomOrder:row.randomOrder,dateUnknown:row.dateUnknown,userRating:ratings.get(row.media.id),
      localizedTitle:this.presentationLanguage==='zh' ? this.displayTitle(row.media) : undefined,
      localizedEpisode:this.presentationLanguage==='zh' ? this.displayEpisode(row.media,row.episode.season,row.episode.id,row.episode.title) : undefined};
  }
  private async prepareProgressCandidates(businessKey: string,now: number): Promise<void> {
    if (this.candidateFailureKey===businessKey) { return; }
    const token=this.sortJobs.begin('show-candidates',businessKey);
    if (!token) { return; }
    const scope=this.candidateScope();
    const current=(): boolean=>this.sortJobs.current('show-candidates',token) && this.progressCandidateActive() &&
      scope===this.candidateScope() && businessKey===this.progressBusinessKey() && (!this.signedIn || !!this.activeCloud());
    try {
      this.candidateIndex.begin(scope);
      const inputs: CandidateInput[]=[];
      for (const row of this.nextShows) {
        if (row.source && !this.isHidden(row.source.media)) {
          inputs.push({source:row.source,stateKey:row.sourceStateKey,catalogKey:row.sourceCatalogKey,flag:this.progressFlag(row.source.media)});
        }
      }
      const plan=this.candidateIndex.plan(inputs,this.progressPrefs,now);
      let built: CandidateResult[]=[];
      if (plan.pending.length) {
        this.candidateRuns+=plan.pending.length;
        const batch: CandidateBatch={inputs:plan.pending,prefs:plan.prefs,now:now};
        built=await computeCandidateDisplay(batch,this.sortJobs.consumer('show-candidates',token));
      } else { await Promise.resolve(); }
      if (!current() || Date.now()<now) { return; }
      const output=this.candidateIndex.commit(plan,built);
      if (Date.now()>=output.expiry) { return; }
      const candidates=output.rows;
      this.candidateExpiry=output.expiry;
      this.candidateMemo.put(businessKey,candidates,now,this.candidateExpiry);
      this.scheduleCandidateWake(output.expiry);
    } catch (error) {
      if (current()) { this.candidateFailureKey=businessKey; this.nextStatus='下一集计算暂不可用，请刷新。'; }
    } finally {
      if (this.sortJobs.finish('show-candidates',token) && this.pageVisible) { this.sortedViewRevision++; this.requestPresentation(); }
    }
  }
  private progressData(query: string, live: boolean = false, prepare: boolean = false): ProgressRow[] {
    if (this.signedIn && !this.activeCloud()) { return []; }
    const now=Date.now();
    const businessKey=this.progressBusinessKey();
    const key=this.progressSortKey(query);
    const memo=query ? this.progressMemo : this.progressAllMemo;
    const cached=this.sortedViewRevision>=0 ? memo.get(key,now) : undefined;
    if (cached) { if (prepare) { this.scheduleCandidateWake(this.candidateExpiry); } return cached; }
    if (!prepare) { return []; }
    if (this.sortJobs.matches(query ? 'show-query' : 'show-all',JSON.stringify([this.presentationEpoch,key]))) { return []; }
    const candidates=this.candidateMemo.get(businessKey,now);
    if (!candidates) { this.prepareProgressCandidates(businessKey,now); return []; }
    this.scheduleCandidateWake(this.candidateExpiry);
    const ratings=this.progressPrefs.sort==='userRating' ? this.showRatingIndex() : new Map<string,number>();
    const index=query?this.progressTitleOrder:this.progressAllTitleOrder;
    const delta=index.update(candidates,this.progressTitleScope(query),now,this.progressPrefs,this.nextFilter,query,
      (row:ProgressRow)=>this.localizedProgress(row,ratings));
    if (delta!==undefined) { memo.put(key,delta,now,this.candidateExpiry); return delta; }
    const localized=candidates.map((row: ProgressRow): ProgressRow=>this.localizedProgress(row,ratings));
    const input: ProgressSortInput={rows:localized,prefs:this.progressPrefs,filter:this.nextFilter,query:query};
    this.runShowSort(input,key,now,this.candidateExpiry,candidates);
    return [];
  }
  private validateNextTarget(row: ProgressRow): boolean {
    if (!this.progressCandidateActive() || (this.signedIn && !this.activeCloud()) || this.isHidden(row.media)) { return false; }
    const target=this.nextShows.find((item: NextShow)=>item.media.id===row.media.id);
    const source=target?.source;
    if (!source) { return false; }
    const flag=this.progressFlag(row.media);
    const candidate=selectProgress(source,this.progressPrefs,flag ? [flag] : [],Date.now());
    if (!candidate || candidate.upcoming || candidate.episode.id!==row.episode.id) { return false; }
    // Same search/group eligibility as the old full-list live check, but only
    // the selected show is scanned. Disk/catalog and effective-state fences
    // in markNext remain authoritative and are not replaced by this check.
    return sortProgressCandidates([this.localizedProgress(candidate,new Map<string,number>())],this.progressPrefs,this.nextFilter,this.nextQuery).length===1;
  }
  private async runShowSort(input: ProgressSortInput, key: string, now: number, expiry: number,candidates:ProgressRow[]): Promise<void> {
    const slot = input.query ? 'show-query' : 'show-all';
    const epoch = this.presentationEpoch;
    const token = this.sortJobs.begin(slot,JSON.stringify([epoch,key]));
    if (!token) { return; }
    try {
      const rows = await showDisplay(input,this.sortJobs.consumer(slot,token));
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'progress' ||
          this.mediaMode !== 'show' || this.progressMode !== 'next' || epoch !== this.presentationEpoch ||
          (input.query && input.query !== this.nextQuery) || key !== this.progressSortKey(input.query) ||
          Date.now() < now || Date.now() >= expiry) { return; }
      const memo = input.query ? this.progressMemo : this.progressAllMemo;
      memo.put(key,rows,now,expiry);
      (input.query?this.progressTitleOrder:this.progressAllTitleOrder).seed(candidates,this.progressTitleScope(input.query),now,expiry,rows);
    } catch (error) { if (!(error instanceof ReadCancelled)) { throw new Error((error as Error).message); } }
    finally {
      if (this.sortJobs.finish(slot,token) && this.pageVisible) { this.sortedViewRevision++; this.requestPresentation(false); }
    }
  }
  private nextFiltered(): ProgressRow[] { return this.progressData(this.nextQuery); }

  private nextEntries(): ProgressEntry[] {
    return progressEntries(progressSections(this.nextFiltered(), this.progressPrefs));
  }

  private nextPages(): number { return Math.max(1, Math.ceil(this.nextEntries().length / this.collectionPageSize)); }
  private nextSlice(): ProgressEntry[] {
    const entries = this.nextEntries();
    return entries;
  }

  private watchScope():string{return JSON.stringify([this.currentProgressScope(),this.viewScope(),this.clientId,this.activeCloud()?.generation??-1,this.detailRevision]);}
  private chooseWatchTime(release:string,commit:(at:number)=>void):void{
    const scope=this.watchScope(),token=this.watchSelection.begin(scope);
    const apply=(at:number):void=>{
      if(!this.pageVisible||!this.watchSelection.consume(this.watchScope(),token)){return;}
      if(!validWatchTime(at,Date.now())){this.progressOptionStatus='观看时间无效或尚未到达。';return;}
      commit(at);
    };
    if(this.progressWatchMode==='now'){apply(Date.now());return;}
    try{
      const released=releaseWatchTime(release,Date.now());
      const choices:SheetInfo[]=[
        {title:'现在',action:()=>{apply(Date.now());}},
        {title:'自定义日期与时间',action:()=>{
          if(!this.watchSelection.current(this.watchScope(),token)){return;}
          try{this.getUIContext().showDatePickerDialog({selected:new Date(),end:new Date(),showTime:true,useMilitaryTime:true,onDateAccept:(value:Date)=>{apply(value.getTime());},onCancel:()=>{if(this.watchSelection.current(this.watchScope(),token)){this.watchSelection.clear();}}});}
          catch(error){this.watchSelection.clear();this.progressOptionStatus='日期选择器无法打开。';}
        }}
      ];
      if(released){choices.push({title:'上映日 · '+new Date(released).toLocaleString(),action:()=>{apply(released);}});}
      this.getUIContext().showActionSheet({title:'观看日期',message:'确认实际观看时间',alignment:DialogAlignment.Bottom,autoCancel:true,sheets:choices,cancel:()=>{if(this.watchSelection.current(this.watchScope(),token)){this.watchSelection.clear();}}});
    }catch(error){this.watchSelection.clear();this.progressOptionStatus='观看日期选择无法打开，未写入记录。';}
  }
  private async toggleWatchMode():Promise<void>{
    const next=this.progressWatchMode==='ask'?'now':'ask';
    try{await this.settings?.saveProgressWatchMode(next);this.progressWatchMode=next;}catch(error){this.progressOptionStatus='观看日期设置保存失败。';}
  }
  private async toggleEpisodeHidden():Promise<void>{
    const next=!this.progressEpisodeHidden;
    try{await this.settings?.saveProgressEpisodeHidden(next);this.progressEpisodeHidden=next;this.requestPresentation(false);}catch(error){this.progressOptionStatus='剧透设置保存失败。';}
  }
  private progressEpisodeLabel(row:ProgressRow):string{
    return collectionSpoilerText(this.displayEpisode(row.media,row.episode.season,row.episode.id,row.episode.title),this.progressEpisodeHidden,this.progressRevealed.has(this.progressRevealKey(row,'title')));
  }
  private progressRatingLabel(row:ProgressRow):string{
    return progressRatingSpoilerText(this.progressPrefs.sort,row.fresh,row.upcoming,row.rating,row.userRating,this.progressRatingHidden,this.progressRevealed.has(this.progressRevealKey(row,'rating')));
  }
  private progressRevealKey(row:ProgressRow,field:string):string{
    return JSON.stringify([this.currentProgressScope(),row.media.id,row.episode.id,field]);
  }
  private revealProgress(row:ProgressRow,field:string):void{
    if(!this.progressTapReveal){return;}
    this.progressRevealed.add(this.progressRevealKey(row,field));
    this.refreshPresentationRows([row.media.id]);
  }
  private async toggleProgressSpoiler(field:string):Promise<void>{
    try{if(field==='rating'){const value=!this.progressRatingHidden;await this.settings?.saveProgressRatingHidden(value);this.progressRatingHidden=value;}
      else{const value=!this.progressTapReveal;await this.settings?.saveProgressTapReveal(value);this.progressTapReveal=value;}
      this.progressRevealed.clear();this.requestPresentation(false);
    }catch(error){this.progressOptionStatus='剧透设置保存失败。';}
  }
  private async markNext(row: ProgressRow,watchedAt:number=Date.now()): Promise<void> {
    if(!validWatchTime(watchedAt,Date.now())){return;}
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
        !this.validateNextTarget(row)) { return; }
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
      if (!current() || !this.validateNextTarget(row)) { return; }
      this.invalidateSync();
      // Same guarded write path as detail. No direct remote request.
      await store.mark(row.media.id, [row.episode.id], true, auto && this.autoActive() ? auto.uuid : '',watchedAt);
      saved = true;
      this.invalidateNextShows(row.media.id);
      this.requestProjection();
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
    this.movieRatingRequest.reset();this.movieCollectionRatingStatus='';
    this.movieRatingKey = '';
    this.movieRatingRows = [];
    this.clearLocalCalendar(true);
    this.calendarBusy = false;
    this.calendarPage = 1;
    this.calendarStatus = '';
  }

  private publishMovieSource(snapshot: CloudLibrary): void {
    if (this.activeCloud() !== snapshot || !snapshot.movieDetails) { return; }
    if (this.movieCalendarCurrent()) { return; }
    this.movieRatingRequest.reset();this.movieCollectionRatingStatus='';
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
        this.cloudBusy || this.authBusy || this.syncBusy || this.setupBusy) { return; }
    const key = JSON.stringify([scope,session.clientId,session.generation,source.activity]);
    if (this.movieRatingKey === key) { return; }
    const ticket=this.movieRatingRequest.begin(key);if(!ticket){return;}
    this.movieRatingKey = key;
    this.movieCollectionRatingStatus='正在读取电影个人评分…';
    const current = (): boolean => this.movieRatingRequest.current(ticket)&&this.activeCloud() === source && this.movieCalendarData === snapshot &&
      this.currentProgressScope() === scope && traktAuth.isCurrent(session.clientId,session.generation);
    try {
      const ratings = await this.sharedTitleRatings('movie',scope);
      if (!current()) { return; }
      const values = new Map<string,number>();
      for (const rating of ratings) { values.set(rating.id,rating.value); }
      this.movieRatingRows = ratings;
      this.movieCollectionRatingStatus = '';
      const movies = snapshot.movies.map((row: PersonalMovie): PersonalMovie => ({
        media: row.media, released: row.released, cloudWatched: row.cloudWatched, cloudWatchlist: row.cloudWatchlist,
        localOnly: row.localOnly, runtime: row.runtime, rating: row.rating, addedAt: row.addedAt,
        dateUncertain: row.dateUncertain, userRating: values.get(row.media.id) }));
      this.movieCalendarData = { generation: snapshot.generation, activity: snapshot.activity, movies: movies, ratingsComplete: true };
    } catch (error) {
      if (current()) { this.movieCollectionRatingStatus = '电影个人评分读取失败；可重试。'; }
    } finally {
      if (!this.movieRatingRequest.finish(ticket)) { return; }
      if (this.activeCloud() !== source || this.currentProgressScope() !== scope ||
          (this.movieCalendarData !== snapshot && this.movieCalendarData?.ratingsComplete !== true)) {
        if (this.movieRatingKey === key) { this.movieRatingKey = ''; }
        this.scheduleLazyRows();
      }
    }
  }

  private calendarAccountKey(): string {
    const scope=this.currentProgressScope();
    return scope ? JSON.stringify([this.clientId,scope,this.activeCloud()?.generation ?? -1]) : '';
  }
  private calendarScopeKey(): string {
    const account=this.calendarAccountKey();
    return account ? JSON.stringify([account,this.activeCloud()?.activity ?? '']) : '';
  }
  private clearLocalCalendar(resetIndex: boolean = false): void {
    this.calendarSourceScope='';
    this.calendarSources=[];
    this.calendarRepairTargets=[];
    this.calendarSourceVersion++;
    this.calendarMemo.clear();
    this.calendarRows.work.hydrate.cancel();this.calendarHydrationKey='';
    this.calendarRows.replace([],[],[]);
    this.calendarSummary={key:'',total:0,page:1,pages:1};
    if (resetIndex) { this.calendarIndex.clear(); }
  }
  private publishLocalCalendar(result: LibraryProjection): void {
    const scope=this.calendarScopeKey();
    if (!scope) { this.clearLocalCalendar(true); return; }
    this.calendarIndex.begin(this.calendarAccountKey());
    if (this.calendarSourceScope!==scope || this.calendarSources!==result.calendar) {
      this.calendarSourceScope=scope;
      this.calendarSources=result.calendar;
      this.calendarRepairTargets=result.repairTargets;
      this.calendarSourceVersion++;
      this.calendarMemo.clear();
      this.requestPresentation();
    }
  }
  private calendarCurrent(): boolean {
    if (this.mediaMode==='movie') { return this.movieCalendarCurrent(); }
    return !!this.calendarSourceScope && this.calendarSourceScope===this.calendarScopeKey();
  }
  private calendarKey(): string {
    return JSON.stringify([this.calendarScopeKey(),this.calendarSourceVersion,this.libraryRevision,this.hiddenVersion('show'),
      this.showCalendarMode,this.calendarPremieres,this.calendarQuery,this.presentationLanguage,this.metaVersion('show'),
      this.calendarQuery ? this.titleVersion('show') : 0,this.calendarQuery ? this.episodeSearchRevision : 0,calendarClockKey(Date.now())]);
  }
  private calendarDisplayKey(): string { return JSON.stringify([this.calendarKey(),this.calendarPage,this.calendarProtect]); }
  private calendarEntries(): CalendarEntry[] | undefined {
    if (!this.calendarCurrent()) { return []; }
    return this.calendarViewRevision>=0 ? this.calendarMemo.get(this.calendarKey(),Date.now()) : undefined;
  }
  private calendarSlice(): CalendarEntry[] { return this.calendarEntries() ?? []; }
  private calendarEpisodeTitle(row: CalendarEntry): string {
    if (row.synthetic) { return '首播日期（待确认分集）'; }
    return calendarTitleHidden(row,this.calendarProtect) ? '' : this.displayEpisode(row.media,row.season,row.episodeId,row.episodeTitle);
  }
  private prepareCalendar(): CalendarEntry[] | undefined {
    const cached=this.calendarEntries();
    if (cached!==undefined) { return cached; }
    const key=this.calendarKey();
    const token=this.sortJobs.begin('calendar',key);
    if (token) { this.runCalendarProjection(key,token); }
    return undefined;
  }
  private async runCalendarProjection(key: string,token: number): Promise<void> {
    const current=(): boolean=>this.sortJobs.current('calendar',token) && this.pageVisible && !this.selectedMedia &&
      this.tab==='progress' && this.mediaMode==='show' && this.progressMode==='calendar' && this.calendarCurrent() && key===this.calendarKey();
    const now=Date.now();
    let retry=true;
    try {
      const inputs: CalendarInput[]=this.calendarSources.map((source: CalendarSource): CalendarInput=>({
        source:source,release:source.queued ? this.titleIndex.get(source.media.id)?.collection?.release ?? '' : ''
      }));
      const plan=this.calendarIndex.plan(inputs);
      const titles: CalendarText[]=[];
      const episodes: CalendarText[]=[];
      if (this.calendarQuery && this.presentationLanguage==='zh') {
        for (const source of this.calendarSources) {
          const title=this.titleIndex.get(source.media.id)?.text.title ?? '';
          if (title) { titles.push({key:source.media.id,title:title}); }
        }
        this.episodeNameIndex.forEach((title: string,id: string): void => { episodes.push({key:id,title:title}); });
      }
      const hidden=this.currentCollectionState().hidden.map((row: HiddenEntry)=>row.media.id);
      const members=this.personalLibrary().filter((row: PersonalLibraryRow)=>row.media.kind==='show' &&
        (row.queued || hasTrackingEvidence(row))).map((row: PersonalLibraryRow)=>row.media.id);
      const input: CalendarJobInput={plan:plan,now:now,mode:this.showCalendarMode,premieres:this.calendarPremieres,query:this.calendarQuery,
        hidden:hidden,members:members,titles:titles,episodes:episodes};
      const output=await calendarDisplay(input,this.sortJobs.consumer('calendar',token));
      if (!current() || Date.now()<now || Date.now()>=calendarExpiry(now)) { return; }
      this.calendarIndex.commit(inputs,output.built);
      this.calendarMemo.put(key,output.entries,now,calendarExpiry(now));
      this.calendarStatus='本地日历 · 重建 '+output.built.length+' 部 · 复用 '+(inputs.length-output.built.length)+' 部 · 日历 API 0 次';
      this.hydrateCalendarSearch();
    } catch (error) { retry=false; if (current()) { this.calendarStatus='本地日历计算失败，请刷新。'; } }
    finally { if (this.sortJobs.finish('calendar',token) && this.pageVisible) { this.calendarViewRevision++; if (retry) { this.requestPresentation(); } } }
  }
  private async hydrateCalendarSearch(): Promise<void> {
    const repo=this.presentation;
    if (!repo || !this.calendarQuery.trim() || this.presentationLanguage!=='zh' || !this.calendarCurrent()) { return; }
    const key=JSON.stringify([this.calendarSourceScope,this.calendarSourceVersion]);
    if (key===this.calendarHydrationKey) { return; }
    const lane=this.calendarRows.work.hydrate;
    const consumer=lane.begin(key);
    if(!consumer){return;}
    this.calendarHydrationKey=key;
    try {
      for (const source of this.calendarSources) {
        for (const season of source.full?.seasons ?? []) {
          if (!this.pageVisible || this.tab!=='progress' || this.progressMode!=='calendar' || this.mediaMode!=='show' ||
              !this.calendarQuery.trim() || key!==JSON.stringify([this.calendarSourceScope,this.calendarSourceVersion])) {
            if (lane.current(consumer)&&this.calendarHydrationKey===key) { this.calendarHydrationKey=''; }
            return;
          }
          await repo.hydrateSeason(source.media,season.number,consumer);
        }
      }
    } catch (error) { if (lane.current(consumer) && this.calendarHydrationKey===key) { lane.finish(consumer,'hydrate');this.calendarHydrationKey=''; } }
    finally { if (lane.current(consumer)) { if(lane.snapshot().loading){lane.finish(consumer);}this.publishPresentation(); } }
  }
  private async loadCalendar(): Promise<void> {
    if (this.calendarBusy || this.authBusy || this.setupBusy || this.syncBusy) { return; }
    if (this.mediaMode==='show') {
      this.calendarPage=1;
      if (!this.calendarCurrent()) {
        this.calendarStatus='正在读取共享个人库与播出目录…';
        if (this.signedIn) { this.requestObservation(); } else { this.requestProjection(); }
      } else if (this.signedIn) { this.requestObservation(); }
      else if (this.calendarRepairTargets.length && this.clientId) { await this.repairDeviceCalendar(); }
      else { this.requestProjection(); }
      this.requestPresentation();
      return;
    }
    if (!this.signedIn || !this.clientId) { return; }
    const source=this.activeCloud();
    if (source?.movieDetails) {
      this.publishMovieSource(source);
      this.calendarStatus='使用已验证账户的个人电影资料，共 '+(this.movieCalendarData?.movies.length ?? 0)+' 部。';
    } else { this.calendarStatus='等待个人库核对及电影资料读取。'; this.requestObservation(); }
  }
  private async repairDeviceCalendar(): Promise<void> {
    const store=this.episodeStore;
    if (!store || this.signedIn || this.calendarBusy || this.localBusy || this.cloudBusy || this.saving || this.backupBusy) { return; }
    const scope=this.calendarSourceScope, client=this.clientId, revision=++this.calendarRevision;
    const targets=this.calendarRepairTargets;
    this.calendarBusy=true; this.localBusy=true;
    const current=(): boolean=>this.pageVisible && !this.signedIn && this.clientId===client && this.calendarRevision===revision &&
      this.calendarSourceScope===scope && this.calendarScopeKey()===scope && this.tab==='progress' && this.mediaMode==='show' &&
      this.progressMode==='calendar' && !this.selectedMedia && !this.backupBusy && !this.syncBusy && !this.authBusy && !this.setupBusy && !this.saving;
    try {
      for (const media of targets) {
        if (!current()) { break; }
        const before=store.readModelRevision();
        const full=await fetchFullEpisodeCatalog(media,client);
        if (!current() || store.readModelRevision()!==before) { break; }
        await store.saveObservedSchedule(full);
      }
    } catch (error) { if (current()) { this.calendarStatus='目录补齐暂停；保留已有日历，下次刷新继续。'; } }
    finally { this.localBusy=false; if (this.calendarRevision===revision) { this.calendarBusy=false; }
      if (!this.signedIn && this.clientId===client) { this.requestProjection(); } }
  }
  private changeShowCalendar(mode: string): void {
    if (mode!=='future' && mode!=='recent') { return; }
    this.showCalendarMode=mode; this.calendarPage=1; this.requestPresentation();
  }

  private chooseProgressMode(mode: string): void {
    this.watchSelection.clear();
    if (!progressTabs(this.mediaMode).includes(mode)) { return; }
    this.progressMode = mode;
    if (mode === 'next') {
      if (this.signedIn) { this.requestObservation(); } else { this.loadNextShows(); }
      if (this.mediaMode === 'movie' && !this.movieCalendarCurrent()) { this.loadCalendar(); }
    }
    if (mode === 'calendar') { if (!this.calendarCurrent()) { this.loadCalendar(); } else { this.requestPresentation(); } }
    if(mode==='history'){this.requestPresentation();if(this.signedIn){this.requestObservation();}else{this.loadNextShows();}}
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
      Button(this.progressEpisodeHidden?'分集标题：隐藏':'分集标题：显示').fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.toggleEpisodeHidden();})
      Row({space:4}){
        Button(this.progressRatingHidden?'评分：隐藏':'评分：显示').fontSize(12).height(32).layoutWeight(1).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.toggleProgressSpoiler('rating');})
        Button(this.progressTapReveal?'点击揭示：开':'点击揭示：关').fontSize(12).height(32).layoutWeight(1).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.toggleProgressSpoiler('reveal');})
      }.width('100%')
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
        this.progressOptionButton('公众评分', 'sort', 'rating', this.progressPrefs.sort === 'rating')
        this.progressOptionButton('随机', 'sort', 'random', this.progressPrefs.sort === 'random')
        this.progressOptionButton('个人评分', 'sort', 'userRating', this.progressPrefs.sort === 'userRating')
      }.width('100%')
      Row({ space: 6 }) {
        this.progressOptionButton(this.progressPrefs.descending ? '降序' : '升序', 'direction', '', false)
        this.progressOptionButton(this.progressPrefs.newAtTop ? '新集优先：开' : '新集优先：关', 'new', '', this.progressPrefs.newAtTop)
      }.width('100%')
      if (this.progressPrefs.sort==='userRating') {
        Text(this.collectionRatingStatus || (this.signedIn ? '未评分影视排在末尾。' : '登录后读取个人评分；未评分排在末尾。')).fontSize(12).width('100%')
      }
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
        (this.progressEpisodeLabel(row) ? ' · ' + this.progressEpisodeLabel(row) : '')).fontSize(14).width('100%').onClick(()=>{this.revealProgress(row,'title');})
      if(this.progressRatingLabel(row)){Text('★ '+this.progressRatingLabel(row)).fontSize(12).fontColor($r('app.color.showly_accent')).onClick(()=>{this.revealProgress(row,'rating');})}
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
        Button('详情').layoutWeight(1).fontSize(12).enabled(!this.detailUi.summaryBusy)
          .onClick(() => { this.openDetail(row.media, false, row.episode.season); })
        Button(row.upcoming ? '尚未播出' : '标记已看').layoutWeight(1).fontSize(12).backgroundColor($r('app.color.showly_accent')).fontColor($r('app.color.showly_on_accent'))
          .enabled(!row.upcoming && this.canEditLibrary() && !this.localBusy && !this.cloudBusy && !this.syncBusy && !this.saving)
          .onClick(() => { this.chooseWatchTime(row.episode.firstAired,(at:number)=>{this.markNext(row,at);}); })
      }.width('100%')
      this.showProgressActions(row.media)
    }.padding(12).borderRadius(10).width('100%').backgroundColor($r('app.color.showly_surface'))
      .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,row.episode.season,[],visible && ratio > 0,'progress','next'); })
  }

  @Builder
  nextShowsView() {
    List({ space: 10, scroller: this.showScroller }) {
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
      } else { Row({space:8}) { LoadingProgress().width(24).height(24); Text('正在更新列表…').fontSize(13) }.width('100%').justifyContent(FlexAlign.Center) }
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
      
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('show',start); })
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
    const rows=this.movieRows(); return moviePage(rows,0,rows.length,new Date());
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
    List({ space: 10, scroller: this.movieCalendarScroller }) {
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
                  Button('查看详情').fontSize(12).layoutWeight(1).enabled(!this.detailUi.summaryBusy && !this.localBusy && !this.syncBusy)
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
        
      }
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('movieCalendar',start); })
  }

  @Builder
  calendarView() {
    List({ space: 10, scroller: this.calendarScroller }) {
      ListItem() {
        Column({space:10}) {
          this.progressHeader()
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
          Text('剧集播出日历').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
          Row({space:8}) {
            Button('未来播出').layoutWeight(1).fontSize(13)
              .backgroundColor(this.showCalendarMode==='future' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
              .fontColor(this.showCalendarMode==='future' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
              .onClick(()=>{ this.changeShowCalendar('future'); })
            Button('近期播出').layoutWeight(1).fontSize(13)
              .backgroundColor(this.showCalendarMode==='recent' ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
              .fontColor(this.showCalendarMode==='recent' ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
              .onClick(()=>{ this.changeShowCalendar('recent'); })
          }.width('100%')
          Text(this.showCalendarMode==='recent' ? '最近3个自然月（不含今天）' : '从当地今天起的已知播出安排').fontSize(12).width('100%')
          Row({space:8}) {
            Button(this.calendarPremieres ? '仅首播：开' : '仅首播：关').layoutWeight(1).fontSize(12)
              .onClick(()=>{ this.calendarPremieres=!this.calendarPremieres; this.calendarPage=1; })
            Button(this.calendarProtect ? '剧透保护：开' : '剧透保护：关').layoutWeight(1).fontSize(12)
              .onClick(()=>{ this.calendarProtect=!this.calendarProtect; })
          }.width('100%')
          TextInput({placeholder:'搜索剧集、分集或日期',text:this.calendarQuery})
            .onChange((value: string)=>{ this.calendarQuery=value; this.calendarPage=1; })
          Button(this.calendarBusy ? '补齐目录中…' : '刷新个人资料').enabled(!this.calendarBusy && !this.authBusy && !this.syncBusy && !this.setupBusy)
            .onClick(()=>{ this.loadCalendar(); })
          if (this.calendarStatus) { Text(this.calendarStatus).fontSize(12).width('100%') }
          if (!this.calendarCurrent()) {
            Text('等待当前账户或本机个人库核对；不显示其他账户日历。').fontSize(12).width('100%')
          } else {
            if (this.calendarRepairTargets.length) { Text('部分目录待补齐 '+this.calendarRepairTargets.length+' 部；以下为已知安排，不代表完整结果。').fontSize(12).width('100%') }
            if (this.signedIn && !this.cloudFresh) { Text('使用已核对账户的上次缓存（非实时）。').fontSize(12).width('100%') }
            if (this.calendarSummary.key===this.calendarDisplayKey()) {
              Text('已知播出 '+this.calendarSummary.total+' 条').fontSize(13).width('100%')
              if (!this.calendarSummary.total && !this.calendarRepairTargets.length) { Text('此范围暂无已知播出安排。').fontSize(13).width('100%') }
            } else { Text('正在更新日历列表…').fontSize(13).width('100%') }
          }
        }.width('100%')
      }
      if (this.calendarCurrent()) {
        LazyForEach(this.calendarRows,(row: CalendarEntry)=>{
          ListItem() {
            Column({space:6}) {
              if (row.header) { Text(row.header).fontSize(18).fontWeight(FontWeight.Medium).width('100%') }
              Text(row.day+' · '+row.time).fontSize(13).fontColor($r('app.color.showly_secondary')).width('100%')
              Row({space:8}) {
                this.posterImage(row.media,54,81)
                Column({space:4}) {
                  Text(this.displayTitle(row.media)).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
                  Text('S'+row.season+'E'+row.number+(this.calendarEpisodeTitle(row) ? ' · '+this.calendarEpisodeTitle(row) : '')).fontSize(14).width('100%')
                  Text(row.synthetic ? '仅展示首播日期' : row.state==='watched' ? '已看' : row.state==='unknown' ? '观看状态未知' : '未看').fontSize(12).width('100%')
                  if (row.queued) { Text('待看列表').fontSize(12).width('100%') }
                }.layoutWeight(1)
              }.width('100%')
              Button('查看详情').fontSize(12).enabled(!this.detailUi.summaryBusy && !this.localBusy && !this.syncBusy)
                .onClick(()=>{ this.openDetail(row.media,false,row.synthetic ? 0 : row.season); })
            }.padding(12).width('100%').borderRadius(10).backgroundColor($r('app.color.showly_surface'))
              .onVisibleAreaChange([0],(visible: boolean,ratio: number)=>{ this.viewportChanged(row.media,row.synthetic ? 0 : row.season,[],visible && ratio>0,'progress','calendar',row.key); })
          }
        },(row: CalendarEntry)=>this.calendarRows.keyFor(row.key))
        
      }
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('calendar',start); })
  }

  private movieSortKey(query: string, utc: string, includeTitles:boolean=true,includeBusiness:boolean=true): string {
    return JSON.stringify([this.displayRevisions.movie,includeBusiness ? this.libraryRevision : 0,this.currentProgressScope(),this.activeCloud()?.generation ?? -1,
      this.presentationLanguage,includeTitles && this.presentationLanguage==='zh' && (query || this.movieProgressOptions.sort==='title' || this.movieProgressOptions.sort==='userRating') ? this.titleVersion('movie') : 0,this.progressFlagScope,this.flagVersion('movie'),this.hiddenVersion('movie'),
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
    const order=query?this.movieTitleOrder:this.movieAllTitleOrder;
    const expiry=Date.parse(utc+'T00:00:00Z')+86400000;
    if(!live){
      const flags=this.progressFlagScope===this.currentProgressScope()?this.progressFlags:[];
      const pins=new Set<string>(flags.filter((f:ProgressFlag)=>f.pinned).map((f:ProgressFlag)=>f.id));
      const delta=order.update(this.movieSortKey(query,utc,false),now,(x:MovieProgressSource):MovieProgressSource=>({row:x.row,metadata:x.metadata,translation:this.presentationLanguage==='zh'?this.titleIndex.get(x.row.media.id)?.text.title??'':''}),
        (x:MovieProgressSource)=>movieSortEligible(x,utc,query),(a:MovieProgressSource,b:MovieProgressSource)=>compareMovieSources(a,b,this.movieProgressOptions,pins,this.movieRandomSeed));
      if(delta){memo.put(key,delta,now,expiry);return delta;}
    }
    const metadata = this.movieMetadataIndex();
    const sources: MovieProgressSource[] = [];
    for (const row of this.personalLibrary()) {
      const movie = metadata.get(row.media.id);
      if (this.isHidden(row.media) || !movie || movie.localOnly || movie.dateUncertain || row.media.kind !== 'movie') { continue; }
      const translation = this.presentationLanguage === 'zh' ?
        (this.presentationPublished>=0 ? this.titleIndex.get(row.media.id)?.text.title ?? '' : '') : '';
      sources.push({ row: row, translation: translation,
        metadata: { id: row.media.id, released: movie.released, year: movie.media.year,
          runtime: movie.runtime, rating: movie.rating, addedAt: movie.addedAt, userRating: movie.userRating } });
    }
    const flags = this.progressFlagScope === this.currentProgressScope() ? this.progressFlags : [];
    if (live) {
      const rows = projectMovieProgress(sources,flags,this.movieProgressOptions,utc,query,this.movieRandomSeed);
      memo.put(key,rows,now,expiry);
      return rows;
    }
    const pins=new Set<string>(flags.filter((f:ProgressFlag)=>f.pinned).map((f:ProgressFlag)=>f.id));
    const reconciled=order.reconcile(this.movieSortKey(query,utc,false),this.movieSortKey(query,utc,false,false),now,expiry,sources,sameMovieSource,
      (x:MovieProgressSource)=>movieSortEligible(x,utc,query),(a:MovieProgressSource,b:MovieProgressSource)=>compareMovieSources(a,b,this.movieProgressOptions,pins,this.movieRandomSeed),
      (id:string)=>this.personalLibraryIndex.ordinal(id));
    if(reconciled){memo.put(key,reconciled,now,expiry);return reconciled;}
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
      const rows = await movieDisplay(input,this.sortJobs.consumer(slot,token));
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'progress' ||
          this.mediaMode !== 'movie' || this.progressMode !== 'next' || epoch !== this.presentationEpoch || !this.movieCalendarCurrent() ||
          (input.query && input.query !== this.movieProgressQuery) || key !== this.movieSortKey(input.query,input.utc) ||
          Date.now() < now || Date.now() >= expiry) { return; }
      const memo = input.query ? this.movieMemo : this.movieAllMemo;
      const order=input.query?this.movieTitleOrder:this.movieAllTitleOrder;
      order.seed(this.movieSortKey(input.query,input.utc,false),now,expiry,input.sources,rows,this.movieSortKey(input.query,input.utc,false,false),
        (id:string)=>this.personalLibraryIndex.ordinal(id));
      memo.put(key,rows,now,expiry);
    } catch (error) { if (!(error instanceof ReadCancelled)) { throw new Error((error as Error).message); } }
    finally {
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

  private async markMovieProgress(item: Media,watchedAt:number=Date.now()): Promise<void> {
    if(!validWatchTime(watchedAt,Date.now())){return;}
    if (!this.pageVisible || this.tab !== 'progress' || this.mediaMode !== 'movie' ||
        this.progressMode !== 'next' || this.selectedMedia || this.authBusy || this.setupBusy ||
        this.backupBusy || this.localBusy || this.calendarBusy || this.progressPrefsBusy ||
        !this.canEditLibrary() || !this.activeCloud()) { return; }
    const row = this.movieProgressRows('',true).find((candidate: PersonalLibraryRow) => candidate.media.id === item.id);
    if (!row) { return; }
    await this.changeMediaIntent(row.media, 'movie', 'yes',watchedAt);
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
    List({ space: 10, scroller: this.movieScroller }) {
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
              this.posterImage(row.media, 80, 120)
              Column({ space: 4 }) {
                Text(this.displayTitle(row.media)).width('100%').onClick(() => { this.openDetail(row.media); })
                this.showProgressActions(row.media)
              }.layoutWeight(1)
              Button('标记已看').fontSize(12)
                .enabled(this.canEditLibrary() && this.ready && !this.saving && !this.cloudBusy && !this.syncBusy &&
                  !this.calendarBusy && !this.progressPrefsBusy)
                .onClick(() => { this.chooseWatchTime(this.movieMetadataIndex().get(row.media.id)?.released??'',(at:number)=>{this.markMovieProgress(row.media,at);}); })
            }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.showly_surface'))
          }
          .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'progress','next'); })
        }, (row: PersonalLibraryRow) => this.movieRowsSource.keyFor(row.media.id))
        
      }
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('movie',start); })
  }

  @Builder
  progressHeader() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.mediaMode === 'show' ? '剧集进度' : '电影进度').fontSize(25).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('同步').fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(() => { this.navigate('account'); })
      }.width('100%')
      Row({ space: 6 }) {
        this.progressModeButton(this.mediaMode === 'show' ? '下一集' : '待看进度', 'next')
        this.progressModeButton(this.mediaMode === 'show' ? '日历' : '上映日历', 'calendar')
        if (this.mediaMode === 'show') { this.progressModeButton('历史', 'history') }
      }.width('100%')
      if(this.progressMode==='next'){
        Button(this.progressWatchMode==='ask'?'观看日期：每次询问':'观看日期：现在').fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.toggleWatchMode();})
        if(this.progressOptionStatus){Text(this.progressOptionStatus).fontSize(12).width('100%')}
      }
    }.width('100%')
  }

  private historyRowKey(row:HistoryEntry):string{
    const ep=row.episode;return ep?JSON.stringify([row.key,ep.at,this.displayTitle(ep.media),this.displayEpisode(ep.media,ep.season,ep.id,ep.title),this.artwork(ep.media)]):row.key;
  }
  private async selectHistoryPeriod(value:string):Promise<void>{
    if(!validHistoryPeriod(value)){return;}
    try{await this.settings?.saveHistoryPeriod(value);this.historyUi={period:value,query:this.historyUi.query,loading:true,error:'',count:0};this.requestPresentation();}
    catch(error){this.historyUi={period:this.historyUi.period,query:this.historyUi.query,loading:false,error:'筛选保存失败。',count:0};}
  }
  @Builder
  progressView() {
    List({space:8,scroller:this.historyScroller}){
      ListItem(){
        Column({space:8}){
          this.progressHeader()
          TextInput({placeholder:'搜索剧集、分集或日期',text:this.historyUi.query}).onChange((value:string)=>{this.historyUi={period:this.historyUi.period,query:value,loading:true,error:'',count:0};this.requestPresentation();})
          Button('时间范围 · '+(HISTORY_PERIODS.find((p:HistoryPeriodOption)=>p.key===this.historyUi.period)?.label??'全部时间')).fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{
            try{const choices:SheetInfo[]=HISTORY_PERIODS.map((p:HistoryPeriodOption):SheetInfo=>({title:p.label,action:()=>{if(this.scrollSlot()==='history'){this.selectHistoryPeriod(p.key);}}}));this.getUIContext().showActionSheet({title:'观看历史时间范围',message:'选择时间范围',alignment:DialogAlignment.Bottom,autoCancel:true,sheets:choices});}
            catch(error){this.historyUi={period:this.historyUi.period,query:this.historyUi.query,loading:false,error:'无法打开时间筛选。',count:this.historyUi.count};}
          })
          Text('仅显示已知最后观看时间的分集；未知记录不补造。').fontSize(12).width('100%')
          if(this.historyUi.error){Text(this.historyUi.error).fontSize(13);Button('重试').onClick(()=>{this.historyOwner.clear();this.requestPresentation();})}
          else if(this.historyUi.loading||this.localBusy||this.cloudBusy){LoadingProgress().width(24).height(24)}
          else if(!this.historyUi.count){Text('暂无符合条件且日期可验证的观看记录。').fontSize(13)}
        }.width('100%')
      }
      LazyForEach(this.historyRows,(row:HistoryEntry)=>{
        ListItem(){
          if(row.episode){this.historyEpisodeCard(row.episode)}
          else{Text(row.day).fontSize(17).fontWeight(FontWeight.Medium).width('100%')}
        }
      },(row:HistoryEntry)=>this.historyRows.keyFor(row.key))
    }.width('100%').height('100%').padding(16).onScrollIndex((start:number,end:number,center:number)=>{this.onListScroll('history',start);})
  }
  @Builder
  historyEpisodeCard(row:HistoryEpisode){
    Row({space:10}){
      this.posterImage(row.media,64,96)
      Column({space:5}){
        Text(this.displayTitle(row.media)).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
        Text('S'+row.season+'E'+row.number+' · '+this.displayEpisode(row.media,row.season,row.id,row.title)).fontSize(13).width('100%')
        Text(new Date(row.at).toLocaleString()).fontSize(12).fontColor($r('app.color.showly_secondary')).width('100%')
      }.layoutWeight(1)
    }.width('100%').padding(8).borderRadius(8).backgroundColor($r('app.color.showly_surface')).onClick(()=>{this.openDetail(row.media,false,row.season);})
    .onVisibleAreaChange([0],(visible:boolean,ratio:number)=>{this.viewportChanged(row.media,row.season,[],visible&&ratio>0,'progress','history','history:'+row.id);})
  }

  private async refreshPage(): Promise<void> {
    this.candidateFailureKey='';
    if(this.tab==='library'){this.collectionRecovery().refresh();this.publishCollectionUi(this.collectionUi.recent,this.collectionUi.other,'',this.collectionUi.retrying);}
    if (this.tab === 'library' || (this.tab==='progress' && this.mediaMode==='show' && this.progressPrefs.sort==='userRating')) { this.showRatingRequest.reset();this.collectionRatingStatus='';this.collectionRatingKey = ''; this.collectionRatings = []; }
    if (this.mediaMode === 'movie') {
      this.movieRatingRequest.reset();this.movieCollectionRatingStatus='';
      this.movieRatingKey = '';
      this.movieRatingRows = [];
    }
    this.presentation?.retryArtwork();
    this.presentationAttempts.retry(); this.presentationQueues.clear();
    presentationGate.manualProbe();
    this.presentationStatus = '';
    try {
      if (this.selectedMedia) {
        if (this.episodePage) { await this.loadLocalEpisodes(this.selectedMedia,true); }
        else { await this.openDetail(this.selectedMedia, true); }
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
    if (cached&&this.personalLibraryIndex.matches(cloud,this.libraryEvidence,this.cloudLocalAllowed)) { return cached; }
    if(this.personalLibraryIndex.matches(cloud,this.libraryEvidence,this.cloudLocalAllowed)){
      const rows=this.personalLibraryIndex.rowsView();this.libraryMemo.put(key,rows,now,Number.MAX_SAFE_INTEGER);return rows;
    }
    const cloudShows = (cloud?.shows ?? []).map((show: ShowProgress): LibraryShowEvidence => {
      const media: Media = { id: show.id, title: show.title, kind: 'show', year: show.year ?? 0, watched: false };
      return { media: media, watchedEpisodes: show.watchedEpisodes };
    });
    const localShows = this.libraryEvidence.filter((show: LibraryShowEvidence) => cloud ? show.merged === true : !show.merged);
    const records=cloud&&!this.cloudLocalAllowed?[]:this.mediaRecords;
    const rows=buildPersonalLibrary(records,cloud?.watchedMovies??[],cloud?.watchlist??[],cloudShows,localShows);
    this.personalLibraryIndex.seed(records,cloud?.watchedMovies??[],cloud?.watchlist??[],cloudShows,localShows,
      cloud,this.libraryEvidence,this.cloudLocalAllowed,rows);
    this.libraryIndex.clear();
    for(const row of rows){this.libraryIndex.set(row.media.id,row);}
    this.mediaInput.acknowledgeLibrary(this.mediaInput.version());
    this.libraryMemo.put(key, rows, now, Number.MAX_SAFE_INTEGER);
    return rows;
  }

  private statisticsInputs(kind:string):StatisticsInput[]{
    const scope=this.currentProgressScope();if(!scope){return [];}
    const library=this.personalLibrary(),state=this.currentCollectionState();
    const mine=collectionMembers(library,state,kind,'mine','all'),members=new Map<string,Media>(),mineIds=new Set<string>();
    for(const row of mine){members.set(row.media.id,row.media);mineIds.add(row.media.id);}
    if(kind==='show'){for(const row of collectionMembers(library,state,kind,'queue','all')){if(!members.has(row.media.id)){members.set(row.media.id,row.media);}}
      for(const hidden of state.hidden){if(hidden.media.kind==='show'&&!members.has(hidden.media.id)){members.set(hidden.media.id,hidden.media);}}}
    const sources=new Map<string,NextShow>();for(const row of this.nextShows){sources.set(row.media.id,row);}
    const movies=this.movieMetadataIndex(),result:StatisticsInput[]=[];
    for(const media of members.values()){if(!isTraktMedia(media)){continue;}const next=sources.get(media.id),meta=this.titleIndex.get(media.id)?.collection,movie=movies.get(media.id);
      result.push({media:media,mine:mineIds.has(media.id),source:next?.source,sourceKey:next?.sourceStateKey&&next?.sourceCatalogKey?JSON.stringify([next.sourceStateKey,next.sourceCatalogKey]):'',observed:next?.completed??0,meta:meta??(movie?.runtime!==undefined?{genres:[],network:'',release:movie.released,runtime:movie.runtime}:undefined),runtimes:[]});}
    return result;
  }
  private async customListRatings(scope:string):Promise<CollectionRating[]>{
    const rows=await Promise.all([this.sharedTitleRatings('show',scope),this.sharedTitleRatings('movie',scope)]);return rows[0].concat(rows[1]);
  }
  private async statisticsRatings(kind:string,scope:string):Promise<StatisticsRating[]>{
    return this.sharedTitleRatings(kind,scope);
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
    this.collectionSpoilers=this.settings.loadCollectionSpoilers(this.mediaMode,this.collectionFilter);this.collectionRevealed=[];
    this.collectionGenreDraft = this.collectionOptions.genres.join(',');
    this.collectionNetworkDraft = this.collectionOptions.networks.join(',');
  }
  private async editCollectionSpoilers(field:string):Promise<void>{
    const settings=this.settings,kind=this.mediaMode,section=this.collectionFilter,scope=this.collectionRecoveryScope();
    if(!settings){return;}
    const old=this.collectionSpoilers;
    const next:CollectionSpoilers={description:field==='description'?!old.description:old.description,rating:field==='rating'?!old.rating:old.rating,reveal:field==='reveal'?!old.reveal:old.reveal};
    try{
      await settings.saveCollectionSpoilers(kind,section,next);
      if(scope===this.collectionRecoveryScope()){this.collectionSpoilers=next;this.collectionRevealed=[];this.requestPresentation(false);}
    }catch(error){this.collectionRuleStatus='剧透保护设置保存失败。';}
  }
  private revealCollection(id:string,field:string):void{
    const key=id+':'+field;
    if(this.collectionSpoilers.reveal&&!this.collectionRevealed.includes(key)){
      this.collectionRevealed=[...this.collectionRevealed,key];this.requestPresentation(false);
    }
  }
  private collectionDescription(item:Media):string{
    const text=this.titleIndex.get(item.id)?.text.overview??'';
    return collectionSpoilerText(text,this.collectionSpoilers.description,this.collectionRevealed.includes(item.id+':description'));
  }
  private collectionRatingText(item:Media):string{
    const rating=this.titleIndex.get(item.id)?.collection?.rating;
    return rating===undefined?'':collectionSpoilerText(rating.toFixed(1),this.collectionSpoilers.rating,this.collectionRevealed.includes(item.id+':rating'),true);
  }
  @Builder
  collectionSpoilerDetails(item:Media){
    if(this.collectionRatingText(item)){
      Text(this.collectionRatingText(item)).fontSize(12).fontColor($r('app.color.showly_secondary')).onClick(()=>{this.revealCollection(item.id,'rating');})
    }
    if(this.collectionDescription(item)){
      Text(this.collectionDescription(item)).fontSize(12).maxLines(3).textOverflow({overflow:TextOverflow.Ellipsis}).width('100%').onClick(()=>{this.revealCollection(item.id,'description');})
    }
  }
  private async toggleCollectionGenre(slug:string):Promise<void>{
    await this.editCollectionOptions('genre',toggleCollectionSelection(this.collectionOptions.genres,[slug]).join(','));
  }
  private async toggleCollectionNetwork(group:CollectionNetworkGroup):Promise<void>{
    await this.editCollectionOptions('network',toggleCollectionSelection(this.collectionOptions.networks,group.channels).join(','));
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
    if (!snapshot || !session || !scope || !this.cloudFresh || this.cloudBusy || this.syncBusy || this.authBusy) { return; }
    const key = JSON.stringify([scope,session.clientId,session.generation,snapshot.activity,kind]);
    if (this.collectionRatingKey === key) { return; }
    const ticket=this.showRatingRequest.begin(key);if(!ticket){return;}
    this.collectionRatingKey = key;
    this.collectionRatings = [];
    const current = (): boolean => this.showRatingRequest.current(ticket)&&this.currentProgressScope() === scope && this.activeCloud() === snapshot &&
      this.clientId === session.clientId && traktAuth.isCurrent(session.clientId,session.generation);
    try {
      this.collectionRatingStatus = '正在读取个人评分…';
      const ratings = await this.sharedTitleRatings(kind,scope);
      if (current()) { this.collectionRatings = ratings; this.collectionRatingStatus = ''; }
    } catch (error) { if (current()) { this.collectionRatingStatus = '个人评分读取失败；可重试。'; } }
    finally {
      const valid=current();
      if(!this.showRatingRequest.finish(ticket)){return;}
      if (!valid && this.collectionRatingKey === key) {
        this.collectionRatingKey = '';
        this.scheduleLazyRows();
      }
    }
  }
  private collectionNeedsMetadata(): boolean {
    const options = this.collectionFilter==='other'?defaultCollection():this.collectionOptions;
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
    const key = JSON.stringify([this.collectionDependencies.source(this.mediaMode),this.currentProgressScope(),this.activeCloud()?.generation??-1,
      this.activeCloud()?.activity??'',this.collectionScope,this.mediaMode,section,this.collectionRatingKey,this.movieRatingKey,this.movieCalendarCurrent()]);
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
  private collectionCandidateForRow(row:PersonalLibraryRow,section:string,indexes:CollectionIndexes=this.collectionIndexes(section)):CollectionCandidate{
    const metadata=this.titleIndex.get(row.media.id),movie=indexes.movies.get(row.media.id);
    if(!this.collectionRandomKeys.has(row.media.id)){this.collectionRandomKeys.set(row.media.id,Math.random());}
    return {row:row,translation:this.presentationLanguage==='zh'?metadata?.text.title??'':'',
      meta:metadata?.collection,added:indexes.times.get(row.media.id),recent:indexes.recent.get(row.media.id),
      userRating:indexes.ratings.get(row.media.id)??movie?.userRating,randomOrder:this.collectionRandomKeys.get(row.media.id)??0};
  }
  private collectionCandidates(rows: PersonalLibraryRow[], section: string): CollectionCandidate[] {
    const indexes=this.collectionIndexes(section);
    return rows.map((row:PersonalLibraryRow)=>this.collectionCandidateForRow(row,section,indexes));
  }
  private recentCollectionRows(): PersonalLibraryRow[] {
    if(this.collectionRecentAmount===0){return [];}
    const now = Date.now();
    const key = JSON.stringify([this.collectionDependencies.source(this.mediaMode),this.collectionDependencies.business(this.mediaMode),this.collectionScope,this.currentProgressScope(),this.mediaMode,this.collectionRecentAmount]);
    const cached = this.recentCollectionMemo().get(key,now);
    if (cached) { return cached; }
    const members = collectionMembers(this.personalLibrary(),this.currentCollectionState(),this.mediaMode,'mine','all');
    const rows = recentCollection(this.collectionCandidates(members,'mine'),this.collectionRecentAmount);
    this.recentCollectionMemo().put(key,rows,now,Number.MAX_SAFE_INTEGER);
    return rows;
  }
  private collectionSource(): PersonalLibraryRow[] { return this.collectionBase(); }
  private collectionHasFilters():boolean{
    const options=this.collectionFilter==='other'?defaultCollection():this.collectionOptions;
    return !!this.collectionQuery.trim()||this.collectionStatusFilter!=='all'||options.genres.length>0||
      (this.mediaMode==='show'&&options.networks.length>0)||(this.collectionFilter==='queue'&&options.upcoming!=='all');
  }
  private async changeCollectionRecentAmount(value:number):Promise<void>{
    const settings=this.settings;
    if(!settings||this.collectionRecentSaving||value===this.collectionRecentAmount){return;}
    this.collectionRecentSaving=true;
    try{await settings.saveCollectionRecentAmount(value);this.collectionRecentAmount=value;this.requestPresentation();}
    catch(error){this.collectionRuleStatus='最近添加数量保存失败。';}
    finally{this.collectionRecentSaving=false;}
  }
  private retryCollectionRatings():void{
    if(this.mediaMode==='movie'){
      this.movieRatingRequest.reset();this.movieRatingKey='';this.movieCollectionRatingStatus='';this.loadMovieRatings();
    }else{
      this.showRatingRequest.reset();this.collectionRatingKey='';this.collectionRatingStatus='';this.loadCollectionRatings();
    }
  }
  private collectionMetadataKey():string{
    const options=this.collectionFilter==='other'?defaultCollection():this.collectionOptions;
    return this.collectionMetadata.key(this.mediaMode,options,this.collectionFilter);
  }
  private collectionSortKey(includeTitles:boolean=true,includeBusiness:boolean=true): string {
    const options = this.collectionFilter === 'other' ? defaultCollection() : this.collectionOptions;
    return JSON.stringify([this.collectionDependencies.source(this.mediaMode),includeBusiness?this.collectionDependencies.business(this.mediaMode):0,this.collectionScope,this.currentProgressScope(),
      this.mediaMode,this.collectionFilter,this.collectionStatusFilter,this.collectionQuery,options,this.presentationLanguage,
      includeTitles && this.presentationLanguage==='zh' && (this.collectionQuery.trim() || options.sort==='title' || options.sort==='userRating') ? this.titleVersion(this.mediaMode) : 0,this.collectionMetadataKey()]);
  }
  private collectionItems(prepare: boolean = false): PersonalLibraryRow[] {
    if (this.signedIn && !this.activeCloud()) { return []; }
    const now = Date.now();
    const options = this.collectionFilter === 'other' ? defaultCollection() : this.collectionOptions;
    const key = this.collectionSortKey();
    const cached = this.sortedViewRevision >= 0 ? this.collectionItemsMemo().get(key,now) : undefined;
    if (cached) { return cached; }
    if (!prepare || this.sortJobs.matches(this.collectionSortSlot(),JSON.stringify([this.presentationEpoch,key]))) { return []; }
    if(this.collectionRecovery().needsFull()){
      const candidates=this.collectionCandidates(this.collectionSource(),this.collectionFilter);
      const rows=projectCollection(candidates,options,this.collectionFilter,this.collectionQuery,now).map((candidate:CollectionCandidate)=>candidate.row);
      let expiry=Number.MAX_SAFE_INTEGER;
      if(this.collectionFilter==='queue'&&options.upcoming!=='all'){
        expiry=Date.parse(new Date(now).toISOString().substring(0,10)+'T00:00:00Z')+86400000;
        for(const candidate of candidates){const date=Date.parse(candidate.meta?.release??'');if(date>=now){expiry=Math.min(expiry,date===now?date+1:date);}}
      }
      this.collectionTitleOrder().seed(this.collectionSortKey(false),now,expiry,candidates,rows,this.collectionSortKey(false,false),(id:string)=>this.collectionFilter==='mine'||this.collectionFilter==='queue'?this.personalLibraryIndex.ordinal(id):undefined);
      this.collectionItemsMemo().put(key,rows,now,expiry);return rows;
    }
    const delta=this.collectionTitleOrder().update(this.collectionSortKey(false),now,(x:CollectionCandidate):CollectionCandidate=>({row:x.row,translation:this.presentationLanguage==='zh'?this.titleIndex.get(x.row.media.id)?.text.title??'':'',meta:x.meta,added:x.added,recent:x.recent,userRating:x.userRating,randomOrder:x.randomOrder}),
      (x:CollectionCandidate)=>collectionSortEligible(x,options,this.collectionFilter,this.collectionQuery,now),
      (a:CollectionCandidate,b:CollectionCandidate)=>compareCollectionCandidates(a,b,options,this.collectionFilter));
    if(delta){this.collectionItemsMemo().put(key,delta,now,this.collectionTitleOrder().validUntil());return delta;}
    const candidates = this.collectionCandidates(this.collectionSource(),this.collectionFilter);
    let expiry = Number.MAX_SAFE_INTEGER;
    if (this.collectionFilter === 'queue' && options.upcoming !== 'all') {
      expiry = Date.parse(new Date(now).toISOString().substring(0,10)+'T00:00:00Z') + 86400000;
      for (const candidate of candidates) {
        const date = Date.parse(candidate.meta?.release ?? '');
        if (date >= now) { expiry = Math.min(expiry,date === now ? date + 1 : date); }
      }
    }
    const reconciled=this.collectionTitleOrder().reconcile(this.collectionSortKey(false),this.collectionSortKey(false,false),now,expiry,candidates,sameCollectionCandidate,
      (x:CollectionCandidate)=>collectionSortEligible(x,options,this.collectionFilter,this.collectionQuery,now),
      (a:CollectionCandidate,b:CollectionCandidate)=>compareCollectionCandidates(a,b,options,this.collectionFilter),
      (id:string)=>this.collectionFilter==='mine'||this.collectionFilter==='queue'?this.personalLibraryIndex.ordinal(id):undefined);
    if(reconciled){this.collectionItemsMemo().put(key,reconciled,now,expiry);return reconciled;}
    const input: CollectionSortInput = {candidates:candidates,options:options,section:this.collectionFilter,query:this.collectionQuery,now:now};
    this.runCollectionSort(input,key,expiry);
    return [];
  }
  private async runCollectionSort(input: CollectionSortInput, key: string, expiry: number): Promise<void> {
    const slot = this.collectionSortSlot();
    const epoch = this.presentationEpoch;
    const token = this.sortJobs.begin(slot,JSON.stringify([epoch,key]));
    if (!token) { return; }
    try {
      const rows = await collectionDisplay(input,this.sortJobs.consumer(slot,token));
      if (!this.sortJobs.current(slot,token) || !this.pageVisible || this.selectedMedia || this.tab !== 'library' ||
          epoch !== this.presentationEpoch || key !== this.collectionSortKey() ||
          (this.signedIn && !this.activeCloud()) || Date.now() < input.now || Date.now() >= expiry) { return; }
      this.collectionTitleOrder().seed(this.collectionSortKey(false),input.now,expiry,input.candidates,rows,this.collectionSortKey(false,false),
        (id:string)=>this.collectionFilter==='mine'||this.collectionFilter==='queue'?this.personalLibraryIndex.ordinal(id):undefined);
      this.collectionItemsMemo().put(key,rows,input.now,expiry);
    } catch (error) {
      if (!(error instanceof ReadCancelled) && this.sortJobs.current(slot,token) && this.pageVisible && this.tab==='library' && epoch===this.presentationEpoch && key===this.collectionSortKey()) {
        this.reportCollectionFailure(key,'排序',error as Error);
      }
    }
    finally {
      if (this.sortJobs.finish(slot,token) && this.pageVisible && !this.collectionRecovery().blocked(key)) { this.sortedViewRevision++; this.requestPresentation(); }
    }
  }

  private collectionEntries(): GroupEntry[] {
    const label = this.collectionFilter === 'hidden' ? '隐藏影视' : this.collectionFilter === 'queue' ? '待看清单' : '全部';
    return this.collectionItems().map((row: PersonalLibraryRow): GroupEntry => ({ key: this.collectionFilter, label: label, row: row }));
  }

  private collectionPageGroups(): CollectionGroup[] {
    const entries=this.collectionEntries(); return pageGroups(entries,1,entries.length);
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
      this.collectionSearchOpen = false;
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
    Column({space:3}) {
      Text(label).fontSize(13).fontColor(this.collectionFilter===value?$r('app.color.showly_accent'):$r('app.color.showly_secondary'))
      Divider().strokeWidth(2).color(this.collectionFilter===value?$r('app.color.showly_accent'):$r('app.color.showly_muted_surface'))
    }.layoutWeight(1).height(36).justifyContent(FlexAlign.Center).onClick(()=>{this.chooseCollection(value);})
  }

  @Builder
  collectionView() {
    List({ space: 12, scroller: this.collectionScroller }) {
      ListItem() {
        Column({ space: 12 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
      Row({ space: 8 }) {
        Text('收藏').fontSize(25).fontWeight(FontWeight.Bold).layoutWeight(1)
        Image($r('app.media.nav_ic_search')).width(36).height(36).padding(8)
          .fillColor(this.collectionSearchOpen?$r('app.color.showly_accent'):$r('app.color.showly_secondary'))
          .accessibilityText(this.collectionSearchOpen?'关闭搜索':'搜索').onClick(()=>{
          this.collectionSearchOpen=!this.collectionSearchOpen;
          if(!this.collectionSearchOpen){this.collectionQuery='';this.resetCollection();}
          this.captureCollectionView();
        })
        Button('统计').fontSize(12).height(32).onClick(()=>{this.navigate('statistics');})
        Button('列表').fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(() => { this.chooseCollection('lists'); })
      }.width('100%')
      this.librarySyncNotice()
      this.movieUndoView()
      if (this.cloudBusy || this.localBusy) { Text('正在更新收藏…').fontSize(12).width('100%') }
      else if (this.libraryNotice) { Text(this.libraryNotice).fontSize(12).width('100%') }
      Row({ space: 6 }) {
        this.collectionFilterButton(this.mediaMode === 'show' ? '我的剧集' : '我的电影', 'mine')
        this.collectionFilterButton('待看', 'queue')
        this.collectionFilterButton('隐藏', 'hidden')
        if (this.collectionUi.other) {
          this.collectionFilterButton('其他', 'other')
        }
      }.width('100%')
      if (this.collectionFilter === 'lists') {
        Text('请返回列表总览。').fontSize(12).width('100%')
      } else {
      if(this.collectionSearchOpen || this.collectionQuery.length>0){
      TextInput({ placeholder: this.mediaMode === 'show' ? '搜索收藏剧集' : '搜索收藏电影', text: this.collectionQuery })
        .onChange((value: string) => {
          this.collectionQuery = value;
          this.resetCollection();
        }).onSubmit(() => { if (this.collectionGrid) { this.loadCollectionPosters(); } })
      }
      if (this.collectionFilter !== 'other') { this.collectionRuleControls() }
      if (this.collectionRuleStatus) { Text(this.collectionRuleStatus).fontSize(12).width('100%') }
      if (this.collectionOptions.sort==='userRating' && (this.mediaMode==='movie'?this.movieCollectionRatingStatus:this.collectionRatingStatus)) {
        Row({space:6}) {
          Text(this.mediaMode==='movie'?this.movieCollectionRatingStatus:this.collectionRatingStatus).fontSize(12).layoutWeight(1)
          if((this.mediaMode==='movie'?this.movieCollectionRatingStatus:this.collectionRatingStatus).includes('失败')){Button('重试').fontSize(12).onClick(()=>{this.retryCollectionRatings();})}
        }.width('100%')
      }
      if (this.collectionFilter === 'hidden') { Text('仅本机隐藏，不删除历史、不写入 Trakt。').fontSize(12).width('100%') }
      if (this.presentationRevision>=0 && this.collectionFilter === 'mine' && this.collectionPage === 1 && !this.collectionQuery.trim() && this.collectionUi.recent.length) {
        Text('最近添加（已记录时间）').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
        Flex({wrap:FlexWrap.Wrap,justifyContent:FlexAlign.SpaceBetween}){
          ForEach(this.collectionUi.recent, (row: PersonalLibraryRow) => {
            Column({space:4}){
              if(this.collectionFanart.get(row.media.id)){
                ArtworkImage({uri:this.collectionFanart.get(row.media.id)??'',widthValue:'100%',ratio:16/9,corner:8,onFailure:(uri:string)=>{this.recentFanartFailed(row.media,uri);}})
              }else{
                Column(){Text('背景图').fontSize(12).fontColor($r('app.color.showly_secondary'))}.width('100%').aspectRatio(16/9).justifyContent(FlexAlign.Center).backgroundColor($r('app.color.showly_placeholder')).borderRadius(8)
              }
              Text(this.displayTitle(row.media)).fontSize(13).maxLines(2).width('100%')
            }.width('48%').padding({bottom:8}).onClick(()=>{this.openDetail(row.media);})
              .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'library','','recent:' + row.media.id);this.recentFanartVisible(row.media,visible&&ratio>0); })
          }, (row: PersonalLibraryRow) => 'recent:' + row.media.id + ':' + this.displayTitle(row.media)+':'+(this.collectionFanart.get(row.media.id)??''))
        }.width('100%')
      }
      if(this.collectionUi.error){
        Row({space:8}){Text(this.collectionUi.error).fontSize(12).layoutWeight(1);Button(this.collectionUi.retrying?'重试中…':'重试').fontSize(12).height(32).backgroundColor($r('app.color.showly_accent')).fontColor($r('app.color.showly_on_accent')).enabled(!this.collectionUi.retrying).onClick(()=>{this.retryCollectionDisplay();})}.width('100%')
      } else if (this.collectionSummary.key === this.collectionDisplayKey()) {
        if (!this.collectionSummary.total && !this.cloudBusy && !this.localBusy) { Text(collectionEmptyText(this.collectionHasFilters(),this.collectionFilter)).fontSize(14).width('100%').textAlign(TextAlign.Center).padding(16) }
        Text('共 ' + this.collectionSummary.total + ' 部').fontSize(14)
      } else { Row({space:8}){LoadingProgress().width(24).height(24).color($r('app.color.showly_accent'));Text('正在更新列表…').fontSize(13)}.width('100%').justifyContent(FlexAlign.Center) }
      Row({ space: 8 }) {
        Button(this.collectionGrid ? '文字列表' : '海报网格').fontSize(12).height(32).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text'))
          .onClick(() => {
            this.collectionGrid = !this.collectionGrid;
            this.captureCollectionView();
            this.scheduleLazyRows();
            if (this.collectionGrid) { this.loadCollectionPosters(); }
          })
        if (this.collectionGrid && this.collectionBusy) { Text('加载中…').fontSize(12) }
      }.width('100%')
      if (this.collectionGrid && this.collectionStatus) { Text(this.collectionStatus).fontSize(12) }
      }
        }.width('100%')
      }
      if ((!this.signedIn || this.activeCloud()) && this.collectionFilter !== 'lists') {
        if (this.mediaMode==='movie') {
          LazyForEach(this.movieCollectionRowsSource, (group: CollectionGroup) => {
            ListItem() { this.collectionGroupView(group) }
          }, (group: CollectionGroup) => this.movieCollectionRowsSource.keyFor(group.key))
        } else {
          LazyForEach(this.showCollectionRowsSource, (group: CollectionGroup) => {
            ListItem() { this.collectionGroupView(group) }
          }, (group: CollectionGroup) => this.showCollectionRowsSource.keyFor(group.key))
        }
        
      }
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('library',start); })
  }

  @Builder
  collectionSortButton(label: string, sort: string) {
    Button(label).layoutWeight(1).fontSize(12).enabled(!this.collectionEditBusy)
      .backgroundColor(this.collectionOptions.sort === sort ? $r('app.color.showly_accent') : $r('app.color.showly_muted_surface'))
      .fontColor(this.collectionOptions.sort === sort ? $r('app.color.showly_on_accent') : $r('app.color.showly_text'))
      .onClick(() => { this.editCollectionOptions('sort',sort); })
  }

  private collectionStatusLabel():string{
    if(this.mediaMode!=='show'||this.collectionFilter!=='mine'){return '全部';}
    switch(this.collectionStatusFilter){case 'watching':return '正在追';case 'finished':return '已完结';case 'upcoming':return '等待更新';case 'unclassified':return '待核实';default:return '全部';}
  }
  @Builder
  collectionRuleControls() {
    Button(this.collectionOptionsOpen?'收起筛选':'排序与筛选 · '+this.collectionStatusLabel()).fontSize(12).height(32)
      .backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text'))
      .onClick(() => {
        this.collectionOptionsOpen = !this.collectionOptionsOpen;
        if(this.collectionOptionsOpen){this.requestPresentation();}
      })
    // A lazy-list header can be detached and recycled; do not attach an
    // overlay lifecycle to it. Mount ordinary controls only after user action.
    if(this.collectionOptionsOpen){this.collectionFilterPanel()}
  }

  @Builder
  collectionFilterPanel(){
    Column({space:12}){
      Text('排序与筛选').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      Text('剧透保护').fontSize(13).width('100%')
      Row({space:4}){
        Button(this.collectionSpoilers.description?'简介：隐藏':'简介：显示').fontSize(12).layoutWeight(1).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.editCollectionSpoilers('description');})
        Button(this.collectionSpoilers.rating?'评分：隐藏':'评分：显示').fontSize(12).layoutWeight(1).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.editCollectionSpoilers('rating');})
        Button(this.collectionSpoilers.reveal?'点击揭示：开':'点击揭示：关').fontSize(12).layoutWeight(1).backgroundColor($r('app.color.showly_muted_surface')).fontColor($r('app.color.showly_text')).onClick(()=>{this.editCollectionSpoilers('reveal');})
      }.width('100%')
      if(this.mediaMode==='show'&&this.collectionFilter==='mine'){
        Text('剧集状态').fontSize(13).width('100%')
        Row({space:4}){
          this.collectionStatusButton('全部','all')
          this.collectionStatusButton('正在追','watching')
          this.collectionStatusButton('已完结','finished')
        }.width('100%')
        Row({space:4}){
          this.collectionStatusButton('等待更新','upcoming')
          this.collectionStatusButton('待核实','unclassified')
        }.width('100%')
      }
      if(this.collectionFilter==='mine'){
        Text('最近添加数量').fontSize(13).width('100%')
        Row({space:4}){
          ForEach(COLLECTION_RECENT_AMOUNTS,(amount:number)=>{
            Button(amount.toString()).layoutWeight(1).fontSize(12).enabled(!this.collectionRecentSaving)
              .backgroundColor(this.collectionRecentAmount===amount?$r('app.color.showly_accent'):$r('app.color.showly_muted_surface'))
              .fontColor(this.collectionRecentAmount===amount?$r('app.color.showly_on_accent'):$r('app.color.showly_text'))
              .onClick(()=>{this.changeCollectionRecentAmount(amount);})
          },(amount:number)=>amount.toString())
        }.width('100%')
      }
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
      Text('类型').fontSize(13).width('100%')
      Flex({wrap:FlexWrap.Wrap}){
        ForEach(COLLECTION_GENRES,(genre:CollectionGenreOption)=>{
          Button(genre.label).fontSize(12).margin(2).enabled(!this.collectionEditBusy)
            .backgroundColor(this.collectionOptions.genres.includes(genre.slug)?$r('app.color.showly_accent'):$r('app.color.showly_muted_surface'))
            .fontColor(this.collectionOptions.genres.includes(genre.slug)?$r('app.color.showly_on_accent'):$r('app.color.showly_text'))
            .onClick(()=>{this.toggleCollectionGenre(genre.slug);})
        },(genre:CollectionGenreOption)=>genre.slug)
      }.width('100%')
      Text('自定义类型（英文 slug，回车保存）').fontSize(12).width('100%')
      TextInput({ text: this.collectionGenreDraft, placeholder: '如 drama,comedy' })
        .onChange((value: string) => { this.collectionGenreDraft = value; })
        .onSubmit(() => { this.editCollectionOptions('genre',this.collectionGenreDraft); })
      if (this.mediaMode === 'show') {
        Text('电视网').fontSize(13).width('100%')
        Flex({wrap:FlexWrap.Wrap}){
          ForEach(COLLECTION_NETWORK_GROUPS,(group:CollectionNetworkGroup)=>{
            Button(group.name).fontSize(12).margin(2).enabled(!this.collectionEditBusy)
              .backgroundColor(group.channels.every((channel:string)=>this.collectionOptions.networks.includes(channel))?$r('app.color.showly_accent'):$r('app.color.showly_muted_surface'))
              .fontColor($r('app.color.showly_text')).onClick(()=>{this.toggleCollectionNetwork(group);})
          },(group:CollectionNetworkGroup)=>group.name)
        }.width('100%')
        Text('自定义频道（Trakt 原名，回车保存）').fontSize(12).width('100%')
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
      Text('未知添加时间、评分和分类不会被猜测；资料未齐时筛选结果可能不完整。').fontSize(12).width('100%')
      Button('完成').width('100%').onClick(()=>{this.collectionOptionsOpen=false;})
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.showly_surface'))
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
                ArtworkImage({uri:this.artwork(row.media),widthValue:'100%',ratio:2/3,corner:10,onFailure:(uri: string)=>{this.artworkFailed(row.media,uri);}})
              } else {
                Column() {
                  Text('海报').fontSize(13).fontColor($r('app.color.showly_secondary'))
                }.width('100%').aspectRatio(0.667).justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.showly_placeholder')).borderRadius(10)
              }
              Text(this.displayLabel(row.media)).fontSize(14).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(businessLibraryLabel(row)).fontSize(11).width('100%')
              this.collectionSpoilerDetails(row.media)
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
            this.artwork(row.media) + ':' + this.displayTitle(row.media)+':'+this.collectionRatingText(row.media)+':'+this.collectionDescription(row.media))
        }.width('100%')
      } else {
        ForEach(group.rows, (row: PersonalLibraryRow) => {
          Row({ space: 8 }) {
            this.posterImage(row.media, 80, 120)
            Column({ space: 4 }) {
              Text(this.displayLabel(row.media)).width('100%')
              Text(businessLibraryLabel(row)).fontSize(12).width('100%')
              if(row.media.kind==='show'&&row.effectiveWatched!==undefined&&row.effectiveTotal!==undefined&&row.effectiveTotal>0){
                Progress({value:Math.min(row.effectiveWatched,row.effectiveTotal),total:row.effectiveTotal,type:ProgressType.Linear}).width('100%').color($r('app.color.showly_accent'))
              }
              this.collectionSpoilerDetails(row.media)
              this.showProgressActions(row.media)
            }.layoutWeight(1).onClick(() => { this.openDetail(row.media); })
            if (!this.isHidden(row.media) && row.media.kind !== 'show' && this.canEditLibrary()) {
              Button(row.watched ? '撤销已看' : '标记已看').fontSize(12)
                .enabled(this.ready && !this.saving && !this.cloudBusy && !this.syncBusy)
                .onClick(() => { this.toggleCollectionLocal(row.media.id); })
            }
          }.width('100%')
            .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(row.media,0,[],visible && ratio > 0,'library',''); })
        }, (row: PersonalLibraryRow) => row.media.id + ':' + businessLibraryLabel(row) + ':' +
          (row.watched ? 'yes' : 'no') + ':' + this.artwork(row.media) + ':' + this.displayTitle(row.media)+':'+this.collectionRatingText(row.media)+':'+this.collectionDescription(row.media))
      }
    }.width('100%')
  }

  private async loadProgress(item: Media): Promise<void> {
    if (this.progressBusy || this.authBusy || this.setupBusy || item.kind !== 'show') {
      return;
    }
    const revision = this.detailRevision;
    const clientId = this.clientId;
    const consumer=this.detailConsumer;
    this.progressBusy = true;
    this.progress = undefined;
    this.seasonNumber = -1;
    this.progressStatus = '正在读取真实分集进度…';
    try {
      await traktAuth.restore(clientId, true);
      consumer.check();
      if (!this.pageVisible || revision!==this.detailRevision) { return; }
      const session = traktAuth.session(clientId);
      if (!session) { throw new Error('Sign in required'); }
      const progress = await readSeriesProgress(item, session,consumer);
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
      if (revision===this.detailRevision) { this.progressBusy = false; }
    }
  }

  private async translateDetail(item: Media): Promise<void> {
    if (this.selectedMedia?.id !== item.id) { return; }
    this.presentation?.retryArtwork();
    this.presentationAttempts.retry(); this.presentationQueues.clear();
    presentationGate.manualProbe();
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

  private pauseDetail(): void {
    if (!this.selectedMedia) { return; }
    this.detailResumePending=true;
    this.detailSession.clear(); this.detailConsumer=this.detailSession.consumer();
    this.detailRevision++; this.resetDetailUi();
    this.effectiveEditable=false;
    this.localSeries=undefined; this.fullSchedule=undefined;
    this.clearSeasonDetail();
    this.progress=undefined; this.progressBusy=false;
  }
  private resumeDetail(): void {
    const item=this.selectedMedia;
    if (!this.detailResumePending || !item || !this.pageVisible || this.localBusy || this.cloudBusy || this.syncBusy || this.setupBusy || this.authBusy) { return; }
    this.detailResumePending=false;
    this.detailSession.begin(this.currentSearchAccount(),item.id); this.detailConsumer=this.detailSession.consumer();
    this.beginDetailUi(item);
    if (item.kind==='show') { this.loadLocalEpisodes(item); }
    this.loadDetailRating(item); this.loadDetailFanart(item); this.loadDetailSummary(item);
  }
  private closeDetail(preserveRelated:boolean=false): void {
    this.gallerySheetOpen=false;
    this.commentSheetOpen=false;
    this.closeRating();
    if(!preserveRelated){this.relatedBack=[];this.relatedOffsets=[];}
    this.detailSession.clear(); this.detailConsumer=this.detailSession.consumer();
    this.detailResumePending=false;
    this.episodePage=false; this.clearSeasonDetail();
    this.detailScrollOffset=0;
    this.resetDetailUi();
    this.detailRevision++;
    this.localSeries = undefined;
    this.effectiveEditable = false;
    this.fullSchedule = undefined;
    this.schedulePage = 1;
    this.localSeason = -1;
    this.localStatus = '';
    this.confirmSeason = -1;
    this.progress = undefined;
    this.progressBusy=false;
    this.progressStatus = '';
    this.seasonNumber = -1;
    this.selectedMedia = undefined;
  }

  private openRelatedDetail(item:Media):void{
    if(!this.selectedMedia||this.detailUi.summaryBusy||this.localBusy||this.setupBusy||!this.clientId||!canReadDetails(item)){return;}
    this.relatedBack.push(this.selectedMedia);let offset=0;try{offset=this.detailScroller.currentOffset().yOffset;}catch(error){}this.relatedOffsets.push(offset);this.openDetail(item);
  }
  private backFromDetail():boolean{
    const previous=this.relatedBack.pop(),offset=this.relatedOffsets.pop()??0;
    if(!previous){return false;}
    this.openDetail(previous).then(()=>{const revision=this.detailRevision;this.getUIContext().postFrameCallback(new RestoreScrollFrame(()=>{if(revision===this.detailRevision&&this.selectedMedia?.id===previous.id){try{this.detailScroller.scrollTo({xOffset:0,yOffset:offset,animation:false});}catch(error){}}}));});return true;
  }
  onBackPress(): boolean {
    if(this.gallerySheetOpen){this.gallerySheetOpen=false;return true;}
    if(this.commentSheetOpen){this.commentSheetOpen=false;return true;}
    if(this.ratingSheetOpen){this.closeRating();return true;}
    if (this.episodePage && this.selectedMedia) { this.closeSeasonPage(); return true; }
    if (this.selectedMedia) {
      if(this.backFromDetail()){return true;}
      this.closeDetail();
      if ((this.tab === 'library' || (this.tab === 'progress' && this.progressMode === 'next')) && !this.nextShows.length) { this.loadNextShows(); }
      return true;
    }
    if (this.tab === 'search' || this.tab === 'cloud' || this.tab === 'account' || this.tab === 'statistics') {
      this.navigate(this.returnTab);
      return true;
    }
    return false;
  }

  private async openDetail(item: Media, reload: boolean = false, preferredSeason: number = 0): Promise<void> {
    if (this.detailUi.summaryBusy || this.localBusy || this.setupBusy || !canReadDetails(item) || (!this.clientId && item.kind !== 'show')) {
      return;
    }
    if (!this.selectedMedia) { this.rememberScroll(); }
    this.closeDetail(true);
    if (preferredSeason > 0 && item.kind === 'show') { this.localSeason = preferredSeason; this.episodePage=true; }
    this.detailRevision++;
    this.detailSession.begin(this.currentSearchAccount(),item.id); this.detailConsumer=this.detailSession.consumer();
    this.selectedMedia = item;
    this.beginDetailUi(item);
    if (item.kind === 'show') { this.loadLocalEpisodes(item); }
    this.loadDetailRating(item); this.loadDetailFanart(item);
    await this.loadDetailSummary(item,reload);
  }

  private beginDetailUi(item:Media):void{
    this.detailFanart.clear();
    this.detailOwner.begin(this.currentSearchAccount(),item.id,this.settings?.loadCollectionSpoilers(item.kind,'detail')??defaultCollectionSpoilers());this.publishDetail();
  }
  private detailCurrent(token:number,scope:string,item:Media):boolean{
    return this.pageVisible&&this.selectedMedia?.id===item.id&&scope===this.currentSearchAccount()&&this.detailOwner.current(token,scope,item.id);
  }
  private async loadDetailSummary(item: Media,reload: boolean=false): Promise<void> {
    if(this.detailUi.summaryBusy){return;}
    const token=this.detailOwner.token(),clientId=this.clientId,scope=this.currentSearchAccount(),consumer=this.detailConsumer;
    const current=():boolean=>this.detailCurrent(token,scope,item)&&this.clientId===clientId&&!consumer.cancelled();
    if(!current()){return;}
    this.detailOwner.summary(token,this.detailUi.summary,true,'正在读取影视详情…');this.publishDetail();
    try{
      if(!this.detailUi.summary){
        const cached=await this.presentation?.readCachedDetail(item,consumer);
        if(!current()){return;}
        if(cached){this.detailOwner.summary(token,cached,true,'已恢复本地资料，正在核对…');this.publishDetail();this.requestPresentation();}
      }
      if(!clientId){
        if(current()){this.detailOwner.summary(token,this.detailUi.summary,false,this.detailUi.summary?'本地缓存资料':'离线本机详情');this.publishDetail();}
        return;
      }
      const data=await readDetails(item,clientId,reload,consumer);
      if(!current()){return;}
      this.detailOwner.summary(token,data,false,'');this.publishDetail();this.requestPresentation();
      try{await this.presentation?.saveCachedDetail(item,data,consumer);}catch(error){}
    }catch(error){
      if(current()){this.detailOwner.summary(token,this.detailUi.summary,false,this.detailUi.summary?'显示本地缓存；联网更新失败，可重试。':'详情读取失败，请重试。');this.publishDetail();}
    }
  }
  private async loadDetailRating(item:Media):Promise<void>{
    if(this.detailUi.ratingBusy){return;}
    const token=this.detailOwner.token(),scope=this.currentSearchAccount(),ratingScope=this.currentProgressScope();
    const current=():boolean=>this.detailCurrent(token,scope,item)&&ratingScope===this.currentProgressScope();
    if(!current()||!ratingScope){return;}
    this.detailOwner.personalRating(token,undefined,true,'正在读取个人评分…');this.publishDetail();
    try{const rows=await this.sharedTitleRatings(item.kind,ratingScope);if(current()){const value=rows.find((r:CollectionRating)=>r.id===item.id)?.value;this.detailOwner.personalRating(token,value,false,value===undefined?'尚未评分':'');this.publishDetail();}}
    catch(error){if(current()){this.detailOwner.personalRating(token,undefined,false,'评分状态未知，可重试。');this.publishDetail();}}
  }
  private async loadDetailFanart(item:Media):Promise<void>{
    if(this.detailUi.artBusy){return;}
    const token=this.detailOwner.token(),scope=this.currentSearchAccount(),client=this.clientId;
    const current=():boolean=>this.detailCurrent(token,scope,item)&&client===this.clientId;
    if(!current()){return;}
    this.detailFanart.clear();
    this.detailOwner.artwork(token,'',true,'');this.publishDetail();
    await this.detailFanart.visible(item,client,this.context().cacheDir,this.settings,current,(rows:Map<string,string>)=>{
      if(current()){this.detailOwner.artwork(token,rows.get(item.id)??'',false,'');this.publishDetail();}
    });
    if(current()&&this.detailUi.artBusy){this.detailOwner.artwork(token,'',false,'背景图暂无或加载失败');this.publishDetail();}
  }
  private async toggleDetailSpoiler(item:Media,field:string):Promise<void>{
    const token=this.detailOwner.token(),scope=this.currentSearchAccount(),v=this.detailUi.spoilers;
    const next:CollectionSpoilers={description:field==='description'?!v.description:v.description,rating:field==='rating'?!v.rating:v.rating,reveal:field==='reveal'?!v.reveal:v.reveal};
    try{
      await this.settings?.saveCollectionSpoilers(item.kind,'detail',next);
      if(this.detailCurrent(token,scope,item)){this.detailOwner.setSpoilers(token,next);this.publishDetail();}
    }catch(error){if(this.detailCurrent(token,scope,item)){this.presentationStatus='详情剧透设置保存失败。';}}
  }
  private revealDetail(field:string):void{this.detailOwner.reveal(this.detailOwner.token(),field);this.publishDetail();}
  private detailSubtitle(item:Media):string{
    const d=this.detailUi.summary;
    const year=d?.year??item.year;return (year>0?year+' · ':'')+(item.kind==='movie'?'电影':'剧集')+(d?.status?' · '+d.status:'')+(d?.runtime?' · '+d.runtime+' 分钟':'');
  }

  private async changeMediaMode(mode: string): Promise<void> {
    this.watchSelection.clear();
    if (this.modeBusy || this.selectedMedia || (mode !== 'show' && mode !== 'movie') || mode === this.mediaMode) { return; }
    this.modeBusy = true;
    try {
      this.captureCollectionView();
      this.clearCollectionHeader();
      this.mediaMode = normalizeMode(mode);
      this.restoreCollectionView();
      this.restoreDiscoverOptions();
      this.progressMode = 'next';
      this.nextPage = 1;
      this.movieProgressPage = 1;
      this.showCalendarMode = 'future';
      this.calendarQuery = '';
      this.resetDiscover();
      // Calendar range changes do not discard account movie metadata.
      ++this.calendarRevision;
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
    this.watchSelection.clear();
    if (value==='search' || value==='account' || value==='cloud' || value==='statistics') { this.rememberScroll(); }
    if (this.tab === 'progress' || this.tab === 'discover' || this.tab === 'library') { this.returnTab = this.tab; }
    this.closeDetail();
    if (this.tab === 'discover' && value !== 'discover') { this.cancelDiscoverRead(); this.discoverBusy = false; }
    if (this.tab === 'library' && value !== 'library') {
      this.collectionOptionsOpen=false;
      if(this.collectionBusy){this.resetCollection();}
    }
    this.tab = value === 'cloud' ? 'account' : value;
    if (value === 'cloud') { this.advancedSync = true; }
    if (value === 'progress') { this.chooseProgressMode(this.progressMode); }
    if (value === 'discover' && !this.discoverBusy) { this.loadDiscover(this.discoverPage); }
    if (value === 'library' && this.episodeReady && this.ready) {
      if (this.signedIn) { this.requestObservation(); }
      else if (!this.libraryEvidence.length) { this.loadNextShows(); }
    }
    if (value === 'library' && this.collectionGrid && !this.collectionBusy) {
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
    Column({space:12}){
      DetailHeader({title:this.displayTitle(item),subtitle:this.detailSubtitle(item),poster:this.artwork(item),fanart:this.detailUi.fanart,
        onBack:()=>{if(this.backFromDetail()){return;}this.closeDetail();if((this.tab==='library'||(this.tab==='progress'&&this.progressMode==='next'))&&!this.nextShows.length){this.loadNextShows();}},
        onPosterFailure:(uri:string)=>{this.artworkFailed(item,uri);},
        onFanartFailure:(uri:string)=>{if(this.detailFanart.failed(item.id,uri)){this.detailOwner.artwork(this.detailOwner.token(),'',false,'背景图读取失败');this.publishDetail();}}})
      if(isTraktMedia(item)){
        Row({space:6}){Button('海报图库').fontSize(12).layoutWeight(1).onClick(()=>{this.openMediaGallery(item,'poster');});Button('背景图图库').fontSize(12).layoutWeight(1).onClick(()=>{this.openMediaGallery(item,'fanart');})}.width('100%')
        this.mediaStateView(item)
        ForEach([JSON.stringify([this.currentProgressScope(),item.id,this.detailRevision])],(_key:string)=>{
          CustomListsPage({scope:this.currentProgressScope(),client:this.clientId,language:this.presentationLanguage,manage:true,selectedItem:item,
            current:()=>this.pageVisible&&this.selectedMedia?.id===item.id&&JSON.stringify([this.currentProgressScope(),item.id,this.detailRevision])===_key})
        },(key:string)=>key)
      }
      if(item.kind==='show'){this.localEpisodesView(item)}
      DetailSummarySection({summary:this.detailUi.summary,kind:item.kind,overview:this.displayOverview(item,this.detailUi.summary?.overview??''),chinese:this.presentationLanguage==='zh',
        spoilers:this.detailUi.spoilers,ratingRevealed:this.detailUi.ratingRevealed,descriptionRevealed:this.detailUi.descriptionRevealed,
        onTranslate:()=>{this.translateDetail(item);},onToggle:(field:string)=>{this.toggleDetailSpoiler(item,field);},onReveal:(field:string)=>{this.revealDetail(field);}})
      ForEach([JSON.stringify([this.currentSearchAccount(),item.id,this.detailRevision])],(_key:string)=>{
        if(this.watchOptions.enabled){ForEach([this.watchOptions.region+':'+this.watchCredentialVersion],(_regionKey:string)=>{StreamingSection({item:item,client:this.clientId,region:this.watchOptions.region,version:this.watchCredentialVersion})},(k:string)=>k)}
        if(item.kind==='movie'){MovieSeriesSection({item:item,client:this.clientId,language:this.presentationLanguage,repository:this.presentation,member:(movie:Media)=>{const r=this.detailLibraryRow(movie);return r?.watched?'已观看':r?.queued?'待看':'未收藏';},onOpen:(movie:Media)=>{this.openRelatedDetail(movie);}})}
        DetailPeopleSection({item:item,client:this.clientId,scope:this.currentSearchAccount(),repository:this.presentation,cacheDir:this.context().cacheDir,language:this.presentationLanguage,members:()=>{const ids=new Set<string>();for(const row of this.personalLibrary()){if(isPersonalMember(row)){ids.add(row.media.id);}}return ids;},onOpen:(work:Media)=>{this.openRelatedDetail(work);}})
        DetailRelatedSection({item:item,client:this.clientId,scope:this.currentSearchAccount(),cacheDir:this.context().filesDir,repository:this.presentation,
          hiddenKey:this.hiddenVersion('show'),onOpen:(related:Media)=>{this.openRelatedDetail(related);}})
      },(key:string)=>key)
      Button('评论').fontSize(14).enabled(!!this.clientId).onClick(()=>{this.openComments({kind:item.kind,id:Number(item.id.substring(item.kind.length+1)),label:this.displayTitle(item)});})
      Button('我的评分').fontSize(14).enabled(!!this.currentProgressScope()&&!this.syncBusy&&!this.cloudBusy).onClick(()=>{this.openRating(item.kind,Number(item.id.substring(item.kind.length+1)),this.displayTitle(item));})
      if(this.detailUi.ratingBusy){LoadingProgress().width(24).height(24)}
      if(this.detailUi.rating!==undefined){Text('我的评分：'+this.detailUi.rating+' / 10').fontSize(15).width('100%')}
      if(this.detailUi.ratingStatus){Text(this.detailUi.ratingStatus).fontSize(12).width('100%')}
      if(this.detailUi.ratingStatus.includes('失败')||this.detailUi.ratingStatus.includes('重试')){Button('重试个人评分').fontSize(12).onClick(()=>{this.loadDetailRating(item);})}
      if(this.detailUi.artStatus){Text(this.detailUi.artStatus).fontSize(12).width('100%');Button('重试背景图').fontSize(12).onClick(()=>{this.loadDetailFanart(item);})}
      if(this.detailUi.summaryBusy){LoadingProgress().width(24).height(24)}
      if(this.detailUi.summaryStatus){Text(this.detailUi.summaryStatus).fontSize(12).width('100%')}
      Button('刷新详情').enabled(!this.detailUi.summaryBusy&&!this.setupBusy).onClick(()=>{this.loadDetailSummary(item,true);})
    }.width('100%')
  }

  @Builder
  libraryRow(item: Media) {
    Row({ space: 8 }) {
      Text(mediaLabel(item)).layoutWeight(1)
        .onClick(() => { this.openDetail(item); })
      if (this.clientId && canReadDetails(item)) {
        Button('详情').fontSize(12).enabled(!this.detailUi.summaryBusy && !this.setupBusy)
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
        SyncStatusPanel({busy:this.syncBusy,cloudBusy:this.cloudBusy,
          cloudText:this.cloud && this.cloudFresh ? '云端版本已核对' :
            this.cloud ? '显示上次缓存，尚未确认最新版本' : '尚未核对云端版本',
          bound:!!this.syncBound && !!this.syncAccount && traktAuth.isCurrent(this.clientId,this.syncAccount.generation),
          rows:this.queueRows,lastUpload:this.lastEpisodeUpload,lastVerified:this.cloud?.verifiedAt ?? 0})
        if (this.autoStatus) { Text(this.autoStatus).fontSize(12).width('100%') }
        if (this.mediaSyncStatus) { Text(this.mediaSyncStatus).fontSize(12).width('100%') }
        Button(this.cloudBusy || this.syncBusy ? '同步处理中…' : '立即同步').width('100%')
          .enabled(this.ready && this.episodeReady && !this.backupBusy && !this.authBusy && !this.setupBusy)
          .onClick(() => { this.requestSyncNow(); })
        Text('核对云端并处理已授权的待同步操作；不会自动上传旧记录或删除观看历史。').fontSize(12).width('100%')
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
    List({ space: 10, scroller: this.searchScroller }) {
      ListItem() {
        Column({ space: 12 }) {
          if (this.presentationStatus) { Text(this.presentationStatus).fontSize(12).width('100%') }
        Row({space:6}){
          TextInput({placeholder:'电影或剧集名称',text:this.title}).layoutWeight(1).height(40)
            .onChange((value:string)=>{this.changeSearchText(value);})
            .onSubmit(()=>{this.search();})
          if(this.title){Button('清空').height(34).fontSize(12).onClick(()=>{this.changeSearchText('');})}
        }.width('100%')
        Row({ space: 8 }) {
          Button(this.searching ? '重新搜索' : '搜索').layoutWeight(1)
            .enabled(!this.setupBusy && this.title.trim().length > 0)
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
        if (!this.title.trim() && this.searchRecents.length) {
          Row({space:8}) {
            Text('最近搜索').layoutWeight(1)
            Button('清除历史').fontSize(12).onClick(()=>{ this.clearSearchHistory(); })
          }.width('100%')
          ForEach(this.searchRecents,(query: string)=>{
            Button(query).fontSize(13).width('100%').onClick(()=>{ this.changeSearchText(query); this.search(); })
          })
        }
        if (this.title.trim()) {
          Row({space:6}) {
            Button('全部').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions('all',this.searchOptions.sort,this.searchOptions.descending); })
            Button('剧集').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions('show',this.searchOptions.sort,this.searchOptions.descending); })
            Button('电影').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions('movie',this.searchOptions.sort,this.searchOptions.descending); })
          }.width('100%')
          Text('类型：'+(this.searchOptions.kind==='show' ? '剧集' : this.searchOptions.kind==='movie' ? '电影' : '全部')).fontSize(12)
          if (this.searchSubmitted) {
            Row({space:6}) {
              Button('相关度').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions(this.searchOptions.kind,'rank',this.searchOptions.descending); })
              Button('名称').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions(this.searchOptions.kind,'title',this.searchOptions.descending); })
              Button('年份').layoutWeight(1).fontSize(12).onClick(()=>{ this.changeSearchOptions(this.searchOptions.kind,'year',this.searchOptions.descending); })
              Button(this.searchOptions.descending ? '降序' : '升序').fontSize(12).onClick(()=>{ this.changeSearchOptions(this.searchOptions.kind,this.searchOptions.sort,!this.searchOptions.descending); })
            }.width('100%')
            Text('排序：'+(this.searchOptions.sort==='rank' ? '相关度' : this.searchOptions.sort==='title' ? '名称' : '年份')).fontSize(12)
          }
        }
        if(this.searchSubmitted&&this.searchSnapshot.remoteReady){
          Row({space:6}){
            Button(this.searchSnapshot.offline?'网络结果':'✓ 网络结果').fontSize(12).layoutWeight(1).onClick(()=>{this.chooseSearchSource(false);})
            Button(this.searchSnapshot.offline?'✓ 本地补充':'本地补充').fontSize(12).layoutWeight(1).onClick(()=>{this.chooseSearchSource(true);})
          }.width('100%')
        }
        if(this.searching){LoadingProgress().width(22).height(22)}
        Text(this.searchStatus).fontSize(13)
        if(!this.searching&&this.searchStatus.includes('失败')){Button('重试网络搜索').fontSize(12).onClick(()=>{this.search();})}
        if(this.searchSubmitted&&!this.searching&&!this.results.length){Text(this.searchSnapshot.remoteReady&&!this.searchSnapshot.offline?'网络无匹配结果':'本地无匹配结果').fontSize(12)}
        }.width('100%')
      }
        LazyForEach(this.searchRows, (item: Media) => {
          ListItem() {
          Row({ space: 8 }) {
            this.posterImage(item, 54, 81)
            Text(this.displayLabel(item)).layoutWeight(1)
              .onClick(() => { this.openDetail(item); })
            if (this.isHidden(item)) { Text('已隐藏').fontSize(12) }
            if(this.isInLibrary(item)){Text('已收藏').fontSize(11)}
            Button('详情').fontSize(12).enabled(!this.detailUi.summaryBusy && !this.setupBusy)
              .onClick(() => { this.openDetail(item); })
            Button(this.isInLibrary(item) ? '已收藏' : '添加')
              .enabled(this.ready && !this.saving && !this.cloudBusy && this.canEditLibrary() && !this.isInLibrary(item))
              .onClick(() => { this.changeMediaIntent(item, 'watchlist', 'yes'); })
          }.width('100%')
            .onVisibleAreaChange([0], (visible: boolean, ratio: number) => { this.viewportChanged(item,0,[],visible && ratio > 0,'search',''); })
          }
        }, (item: Media) => this.searchRows.keyFor(item.id))
    }.width('100%').height('100%').padding(16)
      .onScrollIndex((start: number,end: number,center: number)=>{ this.onListScroll('search',start); })
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('Showly').fontSize(27).fontWeight(FontWeight.Bold).layoutWeight(1)
        this.headerAction('搜索', 'search')
        this.headerAction('设置', 'account')
      }.width('100%').padding(12).backgroundColor($r('app.color.showly_surface'))
      Divider().color($r('app.color.showly_line'))
      if (!this.selectedMedia && (this.tab === 'progress' || this.tab === 'discover' || this.tab === 'library' || this.tab==='statistics')) {
        this.mediaModeTabs()
        if (this.modeStatus) { Text(this.modeStatus).fontSize(12).width('100%') }
      }
      Refresh({ refreshing: $$this.refreshing }) {
        if (!this.selectedMedia && this.tab === 'progress' && this.progressMode === 'next') {
          if (this.mediaMode === 'movie') { this.movieProgressView() }
          else { this.nextShowsView() }
        } else if (!this.selectedMedia && this.tab === 'library') {
          if(this.collectionFilter==='lists'){
            Column(){
              ForEach([this.currentProgressScope()],(scope:string)=>{
                CustomListsPage({scope:scope,client:this.clientId,language:this.presentationLanguage,presentation:this.presentation,readRatings:()=>this.customListRatings(scope),
                  current:()=>this.pageVisible&&this.currentProgressScope()===scope&&this.tab==='library'&&this.collectionFilter==='lists'&&!this.selectedMedia,
                  onBack:()=>{this.chooseCollection('mine');},onOpen:(item:Media)=>{this.openDetail(item);}})
              },(scope:string)=>scope)
            }.width('100%').height('100%')
          }else{this.collectionView()}
        } else if (!this.selectedMedia && this.tab==='statistics') {
          Column(){
            ForEach([this.currentProgressScope()+'|'+this.mediaMode],(key:string)=>{
              StatisticsPage({scope:this.currentProgressScope(),kind:this.mediaMode,client:this.clientId,language:this.presentationLanguage,repository:this.presentation,
                current:()=>this.pageVisible&&!this.selectedMedia&&this.tab==='statistics'&&key===this.currentProgressScope()+'|'+this.mediaMode,
                inputs:()=>this.statisticsInputs(this.mediaMode),readRatings:()=>this.statisticsRatings(this.mediaMode,this.currentProgressScope()),
                onBack:()=>{this.navigate(this.returnTab);},onOpen:(item:Media)=>{this.openDetail(item);}})
            },(key:string)=>key)
          }.width('100%').height('100%')
        } else if (!this.selectedMedia && this.tab === 'discover') {
          this.discoverView()
        } else if (!this.selectedMedia && this.tab === 'search') {
          this.searchView()
        } else if (!this.selectedMedia && this.tab === 'progress' && this.progressMode === 'calendar') {
          if (this.mediaMode === 'movie') { this.personalMovieCalendarView() } else { this.calendarView() }
        } else if (!this.selectedMedia && this.tab==='progress' && this.progressMode==='history' && this.mediaMode==='show') {
          this.progressView()
        } else if (this.selectedMedia && this.episodePage) {
          this.episodeDetailPage(this.selectedMedia)
        } else {
        Scroll(this.detailScroller) {
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
            WatchSettings({options:this.watchOptions,onChange:(value:WatchOptions)=>{this.watchOptions=value;},onCredential:(version:number)=>{this.watchCredentialVersion=version;}})
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
      .bindSheet($$this.ratingSheetOpen,this.ratingSheet(),{height:SheetSize.MEDIUM,showClose:true})
      .bindSheet($$this.commentSheetOpen,this.commentSheet(),{height:SheetSize.LARGE,showClose:true})
      .bindSheet($$this.gallerySheetOpen,this.gallerySheet(),{height:SheetSize.LARGE,showClose:true})
  }
}
