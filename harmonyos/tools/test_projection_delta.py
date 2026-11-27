#!/usr/bin/env python3
"""Actual production scoped read methods over SQL fixtures, cache and evidence parity."""
from pathlib import Path
import json,re,sqlite3,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
store=(root/"data/EpisodeStore.ets").read_text()
lib=(root/"data/LibraryProjection.ets").read_text()
page=(root/"pages/Index.ets").read_text()
def region(start,end):
    return store.split(start,1)[1].split(end,1)[0]
def method(name):
    start=store.index("  async "+name+"(")
    end=store.index("\n  }",start)+len("\n  }")
    return store[start:end]
sqls=re.findall(r"this\.queryRead\('([^']+)'",method("projectionLocalInputs"))
catalog,scoped_catalog,event,scoped_event=sqls
schedule_prefix,=re.findall(r"this\.queryRead\('([^']+)'",method("projectionCatalogs"))
def fixture(n):
    db=sqlite3.connect(":memory:")
    db.executescript("""
    CREATE TABLE episode_catalog(show_id TEXT PRIMARY KEY,catalog TEXT);
    CREATE TABLE episode_restore_baseline(show_id TEXT PRIMARY KEY,episode_ids TEXT);
    CREATE TABLE episode_event(seq INTEGER PRIMARY KEY,show_id TEXT NOT NULL,episode_ids TEXT,watched INTEGER,auto_uuid TEXT,changed_at INTEGER);
    CREATE INDEX episode_event_show_seq ON episode_event(show_id,seq);
    CREATE TABLE episode_schedule(show_id TEXT PRIMARY KEY,payload TEXT);
    """)
    now=1768046400000
    for i in range(1,n+1):
        ident="show:"+str(i)
        ep={"id":i,"season":1,"number":1,"title":"One"}
        cat={"showId":ident,"title":ident,"year":2025,"episodes":[ep]}
        full={"media":{"id":ident,"kind":"show","title":ident,"year":2025,"watched":False},"status":"returning series","fetchedAt":now,
              "seasons":[{"number":1,"firstAired":"2025-01-01","episodes":[dict(ep,firstAired="2025-01-01")]}]}
        db.execute("INSERT INTO episode_catalog VALUES(?,?)",(ident,json.dumps(cat)))
        db.execute("INSERT INTO episode_event VALUES(?,?,?,?,?,?)",(i,ident,json.dumps([i]),1,"",now+i))
        db.execute("INSERT INTO episode_schedule VALUES(?,?)",(ident,json.dumps(full)))
    cats=db.execute(catalog).fetchall(); events=db.execute(event).fetchall()
    assert len(cats)==n and len(events)==n
    assert len(db.execute(scoped_catalog,("show:1",)).fetchall())==1
    assert len(db.execute(scoped_event,("show:1",)).fetchall())==1
    assert any("episode_event_show_seq" in str(row) for row in db.execute("EXPLAIN QUERY PLAN "+scoped_event,("show:1",)))
    schedules=db.execute("SELECT show_id,payload FROM episode_schedule").fetchall()
    db.close()
    return {"n":n,"now":now,"catalog":catalog,"scopedCatalog":scoped_catalog,"event":event,"scopedEvent":scoped_event,
            "schedulePrefix":schedule_prefix,"cats":cats,"events":events,"schedules":schedules}
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    types="export interface LocalEpisode"+region("export interface LocalEpisode","export interface LocalEpisodeState")
    validators="function validId"+region("function validId","// Public catalog only")
    derived="  private localInputIndex"+region("  private localInputIndex","  private readQueries:")
    harness="""import {ReadEpisodeIdentity,ReadJournalEvent,validReadIds,replayWatchedIds} from './BatchEpisodeRead';
import {FullEpisodeCatalog,validateFullCatalog} from './ShowCatalog';
import {ScheduleReadCache,SQLITE_BIND_LIMIT,bindPlaceholders} from './IndexedProjection';
import {ProjectionInputIndex} from './ProjectionDelta';
import {CommitFence} from './CommitFence';
import {ReadCheckpoint} from './EffectiveState';
import {CommonEntry,commonId} from './ThreeWay';
type Cell=string|number|null;
interface Fixture {n:number;now:number;catalog:string;scopedCatalog:string;event:string;scopedEvent:string;schedulePrefix:string;cats:Cell[][];events:Cell[][];schedules:Cell[][]}
class Result {
 private i=-1;
 constructor(private rows:Cell[][]){}
 goToFirstRow(){this.i=0;return this.rows.length>0;}
 goToNextRow(){return ++this.i<this.rows.length;}
 getString(i:number){return this.rows[this.i][i] as string;}
 getLong(i:number){return this.rows[this.i][i] as number;}
 isColumnNull(i:number){return this.rows[this.i][i]===null;}
 close(){}
}
"""+types+validators+"""
export class Harness {
 private projectionFence=new CommitFence();
 private projectionSchedules=new ScheduleReadCache();
 account='account-A';
 checkpointPayload=JSON.stringify([{id:1,seq:1,watched:true}]);
 commonPayload=JSON.stringify([{id:'1',value:true,activity:'a'}]);
 catalogRows=0; eventRows=0; scheduleRows=0; evidenceRows=0;
 interrupt=false;
 constructor(public fixture:Fixture){}
 assertProjectionReadable(){return this.projectionFence.assertReadable();}
 projectionReadable(revision:number){return this.projectionFence.readable(revision);}
 projectionChangedIds(){return this.projectionFence.changedIds();}
 projectionGlobalChanged(){return this.projectionFence.globalChanged();}
 clearProjectionChanges(revision:number){if(this.projectionReadable(revision))this.projectionFence.clearChanges();}
 commit(ids:string[],success=true,unknown=false){const token=this.projectionFence.begin();this.projectionFence.finish(token,success,ids,unknown);}
 resetCounts(){this.catalogRows=0;this.eventRows=0;this.scheduleRows=0;this.evidenceRows=0;}
 async queryRead(sql:string,args:(string|number)[]=[]):Promise<Result>{
  if(sql===this.fixture.catalog||sql===this.fixture.scopedCatalog){
    const rows=sql===this.fixture.catalog?this.fixture.cats:this.fixture.cats.filter(x=>x[0]===args[0]);
    this.catalogRows+=rows.length;
    if(this.interrupt){this.interrupt=false;this.commit(['show:1']);}
    return new Result(rows);
  }
  if(sql===this.fixture.event||sql===this.fixture.scopedEvent){
    const rows=sql===this.fixture.event?this.fixture.events:this.fixture.events.filter(x=>x[0]===args[0]);
    this.eventRows+=rows.length;return new Result(rows);
  }
  if(sql.startsWith(this.fixture.schedulePrefix)){
    const ids=new Set(args), rows=this.fixture.schedules.filter(x=>ids.has(x[0] as string));
    this.scheduleRows+=rows.length;return new Result(rows);
  }
  if(sql==='SELECT account_uuid FROM sync_binding WHERE slot=1')return new Result([[this.account]]);
  if(args[0]!==this.account)throw Error('Wrong account');
  if(sql.includes('FROM sync_cloud_baseline'))return new Result([['[]']]);
  if(sql.includes('FROM episode_read_checkpoint')){this.evidenceRows++;return new Result([[this.checkpointPayload]]);}
  if(sql.includes('FROM sync_common_state')){this.evidenceRows++;return new Result([[this.commonPayload]]);}
  throw Error('Unexpected SQL '+sql);
 }
"""+derived+"\n"+"\n".join(method(n) for n in ("boundAccount","cloudBaseline","projectionLocalInputs","projectionCatalogs","readCheckpoints","commonStates"))+"\n}\n"
    (work/"Harness.ts").write_text(harness,encoding="utf-8")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Harness.ts","ProjectionCompute.ts"],cwd=work,check=True)
    (work/"fixtures.json").write_text(json.dumps([fixture(393),fixture(10000)]),encoding="utf-8")
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {Harness}=require('./Harness');
const {computeProjection,ShowProjectionCache,showProjectionStateKey}=require('./ProjectionCompute');
const {summarizeAired}=require('./BatchEpisodeRead');
const fixtures=require('./fixtures.json');
const order=x=>({states:x.states.slice().sort((a,b)=>a.catalog.showId.localeCompare(b.catalog.showId)),intents:x.intents.slice().sort((a,b)=>a.episodeId-b.episodeId)});
(async()=>{
 for(const f of fixtures){
  const h=new Harness(f),ids=new Set(f.cats.map(x=>x[0]));
  const first=await h.projectionReadInputs('account-A');
  const schedules=await h.projectionReadCatalogs(ids);
  assert.equal(first.states.length,f.n);assert.equal(schedules.size,f.n);
  assert.deepEqual([h.catalogRows,h.eventRows,h.scheduleRows],[f.n,f.n,f.n]);
  await h.projectionCheckpoints('account-A');await h.projectionCommonStates('account-A');
  h.resetCounts();
  const oldParse=JSON.parse;let parses=0;
  JSON.parse=(...args)=>{parses++;return oldParse(...args);};
  try {
   const hot=await h.projectionReadInputs('account-A');
   await h.projectionReadCatalogs(ids);await h.projectionCheckpoints('account-A',new Set([1]));await h.projectionCommonStates('account-A',new Set([1]));
   assert.equal(hot.states.find(x=>x.catalog.showId==='show:2'),first.states.find(x=>x.catalog.showId==='show:2'));
   assert.deepEqual([h.catalogRows,h.eventRows,h.scheduleRows,h.evidenceRows,parses],[0,0,0,0,0]);
   h.commit(['show:1'],false);
   await h.projectionReadInputs('account-A');assert.equal(h.catalogRows,0);
   f.events.push(['show:1','[1]',0,f.n+1,'',f.now+f.n+1]);
   h.commit(['show:1']);
   const next=await h.projectionReadInputs('account-A');
   const nextSchedules=await h.projectionReadCatalogs(ids);
   assert.deepEqual([h.catalogRows,h.eventRows,h.scheduleRows],[1,2,1]);assert.equal(parses,3);
   assert.equal(next.states.find(x=>x.catalog.showId==='show:2'),first.states.find(x=>x.catalog.showId==='show:2'));
   assert.equal(nextSchedules.get('show:2'),schedules.get('show:2'));
   assert.deepEqual(next.states.find(x=>x.catalog.showId==='show:1').watchedIds,[]);
   h.resetCounts();
   const scoped=await h.projectionReadInputs('account-A',new Set(['show:1']));
   assert.equal(scoped.states.length,1);assert.equal(scoped.intents.length,1);
   assert.deepEqual(scoped.states[0],next.states.find(x=>x.catalog.showId==='show:1'));
   const scopedSchedules=await h.projectionReadCatalogs(new Set(['show:1']),true);
   assert.equal(scopedSchedules.size,1);
   assert.equal((await h.projectionReadCatalogs(ids)).get('show:2'),schedules.get('show:2'));
   assert.deepEqual([h.catalogRows,h.eventRows,h.scheduleRows],[0,0,0]);
   assert.deepEqual(order(next),order(await h.projectionLocalInputs('account-A')));
   console.log(f.n+' shows: hot 0 catalog/event/schedule rows and 0 parses; single edit 1 catalog + 2 events + 1 schedule row, 3 parses; full parity passed');
  }finally{JSON.parse=oldParse;}
  // Corrupt only the derived owner index, then verify automatic full rebuild.
  h.localInputIndex.owner.set(1,'show:999999');
  h.commit(['show:1']);h.resetCounts();
  assert.deepEqual(order(await h.projectionReadInputs('account-A')),order(await h.projectionLocalInputs('account-A')));
  // Real authoritative conflict must fail closed, including unknown event IDs.
  f.events.push(['show:1','[2]',1,f.n+2,'',f.now+f.n+2]);h.commit(['show:1']);
  await assert.rejects(h.projectionReadInputs('account-A'),/Conflicting episode identity/);
  f.events.pop();h.commit(['show:1']);assert.equal((await h.projectionReadInputs('account-A')).states.length,f.n);
  h.commit(['show:1']);h.interrupt=true;
  await assert.rejects(h.projectionReadInputs('account-A'),/inputs changed/i);
  await h.projectionReadInputs('account-A');
  h.checkpointPayload='broken';h.commit([]);
  await assert.rejects(h.projectionCheckpoints('account-A'));
  h.checkpointPayload='[]';h.commit([]);assert.equal((await h.projectionCheckpoints('account-A')).size,0);
  h.account='account-B';h.commit([]);await assert.rejects(h.projectionReadInputs('account-A'),/Account binding changed/);
  assert.equal((await h.projectionReadInputs('account-B')).states.length,f.n);
  h.releaseProjectionReadCache();h.resetCounts();await h.projectionReadInputs('account-B');assert.equal(h.catalogRows,f.n);
 }
 const f=fixtures[0],full=JSON.parse(f.schedules[0][1]);const now=f.now;
 full.seasons[0].episodes[0].firstAired=new Date(now+1).toISOString();full.seasons[0].firstAired=new Date(now+1).toISOString();
 const input={full,cloudActive:false,localIds:[],decisions:[],timed:[],checkpoints:[],common:[],now};
 const out=computeProjection(input),key=showProjectionStateKey(input),cache=new ShowProjectionCache();
 assert.deepEqual(out.summary,summarizeAired(full,[],now));assert.equal(out.summary.total,0);
 cache.begin('account-A');cache.put(full.media.id,key,now,out,'catalog');assert(!cache.diskKnown(full.media.id,key,now,'catalog'));
 cache.markDiskKnown(full.media.id,key,'catalog');assert(cache.diskKnown(full.media.id,key,now,'catalog'));assert.equal(cache.get(full.media.id,key,now,'catalog'),out);
 assert.equal(cache.get(full.media.id,key,now+1,'catalog'),undefined);
 const after=computeProjection({...input,now:now+1});assert.equal(after.summary.total,1);
 cache.begin('account-B');assert(!cache.diskKnown(full.media.id,key,now,'catalog'));
 console.log('Derived index recovery, global conflict, concurrent commit, evidence corruption, account isolation, memory eviction, summary boundary and confirmed disk reuse passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
assert "store.projectionReadInputs(bound)" in lib and "store.projectionReadCatalogs(targetIds)" in lib
assert "this.projectionChangedIds()" in store and "this.clearProjectionChanges(revision)" in store
assert "await this.projectionLocalInputs(bound,undefined,baseline)" in store
assert "store.projectionPositions(full)" in lib and "calculated?.summary ?? summarizeAired" in lib
assert "store.readProjectionRows(diskScope,diskNeeded)" in lib and "cache.diskKnown(" in lib
assert "store.projectionCheckpoints(uuid,ids)" in lib and "store.projectionCommonStates(uuid,ids)" in lib
assert "await store.readCheckpoints(uuid,ids)" in lib and "await store.commonStates(uuid, 'episode',ids)" in lib
assert "this.episodeStore?.releaseProjectionReadCache()" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Production incremental projection, authoritative fallback, unchanged sync write and verification paths passed")

assert "store.projectionReadInputs(bound,scope.ids)" in lib and "store.projectionReadCatalogs(targetIds,true)" in lib
assert "store.acknowledgeLibrary(revision)" in lib and "this.libraryProjectionSession.read(" in page
assert "hiTraceMeter.startTrace(" in lib and "hiTraceMeter.finishTrace(" in lib
assert "workerInputBytes=utf8ProjectionBytes(payload)" in lib
