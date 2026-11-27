#!/usr/bin/env python3
"""Production viewport/read models, deterministic cancellation and native wiring."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation","ViewportTasks","ReadFlight","DisplayJobs","PresentationPolicy","DiscoverRules","DiscoverRead","ScrollAnchor"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ViewportTasks.ts","DisplayJobs.ts","PresentationPolicy.ts","DiscoverRead.ts","ScrollAnchor.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {ViewportTasks,mergeViewportTasks,addPresentationTask}=require('./ViewportTasks');
const {ReadCancel,ReadCancelled,ConsumerReadFlight}=require('./ReadFlight');
const {LatestDisplayJobs}=require('./DisplayJobs');
const {PresentationAttempts,runPresentationPass}=require('./PresentationPolicy');
const {DiscoverRead}=require('./DiscoverRead');
const {discoverRequest,defaultDiscover}=require('./DiscoverRules');
const {ScrollAnchors,captureAnchor,resolveAnchor}=require('./ScrollAnchor');
const tick=()=>new Promise(r=>setImmediate(r));
const media=i=>({id:'show:'+i,title:'Show '+i,year:2026,kind:'show',watched:false});
(async()=>{
 const all=Array.from({length:10000},(_,i)=>media(i+1));
 const viewport=new ViewportTasks(),business=new Map();
 for(let i=0;i<12;i++) viewport.update(all[i],1,[],true,'card');
 viewport.update(all[0],1,[],true,'duplicate');
 let visits=0;const original=viewport.rows.bind(viewport);viewport.rows=()=>{const rows=original();visits+=rows.length;return rows};
 for(let i=0;i<100;i++){assert.equal(mergeViewportTasks(viewport,business).length,12);}
 assert.equal(visits,1300); // 13 visible consumers, not 10,000 backing rows
 addPresentationTask(business,all[0],false,1,[]);
 addPresentationTask(business,all[9999],false,0,[]);
 let tasks=mergeViewportTasks(viewport,business);
 assert.equal(tasks.length,13);assert.equal(tasks[0].artwork,true);
 assert.equal(tasks.find(x=>x.media.id===all[9999].id).artwork,false);
 viewport.update(all[0],1,[],false,'card');assert(viewport.has(all[0],1));
 viewport.update(all[0],1,[],false,'duplicate');assert(!viewport.has(all[0],1));
 assert.equal(mergeViewportTasks(viewport,business).find(x=>x.media.id===all[0].id).artwork,false);
 const jobs=new LatestDisplayJobs(),anchors=new ScrollAnchors(),rows={totalCount:()=>all.length,idAt:i=>all[i]?.id??'',indexOfId:id=>all.findIndex(x=>x.id===id)};
 for(let i=0;i<100;i++){
  const t=jobs.begin('search','accountA:'+i),old=jobs.consumer('search',t);
  jobs.clear();assert(old.cancelled());assert(!jobs.current('search',t));
  const n=jobs.begin('search','accountB:'+i);assert(!jobs.consumer('search',n).cancelled());assert(!jobs.finish('search',t));jobs.clear();
  const a=captureAnchor('accountA:discover',rows,432,17);
  anchors.save('discover',a);assert.equal(resolveAnchor(a,'accountA:discover',rows).index,432);
  assert.equal(anchors.pending('discover','accountB:discover'),undefined);
  viewport.clear();assert.equal(mergeViewportTasks(viewport,new Map()).length,0);
 }
 const first=jobs.begin('sort','a'),signal=jobs.consumer('sort',first),second=jobs.begin('sort','b');
 assert(signal.cancelled());assert(!jobs.consumer('sort',second).cancelled());assert(!jobs.finish('sort',first));jobs.clear();
 const attempts=new PresentationAttempts();let reported=0;
 await runPresentationPass([tasks[0]],'artwork',attempts,'A',()=>true,()=>true,async()=>{throw new ReadCancelled()},()=>{},()=>reported++);
 assert.equal(reported,0);assert(attempts.allowed(JSON.stringify(['A','artwork',tasks[0].media.id]),Date.now()));
 let reads=0,aborts=0,resolve;
 const repo=new DiscoverRead({read:async()=>'',write:async()=>{}},{read:async(client,request,mode,page,limit,scope)=>{reads++;return new Promise((r,j)=>{resolve=()=>r({items:[{media:all[0],rating:0,posterUrls:[],posterUri:'',firstAired:''}],page,pages:1,limit,count:1});scope.subscribe(()=>{aborts++;j(new ReadCancelled())})})}});
 const request=discoverRequest('show',{...defaultDiscover(),mode:'popular'},0);
 const a=new ReadCancel(),b=new ReadCancel();
 const pa=repo.load('client',request,false,()=>{},a).catch(e=>e.message),pb=repo.load('client',request,false,()=>{},b);
 await tick();assert.equal(reads,1);a.cancel();assert.equal(await pa,'Read cancelled');assert.equal(aborts,0);resolve();assert.equal((await pb).items.length,1);
 const c=new ReadCancel(),pc=repo.load('client',request,true,()=>{},c).catch(e=>e.message);await tick();c.cancel();assert.equal(await pc,'Read cancelled');assert.equal(reads,2);
 console.log('10k list: 13 visible consumers per pass, business metadata retained; 100 route/account cycles, scroll anchors, worker and discovery cancellation passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages/Index.ets").read_text()
tasks=page.split("  private presentationTasks()",1)[1].split("  private cancelPresentationReads()",1)[0]
assert "mergeViewportTasks(this.viewport,this.businessTasks())" in tasks
for old in ("this.visibleDiscover()","this.results","this.collectionSlice()","this.nextSlice()","this.movieProgressRows()","this.calendarSlice()","this.movieSlice()"):
    assert old not in tasks,old
assert "this.businessPresentationTasks=tasks" in page
assert "this.cancelInvisiblePresentationReads()" in page
assert "repo.load(clientId,request,force,publish,consumer)" in page
assert "repo.translation(task.media,client,language,consumer)" in page
assert "repo.season(task.media,task.season,client,language,consumer)" in page
assert "repo.artwork(task.media,client,task.artwork,task.posterUrls,collection,consumer)" in page
assert "fetchFullEpisodeCatalog(item, clientId,this.detailConsumer)" in page
assert "this.sortJobs.consumer(slot,token)" in page
assert "this.getUIContext().postFrameCallback" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
task=(root/"data/CancelableDisplayTask.ets").read_text()
assert "taskpool.cancel(task)" in task and "Promise.race" in task
for name in ("DisplayTasks","SearchTask","CalendarTask","ProgressCandidateTask"):
    raw=(root/"data"/(name+".ets")).read_text()
    assert "new taskpool.Task(" in raw and "scope?.check(); return" in raw
print("Viewport-only enumeration, explicit business tasks, read cancellation, native TaskPool detachment, scroll and synchronization wiring passed")
