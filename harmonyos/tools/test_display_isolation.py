#!/usr/bin/env python3
"""Pure diff, latest-request gates and sort equivalence; native device separate."""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    (work/"arkui.d.ts").write_text("interface IDataSource { totalCount(): number; getData(index:number): unknown; registerDataChangeListener(l:DataChangeListener):void; unregisterDataChangeListener(l:DataChangeListener):void; } interface DataChangeListener { onDataReloaded():void; onDataChange(i:number):void; onDataAdd(i:number):void; onDataDelete(i:number):void; onDataMove(a:number,b:number):void; }")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","ListDiff.ts","LazyRows.ts","DisplayJobs.ts","DisplaySort.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {planListDiff}=require('./ListDiff.js');
const {LazyRows}=require('./LazyRows.js');
const {DisplayRevisions,LatestDisplayJobs}=require('./DisplayJobs.js');
const sort=require('./DisplaySort.js'), progress=require('./ProgressRules.js'), collection=require('./CollectionRules.js'), movie=require('./MovieProgressRules.js');
const rev=new DisplayRevisions();
rev.collectionChanged();assert.deepEqual([rev.show,rev.movie,rev.collection],[0,0,1]);
rev.moviesChanged();assert.deepEqual([rev.show,rev.movie,rev.collection],[0,1,2]);
rev.showsChanged();assert.deepEqual([rev.show,rev.movie,rev.collection],[1,1,3]);
const jobs=new LatestDisplayJobs(), a=jobs.begin('show','A'), b=jobs.begin('show','B'), c=jobs.begin('movie','A');
assert.equal(jobs.begin('show','B'),0);assert(jobs.matches('show','B'));assert(!jobs.matches('show','A'));assert(!jobs.current('show',a));assert(!jobs.finish('show',a));
assert(jobs.current('show',b));assert(jobs.current('movie',c));jobs.clear();assert(!jobs.current('movie',c));
let seed=19;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed};
const perm=()=>{const x=Array.from({length:16},(_,i)=>String(i)).filter(()=>rand()%3!==0);for(let i=x.length-1;i>0;i--){const j=rand()%(i+1);[x[i],x[j]]=[x[j],x[i]]}return x};
let trials=0;
function check(oldIds,ids){
 const oldKeys=oldIds.map(x=>x+':old'),keys=ids.map(x=>x+(rand()%4===0?':new':':old'));
 const data=new LazyRows(), seen=[];
 let expected=[...oldIds], rendered=[...oldKeys];
 data.replace(oldIds,oldIds,oldKeys);
 data.registerDataChangeListener({
  onDataReloaded(){expected=[...ids];rendered=[...keys];seen.push('reload')},
  onDataDelete(i){expected.splice(i,1);rendered.splice(i,1);seen.push('delete')},
  onDataAdd(i){expected.splice(i,0,data.getData(i));rendered.splice(i,0,keys[i]);seen.push('add')},
  onDataMove(a,b){[expected[a],expected[b]]=[expected[b],expected[a]];[rendered[a],rendered[b]]=[rendered[b],rendered[a]];seen.push('move')},
  onDataChange(i){rendered[i]=keys[i];seen.push('change')}
 });
 data.replace(ids,ids,keys);
 assert.deepEqual(expected,ids);assert.deepEqual(rendered,keys);
 assert.deepEqual(Array.from({length:data.totalCount()},(_,i)=>data.getData(i)),ids);
 ids.forEach((id,i)=>assert.equal(data.keyFor(id),id+':'+keys[i]));
 if(oldIds.length&&ids.length)assert(!seen.includes('reload'));
 trials++;
}
for(let n=0;n<512;n++)check(perm(),perm());
const d=new LazyRows(), updates=[];
d.replace(['a','b'],['a','b'],['1','1']);
d.registerDataChangeListener({onDataReloaded:()=>updates.push('reload'),onDataAdd:()=>updates.push('add'),onDataDelete:()=>updates.push('delete'),onDataMove:()=>updates.push('move'),onDataChange:i=>updates.push('change:'+i)});
d.replace(['a','B'],['a','b'],['1','2']);assert.deepEqual(updates,['change:1']);
let release;
(async()=>{
 const old=d.submit(['B','a'],['b','a'],['2','1'],input=>new Promise(r=>{release=()=>r(planListDiff(input))}),()=>true);
 d.replace([],[],[]);release();assert.equal(await old,false);assert.equal(d.totalCount(),0);
 d.replace(['a','b'],['a','b'],['1','1']);
 const stale=await d.submit(['b','a'],['b','a'],['1','1'],async x=>planListDiff(x),()=>false);
 assert.equal(stale,false);assert.equal(d.getData(0),'a');
 const fresh=await d.submit(['b','a'],['b','a'],['1','1'],async x=>planListDiff(x),()=>true);
 assert(fresh);assert.equal(d.getData(0),'b');assert.equal(d.keyFor('a'),'a:1');
 const now=Date.parse('2026-01-10T12:00:00Z'), prefs=progress.defaultProgress(), flags=[];
 const media=(i,kind)=>({id:kind+':'+i,kind,title:i%2?'The '+i:'A '+i,year:2025,watched:false});
 const sources=Array.from({length:393},(_,i)=>({media:media(i+1,'show'),episodes:[{episode:{id:i+1,season:1,number:1,title:'Episode',firstAired:'2025-01-01'},watched:false,watchedAt:0}],recentAt:i,rating:i%10,randomOrder:i}));
 const rows=sources.map(x=>progress.selectProgress(x,prefs,flags,now));
 const base=Array.from({length:393},(_,i)=>({media:media(i+1,'movie'),queued:true,watched:false,localEpisodes:-1,cloudEpisodes:-1,sections:[],merged:true}));
 const movies=base.map((row,i)=>({row,translation:i%2?'电影':'',metadata:{id:row.media.id,released:'2025-01-01',year:2025,rating:i%10,runtime:i+30}}));
 const candidates=base.map((row,i)=>({row,translation:i%2?'电影':'',added:i,randomOrder:i}));
 let comparisons=0;
 for(const query of ['', 'A', '电影'])for(const descending of [true,false]){
  for(const mode of ['recent','remaining','title','rating','random']){
   const p={...prefs,sort:mode,descending};
   assert.deepEqual(sort.sortShowDisplay({rows,prefs:p,filter:'all',query}),progress.sortProgressCandidates(rows,p,'all',query));comparisons++;
  }
  for(const mode of ['added','title','runtime','rating','random','userRating']){
   const o={sort:mode,descending};
   assert.deepEqual(sort.sortMovieDisplay({sources:movies,flags,options:o,utc:'2026-01-10',query,seed:42}),movie.movieProgressRows(movies,flags,o,'2026-01-10',query,42));comparisons++;
   const co={...collection.defaultCollection(),sort:mode,descending};
   assert.deepEqual(sort.sortCollectionDisplay({candidates,options:co,section:'queue',query,now}),collection.projectCollection(candidates,co,'queue',query,now).map(x=>x.row));comparisons++;
  }
 }
 console.log('Display isolation: '+trials+' diff replay cases, one row change, stale clear/route rejection, '+comparisons+' sort parity cases passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
tasks=(root/"data"/"DisplayTasks.ets").read_text()
assert "this.listRevision" not in page
assert "this.displayRevisions.showsChanged()" in page and "this.displayRevisions.moviesChanged()" in page
assert "this.displayRevisions.collectionChanged()" in page
assert "this.flagVersion('show')" in page and "this.hiddenVersion('show')" in page
assert page.count("differ,current)")==7
assert page.count("this.sortJobs.current(slot,token)")==3
assert page.count("epoch !== this.presentationEpoch")>=3
assert "this.validateNextTarget(row)" in page
assert "this.movieProgressRows('',true).find(" in page
assert "executeDisplayTask(new taskpool.Task(showDisplayTask" in tasks and "executeDisplayTask(new taskpool.Task(movieDisplayTask" in tasks and "executeDisplayTask(new taskpool.Task(collectionDisplayTask" in tasks
assert "executeDisplayTask(new taskpool.Task(diffDisplayTask" in tasks
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Display worker, domain dependency, live mark verification and native list wiring passed")
