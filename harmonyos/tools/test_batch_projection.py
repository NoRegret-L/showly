#!/usr/bin/env python3
"""Host SQL and production read-method fixtures. No device or remote writes."""
from pathlib import Path
import json, re, shutil, sqlite3, subprocess, tempfile, time
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
source=(root/"data"/"EpisodeStore.ets").read_text()
def region(start,end):
    return source.split(start,1)[1].split(end,1)[0]
def method(name):
    start=source.index("  async "+name+"(")
    # The production methods use two-space class indentation.
    end=source.index("\n  }",start)+len("\n  }")
    return source[start:end]
def sql_for(name):
    return re.findall(r"this\.queryRead\('([^']+)'",method(name))
bound_sql,=sql_for("boundAccount")
baseline_sql,=sql_for("cloudBaseline")
catalog_sql,event_sql=sql_for("projectionLocalInputs")
schedule_prefix,=sql_for("projectionCatalogs")
schedule_sql=schedule_prefix+','.join('?' for _ in range(393))+') ORDER BY show_id'
db=sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE episode_catalog(show_id TEXT PRIMARY KEY,catalog TEXT,updated_at INTEGER);
CREATE TABLE episode_restore_baseline(show_id TEXT PRIMARY KEY,episode_ids TEXT,verified INTEGER);
CREATE TABLE episode_event(seq INTEGER PRIMARY KEY,show_id TEXT,episode_ids TEXT,watched INTEGER,auto_uuid TEXT,changed_at INTEGER);
CREATE INDEX episode_event_show_seq ON episode_event(show_id,seq);
CREATE TABLE sync_binding(slot INTEGER PRIMARY KEY,account_uuid TEXT);
CREATE TABLE sync_cloud_baseline(account_uuid TEXT PRIMARY KEY,episode_ids TEXT,imported_at INTEGER);
CREATE TABLE episode_schedule(show_id TEXT PRIMARY KEY,payload TEXT);
""")
now=1768046400000
count=393
base=[]
db.execute("INSERT INTO sync_binding VALUES(1,'account-A')")
for i in range(1,count+1):
    ident="show:"+str(i)
    # Deliberately interleaved season order, duplicate IDs within one action,
    # restored baseline, explicit unwatch, later watch, and unknown event ID.
    episodes=[{"id":i*100+j,"season":s,"number":n,"title":f"E{j}"} for j,s,n in [(1,2,1),(2,1,2),(3,2,2),(4,1,1)]]
    cat={"showId":ident,"title":ident,"year":2025,"episodes":episodes}
    db.execute("INSERT INTO episode_catalog VALUES(?,?,?)",(ident,json.dumps(cat),now))
    base.append(i*100+1)
    db.execute("INSERT INTO episode_restore_baseline VALUES(?,?,0)",(ident,json.dumps([i*100+2])))
    for j,ids,watched in [(1,[i*100+1,i*100+1],0),(2,[i*100+3,i*100+99],1),(3,[i*100+1],1)]:
        db.execute("INSERT INTO episode_event VALUES(?,?,?,?,?,?)",(i*10+j,ident,json.dumps(ids),watched,"account-A" if j==3 else "",now+j))
    if i != count:  # one missing schedule must remain missing
        full={"media":{"id":ident,"kind":"show","title":ident,"year":2025,"watched":False},"status":"returning series","fetchedAt":now,
              "seasons":[{"number":s,"firstAired":"2025-01-01","episodes":[dict(ep,firstAired="2025-01-01") for ep in episodes if ep["season"]==s]} for s in (2,1)]}
        db.execute("INSERT INTO episode_schedule VALUES(?,?)",(ident,json.dumps(full)))
db.execute("INSERT INTO sync_cloud_baseline VALUES(?,?,?)",("account-A",json.dumps(base),now))
db.execute("INSERT INTO episode_schedule VALUES('show:999999','invalid unrelated JSON')")
db.commit()
queries=[]
db.set_trace_callback(lambda q: queries.append(q) if q.lstrip().upper().startswith("SELECT") else None)
def read(sql,args=()):
    return db.execute(sql,args).fetchall()
# Baseline uses the actual legacy query shapes and semantics from read().
legacy={}
start=time.perf_counter()
ids=[r[0] for r in read("SELECT show_id FROM episode_catalog ORDER BY show_id")]
for ident in ids:
    cat=json.loads(read("SELECT catalog FROM episode_catalog WHERE show_id = ?",(ident,))[0][0])
    events=read("SELECT episode_ids,watched FROM episode_event WHERE show_id = ? ORDER BY seq",(ident,))
    bound=read(bound_sql)[0][0]
    baseline=json.loads(read(baseline_sql,(bound,))[0][0])
    restored=json.loads(read("SELECT episode_ids FROM episode_restore_baseline WHERE show_id=?",(ident,))[0][0])
    flags=dict.fromkeys(baseline+restored,True)
    for raw,watched in events:
        for ep in json.loads(raw): flags[ep]=bool(watched)
    seasons={}
    for ep in cat["episodes"]:
        season=seasons.setdefault(ep["season"],[])
        if flags.get(ep["id"],False): season.append(ep["id"])
    legacy[ident]=[ep for season in seasons.values() for ep in season]
    read("SELECT payload FROM episode_schedule WHERE show_id=?",(ident,))
# Prior journalIntents() was one additional SELECT.
read("SELECT e.show_id,e.episode_ids,e.watched,c.catalog,e.seq,e.auto_uuid,e.changed_at FROM episode_event e LEFT JOIN episode_catalog c ON c.show_id=e.show_id ORDER BY e.seq")
old_count=len(queries)
old_ms=(time.perf_counter()-start)*1000
assert old_count==2+6*count,old_count
queries.clear()
start=time.perf_counter()
# Capture actual SQL result sets used by the extracted production methods.
fixture={}
fixture[bound_sql]=read(bound_sql)
fixture[catalog_sql]=read(catalog_sql)
fixture[baseline_sql]=read(baseline_sql,("account-A",))
fixture[event_sql]=read(event_sql)
read(bound_sql)
fixture[schedule_prefix]=read(schedule_sql,ids)
assert len(fixture[schedule_prefix])==392
assert any('SEARCH' in row[3] for row in read('EXPLAIN QUERY PLAN '+schedule_sql,ids))
new_count=len(queries)
new_ms=(time.perf_counter()-start)*1000
assert new_count==6,new_count
assert len(fixture[catalog_sql])==count and len(fixture[event_sql])==count*3
print(f"SQLite 393-show projection input fixture: {old_count} legacy SELECTs -> {new_count} batch SELECTs; host sample {old_ms:.2f} ms vs {new_ms:.2f} ms (not device latency)")
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    # Compile the actual production read methods with a minimal ResultSet
    # adapter. SQLite above supplies the real result rows, not invented API data.
    types="export interface LocalEpisode"+region("export interface LocalEpisode","export interface LocalEpisodeState")
    validators="function validId"+region("function validId","// Public catalog only")
    harness="""import { ReadEpisodeIdentity, ReadJournalEvent, validReadIds, replayWatchedIds } from './BatchEpisodeRead';
import { FullEpisodeCatalog, validateFullCatalog } from './ShowCatalog';
import { ScheduleReadCache, SQLITE_BIND_LIMIT, bindPlaceholders } from './IndexedProjection';
type Cell=string|number|null;
class FixtureResult {
  private index=-1;
  constructor(private rows: Cell[][]) {}
  goToFirstRow(): boolean { this.index=0;return this.rows.length>0; }
  goToNextRow(): boolean { return ++this.index<this.rows.length; }
  getString(i: number): string { return this.rows[this.index][i] as string; }
  getLong(i: number): number { return this.rows[this.index][i] as number; }
  isColumnNull(i: number): boolean { return this.rows[this.index][i]===null; }
  close(): void {}
}
"""+types+validators+"""
export class BatchHarness {
  private projectionRevision=0;
  private projectionSchedules=new ScheduleReadCache();
  public scheduleParses(){return this.projectionSchedules.parseCount();}
  public count=0;
  public changeAt=0;
  constructor(private fixture: Record<string,Cell[][]>) {}
  async queryRead(sql:string,args:(string|number)[]=[]):Promise<FixtureResult>{
    this.count++;
    if(this.changeAt===this.count)this.projectionRevision++;
    if(sql.startsWith('SELECT show_id,payload FROM episode_schedule WHERE show_id IN (')) {
      if(sql.split('?').length-1!==args.length || args.length>999)throw Error('Invalid bindings');
      return new FixtureResult(this.fixture['SELECT show_id,payload FROM episode_schedule WHERE show_id IN ('].filter(row=>args.includes(row[0] as string)));
    }
    if(!Object.prototype.hasOwnProperty.call(this.fixture,sql))throw Error('Unexpected SQL '+sql);
    if(args.length && (args.length!==1 || args[0]!=='account-A'))throw Error('Unexpected scope');
    return new FixtureResult(this.fixture[sql]);
  }
"""+ "\n".join(method(n) for n in ("boundAccount","cloudBaseline","projectionLocalInputs","projectionCatalogs"))+"\n}\n"
    (work/"BatchHarness.ts").write_text(harness,encoding="utf-8")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","BatchHarness.ts","BatchEpisodeRead.ts"],cwd=work,check=True)
    (work/"fixture.json").write_text(json.dumps({"queries":fixture,"legacy":legacy,"eventSql":event_sql,"boundSql":bound_sql,"scheduleSql":schedule_prefix,"now":now}),encoding="utf-8")
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const f=require('./fixture.json');
const {BatchHarness}=require('./BatchHarness.js');
const {replayWatchedIds,summarizeAired,validReadIds}=require('./BatchEpisodeRead.js');
const {aired}=require('./ShowCatalog.js');
(async()=>{
 const h=new BatchHarness(f.queries);
 const batch=await h.projectionLocalInputs('account-A');
 assert.equal(batch.states.length,393);
 assert.deepEqual(Object.fromEntries(batch.states.map(s=>[s.catalog.showId,s.watchedIds])),f.legacy);
 assert.equal(batch.intents.length,393*3);
 const intent=batch.intents.find(x=>x.episodeId===101);
 assert.equal(intent.watched,true);assert.equal(intent.seq,13);assert.equal(intent.autoUuid,'account-A');assert.equal(intent.catalogKnown,true);
 const unknown=batch.intents.find(x=>x.episodeId===199);assert.equal(unknown.catalogKnown,false);
 const all=new Set(batch.states.map(s=>s.catalog.showId));
 const schedules=await h.projectionCatalogs(all);
 assert.equal(schedules.size,392);assert.equal(schedules.has('show:393'),false);
 assert.equal(h.count,6);assert.equal(h.scheduleParses(),392);
 await h.projectionCatalogs(all);assert.equal(h.scheduleParses(),392);assert.equal(h.count,7);
 const changedSchedule=JSON.parse(JSON.stringify(f.queries));
 const warm=new BatchHarness(changedSchedule);await warm.projectionCatalogs(all);assert.equal(warm.scheduleParses(),392);
 const raw=JSON.parse(changedSchedule[f.scheduleSql][0][1]);raw.rating=8;changedSchedule[f.scheduleSql][0][1]=JSON.stringify(raw);
 await warm.projectionCatalogs(all);assert.equal(warm.scheduleParses(),393);
 // One, zero or many targets within SQLite's binding limit use at most one query.
 const one=new BatchHarness(f.queries);
 assert.equal((await one.projectionCatalogs(new Set())).size,0);assert.equal(one.count,0);
 assert.equal((await one.projectionCatalogs(new Set(['show:1']))).size,1);assert.equal(one.count,1);
 const many=new BatchHarness(f.queries);await many.projectionCatalogs(new Set(Array.from({length:1000},(_,i)=>'show:'+(i+1))));assert.equal(many.count,2);
 // Compare direct summary against original aired-filter + sort path.
 for(const state of batch.states) {
   const full=schedules.get(state.catalog.showId);if(!full)continue;
   const list=full.seasons.flatMap(s=>s.episodes).filter(e=>aired(e,f.now)).sort((a,b)=>a.season-b.season||a.number-b.number);
   const watched=new Set(state.watchedIds),next=list.find(e=>!watched.has(e.id));
   assert.deepEqual(summarizeAired(full,state.watchedIds,f.now),{total:list.length,completed:list.filter(e=>watched.has(e.id)).length,nextSeason:next?.season??0,nextNumber:next?.number??0,nextTitle:next?.title??''});
 }
 const changed=new BatchHarness(f.queries);changed.changeAt=3;
 await assert.rejects(changed.projectionLocalInputs('account-A'),/Local read inputs changed/);
 await assert.rejects(new BatchHarness(f.queries).projectionLocalInputs('account-B'),/Account binding changed/);
 const conflict=JSON.parse(JSON.stringify(f.queries));
 conflict[f.eventSql].push(['show:2','[101]',1,99999,'',f.now]);
 await assert.rejects(new BatchHarness(conflict).projectionLocalInputs('account-A'),/Conflicting episode identity/);
 const broken=JSON.parse(JSON.stringify(f.queries));broken[f.eventSql][0][1]='[]';
 await assert.rejects(new BatchHarness(broken).projectionLocalInputs('account-A'),/Invalid journal event/);
 assert.equal(validReadIds([1,1],false,true),true);
 assert.equal(validReadIds([1,1],true,true),false);
 assert.deepEqual(replayWatchedIds([{id:1,season:1}],new Set([1]),[],[{ids:[1],watched:false}]),[]);
 const boundary={media:{id:'show:1',kind:'show',title:'x',year:2025,watched:false},status:'returning series',fetchedAt:f.now,seasons:[{number:1,firstAired:'',episodes:[{id:1,season:1,number:1,title:'x',firstAired:new Date(f.now).toISOString()},{id:2,season:1,number:2,title:'future',firstAired:new Date(f.now+1).toISOString()},{id:3,season:1,number:3,title:'unknown',firstAired:''}]}]};
 assert.equal(summarizeAired(boundary,[],f.now-1).total,0);assert.equal(summarizeAired(boundary,[],f.now).total,1);assert.equal(summarizeAired(boundary,[1],f.now+1).nextNumber,2);
 console.log('Production batch methods: 393-state parity, 6 SELECTs, global identity conflict, revision/account changes, missing schedule, summary and air boundary passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
projection=(root/"data"/"LibraryProjection.ets").read_text()
page=(root/"pages"/"Index.ets").read_text()
comp=(root/"model"/"ProjectionCompute.ets").read_text()
lib=projection.split("export async function projectLibrary(",1)[1].split("export interface DetailProjection",1)[0]
assert "store.projectionLocalInputs(bound)" in lib and "store.projectionCatalogs(" in lib
assert "await store.backupStates()" not in lib and "await store.journalIntents()" not in lib and "await store.fullCatalog(" not in lib
assert lib.count("decodeIndexedProjection(")==1
assert "if (changedDisk.length) { await store.saveProjectionRows(diskScope,changedDisk); }" in lib
assert "summarizeAired(full,effective.ids,now)" in lib
assert "store.readModelRevision() !== revision" in lib
assert "JSON.stringify(row.episode)" not in comp
assert "initialRevision === store.readModelRevision()" in page and "initialSnapshot === snapshot" in page
assert "now >= initialProjection.computedAt && now < initialProjection.validUntil" in page
assert "store.readQueryCount() - queryStart" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
print("Batch projection wiring, first-pass reuse, query diagnostics and sync safety assertions passed")
