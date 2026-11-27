#!/usr/bin/env python3
from pathlib import Path
import json,shutil,sqlite3,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation","SearchRules","SearchRead","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","SearchRead.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),fs=require('node:fs'),m=require('./SearchRules.js'),{SearchRead}=require('./SearchRead.js');
const row=(i,kind='show',title='Test '+i)=>({media:{id:kind+':'+i,kind,title,year:2000+i,watched:true},votes:i});
const candidates=Array.from({length:12},(_,i)=>({...row(i+1,i<6?'show':'movie'),localized:i===0?'中文测试':''}));
const opt=m.defaultSearch(),input={catalog:candidates,remote:[],query:'test',suggestions:true,options:opt};
assert.equal(m.searchRows({...input,query:'t'}).length,0);
assert.equal(m.searchRows(input).length,10);assert.equal(m.searchRows(input)[0].id,'movie:11');
assert.equal(m.searchRows({...input,query:'中文'}).length,1);
const remote=[{...row(99,'movie','Alias'),localized:'别名'},{...row(1),localized:'中文测试'}];
const full={...input,suggestions:false,remote};
assert.deepEqual(m.searchRows(full).slice(0,2).map(x=>x.id),['movie:99','show:1']);
assert.equal(m.searchRows(full).length,13);
assert(m.searchRows({...full,options:{kind:'show',sort:'year',descending:true}}).every(x=>x.kind==='show'));
for (const kind of ['all','show','movie']) for (const sort of ['rank','title','year']) for (const descending of [false,true]){
 const expected=[...remote,...candidates.filter(x=>!remote.some(y=>y.media.id===x.media.id))].filter(x=>kind==='all'||x.media.kind===kind);
 const sign=descending?-1:1;
 if(sort==='rank'){if(descending)expected.reverse()}else expected.sort((a,b)=>{if(sort==='year')return sign*(a.media.year-b.media.year);const x=(a.localized||a.media.title).toUpperCase(),y=(b.localized||b.media.title).toUpperCase();return sign*(x<y?-1:x>y?1:0)});
 assert.deepEqual(m.searchRows({...full,options:{kind,sort,descending}}),expected.map(x=>x.media));
}
const gate=new m.SearchGeneration(),old=gate.begin(),latest=gate.begin();assert(!gate.current(old));assert(gate.current(latest));gate.cancel();assert(!gate.current(latest));
const A=m.searchScope('client','account:A'),B=m.searchScope('client','account:B');
const catalog=new Map(),history=new Map();let reads=0,writes=0,calls=0;
const storage={read:async s=>{reads++;return catalog.get(s)||[]},write:async(s,rows)=>{writes++;const map=new Map((catalog.get(s)||[]).map(x=>[x.media.id,x]));rows.forEach(x=>map.set(x.media.id,x));catalog.set(s,[...map.values()])},recents:async s=>history.get(s)||[],remember:async(s,q)=>history.set(s,[q,...(history.get(s)||[])].slice(0,5)),clear:async s=>history.delete(s)};
const transport={read:async(c,q)=>{calls++;if(q==='offline')throw Error('offline');return [row(1)]}};
const repo=new SearchRead(storage,transport);
(async()=>{
 if(process.argv[2]==='write'){
  await Promise.all(Array.from({length:393},()=>repo.catalog(A)));assert.equal(reads,1);
  await Promise.all(Array.from({length:393},()=>repo.remote('client','test')));assert.equal(calls,1);
  await repo.rememberCatalog(A,[row(1)]);await repo.rememberCatalog(A,[row(1)]);assert.equal(writes,1);
  for(let i=0;i<7;i++)await repo.remember(A,'q'+i);
  assert.deepEqual(await repo.recents(A),['q6','q5','q4','q3','q2']);
  assert.deepEqual(await repo.catalog(B),[]);assert.deepEqual(await repo.recents(B),[]);
  fs.writeFileSync('saved.json',JSON.stringify({catalog:[...catalog],history:[...history]}));
 }else{
  const data=JSON.parse(fs.readFileSync('saved.json'));data.catalog.forEach(([s,r])=>catalog.set(s,r));data.history.forEach(([s,r])=>history.set(s,r));
  assert.equal((await repo.catalog(A))[0].media.watched,false);assert.equal((await repo.recents(A)).length,5);
  await assert.rejects(repo.remote('client','offline'));assert.equal((await repo.catalog(A)).length,1);
  await repo.clear(A);assert.deepEqual(await repo.recents(A),[]);assert.equal((await repo.catalog(A)).length,1);
  console.log('Search local: original suggestion limits, 18 filter/sort comparisons, 393-to-1 flights, one disk load, unchanged write suppression, offline retention, scoped history and cold restore passed');
 }
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs","write"],cwd=work,check=True)
    data=json.loads((work/"saved.json").read_text())
    db=sqlite3.connect(work/"search.db")
    db.execute("CREATE TABLE search_catalog(scope TEXT,id TEXT,payload TEXT,PRIMARY KEY(scope,id))")
    db.execute("CREATE TABLE search_recent(seq INTEGER PRIMARY KEY AUTOINCREMENT,scope TEXT,query TEXT)")
    for scope,rows in data["catalog"]:
        db.executemany("INSERT OR REPLACE INTO search_catalog VALUES(?,?,?)",[(scope,row["media"]["id"],json.dumps(row)) for row in rows])
    for scope,rows in data["history"]:
        db.executemany("INSERT INTO search_recent(scope,query) VALUES(?,?)",[(scope,q) for q in reversed(rows)])
    db.commit();db.close()
    db=sqlite3.connect(work/"search.db")
    catalogs={}
    for s,raw in db.execute("SELECT scope,payload FROM search_catalog ORDER BY id"):catalogs.setdefault(s,[]).append(json.loads(raw))
    histories={}
    for s,q in db.execute("SELECT scope,query FROM search_recent ORDER BY seq DESC"):histories.setdefault(s,[]).append(q)
    db.close()
    (work/"saved.json").write_text(json.dumps({"catalog":list(catalogs.items()),"history":list(histories.items())}))
    subprocess.run(["node","test.cjs","read"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
repo=(root/"data"/"SearchRepository.ets").read_text()
task=(root/"data"/"SearchTask.ets").read_text()
assert "this.searchGeneration.current(token)" in page and "scope===this.currentSearchAccount()" in page
assert "this.searchRows.replace([],[],[])" in page and "this.searchRows.submit(" in page
assert "await searchDisplay(input)" in page and "await taskpool.execute(searchTask" in task
assert "repo.rememberCatalog(scope,rows)" in page and "repo.remember(scope,query)" in page
assert "search_catalog WHERE scope=?" in repo and "search_recent WHERE scope=?" in repo
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Search scope, latest-query gate, TaskPool, native lazy rows and sync safety wiring passed")
