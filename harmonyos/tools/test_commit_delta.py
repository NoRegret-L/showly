#!/usr/bin/env python3
"""Production commit fences, exact input versions and native row notifications."""
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for p in (root/"model").glob("*.ets"):
        shutil.copyfile(p,work/(p.stem+".ts"))
    (work/"arkui.d.ts").write_text("""
interface DataChangeListener { onDataReloaded():void; onDataAdd(i:number):void; onDataDelete(i:number):void; onDataMove(i:number,j:number):void; onDataChange(i:number):void; }
interface IDataSource { totalCount():number; getData(i:number):unknown; registerDataChangeListener(l:DataChangeListener):void; unregisterDataChangeListener(l:DataChangeListener):void; }
""")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","CommitFence.ts","MediaInputVersion.ts","RowDependencies.ts","LazyRows.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {CommitFence}=require('./CommitFence');
const {MediaInputVersion}=require('./MediaInputVersion');
const {LazyRows}=require('./LazyRows');
const {planListDiff}=require('./ListDiff');
(async()=>{
 const gate=new CommitFence(),initial=gate.assertReadable(),key=gate.cacheVersion();
 const a=gate.begin();assert(!gate.readable(initial));assert.throws(()=>gate.assertReadable());assert.throws(()=>gate.begin());
 gate.finish(a,false,[]);assert.equal(gate.cacheVersion(),key);assert(!gate.readable(initial));
 const b=gate.begin();gate.finish(b,true,['show:1']);assert.equal(gate.version(),1);assert.deepEqual(gate.changedIds(),['show:1']);
 const c=gate.begin();gate.finish(c,true,['show:1','show:2']);assert.deepEqual(gate.changedIds(),['show:1','show:2']);
 const previous=gate.cacheVersion(),bad=gate.begin();gate.finish(bad,false,[],true);assert.notEqual(gate.cacheVersion(),previous);assert.equal(gate.version(),2);assert(gate.globalChanged());gate.clearChanges();assert(!gate.globalChanged());
 const records=Array.from({length:10000},(_,i)=>({media:{id:'show:'+(i+1),kind:'show',title:'Show '+i,year:2026,watched:false},movieState:'unknown',watchlistState:'unknown'}));
 const media=new MediaInputVersion();assert(media.replace(records));const v=media.version();assert(!media.replace(JSON.parse(JSON.stringify(records))));assert.equal(media.version(),v);
 const edited=records.slice();edited[5000]={...edited[5000],watchlistState:'yes'};assert(media.replace(edited));assert.deepEqual(media.changedIds(),['show:5001']);
 const order=edited.slice().reverse();assert(media.replace(order));assert.deepEqual(media.changedIds(),[]);
 const data=new LazyRows(row=>[row.media.id]);const ids=records.map(x=>x.media.id);
 let patches=0,reloads=0,visits=0;
 data.registerDataChangeListener({onDataChange:i=>{patches++;assert.equal(i,5000)},onDataReloaded:()=>reloads++,onDataAdd(){},onDataDelete(){},onDataMove(){}});
 data.replace(records,ids,ids.map(()=>''));patches=0;reloads=0;
 const old=data.keyFor('show:5000'),anchor=data.idAt(5000);
 const compute=row=>{visits++;return row.media.id==='show:5001'?'new poster':''};
 assert(data.refreshDependencies(['show:5001'],compute));assert.equal(visits,1);assert.equal(patches,1);assert.equal(reloads,0);assert.equal(data.keyFor('show:5000'),old);assert.equal(data.indexOfId(anchor),5000);
 assert(data.refreshDependencies(['show:5001'],compute));assert.equal(patches,1);
 assert(data.refreshDependencies(['show:missing'],compute));assert.equal(visits,2);
 let resolve;const pending=data.submit(records.slice().reverse(),ids.slice().reverse(),ids.map(()=>''),input=>new Promise(r=>{resolve=()=>r(planListDiff(input))}),()=>false);
 assert(!data.refreshDependencies(['show:5001'],compute));resolve();assert.equal(await pending,false);
 assert(data.refreshDependencies(['show:5001'],compute));
 console.log('10,000 native-source rows: one signature and one change notification; commit, rollback, stale read and publication versions passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
db=sqlite3.connect(":memory:")
db.execute("CREATE TABLE evidence(id TEXT PRIMARY KEY, value INTEGER)")
db.execute("INSERT INTO evidence VALUES('show:1',0)");db.commit()
try:
    with db:
        db.execute("UPDATE evidence SET value=1 WHERE id='show:1'")
        raise RuntimeError("rollback fixture")
except RuntimeError:
    pass
assert db.execute("SELECT value FROM evidence WHERE id='show:1'").fetchone()==(0,)
page=(root/"pages/Index.ets").read_text()
store=(root/"data/EpisodeStore.ets").read_text()
projection=(root/"data/LibraryProjection.ets").read_text()
assert "JSON.stringify(this.mediaRecords)" not in page
assert "const recordKey = this.mediaInput.version()" in page and "store.committedProjectionKey()" in page
assert "this.mediaRecords=records" in page
assert "this.refreshPresentationRows(Array.from(dirty))" in page
assert "this.discoverRows.refreshDependencies" in page and "this.collectionRowsSource.refreshDependencies" in page
assert "this.projectionFence.finish(token,success,ids" in store
assert "this.db.rollBack()" in store and "await this.markBody(intent.showId, [episodeId], value)" in store
assert "store.assertProjectionReadable()" in projection and "store.projectionReadable(revision)" in projection
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
assert "this.closeSeasonPage()" in page and "this.restoreScroll('discover')" in page
print("Committed-key and local row publication wiring, SQLite rollback fixture and synchronization guards passed")
