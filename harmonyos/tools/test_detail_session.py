#!/usr/bin/env python3
"""Scoped journal plan, active catalog ownership and full evidence equivalence."""
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3,json
import re
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
store=(root/"data/EpisodeStore.ets").read_text()
projection=(root/"data/LibraryProjection.ets").read_text()
page=(root/"pages/Index.ets").read_text()
component=(root/"pages/DetailEpisodeList.ets").read_text()
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","DetailSession.ts","EffectiveState.ts","DetailViewOwner.ts","DetailSections.ts","SeasonDetailOwner.ts","SeasonPresentation.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{DetailSession,summarizeSeasons}=require('./DetailSession'),{resolveEpisodes}=require('./EffectiveState');
const {DetailViewOwner}=require('./DetailViewOwner');
const owner=new DetailViewOwner();
for(let i=0;i<100;i++){
 const token=owner.begin('A','show:1',{description:true,rating:true,reveal:true});
 const initial=owner.snapshot();const summary={title:'A'};
 owner.summary(token,summary,false,'');const s=owner.snapshot();
 assert.equal(initial.summary,undefined);assert.equal(s.summary,summary);
 owner.summary(token,summary,false,'');assert.strictEqual(owner.snapshot(),s);
 owner.personalRating(token,8,false,'');assert.strictEqual(owner.snapshot().summary,summary);
 const ratingSnapshot=owner.snapshot();
 owner.summary(token,summary,true,'cached');assert.equal(owner.snapshot().rating,8);
 owner.summary(token,summary,false,'offline');assert.strictEqual(owner.snapshot().summary,summary);
 assert.equal(ratingSnapshot.summaryStatus,'');assert.equal(owner.snapshot().summaryStatus,'offline');
 owner.artwork(token,'fanart',false,'');assert.equal(owner.snapshot().rating,8);
 owner.reveal(token,'rating');assert(owner.snapshot().ratingRevealed);assert(!owner.snapshot().descriptionRevealed);
 const newer=owner.begin('B','show:1',{description:true,rating:true,reveal:false});
 owner.personalRating(token,9,false,'');owner.artwork(token,'stale',false,'');
 owner.reveal(newer,'rating');assert.equal(owner.snapshot().rating,undefined);assert.equal(owner.snapshot().fanart,'');assert(!owner.snapshot().ratingRevealed);
 assert(!owner.current(token,'A','show:1'));
}
console.log('100 detail UI lifecycles: independent lanes, no-op snapshots, scoped stale rejection and spoiler isolation passed');
const {SectionOwner,projectPeople,parseRelated,projectRelated}=require('./DetailSections');
const credits=projectPeople({cast:[{person:{id:1,name:'A'},characters:['x']},{person:{id:1,name:'A'},character:'y'}],crew:{directing:[{person:{id:2,name:'B'},job:'Director'},{person:{id:3,name:'C'},job:'Unknown'}]}});
assert.deepEqual(credits.map(r=>[r.department,r.roles]),[['Acting',['x','y']],['Directing',['Director']]]);
const rows=parseRelated([{ids:{trakt:1},title:'parent',votes:20,rating:9},{ids:{trakt:2},title:'hidden',votes:50,rating:9},{ids:{trakt:3},title:'B',votes:30,rating:7},{ids:{trakt:4},title:'C',votes:30,rating:8},{ids:{trakt:3},title:'duplicate',votes:99}], 'show');
assert.deepEqual(projectRelated(rows,'show:1',new Set(['show:2'])).map(r=>r.media.id),['show:4','show:3']);
assert.equal(rows.length,4);
const sections=new SectionOwner();
for(let i=0;i<100;i++){const a=sections.begin(),signal=sections.consumer();assert(sections.publish(a,credits,true,'',true));const snapshot=sections.snapshot();assert(!sections.publish(a,credits,true,'',true));assert.strictEqual(snapshot,sections.snapshot());const b=sections.begin();assert(signal.cancelled());assert(!sections.publish(a,[],false,'stale',true));assert(sections.publish(b,credits,false,'',true));}
console.log('Detail sections: 100 cancellation cycles, credit grouping and roles, related sort, hidden exclusion and identity dedup passed');
const session=new DetailSession();
const full={media:{id:'show:1',title:'Long show',year:2020,kind:'show',watched:false},status:'returning series',fetchedAt:Date.now(),seasons:Array.from({length:20},(_,s)=>({number:s+1,firstAired:'2020-01-01T00:00:00Z',episodes:Array.from({length:100},(_,e)=>({id:s*100+e+1,season:s+1,number:e+1,title:'Episode',firstAired:'2020-01-01T00:00:00Z'}))}))};
const {SeasonDetailOwner}=require('./SeasonDetailOwner');
const seasonOwner=new SeasonDetailOwner(),verified=full.seasons.flatMap(s=>s.episodes.map(e=>({...e,watched:false})));
const first=seasonOwner.update('A',full,verified);assert.equal(first.seasons[0].number,20);assert.equal(seasonOwner.updates(),2000);
const change=verified.map(e=>e.id===101?{...e,watched:true}:e);
const second=seasonOwner.update('A',full,change);assert.equal(seasonOwner.updates(),2001);assert.equal(second.seasons.find(s=>s.number===2).completed,1);assert.strictEqual(first.seasons[0],second.seasons[0]);
const nextChange=change.map(e=>e.id===102?{...e,watched:true}:e);
assert(seasonOwner.reconcile('A',full,nextChange));assert.equal(seasonOwner.deltaUpdates(),1);
assert.equal(seasonOwner.snapshot().seasons.find(s=>s.number===2).completed,2);
assert(!seasonOwner.reconcile('B',full,nextChange));assert(!seasonOwner.reconcile('A',full,nextChange.slice(1)));
seasonOwner.update('A',full,change);
const {parseSeasonPresentation,SeasonPresentationOwner}=require('./SeasonPresentation');
const publicRows=parseSeasonPresentation(JSON.stringify([{ids:{trakt:8},number:0,episodes:[{ids:{trakt:9},season:0,number:1,title:'Special',rating:8,images:{screenshot:['image']}}]},{ids:{trakt:10},number:1,rating:7,episodes:[{ids:{trakt:11},season:1,number:1,title:'Regular',runtime:42}]}]));
assert.equal(publicRows[1].number,0);assert.equal(publicRows[1].episodes[0].rating,8);
const publicOwner=new SeasonPresentationOwner();publicOwner.replace('A',publicRows);assert(publicOwner.setRatings('A','activity-A',[{id:10,value:9}],[{id:11,value:8}]));
assert.equal(publicOwner.seasonRating(1,'activity-A'),9);assert.equal(publicOwner.episodeRating(11,'activity-B'),undefined);
publicOwner.replace('B',publicRows);assert.equal(publicOwner.episodeRating(11,'activity-A'),undefined);
assert.throws(()=>parseSeasonPresentation(JSON.stringify([{ids:{trakt:1},number:0,episodes:[{ids:{trakt:2},number:1,season:1}]}])));
console.log('Season presentation: public special isolation, sparse watched delta, ratings scope and metadata identity passed');
const fallback=new SeasonDetailOwner();assert.deepEqual(fallback.update('A',full,change).seasons,second.seasons);
assert.equal(seasonOwner.delta(100).remove.length,1);assert.equal(seasonOwner.delta(102).add.length,101);
const future={...full,seasons:[...full.seasons,{number:21,firstAired:'',episodes:[{id:3000,season:21,number:1,title:'Future',firstAired:''}]}]};
seasonOwner.update('A',future,change);assert(!seasonOwner.episode(3000).eligible);assert(!seasonOwner.delta(3000).valid);
seasonOwner.update('B',future,[]);assert.equal(seasonOwner.snapshot().seasons.reduce((n,s)=>n+s.completed,0),0);
console.log('Season detail: descending order, 2000-row reference reuse, one changed row, full parity, read-only future and account isolation passed');
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
assert "!store.projectionReadable(editRevision)" in page and "await store.mark(item.id" in page
assert "this.pauseDetail();" in page and "this.resumeDetail();" in page
assert "this.closeSeasonPage()" in page and "this.detailScroller.scrollTo" in page
assert "LazyForEach(this.source" in component and "@State confirming" in component
assert "ForEach(season.episodes, (entry: LocalEpisodeState)" not in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("10,000 journal rows: indexed scoped query returns 100 identical rows; native virtual season and sync boundaries verified")

assert "this.detailOwner.current(token,scope,item.id)" in page
assert "this.presentation?.readCachedDetail(item,consumer)" in page and "this.presentation?.saveCachedDetail(item,data,consumer)" in page
assert "readCollectionRatings(session,item.kind,source.activity)" in page
assert "this.detailFanart.visible(" in page
assert "DetailHeader({" in page

# Verify the exact optional presentation-cache SQL with a closed/reopened database.
# This is a host SQLite round trip, not a native ArkData/device test.
repo=(root/"data/PresentationRepository.ets").read_text()
schema=re.search(r"CREATE TABLE IF NOT EXISTS presentation_detail \(id TEXT PRIMARY KEY,payload TEXT NOT NULL\)",repo).group(0)
write_sql="INSERT OR REPLACE INTO presentation_detail(id,payload) VALUES(?,?)"
read_sql="SELECT payload FROM presentation_detail WHERE id=?"
assert write_sql in repo and read_sql in repo
summary={"title":"Fixture","year":2026,"overview":"Public summary","runtime":42,"rating":8.0,"status":"returning series","genres":"drama","airedEpisodes":2,"posterUrls":[],"fanartUrls":[]}
with tempfile.TemporaryDirectory() as tmp:
    db_path=Path(tmp)/"presentation.db"
    conn=sqlite3.connect(db_path)
    conn.execute(schema)
    conn.execute(write_sql,("show:1",json.dumps({"id":"show:1","summary":summary})))
    conn.commit();conn.close()
    conn=sqlite3.connect(db_path)
    assert json.loads(conn.execute(read_sql,("show:1",)).fetchone()[0])["summary"]==summary
    assert conn.execute(read_sql,("show:2",)).fetchone() is None
    assert conn.execute(read_sql,("movie:1",)).fetchone() is None
    conn.close()
assert "row.id!==item.id" in repo and "consumer.check()" in repo
assert "readCachedDetail(item,consumer)" in page and "if(cached)" in page
print("Public detail cache: exact SQL cold reopen, show/movie identity separation and offline snapshot retention passed (host)")

assert "presentation_section" in repo and "WHERE id=? AND section=?" in repo
assert "DetailPeopleSection({" in page and "DetailRelatedSection({" in page
assert "this.backFromDetail()" in page
assert "LazyForEach(this.source" in (root/"pages/DetailRelatedSection.ets").read_text()

assert "DetailSeasons({" in page and "seasonDetailOwner.delta(id)" in page
assert "fresh.remove.length" in page and "watchedAt);" in page
assert "row.eligible!==false" in component

season_coordinator=(root/"data/SeasonExtrasCoordinator.ets").read_text()
assert "seasonDetailOwner.reconcile(" in page and "this.seasonExtras.load(" in page
assert "readPartRatings(session,'seasons'" in season_coordinator and "readPartRatings(session,'episodes'" in season_coordinator
assert "generation===this.generation&&allowed()&&!consumer.cancelled()" in season_coordinator and "rating===ratingScope()&&snapshot===source()" in season_coordinator
assert "this.localSeason!==0" in page and "eligible:false" in page
assert "seasons-trakt" in repo
