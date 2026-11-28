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
(async()=>{
 for(const size of [393,10000]){
  const pages=new PageWorkSet(),owners=new Map();
  for(const page of ['show','movie','calendar','movieCalendar','library','discover','search']){
   const owner=new PageStateOwner(row=>[row.id]);owners.set(page,owner);pages.register(page,owner.work);
  }
  const show=owners.get('show'),movie=owners.get('movie'),jobs=new PageSortJobs(pages);
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
  show.activate('B');show.replace(rows,ids,keys);
  let complete;
  const pending=show.submit(rows.slice().reverse(),ids.slice().reverse(),keys.slice().reverse(),input=>new Promise(resolve=>{complete=()=>resolve(planListDiff(input));}),()=>true);
  show.activate('C');complete();assert.equal(await pending,false);assert.equal(show.totalCount(),0);
 }
 console.log('393/10k page owners: 100 scoped commits, zero unrelated movie invalidations, exact row patches, duplicate suppression, 100 account/route cancellations, stale list rejection passed');
})().catch(e=>{console.error(e);process.exit(1)});
""")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
assert page.count("new PageStateOwner<")==7
assert "this.pageWorks.observe(" in page
assert "work.current(ticket)" in page
assert "this.activePresentationRoute()" in page
assert "this.showRows.work.publishSummary(" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Page state ownership integration and sync guards passed")
