#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1] / "entry/src/main/ets/model"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaState","ShowCatalog","PersonalLibrary","RemoteObservation"):
        shutil.copyfile(root/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Media.ts","MediaState.ts","ShowCatalog.ts","PersonalLibrary.ts","RemoteObservation.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {observedSections,validateObservation}=require('./RemoteObservation.js');
const {buildPersonalLibrary,filterPersonalLibrary}=require('./PersonalLibrary.js');
const now=Date.parse('2026-01-01T00:00:00Z'), date='2025-01-01T00:00:00Z';
const media={id:'show:1',kind:'show',title:'Test',year:2025,watched:false};
const catalog={media,status:'ended',fetchedAt:now,seasons:[{number:1,firstAired:date,episodes:[{id:11,season:1,number:1,title:'A',firstAired:date},{id:12,season:1,number:2,title:'B',firstAired:date}]}]};
const show={id:media.id,title:media.title,watchedEpisodes:2,positions:[{season:1,number:1,plays:2,lastWatchedAt:date},{season:1,number:2,plays:1,lastWatchedAt:date}],updatedAt:date};
const snapshot={generation:1,activity:date,observedAt:now,watchlist:[],watchedMovies:[],moviePlays:[],shows:[show]};
validateObservation(snapshot);
assert.deepEqual(observedSections(catalog,show,[],[],now),['finished']);
assert.deepEqual(observedSections(catalog,show,[],[{episodeId:12,watched:false}],now),['watching']);
assert.deepEqual(observedSections(catalog,{...show,positions:[{...show.positions[0],number:99}]},[],[],now),[]);
assert.throws(()=>validateObservation({...snapshot,shows:[{...show,positions:[show.positions[0],show.positions[0]]}]}));
const rows=buildPersonalLibrary([],[],[],[{media,watchedEpisodes:2}],[{media,watchedEpisodes:-1,sections:['finished'],merged:true}]);
assert.equal(filterPersonalLibrary(rows,'finished').length,1);
assert.equal(filterPersonalLibrary(rows,'unclassified').length,0);
const missing=buildPersonalLibrary([],[],[],[{media,watchedEpisodes:2}],[]);
assert.equal(filterPersonalLibrary(missing,'unclassified').length,1);
console.log('Remote observation assertions passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
