#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    shutil.copyfile(root/"model/SyncCoordinator.ets",w/"SyncCoordinator.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","SyncCoordinator.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {SyncCoordinator,queueIdentity}=require('./SyncCoordinator');
const c=new SyncCoordinator();
for(let cycle=0;cycle<100;cycle++){
  for(const lane of ['titles','observation','media','episodes']){
    c.mark(lane,true);const v=c.version();
    for(let i=0;i<100;i++)c.mark(lane,true);
    assert.equal(c.version(),v);
  }
  assert.equal(c.next(false,false,false,false),'');
  assert.equal(c.next(false,true,true,true),'media');
  for(const lane of ['episodes','media','observation','titles']){
    assert.equal(c.next(true,true,true,true),lane);c.mark(lane,false);
  }
  assert.equal(c.next(true,true,true,true),'');
  c.mark('episodes',true);c.reset();assert.equal(c.has('episodes'),false);
}
const rows=Array.from({length:10000},(_,i)=>({episodeId:i%5000,seq:i+1,blocked:i%3===0}));
const eligible=rows.filter((_,i)=>i%2===0);
const keys=new Set(eligible.map(e=>queueIdentity(e.episodeId,e.seq)));
assert.deepEqual(rows.filter(e=>e.blocked&&keys.has(queueIdentity(e.episodeId,e.seq))),
 rows.filter(e=>e.blocked&&eligible.some(o=>o.episodeId===e.episodeId&&o.seq===e.seq)));
assert.notEqual(queueIdentity(1,23),queueIdentity(12,3));
console.log('Sync coordinator: 100 cycles, coalesced intents, scope reset and 10k exact queue identities passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
page=(root/"pages/Index.ets").read_text()
assert "this.syncCoordinator.reset();" in page
assert "this.requestSyncNow();" in page
executor=(root/"data/EpisodeQueueExecutor.ets").read_text()
assert "sentIdentities.has(queueIdentity(entry.episodeId, entry.seq))" in executor
assert "await reconcileQueue(store, session, expected, attempted)" in executor
assert "await executeEpisodeQueue(" in page
assert "allowed() && clientCurrent() && traktAuth.isCurrent" in executor
assert "if (this.autoActive()) { this.recoveryPending = true; }" in page
assert "if (this.titleQuickActive()) { this.titleQuickPending = true; }" in page
assert "this.syncCoordinator.next(" in page
