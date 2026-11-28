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
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","PageStateOwner.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {PageStateOwner,PageWorkSet,PageSortJobs}=require('./PageStateOwner');
const {planListDiff}=require('./ListDiff');
const {ConsumerReadFlight}=require('./ReadFlight');
(async()=>{
 for(const size of [393,10000]){
  const pages=new PageWorkSet(),owners=new Map();
  for(const page of ['show','movie','calendar','movieCalendar','libraryShow','libraryMovie','discover','search']){
   const owner=new PageStateOwner(row=>[row.id]);owners.set(page,owner);pages.register(page,owner.work);
  }
  const show=owners.get('show'),movie=owners.get('movie'),jobs=new PageSortJobs(pages);
  const collectionPages=new PageWorkSet(),collectionJobs=new PageSortJobs(collectionPages);
  const showLibrary=new PageStateOwner(row=>[row.id]),movieLibrary=new PageStateOwner(row=>[row.id]);
  collectionPages.register('libraryShow',showLibrary.work);collectionPages.register('libraryMovie',movieLibrary.work);
  const movieLibraryTicket=movieLibrary.work.begin();
  const movieLibraryJob=collectionJobs.begin('collection-movie','sort');
  for(let i=0;i<100;i++){
   const ticket=showLibrary.work.begin();
   collectionPages.observe('collection:'+i,['show:'+i],false);
   assert(!showLibrary.work.current(ticket));assert(movieLibrary.work.current(movieLibraryTicket));
   assert(collectionJobs.current('collection-movie',movieLibraryJob));
  }
  assert.equal(movieLibrary.work.snapshot().dependencyVersion,0);
  collectionPages.observe('unknown',[],true);assert(!movieLibrary.work.current(movieLibraryTicket));assert(!collectionJobs.current('collection-movie',movieLibraryJob));
  collectionPages.reset();
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
