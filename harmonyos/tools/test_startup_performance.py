#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ProjectionCompute.ts","ReadModelCache.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {RevisionMemo,projectionKey,progressExpiry}=require('./ReadModelCache.js');
const {computeProjection,ShowProjectionCache,showProjectionKey}=require('./ProjectionCompute.js');
const {resolveEpisodes}=require('./EffectiveState.js');
const {progressSource,defaultProgress,progressRows}=require('./ProgressRules.js');
const {showSections}=require('./ShowCatalog.js');
const now=Date.parse('2026-01-10T12:00:00Z'), day=86400000;
const memo=new RevisionMemo();
const key=projectionKey('client','account-A',1,'revision-1',0,'[]');
const value={rows:[1,2,3]};
memo.put(key,value,now,now+1);
assert.equal(memo.get(key,now),value);
assert.equal(memo.get(key,now+1),undefined);
assert.equal(memo.get(key,now-1),undefined);
for (const other of [
projectionKey('client','account-B',1,'revision-1',0,'[]'),
projectionKey('client','account-A',2,'revision-1',0,'[]'),
projectionKey('client','account-A',1,'revision-2',0,'[]'),
projectionKey('client','account-A',1,'revision-1',1,'[]'),
projectionKey('client','account-A',1,'revision-1',0,'[1]'),
projectionKey('other','account-A',1,'revision-1',0,'[]')]) assert.equal(memo.get(other,now),undefined);
memo.clear(); assert.equal(memo.get(key,now),undefined);
const build=(id)=> {
 const media={id:'show:'+id,kind:'show',title:'Show '+id,year:2026,watched:false};
 const episodes=[{id:id*10+1,season:1,number:1,title:'One',firstAired:new Date(now-day).toISOString()},
 {id:id*10+2,season:1,number:2,title:'Two',firstAired:new Date(now+day).toISOString()}];
 const full={media,status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:episodes[0].firstAired,episodes}]};
 const remote={id:media.id,title:media.title,watchedEpisodes:1,positions:[{season:1,number:1,plays:1,lastWatchedAt:new Date(now-day).toISOString()}],updatedAt:new Date(now).toISOString()};
 return {full,remote,cloudActive:true,localIds:[],decisions:[],timed:[],checkpoints:[],common:[],now};
};
const input=build(1);
const projected=computeProjection(input);
const original=resolveEpisodes(input.full,input.remote,true,[],[],new Map(),new Map());
assert.deepEqual(projected.effective,original);
assert.deepEqual(projected.sections,showSections(input.full,original.ids,now));
const oldSource=progressSource(input.full,original.ids,input.remote,[],new Map(),true);
assert.deepEqual({...projected.source,randomOrder:0},{...oldSource,randomOrder:0});
assert.equal(projected.validUntil,now+day);
assert.equal(progressExpiry([projected.source],defaultProgress(),now),now+day);
assert.deepEqual(progressRows([projected.source],defaultProgress(),[],now,'all','').map(x=>x.episode.id),[12]);
const cache=new ShowProjectionCache(); cache.begin('account-A:1');
let runs=0;
const read=(input)=>{const k=showProjectionKey(input),id=input.full.media.id; let out=cache.get(id,k,input.now); if(!out){runs++;out=computeProjection(input);cache.put(id,k,input.now,out)}return out};
const shows=Array.from({length:393},(_,i)=>build(i+1));
shows.forEach(read);assert.equal(runs,393);
shows.forEach(read);assert.equal(runs,393);
const changed={...shows[0],localIds:[11],decisions:[{episodeId:11,seq:1,watched:true}],timed:[{episodeId:11,seq:1,watched:true,changedAt:now}]};
read(changed);shows.slice(1).forEach(read);assert.equal(runs,394);
const ack={...changed,checkpoints:[{id:11,seq:1,watched:true}]};
const before=read(changed),after=read(ack);
assert.equal(before.source.episodes[0].watchedAt,now);
assert.equal(after.source.episodes[0].watchedAt,now-day);
assert.equal(runs,395);
assert.equal(cache.get(shows[1].full.media.id,showProjectionKey(shows[1]),now+day),undefined);
cache.begin('account-B:1');assert.equal(cache.get(changed.full.media.id,showProjectionKey(changed),now),undefined);
read(changed);cache.retain(new Set());assert.equal(cache.get(changed.full.media.id,showProjectionKey(changed),now),undefined);
console.log('Startup read-model fixtures passed: 393 initial, 0 repeated, 1 changed show; scope and air-time boundaries verified');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
project=(root/"data"/"LibraryProjection.ets").read_text()
presentation=(root/"data"/"PresentationRepository.ets").read_text()
cloud=page.split("  private async loadCloud(",1)[1].split("  private async importCloud(",1)[0]
assert "if (checkpointChanged) { this.projectionPending = true; }" in cloud
assert "await readSyncAccount(session)" in cloud and "await readActivity(session)" in cloud
assert "reconcileTitleObservation" in cloud and "await store.saveReadCheckpoints" in cloud
assert "this.readLibraryProjection(store, restored, account.uuid, clientId, false, false, current)" in cloud
assert "taskpool.execute(computeProjectionTask" in project and "computeProjection(input)" in project
assert "value.posterUri = '';" in presentation
assert "this.titleIndex.get(item.id)" in page
assert "this.scheduleInitialRead()" in page
print("Startup wiring and safety assertions passed")
