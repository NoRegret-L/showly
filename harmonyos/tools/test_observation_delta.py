#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    for n in ("Media","ShowCatalog","RemoteObservation"):
        shutil.copyfile(root/"model"/(n+".ets"),w/(n+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","RemoteObservation.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {observationReadMask,observationCollectionMask}=require('./RemoteObservation');
for(let i=0;i<100;i++){
 const prior={all:'a'+i,movies:'m'+i,shows:'s'+i};
 assert.equal(observationReadMask(undefined,prior),3);
 assert.equal(observationReadMask(prior,prior),0);
 assert.equal(observationReadMask(prior,{...prior,all:'b',movies:'x'}),1);
 assert.equal(observationReadMask(prior,{...prior,all:'b',shows:'x'}),2);
 assert.equal(observationReadMask(prior,{...prior,all:'b'}),3);
 assert.equal(observationReadMask(prior,{...prior,all:'b',movies:''}),3);
 assert.equal(observationReadMask(prior,{...prior,shows:'x'}),3);
 const split={...prior,watchedShows:'w',queuedShows:'q'};
 assert.equal(observationCollectionMask(split,{...split,all:'b',shows:'new',watchedShows:'w2'}),2);
 assert.equal(observationCollectionMask(split,{...split,all:'b',shows:'new',queuedShows:'q2'}),8);
 assert.equal(observationCollectionMask(split,{...split,all:'b',movies:'new'}),5);
 assert.equal(observationCollectionMask(split,{...split,all:'b',shows:'new',watchedShows:''}),10);
 assert.equal(observationCollectionMask(undefined,split),15);
 const full={...split,watchedMovies:'wm',queuedMovies:'qm'};
 assert.equal(observationCollectionMask(full,{...full,all:'b',movies:'new',watchedMovies:'wm2'},true),1);
 assert.equal(observationCollectionMask(full,{...full,all:'b',movies:'new',queuedMovies:'qm2'},true),4);
 assert.equal(observationCollectionMask(full,{...full,all:'b',movies:'new',queuedMovies:'qm2'},false),5);
}
console.log('Observation domain masks: 100 rounds, paired watchlist dependencies, missing and unknown activity full fallback passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
lib=(root/"data/TraktLibrary.ets").read_text()
page=(root/"pages/Index.ets").read_text()
assert "before.all !== after.all || before.movies !== after.movies || before.shows !== after.shows" in lib
assert "readObservationCollections(session,mask,readPermit)" in lib
assert "validateObservation(snapshot)" in lib
assert "readCloudLibraryIncremental(session,snapshot)" in page
assert "await store.saveRemoteObservation(account.uuid, persisted)" in page
assert "verifiedAt: verifiedAt" in page
assert "{ ...snapshot, verifiedAt:" not in page
