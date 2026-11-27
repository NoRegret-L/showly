#!/usr/bin/env python3
"""Indexed derived rows: real SQLite plus production model in separate processes."""
from pathlib import Path
import json,re,shutil,sqlite3,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
store=(root/"data"/"EpisodeStore.ets").read_text()
lib=(root/"data"/"LibraryProjection.ets").read_text().split("export async function projectLibrary(",1)[1].split("export interface DetailProjection",1)[0]
schema=re.search(r"CREATE TABLE IF NOT EXISTS progress_projection_row_v2 [^']+",store).group()
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","IndexedProjection.ts","ProjectionCompute.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'), fs=require('node:fs');
const p=require('./ProjectionCompute.js'), ix=require('./IndexedProjection.js');
const now=Date.parse('2026-01-10T12:00:00Z'), day=86400000;
const scope=p.persistentProjectionScope('client','account-A',true,true);
const make=i=>{
 const media={id:'show:'+i,kind:'show',title:'Show '+i,year:2026,watched:false};
 const episodes=[{id:i*10+1,season:1,number:1,title:'One',firstAired:new Date(now-day).toISOString()},{id:i*10+2,season:1,number:2,title:'Two',firstAired:new Date(now+day).toISOString()}];
 const full={media,status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:episodes[0].firstAired,episodes}]};
 const remote={id:media.id,title:media.title,watchedEpisodes:1,positions:[{season:1,number:1,plays:1,lastWatchedAt:new Date(now-day).toISOString()}],updatedAt:new Date(now).toISOString()};
 return {full,remote,cloudActive:true,localIds:[],decisions:[],timed:[],checkpoints:[],common:[],now};
};
const shows=Array.from({length:393},(_,i)=>make(i+1));
const raw=x=>JSON.stringify(x.full), key=p.showProjectionStateKey;
const normalize=x=>JSON.parse(JSON.stringify({...x,source:{...x.source,randomOrder:0}}));
if(process.argv[2]==='write'){
 const out=p.computeProjectionBatch(shows);
 assert.equal(out.length,393);
 out.forEach((o,i)=>assert.deepEqual(normalize(o),normalize(p.computeProjection(shows[i]))));
 fs.writeFileSync('rows.json',JSON.stringify({scope,rows:shows.map((x,i)=>ix.encodeIndexedProjection(x,raw(x),key(x),out[i]))}));
}else{
 const rows=new Map(JSON.parse(fs.readFileSync('read.json','utf8')).map(r=>[r.id,r]));
 const memo=new p.ShowProjectionCache(), schedules=new ix.ScheduleReadCache();memo.begin(scope);
 let misses=0,parses=0,writes=0;
 function pass(input){
  const id=input.full.media.id, full=schedules.read(id,raw(input));
  const x={...input,full}, c=schedules.key(full), k=key(x), prior=rows.get(id);
  let value=memo.get(id,k,x.now,c), reusable=ix.indexedProjectionMatches(prior,x,c,k);
  if(!value&&reusable){parses++;value=ix.decodeIndexedProjection(prior,x,c,k);reusable=!!value}
  if(!value){misses++;value=p.computeProjection(x)}
  if(!reusable&&value.effective.complete&&p.diskProjectionAllowed(x)){writes++;rows.set(id,ix.encodeIndexedProjection(x,c,k,value))}
  memo.put(id,k,x.now,value,c);
  return value;
 }
 for(const x of shows)assert.deepEqual(normalize(pass(x)),normalize(p.computeProjection(x)));
 assert.deepEqual([schedules.parseCount(),parses,misses,writes],[393,393,0,0]);
 for(const x of shows)pass(x);
 assert.deepEqual([schedules.parseCount(),parses,misses,writes],[393,393,0,0]);
 const changed={...shows[0],remote:{...shows[0].remote,positions:[],watchedEpisodes:0}};
 pass(changed);shows.slice(1).forEach(pass);
 assert.deepEqual([schedules.parseCount(),parses,misses,writes],[393,393,1,1]);
 const catalog={...shows[1],full:{...shows[1].full,rating:8}};
 pass(catalog);assert.deepEqual([schedules.parseCount(),misses,writes],[394,2,2]);
 const x=shows[2],r=rows.get(x.full.media.id);
 assert.equal(ix.decodeIndexedProjection({...r,payload:'broken'},x,raw(x),key(x)),undefined);
 assert.equal(ix.decodeIndexedProjection(r,{...x,now:now+day},raw(x),key(x)),undefined);
 assert.equal(ix.decodeIndexedProjection(r,x,raw(x)+' ',key(x)),undefined);
 const dirty={...x,decisions:[{episodeId:31,seq:1,watched:true}],timed:[{episodeId:31,seq:1,watched:true,changedAt:now}]};
 assert.equal(p.diskProjectionAllowed(dirty),false);
 assert.equal(ix.decodeIndexedProjection(ix.encodeIndexedProjection(dirty,raw(dirty),key(dirty),p.computeProjection(dirty)),dirty,raw(dirty),key(dirty)),undefined);
 memo.begin(p.persistentProjectionScope('client','account-B',true,true));
 assert.equal(memo.get(x.full.media.id,key(x),now,raw(x)),undefined);
 console.log('Indexed cache: 393 cross-process hits, 0 warm parses/recomputations/writes, one changed show, catalog change, corruption, expiry and pending decision gates passed');
}
""",encoding="utf-8")
    subprocess.run(["node","test.cjs","write"],cwd=work,check=True)
    data=json.loads((work/"rows.json").read_text())
    db=sqlite3.connect(work/"cache.db")
    db.execute(schema)
    sql="INSERT OR REPLACE INTO progress_projection_row_v2(scope,show_id,catalog_key,state_key,computed_at,valid_until,payload) VALUES (?,?,?,?,?,?,?)"
    for r in data["rows"]:
        db.execute(sql,(data["scope"],r["id"],r["catalogKey"],r["key"],r["from"],r["until"],r["payload"]))
    db.execute(sql,("account-B","show:1","other","other",0,1,"different"))
    db.commit()
    db.close()
    db=sqlite3.connect(work/"cache.db")
    fields="show_id,catalog_key,state_key,computed_at,valid_until,payload"
    ids=[r["id"] for r in data["rows"]]
    query="SELECT "+fields+" FROM progress_projection_row_v2 WHERE scope=? AND show_id IN ("+",".join("?" for _ in ids)+")"
    plan=db.execute("EXPLAIN QUERY PLAN "+query,[data["scope"],*ids]).fetchall()
    assert any("SEARCH" in row[3] for row in plan),plan
    out=db.execute(query,[data["scope"],*ids]).fetchall()
    assert len(out)==393
    assert len(db.execute(query,["account-B",*ids]).fetchall())==1
    assert db.execute(query,["missing",*ids]).fetchall()==[]
    columns=("id","catalogKey","key","from","until","payload")
    (work/"read.json").write_text(json.dumps([dict(zip(columns,row)) for row in out]))
    before=dict(db.execute("SELECT show_id,payload FROM progress_projection_row_v2 WHERE scope=?",(data["scope"],)))
    r=data["rows"][0]
    db.execute(sql,(data["scope"],r["id"],r["catalogKey"],r["key"],r["from"],r["until"],"one updated row"))
    after=dict(db.execute("SELECT show_id,payload FROM progress_projection_row_v2 WHERE scope=?",(data["scope"],)))
    assert [i for i in before if before[i]!=after[i]]==[r["id"]]
    assert db.execute("SELECT payload FROM progress_projection_row_v2 WHERE scope='account-B'").fetchone()==("different",)
    db.close()
    subprocess.run(["node","test.cjs","read"],cwd=work,check=True)
assert "const payload=JSON.stringify(pending)" in lib and "taskpool.execute(computeProjectionBatchTask, payload)" in lib
assert lib.count("taskpool.execute(")==1
assert "if (pending.length)" in lib
assert "indexedProjectionMatches(prior,input,work.catalogKey,work.key)" in lib
assert "if (work.calculated) { work.diskReusable=metadataMatch; }" in lib
assert "work.diskReusable=!!work.calculated && cache.diskKnown(" in lib
assert "store.readProjectionRows(diskScope,diskNeeded)" in lib
assert "!store.projectionReadable(revision)" in lib
assert "await store.saveProjectionRows(diskScope,changedDisk)" in lib
assert "await store.removeProjectionRows(diskScope,removedDisk)" in lib
print("Indexed SQL scope, target lookup, single-row update, batch worker and safety wiring passed")
