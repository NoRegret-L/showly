#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("ReadFlight","CacheLifecycle"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ReadFlight.ts","CacheLifecycle.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{ReadCancel,ConsumerReadFlight}=require('./ReadFlight'),{CacheLifecycle,cacheResidency}=require('./CacheLifecycle');
(async()=>{
 const f=new ConsumerReadFlight();let starts=0,stops=0,resolve;
 const work=scope=>{starts++;return new Promise((r,j)=>{resolve=r;scope.subscribe(()=>{stops++;j(Error('cancelled'))})})};
 const a=new ReadCancel(),b=new ReadCancel();
 const p=f.run('same',work,a).catch(e=>e.message),q=f.run('same',work,b);
 await Promise.resolve();a.cancel();assert.equal(stops,0);assert.equal(await p,'Read cancelled');resolve(42);assert.equal(await q,42);assert.equal(starts,1);
 const c=new ReadCancel();const x=f.run('same',work,c).catch(e=>e.message);await Promise.resolve();c.cancel();assert.equal(await x,'Read cancelled');
 const d=new ReadCancel();const y=f.run('same',work,d);await Promise.resolve();resolve(43);assert.equal(await y,43);assert.equal(starts,3);
 const life=new CacheLifecycle();
 for(let i=0;i<100;i++){life.transition('movie-next','A');let token=life.generation();assert(cacheResidency(true,'progress','movie','next',false).movieProgress);life.transition('movie-calendar','B');assert(!life.current(token));assert(cacheResidency(true,'progress','movie','calendar',false).movieCalendar);assert(!cacheResidency(false,'progress','movie','calendar',false).movieCalendar)}
 console.log('Shared read consumer cancellation, replacement flight, movie route and account isolation passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
for name in ("Show","Movie","Calendar","MovieCalendar","Collection","Detail","Discover","Search"):
    assert "@Watch('on"+name+"ViewChanged')" in page
assert "this.movieRowsSource.replace([],[],[])" in page and "this.movieCalendarRows.replace([],[],[])" in page
assert "repo.remote(client,query,consumer)" in page
detail=page.split("  private async loadDetailSummary(",1)[1].split("  private async loadDetailRating(",1)[0]
assert "consumer=this.detailConsumer" in detail
assert "readDetails(item,clientId,reload,consumer)" in detail
assert "this.detailCurrent(token,scope,item)&&this.clientId===clientId&&!consumer.cancelled()" in detail
assert "if(!current()){return;}" in detail
assert "this.detailOwner.summary(token,data,false,'')" in detail
assert "const rows = prepared;" in page and "return {items:rows,page:1,pages:1,total:rows.length};" in page
assert "this.viewport.update(item,season,urls,visible,slot)) { this.requestViewportPresentation();" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Scoped display watches, movie eviction, continuous list wiring and synchronization safety passed")
