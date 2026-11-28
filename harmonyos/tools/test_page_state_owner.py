#!/usr/bin/env python3
"""Page-scoped publication, commit invalidation and cancellation."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for p in (root/"model").glob("*.ets"):
        shutil.copyfile(p,work/(p.stem+".ts"))
    (work/"arkui.d.ts").write_text("""
interface DataChangeListener { onDataReloaded():void; onDataAdd(i:number):void; onDataDelete(i:number):void; onDataMove(i:number,j:number):void; onDataChange(i:number):void; }
interface IDataSource { totalCount():number; getData(i:number):unknown; registerDataChangeListener(l:DataChangeListener):void; unregisterDataChangeListener(l:DataChangeListener):void; }
""")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","PageStateOwner.ts","CollectionViewOwner.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {PageStateOwner,PageWorkSet,PageSortJobs}=require('./PageStateOwner');
const {planListDiff}=require('./ListDiff');
const {CollectionViewOwner,COLLECTION_NETWORK_GROUPS,COLLECTION_GENRES,toggleCollectionSelection,CollectionDependencyVersions,CollectionMetadataVersions,CollectionRatingRequest,COLLECTION_RECENT_AMOUNTS,validCollectionRecentAmount,collectionEmptyText}=require('./CollectionViewOwner');
const {ConsumerReadFlight}=require('./ReadFlight');
(async()=>{
 for(const size of [393,10000]){
  const deps=new CollectionDependencyVersions(),meta=new CollectionMetadataVersions();
  const options={sort:'title',descending:true,genres:[],networks:[],upcoming:'all'};
  const ratingOptions={...options,sort:'rating'},ratingKey=meta.key('show',ratingOptions,'mine');
  const titleKey=meta.key('show',options,'mine'),movieKey=meta.key('movie',ratingOptions,'mine');
  for(let i=0;i<100;i++){
    deps.observe(['show:'+i],false);
    const before={genres:['drama'],network:'HBO',release:'2026-01-01',rating:i,runtime:40};
    meta.changed('show:'+i,before,{...before,rating:i+1});
    assert.equal(meta.key('show',options,'mine'),titleKey);
    assert.equal(meta.key('movie',ratingOptions,'mine'),movieKey);
  }
  assert.equal(deps.business('show'),100);assert.equal(deps.business('movie'),0);
  assert.notEqual(meta.key('show',ratingOptions,'mine'),ratingKey);
  deps.observe([],true);assert.equal(deps.business('movie'),1);
  const showRead=new CollectionRatingRequest(),movieRead=new CollectionRatingRequest();
  const staleRatingTicket=showRead.begin('account-A'),movieTicket=movieRead.begin('account-A');
  assert.equal(showRead.begin('account-A'),0);
  showRead.reset();const newRatingTicket=showRead.begin('account-B');
  assert(!showRead.finish(staleRatingTicket));assert(showRead.current(newRatingTicket));assert(movieRead.current(movieTicket));
  assert(showRead.finish(newRatingTicket));assert(movieRead.finish(movieTicket));
  assert.deepEqual(COLLECTION_RECENT_AMOUNTS,[0,2,4,6,8]);assert(!validCollectionRecentAmount(5));
  assert.notEqual(collectionEmptyText(true,'mine'),collectionEmptyText(false,'mine'));
  console.log(size+' collection dependencies: 100 cross-kind commits, field-specific metadata keys, independent stale rating tickets, recents and empty states passed');
  const showView=new CollectionViewOwner(),movieView=new CollectionViewOwner();
  for(let i=0;i<100;i++){
   assert(showView.update('queue','show '+i,'watching',false,true));
   assert(!showView.update('queue','show '+i,'watching',false,true));
   assert.equal(movieView.snapshot().revision,0);
   const snap=showView.snapshot();snap.query='mutated';assert.equal(showView.snapshot().query,'show '+i);
  }
  assert.equal(showView.snapshot().revision,100);showView.clear();assert.equal(showView.snapshot().query,'');
  const hbo=COLLECTION_NETWORK_GROUPS.find(x=>x.name==='HBO');assert(hbo.channels.includes('Max'));
  assert.deepEqual(toggleCollectionSelection(['custom'],hbo.channels),['custom',...hbo.channels]);
  assert.deepEqual(toggleCollectionSelection(['custom',...hbo.channels],hbo.channels),['custom']);
  assert.equal(COLLECTION_GENRES.length,16);
  console.log(size+' collection view: 100 independent state transitions, snapshot copies, exact network group selection passed');
  const pages=new PageWorkSet(),owners=new Map();
  for(const page of ['show','movie','calendar','movieCalendar','libraryShow','libraryMovie','discover','search']){
   const owner=new PageStateOwner(row=>[row.id]);owners.set(page,owner);pages.register(page,owner.work);
  }
  const show=owners.get('show'),movie=owners.get('movie'),jobs=new PageSortJobs(pages);
  const collectionPages=new PageWorkSet(),collectionJobs=new PageSortJobs(collectionPages);
  const showLibrary=new PageStateOwner(row=>[row.id]),movieLibrary=new PageStateOwner(row=>[row.id]);
  collectionPages.register('libraryShow',showLibrary.work);collectionPages.register('libraryMovie',movieLibrary.work);
  showLibrary.activate('account-A:show');movieLibrary.activate('account-A:movie');
  const showData=Array.from({length:size},(_,i)=>({id:'show:'+i,value:i}));
  const movieData=Array.from({length:size},(_,i)=>({id:'movie:'+i,value:i}));
  showLibrary.replace(showData,showData.map(x=>x.id),showData.map(x=>String(x.value)));
  movieLibrary.replace(movieData,movieData.map(x=>x.id),movieData.map(x=>String(x.value)));
  const movieVersion=movieLibrary.publicationVersion(),movieRow=movieLibrary.getData(0);
  const movieLibraryTicket=movieLibrary.work.begin();
  const movieLibraryJob=collectionJobs.begin('collection-movie','sort');
  for(let i=0;i<100;i++){
   const ticket=showLibrary.work.begin();
   collectionPages.observe('collection:'+i,['show:'+i],false);
   assert(!showLibrary.work.current(ticket));assert(movieLibrary.work.current(movieLibraryTicket));
   assert(collectionJobs.current('collection-movie',movieLibraryJob));
   assert(showLibrary.patchRow('show:'+i,{id:'show:'+i,value:size+i},String(size+i)));
   assert.equal(movieLibrary.publicationVersion(),movieVersion);
   assert.equal(movieLibrary.getData(0),movieRow);
  }
  assert.equal(movieLibrary.work.snapshot().dependencyVersion,0);
  collectionPages.observe('unknown',[],true);assert(!movieLibrary.work.current(movieLibraryTicket));assert(!collectionJobs.current('collection-movie',movieLibraryJob));
  collectionPages.reset();
  collectionPages.transition('libraryShow','library:show','account-A');
  const oldShow=showLibrary.work.begin(),showSort=collectionJobs.begin('collection-show','sort');
  const retainedMovie=movieLibrary.work.begin();
  collectionPages.transition('libraryMovie','library:movie','account-A');
  assert(!showLibrary.work.current(oldShow));assert(!collectionJobs.current('collection-show',showSort));
  assert(movieLibrary.work.current(retainedMovie));
  showLibrary.memo.put('scope',showData,1,1000);
  movieLibrary.memo.put('scope',movieData,1,1000);
  showLibrary.memo.clear();showLibrary.allMemo.clear();showLibrary.replace([],[],[]);
  assert.equal(showLibrary.totalCount(),0);assert.equal(movieLibrary.totalCount(),size);
  assert.equal(showLibrary.memo.get('scope',2),undefined);
  assert.equal(movieLibrary.memo.get('scope',2),movieData);
  collectionPages.transition('libraryMovie','library:movie','account-B');
  assert(!movieLibrary.work.current(retainedMovie));
  movieLibrary.activate('account-B:movie');assert.equal(movieLibrary.totalCount(),0);
  console.log(size+' collection owners: 100 scoped commits, zero cross-kind publications, independent sort cancellation, derived cache release and account scope passed');
  const rows=Array.from({length:size},(_,i)=>({id:'show:'+i,value:0}));
  const ids=rows.map(x=>x.id),keys=rows.map(x=>String(x.value));
  show.activate('A');show.replace(rows,ids,keys);
  const version=show.publicationVersion(),old=show.getData(1),unrelated=movie.work.begin();
  for(let i=0;i<100;i++){
   const ticket=show.work.begin();
   const token=jobs.begin('show-query','q'+i);assert(token);assert.equal(jobs.begin('show-query','q'+i),0);
   pages.observe('A:'+i,['show:0'],false);
   pages.observe('A:'+i,['show:0'],false);
   assert(!show.work.current(ticket));assert(!jobs.current('show-query',token));
   assert(movie.work.current(unrelated));
   assert(show.patchRow('show:0',{id:'show:0',value:i+1},String(i+1)));
   assert.equal(show.getData(1),old);
  }
  assert.equal(show.work.snapshot().dependencyVersion,100);
  assert.equal(movie.work.snapshot().dependencyVersion,0);
  assert.equal(show.publicationVersion()-version,100);
  assert.equal(movie.work.snapshot().starts,1);
  let visible={key:'',total:0,page:1,pages:1};
  const next={key:'A',total:size,page:1,pages:1};
  assert(show.work.publishSummary(next,visible));visible=next;
  assert(!show.work.publishSummary(next,visible));
  show.work.readSummary().total=0;
  assert.equal(show.work.readSummary().total,size);
  for(let i=0;i<100;i++){
   const before=show.work.begin();
   const oldJob=jobs.begin('show-query','switch'+i);
   pages.reset();show.activate('account:'+i);
   assert(!show.work.current(before));assert(!jobs.current('show-query',oldJob));
   const newJob=jobs.begin('show-query','switch'+i);
   assert(newJob!==oldJob);assert(!jobs.finish('show-query',oldJob));assert(jobs.finish('show-query',newJob));
  }
  // Route transitions cancel outgoing work, not unrelated owners.
  pages.transition('show','show:next','account-A');
  const third=owners.get('discover'),thirdTicket=third.work.begin();
  const thirdRead=third.work.remote.begin('feed');
  const thirdJob=jobs.begin('discover','feed-sort');
  const baseline=third.work.snapshot().revision;
  let switches=0;
  for(let i=0;i<100;i++){
   const from=i%2===0?'show':'movie',to=i%2===0?'movie':'show';
   const outgoing=owners.get(from),ticket=outgoing.work.begin(),read=outgoing.work.remote.begin('request:'+i);
   pages.transition(to,to+':next','account-A');switches++;
   assert(!outgoing.work.current(ticket));assert(read.cancelled());
   assert(third.work.current(thirdTicket));assert(third.work.remote.current(thirdRead));assert(jobs.current('discover',thirdJob));
  }
  assert.equal(switches,100);assert.equal(third.work.snapshot().revision,baseline);
  const lane=third.work.remote,readState=lane.snapshot();
  assert.equal(lane.begin('feed'),undefined);assert.equal(lane.snapshot().starts,readState.starts);
  assert.equal(lane.snapshot().joins,readState.joins+1);
  readState.loading=false;assert(lane.snapshot().loading);
  const transport=new ConsumerReadFlight();let completeRead,network=0;
  const first=transport.run('shared',()=>{network++;return new Promise(resolve=>{completeRead=resolve;});},thirdRead);
  const secondLane=movie.work.remote,secondRead=secondLane.begin('shared');
  const second=transport.run('shared',()=>{network++;return Promise.resolve(0);},secondRead);
  await Promise.resolve();assert.equal(network,1);
  const firstRejected=assert.rejects(first);lane.cancel();await firstRejected;
  completeRead(size);assert.equal(await second,size);
  assert(!lane.finish(thirdRead,'stale'));assert(secondLane.finish(secondRead));
  pages.resetDisplay();assert(!third.work.current(thirdTicket));assert(secondLane.current(secondRead));
  const beforeAccount=third.work.begin(),beforeAccountJob=jobs.begin('discover','before-account');
  pages.transition('show','show:next','account-B');assert(!third.work.current(beforeAccount));assert(!jobs.current('discover',beforeAccountJob));assert(!jobs.current('discover',thirdJob));
  assert(secondRead.cancelled());assert.equal(lane.snapshot().loading,false);
  const hidden=show.work.remote.begin('hidden');pages.transition('','','account-B');assert(hidden.cancelled());
  show.activate('B');show.replace(rows,ids,keys);
  let complete;
  const pending=show.submit(rows.slice().reverse(),ids.slice().reverse(),keys.slice().reverse(),input=>new Promise(resolve=>{complete=()=>resolve(planListDiff(input));}),()=>true);
  show.activate('C');complete();assert.equal(await pending,false);assert.equal(show.totalCount(),0);
 }
 console.log('393/10k lifecycle: 100 scoped route switches, zero unrelated invalidations, duplicate read suppression, shared transport cancellation, stale read rejection and account/hide reset passed');
 console.log('393/10k page owners: 100 scoped commits, zero unrelated movie invalidations, exact row patches, duplicate suppression, 100 account/route cancellations, stale list rejection passed');
})().catch(e=>{console.error(e);process.exit(1)});
""")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
assert page.count("new PageStateOwner<")==8
assert "this.pageWorks.observe(" in page
assert "work.current(ticket)" in page
assert "this.activePresentationRoute()" in page
assert "this.showRows.work.publishSummary(" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Page state ownership integration and sync guards passed")

# ArkTS requires a common nominal type across the owner and observed state.
assert "interface DisplaySummary" not in page
assert page.count("Summary: PageSummary =")==4
assert page.count("const summary: PageSummary =")==4

assert "this.pageWorks.transition(this.pageOwnerSlot(),route,account)" in page
assert "this.activePageWork()?.changePresentation(route)" in page
assert "this.searchRows.work.remote" in page and "this.searchRows.work.local" in page
assert "this.discoverRows.work.remote" in page and "this.calendarRows.work.hydrate" in page
assert "this.viewport.clear(); this.sortJobs.clear(); this.viewportRouteKey" not in page

assert "this.pageWorks.resetDisplay();" in page

assert "pages.register('libraryShow',this.showCollectionRowsSource.work)" in page
assert "pages.register('libraryMovie',this.movieCollectionRowsSource.work)" in page
assert "LazyForEach(this.showCollectionRowsSource" in page and "LazyForEach(this.movieCollectionRowsSource" in page
assert "this.releaseCollectionOwner(this.mediaMode==='movie'?'show':'movie')" in page

assert "this.captureCollectionView();" in page and "this.restoreCollectionView();" in page
assert "COLLECTION_NETWORK_GROUPS" in page and "COLLECTION_GENRES" in page
assert "if(this.collectionSearchOpen || this.collectionQuery.length>0)" in page
assert "this.posterImage(row.media,80,120)" in page

assert "this.collectionDependencies.observe(" in page
assert "this.collectionMetadata.changed(row.id,prior?.collection,row.collection)" in page
assert "this.collectionMetadataKey()" in page
# Runtime safety: never bind an overlay to a recyclable collection header.
controls=page.split("  collectionRuleControls() {",1)[1].split("  collectionFilterPanel(){",1)[0]
assert "if(this.collectionOptionsOpen){this.collectionFilterPanel()}" in controls
assert ".bindSheet(" not in controls
assert "this.collectionOptionsOpen = !this.collectionOptionsOpen;" in controls
assert "this.tab === 'library' && value !== 'library'" in page
assert "this.collectionOptionsOpen=false;" in page
assert "this.settings.loadCollectionRecentAmount()" in page
assert "this.showRatingRequest.finish(ticket)" in page and "this.movieRatingRequest.finish(ticket)" in page

# Collection render must consume published snapshots, not mutate business caches.
collection_view=page.split("  collectionView() {",1)[1].split("  collectionSortButton(",1)[0]
assert "this.recentCollectionRows()" not in collection_view
assert "this.personalLibrary()" not in collection_view
assert "ForEach(this.collectionRecentRows," in collection_view
assert "this.publishCollectionHeader();" in page
assert "this.updateLazyRows().catch(" in page
sort=page.split("  private async runCollectionSort(",1)[1].split("  private collectionEntries()",1)[0]
assert "throw new Error" not in sort
assert "this.reportCollectionFailure(key,'排序')" in sort
assert "this.collectionFailureKey!==key" in sort
assert "this.retryCollectionDisplay();" in collection_view
