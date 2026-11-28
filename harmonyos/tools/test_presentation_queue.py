#!/usr/bin/env python3
"""Production queue, versioned display owners, exact sorting and projection signatures."""
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
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","PresentationQueue.ts","PageDisplayRows.ts","EpisodeRowsOwner.ts","ProgressTitleOrder.ts","ProjectionCompute.ts","StableDisplayOrder.ts","MovieProgressRules.ts","CollectionRules.ts","SearchRules.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {PresentationQueue,FramePublication}=require('./PresentationQueue');
const {PageDisplayRows}=require('./PageDisplayRows');
const {EpisodeRowsOwner}=require('./EpisodeRowsOwner');
const {ProgressTitleOrder}=require('./ProgressTitleOrder');
const {ShowProjectionCache,showProjectionStateKey}=require('./ProjectionCompute');
const {sortProgressCandidates,defaultProgress}=require('./ProgressRules');
const {planListDiff}=require('./ListDiff');
const {ReadCancel,ConsumerReadFlight}=require('./ReadFlight');
const {PresentationAttempts,PresentationFailure}=require('./PresentationPolicy');
const now=1768046400000,max=Number.MAX_SAFE_INTEGER;
const media=i=>({id:'show:'+i,kind:'show',title:'Show '+i,year:2026,watched:false});
const task=(i,artwork=false,season=1)=>({media:media(i),artwork,season,posterUrls:[]});
const tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 const q=new PresentationQueue('title'),b=new Map();
 for(let i=1;i<=10000;i++)b.set('show:'+i+':1',task(i));
 const visible=Array.from({length:12},(_,i)=>task(i+1,true));
 q.update(visible,b,()=>true,now);
 assert.equal(q.businessCount(),10000);
 const first=q.next();assert.equal(first.task.media.id,'show:1');assert(first.task.artwork);
 q.finish(first,true,max);
 let dispatched=1;let item;
 while(item=q.next()){q.finish(item,true,max);dispatched++;}
 assert.equal(dispatched,10000);
 for(let j=0;j<100;j++){
   q.update(Array.from({length:12},(_,i)=>task(j*12+i+1,true)),b,()=>true,now);
   assert(!q.hasPending());
 }
 assert.equal(q.businessCount(),10000);assert.equal(q.visibleCount(),1212);
 const fresh=new Map(b);fresh.set('show:10001:1',task(10001));
 q.update([],fresh,()=>true,now);
 assert.equal(q.next().task.media.id,'show:10001');
 assert(!q.hasPending());
 const art=new PresentationQueue('artwork');
 const vb=new Map([['show:1:1',task(1)]]);
 art.update([task(1,true)],vb,()=>true,now);
 const image=art.next();assert(image.task.artwork);art.finish(image,true,now+1);
 const metadata=art.next();assert(!metadata.task.artwork);art.finish(metadata,true,max);
 art.update([task(1,true)],vb,()=>true,now);assert(!art.hasPending());
 art.update([task(1,true)],vb,()=>true,now+1);assert(art.next().task.artwork);
 art.clear();art.finish(image,true,max);art.update([task(1,true)],vb,()=>true,now+1);assert(art.hasPending());
 const cancel=new PresentationQueue('title');const noBusiness=new Map();
 cancel.update([task(1,true)],noBusiness,()=>true,now);const old=cancel.next();
 cancel.update([task(2,true)],noBusiness,()=>true,now);assert(!cancel.relevant(old));cancel.finish(old,false,max);
 assert.equal(cancel.next().task.media.id,'show:2');
 const attempts=new PresentationAttempts(),key='x';
 attempts.fail(key,new PresentationFailure('limited',429,now+1),attempts.generation());
 assert.equal(attempts.nextAttempt(key),now+1);assert(!attempts.allowed(key,now));assert(attempts.allowed(key,now+1));
 let starts=0,resolve;
 const flight=new ConsumerReadFlight(),a=new ReadCancel(),c=new ReadCancel();
 const read=scope=>{starts++;return new Promise((r,j)=>{resolve=r;scope.subscribe(()=>j(Error('cancelled')));});};
 const p=flight.run('same',read,a).catch(e=>e.message),r=flight.run('same',read,c);
 await tick();a.cancel();assert.equal(await p,'Read cancelled');assert.equal(starts,1);resolve('ok');assert.equal(await r,'ok');
 const gate=new FramePublication();let publications=0;
 for(let i=0;i<100;i++){
   const token=gate.request();assert(token>=0);
   for(let j=0;j<100;j++)assert.equal(gate.request(),-1);
   if(gate.consume(token))publications++;assert(!gate.consume(token));
 }
 assert.equal(publications,100);const stale=gate.request();gate.clear();assert(!gate.consume(stale));
 const rows=new PageDisplayRows();rows.activate('A');
 rows.replace(['a','b'],['a','b'],['1','2']);
 const v=rows.publicationVersion();rows.replace(['a','b'],['a','b'],['1','2']);assert.equal(rows.publicationVersion(),v);
 let finish;const pending=rows.submit(['b','a'],['b','a'],['2','1'],x=>new Promise(r=>{finish=()=>r(planListDiff(x));}),()=>true);
 rows.activate('B');finish();assert.equal(await pending,false);assert.equal(rows.totalCount(),0);
 const episode=new EpisodeRowsOwner();
 const episodes=Array.from({length:10000},(_,i)=>({id:i+1,number:i+1,title:'E'+(i+1),originalTitle:'E'+(i+1),watched:false}));
 let changes=[],reloads=0;
 episode.source.registerDataChangeListener({onDataChange:i=>changes.push(i),onDataReloaded:()=>reloads++,onDataAdd(){},onDataDelete(){},onDataMove(){}});
 episode.replace('A:show:1:1',episodes);changes=[];reloads=0;
 episode.updateTitle('A:show:1:1',5001,'中文');assert.deepEqual(changes,[5000]);assert.equal(reloads,0);
 episode.updateTitle('B:show:1:1',5001,'wrong');assert.equal(episode.source.getData(5000).title,'中文');
 episode.updateTitle('A:show:1:1',5001,'');assert.equal(episode.source.getData(5000).title,'E5001');
 changes=[];const marked=episodes.slice();marked[5000]={...marked[5000],watched:true};
 episode.replace('A:show:1:1',marked);assert.deepEqual(changes,[5000]);assert.equal(reloads,0);
 const groups=['pinned','new','aired','upcoming','hold'];
 const source=Array.from({length:10000},(_,i)=>({media:media(i+1),episode:{id:i+1,season:1,number:1,title:'E'+i,firstAired:'2026-01-01'},total:10,completed:i%7,group:groups[i%5],upcoming:i%5===3,fresh:i%2===0,pinned:i%5===0,held:i%5===4,recentAt:i%3,rating:i%7,randomOrder:i,userRating:i%4===0?undefined:i%10}));
 for(const sort of ['title','recent','remaining','newest','rating','random','userRating']){
   const prefs={...defaultProgress(),sort,descending:true};
   const translated=new Map(),loc=row=>({...row,localizedTitle:translated.get(row.media.id)||row.media.title,localizedEpisode:'原名'});
   const initial=source.map(loc),idx=new ProgressTitleOrder();
   idx.seed(source,sort,now,max,sortProgressCandidates(initial,prefs,'all',''));
   translated.set('show:5001','中文标题');idx.dirty(['show:5001']);
   let localized=0;const delta=idx.update(source,sort,now,prefs,'all','',row=>{localized++;return loc(row);});
   assert.equal(localized,1);
   assert.deepEqual(delta.map(x=>x.media.id),sortProgressCandidates(source.map(loc),prefs,'all','').map(x=>x.media.id));
   assert(idx.comparisonCount()<=14);
 }
 const prefs=defaultProgress(),idx=new ProgressTitleOrder();
 idx.seed(source,'query',now,max,sortProgressCandidates(source,prefs,'all','专有'));
 idx.dirty(['show:1']);const query=idx.update(source,'query',now,prefs,'all','专有',x=>({...x,localizedTitle:'专有'}));assert.deepEqual(query.map(x=>x.media.id),['show:1']);
 const {StableDisplayOrder}=require('./StableDisplayOrder');
 const {movieProgressRows,movieSortEligible,compareMovieSources,sameMovieSource}=require('./MovieProgressRules');
 const {projectCollection,collectionSortEligible,compareCollectionCandidates,defaultCollection,sameCollectionCandidate}=require('./CollectionRules');
 const {SearchCandidateTitles,searchRows,defaultSearch}=require('./SearchRules');
 for(const size of [393,10000]){
   const base=Array.from({length:size},(_,i)=>({row:{media:{id:'movie:'+(i+1),kind:'movie',title:'Movie '+(i%5),year:2020,watched:false},queued:true,watched:false,localEpisodes:-1,cloudEpisodes:-1},metadata:{id:'movie:'+(i+1),released:'2020-01-01',year:2020,rating:i%5,runtime:i%3,addedAt:i%7,userRating:i%4},translation:''}));
   const flags=[{id:'movie:1',pinned:true}],pins=new Set(['movie:1']),day='2026-01-10';
   for(const sort of ['title','added','rating','runtime','newest','random','userRating']){
     const options={sort,descending:true},query='',seed=23;
     const idx=new StableDisplayOrder(x=>x.row),source=base.map(x=>({...x}));
     idx.seed('movie',now,max,source,movieProgressRows(source,flags,options,day,query,seed));
     const translations=new Map();
     for(let j=0;j<100;j++){
       const x=source[(j*17)%size];translations.set(x.row.media.id,'中文'+j);idx.dirty(x.row.media.id);
       const patch=x=>({...x,translation:translations.get(x.row.media.id)||''});
       const delta=idx.update('movie',now,patch,x=>movieSortEligible(x,day,query),(a,b)=>compareMovieSources(a,b,options,pins,seed));
       assert.deepEqual(delta.map(x=>x.media.id),movieProgressRows(source.map(patch),flags,options,day,query,seed).map(x=>x.media.id));
     }
     assert.equal(idx.patchCount(),100);assert(idx.comparisonCount()<=100*Math.ceil(Math.log2(size+1)));
     assert.equal(idx.update('other',now,x=>x,()=>true,()=>0),undefined);
   }
   const candidates=base.map((x,i)=>({row:x.row,translation:'',added:i%3,recent:i%7,userRating:i%4,randomOrder:i%5,meta:{release:'2020-01-01',rating:i%3,runtime:i%6,genres:[],network:''}}));
   for(const sort of ['title','added','rating','runtime','newest','random','userRating','recent']){
     const options={...defaultCollection(),sort},idx=new StableDisplayOrder(x=>x.row);
     idx.seed('collection',now,max,candidates,projectCollection(candidates,options,'mine','',now).map(x=>x.row));
     const id=candidates[17].row.media.id;idx.dirty(id);
     const patch=x=>x.row.media.id===id?{...x,translation:'中文'}:x;
     const delta=idx.update('collection',now,patch,x=>collectionSortEligible(x,options,'mine','',now),(a,b)=>compareCollectionCandidates(a,b,options,'mine'));
     assert.deepEqual(delta,projectCollection(candidates.map(patch),options,'mine','',now).map(x=>x.row));
     assert.equal(idx.patchCount(),1);
   }
   // Stable equal-key ordering, additions/removals and state flips against full sort.
   for(const sort of ['title','added','rating','runtime','newest','random','userRating']){
     const options={sort,descending:true},seed=23,query='',idx=new StableDisplayOrder(x=>x.row);
     let source=base.slice();let prior=movieProgressRows(source,flags,options,day,query,seed);
     idx.seed('0',now,max,source,prior,'basis');
     const rounds=sort==='title'?100:1;
     for(let j=0;j<rounds;j++){
       const at=(j*17)%source.length;
       const old=source[at],changed={...old,row:{...old.row,watched:!old.row.watched}};
       const added={...base[0],row:{...base[0].row,media:{...base[0].row.media,id:'movie:'+(size+j+1)}},metadata:{...base[0].metadata,id:'movie:'+(size+j+1)}};
       source=source.slice();source[at]=changed;source.splice((at+1)%source.length,1);source.splice(at,0,added);
       const delta=idx.reconcile('v'+j,'basis',now,max,source,sameMovieSource,x=>movieSortEligible(x,day,query),(a,b)=>compareMovieSources(a,b,options,pins,seed));
       assert.deepEqual(delta,movieProgressRows(source,flags,options,day,query,seed));
       prior=delta;
     }
     assert(idx.patchCount()<=rounds*3);
     assert.equal(idx.reconcile('reordered','basis',now,max,source.slice().reverse(),sameMovieSource,()=>true,()=>0),undefined);
   }
   for(const sort of ['title','added','rating','runtime','newest','random','userRating','recent']){
     const options={...defaultCollection(),sort},idx=new StableDisplayOrder(x=>x.row);
     let source=candidates.slice();idx.seed('0',now,max,source,projectCollection(source,options,'mine','',now).map(x=>x.row),'basis');
     const rounds=sort==='title'?100:1;
     for(let j=0;j<rounds;j++){
       const at=(j*17)%source.length,old=source[at];
       const changed={...old,added:j,translation:'中文'+j};
       const added={...candidates[0],row:{...candidates[0].row,media:{...candidates[0].row.media,id:'movie:'+(size+j+1)}}};
       source=source.slice();source[at]=changed;source.splice((at+1)%source.length,1);source.splice(at,0,added);
       const delta=idx.reconcile('v'+j,'basis',now,max,source,sameCollectionCandidate,x=>collectionSortEligible(x,options,'mine','',now),(a,b)=>compareCollectionCandidates(a,b,options,'mine'));
       assert.deepEqual(delta,projectCollection(source,options,'mine','',now).map(x=>x.row));
     }
     assert(idx.patchCount()<=rounds*3);
   }
   const catalog=base.map(x=>({media:x.row.media,votes:0,localized:''}));
   const idx=new SearchCandidateTitles();idx.seed(catalog);
   const first=catalog[0];const id=catalog[17].media.id;idx.patch(id,'独特标题');
   assert.equal(catalog[0],first);assert.equal(idx.patchCount(),1);
   assert.deepEqual(searchRows({catalog,remote:[],query:'独特',suggestions:true,options:defaultSearch()}).map(x=>x.id),[id]);
   idx.clear();idx.patch(id,'wrong');assert.equal(catalog[17].localized,'独特标题');
 }
 console.log('393/10k movie and collection members: 100 state and membership transitions, every sort mode, exact full-sort equivalence and reorder fallback passed');
 console.log('393/10k candidates: 100 title changes preserve original stable movie sort; collection sort and ID-scoped search title changes passed');
 const full={media:media(1),seasons:[],status:'returning series',fetchedAt:now};
 const remote={id:'show:1',title:'Show 1',positions:[],watchedEpisodes:0};
 const input={full,remote,cloudActive:true,localIds:[1],decisions:[{episodeId:1,seq:1,watched:true}],timed:[{episodeId:1,seq:1,watched:true,changedAt:now}],checkpoints:[],common:[],now};
 const memo=new ShowProjectionCache();memo.begin('A');const signature=memo.stateKey(input);assert.equal(signature,showProjectionStateKey(input));
 const stringify=JSON.stringify;let calls=0;JSON.stringify=(...a)=>{calls++;return stringify(...a);};
 try{
   assert.equal(memo.stateKey({...input,now:now+1,localIds:[1],decisions:[{...input.decisions[0]}]}),signature);assert.equal(calls,0);
   const changed={...input,localIds:[2]};assert.notEqual(memo.stateKey(changed),signature);assert.equal(calls,1);
 }finally{JSON.stringify=stringify;}
 console.log('10k business tasks: one initial enumeration, 100 viewport cycles zero duplicate dispatch; 10k row single episode patch; seven sort modes exact delta parity; 100 frame publications; scoped stale result and projection signatures passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages/Index.ets").read_text()
lib=(root/"data/LibraryProjection.ets").read_text()
component=(root/"pages/DetailEpisodeList.ets").read_text()
assert "this.presentationQueues.lane(lane).update(visible,business,eligible,Date.now())" in page
assert "this.viewportFrame.consume(token)" in page and "this.presentationFrame.consume(token)" in page
assert "this.presentationQueues.clear()" in page and "queue.relevant(row)" in page
assert "this.presentationAttempts.nextAttempt(key)" in page
assert "this.episodeRowOwner.updateTitle(" in page and "source:this.episodeRowOwner.source" in page
assert "LazyForEach(this.source" in component
assert "this.progressTitleOrder.dirty(" in page and "const delta=index.update(candidates" in page
assert "work.key = cache.stateKey(input)" in lib
assert page.count("new PageStateOwner<")==9
assert "historyRows:PageStateOwner<HistoryEntry,HistoryEntry[]>" in page
assert "this.showCollectionTitleOrder.dirty(row.id)" in page and "this.movieCollectionTitleOrder.dirty(row.id)" in page
assert "this.activateDisplayOwner(JSON.stringify([account,scope]))" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Frame coalescing, independent display owners, viewport/business separation, incremental episode and progress sorting, original sync guards passed")

assert "this.searchTitleIndex.patch(row.id,row.text.title)" in page
assert "this.movieSortKey(query,utc,false)" in page and "this.collectionTitleOrder().update(" in page

assert "order.reconcile(this.movieSortKey(" in page and "this.collectionTitleOrder().reconcile(" in page
