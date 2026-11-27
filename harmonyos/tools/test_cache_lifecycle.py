#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","CacheLifecycle.ts","SearchRead.ts","ProgressRules.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{CacheLifecycle,cacheResidency,MemoryEvents}=require('./CacheLifecycle'),{SearchRead}=require('./SearchRead'),{stableProgressRandom}=require('./ProgressRules');
const life=new CacheLifecycle();assert(life.transition('search','A'));const first=life.generation();assert(!life.transition('search','A'));assert(life.current(first));assert(life.transition('progress','A'));assert(!life.current(first));
for(let i=0;i<100;i++){life.transition('search','A');assert(cacheResidency(true,'search','show','next',false).search);life.transition('progress','B');assert(!cacheResidency(true,'progress','show','calendar',false).progress);}
assert(!cacheResidency(false,'search','show','next',false).search);assert(!cacheResidency(true,'search','show','next',true).search);
const events=new MemoryEvents();let count=0;const cb=()=>count++;events.subscribe(cb);events.subscribe(cb);events.notify();events.unsubscribe(cb);events.notify();assert.equal(count,1);
const data=new Map(),history=new Map();let reads=0,unblock,hold=false;
const row=(i,title='Title '+i)=>({media:{id:'show:'+i,kind:'show',title,year:2026,watched:false},votes:i});
const store={read:async s=>{reads++;if(hold){hold=false;await new Promise(r=>unblock=r)}return data.get(s)||[]},write:async(s,rs)=>{const m=new Map((data.get(s)||[]).map(r=>[r.media.id,r]));rs.forEach(r=>m.set(r.media.id,r));data.set(s,[...m.values()])},recents:async s=>history.get(s)||[],remember:async(s,q)=>history.set(s,[q]),clear:async s=>history.delete(s)};
const repo=new SearchRead(store,{read:async()=>{throw Error('offline')}});
(async()=>{
repo.setResidentScope('A');await repo.rememberCatalog('A',[row(1)]);await repo.remember('A','test');const warm=await repo.catalog('A');assert.equal(await repo.catalog('A'),warm);
repo.setResidentScope('');const cold=await repo.catalog('A');assert.notEqual(cold,warm);assert.notEqual(await repo.catalog('A'),cold);assert.deepEqual(cold,warm);
repo.setResidentScope('A');assert.deepEqual(await repo.catalog('A'),warm);assert.deepEqual(await repo.recents('A'),['test']);
repo.releaseCatalogs();hold=true;const pending=repo.catalog('A');await Promise.resolve();await Promise.resolve();repo.setResidentScope('B');unblock();await pending;const old=reads;await repo.catalog('A');await repo.catalog('A');assert.equal(reads,old+2);
assert.deepEqual(await repo.catalog('B'),[]);await repo.rememberCatalog('A',[row(1,'Updated')]);repo.setResidentScope('A');assert.equal((await repo.catalog('A'))[0].media.title,'Updated');
assert.equal(stableProgressRandom('show:1'),stableProgressRandom('show:1'));assert.notEqual(stableProgressRandom('show:1'),stableProgressRandom('show:2'));
console.log('Cache lifecycle: 100 route/account transitions, memory event subscription, offline recovery, stale async catalog rejection, scoped history and stable random order passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
repo=(root/"data"/"PresentationRepository.ets").read_text()
search=(root/"data"/"SearchRepository.ets").read_text()
ability=(root/"entryability"/"EntryAbility.ets").read_text()
assert "onMemoryLevel(level: AbilityConstant.MemoryLevel)" in ability and "memoryEvents.notify()" in ability
assert "memoryEvents.unsubscribe(this.memoryListener)" in page and "this.cacheLifecycle.current(generation)" in page
assert "repo.setResidentScope(scope)" in page and "this.presentation?.releaseTransient()" in page
assert "repo.dirtyTitles.set(value.id,repo.lightTitle(value))" in repo and "repo.titles.set(value.id" not in repo
assert "SELECT payload FROM presentation_title WHERE id=?" in repo and "version!==this.residency" in repo
assert "batchInsertWithConflictResolution('search_catalog',values,relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)" in search
release=page.split("  private releaseInactiveCaches(",1)[1].split("  private scheduleLazyRows(",1)[0]
assert "store.mark(" not in release and "invalidateSync(" not in release and "this.cloud = undefined" not in release
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page and "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Native memory callback, lightweight title hydration, explicit search upsert, generation fencing and synchronization safety wiring passed")
