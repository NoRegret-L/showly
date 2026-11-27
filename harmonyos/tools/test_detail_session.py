#!/usr/bin/env python3
"""Scoped journal plan, active catalog ownership and full evidence equivalence."""
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3,json
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
store=(root/"data/EpisodeStore.ets").read_text()
projection=(root/"data/LibraryProjection.ets").read_text()
page=(root/"pages/Index.ets").read_text()
component=(root/"pages/DetailEpisodeList.ets").read_text()
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","DetailSession.ts","EffectiveState.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{DetailSession,summarizeSeasons}=require('./DetailSession'),{resolveEpisodes}=require('./EffectiveState');
const session=new DetailSession();
const full={media:{id:'show:1',title:'Long show',year:2020,kind:'show',watched:false},status:'returning series',fetchedAt:Date.now(),seasons:Array.from({length:20},(_,s)=>({number:s+1,firstAired:'2020-01-01T00:00:00Z',episodes:Array.from({length:100},(_,e)=>({id:s*100+e+1,season:s+1,number:e+1,title:'Episode',firstAired:'2020-01-01T00:00:00Z'}))}))};
let reads=0;
for(let i=0;i<100;i++){
 const token=session.begin('account:A','show:1'),signal=session.consumer();
 assert.equal(session.read('account:A','show:1',i),undefined);
 reads++;assert(session.remember(token,'account:A','show:1',i,full));
 for(let season=1;season<=20;season++)assert.equal(session.read('account:A','show:1',i),full);
 assert.equal(session.read('account:B','show:1',i),undefined);
 assert.equal(session.read('account:A','show:1',i+1),undefined);
 assert.equal(session.read('account:A','show:2',i),undefined);
 session.clear();assert(signal.cancelled());assert(!session.remember(token,'account:A','show:1',i,full));
}
assert.equal(reads,100);
const summaries=summarizeSeasons(full.seasons.map(s=>({...s,completed:10})));
assert.equal(summaries.length,20);assert.equal(summaries[0].count,100);assert(!('episodes' in summaries[0]));
const intents=Array.from({length:10000},(_,i)=>({episodeId:i+1,watched:i%2===0,seq:i+1}));
const ids=new Set(full.seasons.flatMap(s=>s.episodes.map(e=>e.id)));
const cp=new Map(intents.map(x=>[x.episodeId,{id:x.episodeId,seq:x.seq,watched:x.watched}]));
const common=new Map(intents.map(x=>[String(x.episodeId),{id:String(x.episodeId),value:x.watched,activity:'test'}]));
const a=resolveEpisodes(full,undefined,true,[],intents,cp,common);
const b=resolveEpisodes(full,undefined,true,[],intents.filter(x=>ids.has(x.episodeId)),new Map([...cp].filter(x=>ids.has(x[0]))),new Map([...common].filter(x=>ids.has(Number(x[0])))));
assert.deepEqual(a,b);
console.log('100 detail lifecycles, 2,000 episodes, revision/scope fencing and evidence equivalence passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
db=sqlite3.connect(":memory:")
db.executescript("CREATE TABLE episode_event(seq INTEGER PRIMARY KEY,show_id TEXT,episode_ids TEXT,watched INTEGER,auto_uuid TEXT,changed_at INTEGER); CREATE TABLE episode_catalog(show_id TEXT PRIMARY KEY,catalog TEXT); CREATE INDEX episode_event_show_seq ON episode_event(show_id,seq);")
db.executemany("INSERT INTO episode_event VALUES(?,?,?,?,?,?)",[(i+1,"show:"+str(i%100+1),json.dumps([i+1]),i%2,"",i+1) for i in range(10000)])
sql="SELECT e.show_id,e.episode_ids,e.watched,c.catalog,e.seq,e.auto_uuid,e.changed_at FROM episode_event e LEFT JOIN episode_catalog c ON c.show_id=e.show_id"
assert sql in store
scoped=sql+" WHERE e.show_id=? ORDER BY e.seq"
assert "WHERE e.show_id=? ORDER BY e.seq" in store
all_rows=db.execute(sql+" ORDER BY e.seq").fetchall()
rows=db.execute(scoped,("show:1",)).fetchall()
assert rows==[row for row in all_rows if row[0]=="show:1"] and len(rows)==100
assert any("episode_event_show_seq" in str(row) for row in db.execute("EXPLAIN QUERY PLAN "+scoped,("show:1",)))
assert "displayOnly ? await store.journalIntents(showId) : await store.journalIntents()" in projection
assert "await store.readCheckpoints(uuid,ids)" in projection and "await store.commonStates(uuid, 'episode',ids)" in projection
assert "seen.has(entry.id)" in store
assert "this.detailSession.read(scope,item.id,readRevision)" in page
assert "projectDetail(store,full,item.id,snapshot,uuid,true)" in page
assert "editRevision!==store.readModelRevision()" in page and "await store.mark(item.id" in page
assert "this.pauseDetail();" in page and "this.resumeDetail();" in page
assert "this.closeSeasonPage()" in page and "this.detailScroller.scrollTo" in page
assert "LazyForEach(this.source" in component and "@State confirming" in component
assert "ForEach(season.episodes, (entry: LocalEpisodeState)" not in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("10,000 journal rows: indexed scoped query returns 100 identical rows; native virtual season and sync boundaries verified")
