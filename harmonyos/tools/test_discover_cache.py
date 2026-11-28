#!/usr/bin/env python3
"""Production discovery model + real SQLite cache reopened across processes."""
from pathlib import Path
import json,re,shutil,sqlite3,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
repo=(root/"data"/"DiscoverRepository.ets").read_text()
schema=re.search(r"CREATE TABLE IF NOT EXISTS discover_feed [^']+",repo).group()
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","ReadFlight","DiscoverRules","DiscoverRead"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","DiscoverRead.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),fs=require('node:fs');
const d=require('./DiscoverRules.js'),{DiscoverRead}=require('./DiscoverRead.js');
const now=Date.parse('2026-01-10T12:00:00Z');Date.now=()=>now;
const item=(i,kind='show',date='2025-01-01')=>({media:{id:kind+':'+i,kind,title:'Title '+i,year:2025,watched:false},rating:7,posterUrls:[],posterUri:'',firstAired:date});
const defaults=d.defaultDiscover(),request=d.discoverRequest('show',defaults,393),key=d.discoverKey('client-A',request);
assert.equal(request.limit,280);assert.equal(d.discoverRequest('show',{...defaults,hideCollection:true},393).limit,476);
assert.equal(d.discoverKey('client-A',d.discoverRequest('show',{...defaults,mode:'recent'},0)),key);
const filtered=d.discoverRequest('show',{...defaults,genres:['drama','action'],networks:['HBO','NETFLIX']},0);
assert.deepEqual(filtered.genres,['action','drama']);assert(filtered.networks.includes('HBO Max')&&filtered.networks.includes('Netflix'));
assert.deepEqual(d.discoverRequest('movie',{...defaults,networks:['HBO']},0).networks,[]);
const rows=Array.from({length:280},(_,i)=>item(i+1)),anticipated=Array.from({length:30},(_,i)=>item(i+1001));
const reference=[];let j=0;const add=x=>{if(!reference.some(y=>y.media.id===x.media.id))reference.push(x)};
rows.forEach((x,i)=>{add(x);if(i!==0&&i%6===0&&j<anticipated.length)add(anticipated[j++])});
assert.deepEqual(d.mixDiscover(rows,anticipated),reference);
assert.equal(reference[7].media.id,'show:1001');
assert.deepEqual(d.mixDiscover([item(1),item(2),item(3),item(4),item(5),item(6),item(7),item(8)], [item(1),item(9)]).map(x=>x.media.id),Array.from({length:8},(_,i)=>'show:'+(i+1)));
const hidden=new Set(['show:1']),members=new Set(['show:2']);
assert.equal(d.filterDiscover(reference,{...defaults,hideCollection:true},hidden,members,now).length,308);
assert.deepEqual(d.filterDiscover([item(1,'show','2027-01-01'),item(2,'show',''),item(3,'show','2026-01-10T23:00:00Z'),item(4)],{...defaults,mode:'recent'},new Set(),new Set(),now).map(x=>x.media.id),['show:3','show:4']);
assert.equal(d.discoverPage(reference,2).items.length,12);
assert.equal(d.discoverPage(reference,999).page,26);
assert(!d.discoverFresh({fetchedAt:now,items:[]},now-1));assert(!d.discoverFresh({fetchedAt:now,items:[]},now+d.DISCOVER_CACHE_MS));
const map=new Map();let calls=0,fail=false;
const disk={read:async k=>map.get(k)||'',write:async(k,v)=>{map.set(k,v)}};
const net={read:async(client,r,mode,page,limit)=>{calls++;if(fail)throw Error('offline');const all=mode==='anticipated'?anticipated:rows;const effective=Math.min(limit,100);return {items:all.slice((page-1)*effective,page*effective),page,pages:Math.ceil(all.length/effective),limit:effective,count:all.slice((page-1)*effective,page*effective).length}}};
const repo=new DiscoverRead(disk,net);
(async()=>{
 if(process.argv[2]==='write'){
  const result=await Promise.all(Array.from({length:393},()=>repo.load('client-A',request,false,()=>{})));
  assert.equal(calls,4);result.forEach(x=>assert.deepEqual(x.items,reference));
  await repo.load('client-A',request,false,()=>{});assert.equal(calls,4);
  const ranked=[item(1),item(2),item(3),item(4),item(5),item(6),item(1),item(7),item(8),item(9)];
  const dupStore={read:async()=>'',write:async()=>{}};
  const dupNet={read:async(c,r,mode,page,limit)=>{const all=mode==='anticipated'?[item(999)]:ranked;const n=4;const items=all.slice((page-1)*n,page*n);return {items,page,pages:Math.ceil(all.length/n),limit:n,count:items.length}}};
  const dup=await new DiscoverRead(dupStore,dupNet).load('client-A',request,false,()=>{});
  assert.deepEqual(dup.items,d.mixDiscover(ranked,[item(999)]));assert.equal(dup.items[6].media.id,'show:999');
  fs.writeFileSync('saved.json',JSON.stringify([...map]));
 }else{
  for(const [k,v] of JSON.parse(fs.readFileSync('saved.json','utf8')))map.set(k,v);
  fail=true;let shown;
  const feed=await repo.load('client-A',request,false,(f,fresh)=>{shown=f;assert(fresh)});
  assert.deepEqual(feed,shown);assert.equal(calls,0);assert.equal(feed.items.length,310);
  assert.equal(await repo.cached('client-B',request),undefined);
  assert.equal(await repo.cached('client-A',filtered),undefined);
  assert.equal(await repo.cached('client-A',d.discoverRequest('movie',defaults,0)),undefined);
  map.set(key,JSON.stringify({...feed,fetchedAt:now-d.DISCOVER_CACHE_MS}));
  await assert.rejects(repo.load('client-A',request,false,(f,fresh)=>{shown=f;assert(!fresh)}),/offline/);
  assert.equal(shown.items.length,310);assert.equal((await repo.cached('client-A',request)).items.length,310);
  await assert.rejects(repo.load('client-A',request,true,()=>{}),/offline/);
  assert.equal((await repo.cached('client-A',request)).items.length,310);
  map.set(key,'broken');assert.equal(await repo.cached('client-A',request),undefined);
  console.log('Discover cache: 393 callers -> 4 paginated HTTP reads, 310 ranked titles, zero fresh offline reads, filter/client isolation, stale retention and corruption passed');
 }
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs","write"],cwd=work,check=True)
    db=sqlite3.connect(work/"discover.db")
    db.execute(schema)
    db.executemany("INSERT OR REPLACE INTO discover_feed(feed_key,payload) VALUES (?,?)",json.loads((work/"saved.json").read_text()))
    db.commit();db.close()
    db=sqlite3.connect(work/"discover.db")
    records=db.execute("SELECT feed_key,payload FROM discover_feed").fetchall()
    assert len(records)==1
    (work/"saved.json").write_text(json.dumps(records));db.close()
    subprocess.run(["node","test.cjs","read"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
assert "repo.load(clientId,request,force,publish,consumer)" in page
assert "revision === lane.version() && lane.current(consumer) && clientId === this.clientId" in page
assert "this.discoverOptions === options" in page
assert "this.discoverOptions.hideCollection && (!this.ready || (this.signedIn && !this.activeCloud()))" in page
assert "filterDiscover(this.discoverItems,this.discoverOptions,hidden,members,now)" in page
assert "if (committed && current() && this.showRows.work.publishSummary(summary,this.showSummary)) { this.showSummary = summary; }" in page
assert "if (committed && current() && this.movieRowsSource.work.publishSummary(summary,this.movieSummary)) { this.movieSummary = summary; }" in page
assert "if (committed && current() && this.collectionRowsSource().work.publishSummary(summary,this.collectionSummary)) { this.collectionSummary = summary; }" in page
assert "this.showSummary.key === this.showDisplayKey()" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Discovery local-first, async summary commit and synchronization wiring passed")

assert "if(!slot||slot==='show'||slot==='calendar'||slot==='library'||slot==='discover'||slot==='search'){this.onPresentationChanged();}" in page

assert "if(!slot||slot==='movie'||slot==='movieCalendar'||slot==='library'||slot==='discover'||slot==='search'){this.onPresentationChanged();}" in page
