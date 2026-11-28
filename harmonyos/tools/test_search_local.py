#!/usr/bin/env python3
from pathlib import Path
import json,shutil,sqlite3,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation","SearchRules","SearchRead","ReadFlight","SearchController"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","SearchRead.ts","SearchController.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),fs=require('node:fs'),m=require('./SearchRules.js'),{SearchRead}=require('./SearchRead.js');
const row=(i,kind='show',title='Test '+i)=>({media:{id:kind+':'+i,kind,title,year:2000+i,watched:true},votes:i});
const candidates=Array.from({length:12},(_,i)=>({...row(i+1,i<6?'show':'movie'),localized:i===0?'中文测试':''}));
const opt=m.defaultSearch(),input={catalog:candidates,remote:[],query:'test',suggestions:true,options:opt};
assert.equal(m.searchRows({...input,query:'t'}).length,10);
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
for(const size of [393,10000]){
 const catalog=Array.from({length:size},(_,i)=>({...row(i+1,i%2?'show':'movie','Test '+(i%13)),localized:i%3?'中文😀':''}));
 let oldBytes=0,newBytes=0;
 for(const kind of ['all','show','movie'])for(const sort of ['rank','title','year'])for(const suggestions of [false,true]){
   const input={catalog,remote,query:'Test',suggestions,options:{kind,sort,descending:true}};
   const raw=JSON.stringify(m.packSearch(input));
   const restored=m.unpackSearch(JSON.parse(raw));
   assert.deepEqual(restored,input);assert.deepEqual(m.searchRows(restored),m.searchRows(input));
   oldBytes+=Buffer.byteLength(JSON.stringify(input));newBytes+=Buffer.byteLength(raw);
 }
 assert(newBytes<oldBytes);
 console.log(size+' search candidates: compact wire '+oldBytes+' -> '+newBytes+' UTF-8 bytes across 18 exact parity cases');
}
const {SearchController}=require('./SearchController.js');
const owner=new SearchController(),catalogRows=Array.from({length:10000},(_,i)=>row(i+1,i%2?'show':'movie',i===42?'独特😀':'Test '+(i%13)));
const candidate=r=>({...r,localized:r.media.id==='show:44'?'中文':''});
owner.seed(catalogRows,'A',[],candidate);
for(const q of ['t','Test 1','独','😀','中文','absent'])for(const kind of ['all','show','movie']){
 const options={kind,sort:'rank',descending:false};
 assert.deepEqual(m.searchRows(owner.input(q,false,options,candidate)),m.searchRows({catalog:owner.candidates,remote:[],query:q,suggestions:true,options}));
}
owner.acceptRemote(remote);assert.deepEqual(m.searchRows(owner.input('test',true,opt,candidate)).map(x=>x.id),['movie:99','show:1']);
owner.acceptRemote([]);assert.deepEqual(m.searchRows(owner.input('test',true,opt,candidate)),[]);
owner.chooseOffline(true);assert(m.searchRows(owner.input('test',true,opt,candidate)).length>0);
owner.titles.patch('show:44','新增翻译');assert.deepEqual(m.searchRows(owner.input('新增',false,opt,candidate)).map(x=>x.id),['show:44']);
owner.clearCandidates();assert.equal(owner.input('新增',false,opt,candidate).catalog.length,0);
console.log('10k exact indexed candidates, single-character suggestion, remote empty separation, offline switch and scoped reset passed');
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
  const empty=await repo.catalog(A);assert.equal(await repo.catalog(A),empty);
  await repo.rememberCatalog(A,[row(9),row(1),row(2)]);const warm=await repo.catalog(A);
  assert.deepEqual(warm.map(x=>x.media.id),['show:1','show:2','show:9']);
  await repo.rememberCatalog(A,[row(1)]);assert.equal(writes,1);assert.equal(await repo.catalog(A),warm);
  let finishOld,finishNew;const pending=new SearchRead(storage,{read:async(c,q)=>new Promise(resolve=>{if(q==='old')finishOld=resolve;else finishNew=resolve})});
  const generations=new m.SearchGeneration(),published=[];
  const send=async q=>{const token=generations.begin();const result=await pending.remote('client',q);if(generations.current(token))published.push(result[0].media.id)};
  const first=send('old'),second=send('new');await Promise.resolve();await Promise.resolve();finishNew([row(2)]);await second;finishOld([row(1)]);await first;assert.deepEqual(published,['show:2']);
  for(let i=0;i<7;i++)await repo.remember(A,'q'+i);
  assert.deepEqual(await repo.recents(A),['q6','q5','q4','q3','q2']);
  assert.deepEqual(await repo.catalog(B),[]);assert.deepEqual(await repo.recents(B),[]);
  fs.writeFileSync('saved.json',JSON.stringify({catalog:[...catalog],history:[...history]}));
 }else{
  const data=JSON.parse(fs.readFileSync('saved.json'));data.catalog.forEach(([s,r])=>catalog.set(s,r));data.history.forEach(([s,r])=>history.set(s,r));
  assert.equal((await repo.catalog(A))[0].media.watched,false);assert.equal((await repo.recents(A)).length,5);
  assert.deepEqual((await repo.catalog(A)).map(x=>x.media.id),['show:1','show:2','show:9']);
  await assert.rejects(repo.remote('client','offline'));assert.equal((await repo.catalog(A)).length,3);
  await repo.clear(A);assert.deepEqual(await repo.recents(A),[]);assert.equal((await repo.catalog(A)).length,3);
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
assert "await searchDisplay(input,consumer)" in page and "executeDisplayTask(new taskpool.Task(searchTask" in task
assert "this.searchController.source!==stored || this.searchController.key!==key" in page
assert "repo.rememberCatalog(scope,rows)" in page and "repo.remember(scope,query)" in page
assert "GROUP BY query ORDER BY MAX(seq) DESC" in repo
assert "search_catalog WHERE scope=?" in repo and "search_recent WHERE scope=?" in repo
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Search scope, latest-query gate, TaskPool, native lazy rows and sync safety wiring passed")

assert "JSON.stringify(packSearch(input))" in task and "unpackSearch(JSON.parse(raw)" in task
