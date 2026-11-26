#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1] / "entry/src/main/ets/model"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    names=("Media","ShowCatalog","RemoteObservation","ThreeWay","EffectiveState")
    for name in names:
        shutil.copyfile(root/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs",*[n+".ts" for n in names]],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {resolveEpisodes,effectiveDecision,allowLocalScope}=require('./EffectiveState.js');
const {showSections}=require('./ShowCatalog.js');
const date='2025-01-01T00:00:00Z',now=Date.parse('2026-01-01T00:00:00Z');
const media={id:'show:1',kind:'show',title:'Test',year:2025,watched:false};
const full={media,status:'ended',fetchedAt:now,seasons:[{number:1,firstAired:date,episodes:[{id:11,season:1,number:1,title:'A',firstAired:date},{id:12,season:1,number:2,title:'B',firstAired:date}]}]};
const show={id:media.id,title:media.title,watchedEpisodes:2,positions:[{season:1,number:1,plays:2,lastWatchedAt:date},{season:1,number:2,plays:1,lastWatchedAt:date}],updatedAt:date};
const d={episodeId:11,seq:3,watched:true};
const e=new Map();
const match=resolveEpisodes(full,show,true,[],[d],e,e);
assert.deepEqual(match.ids.sort(),[11,12]);
assert.deepEqual(showSections(full,match.ids,now),['finished']);
assert.deepEqual(match.matches,[{id:11,seq:3,watched:true}]);
const ack=new Map([[11,match.matches[0]]]);
const removed={...show,positions:[show.positions[1]]};
assert.deepEqual(resolveEpisodes(full,removed,true,[],[d],ack,e).ids,[12]);
assert.deepEqual(resolveEpisodes(full,removed,true,[],[{...d,seq:4}],ack,e).ids.sort(),[11,12]);
assert.equal(effectiveDecision(true,false,3,undefined,{id:'11',value:true,activity:date}),false);
assert.equal(resolveEpisodes(full,{...show,positions:[{...show.positions[0],number:99}]},true,[],[d],e,e).complete,false);
assert.equal(allowLocalScope(true,'A','B'),false);
assert.equal(allowLocalScope(true,'','B'),false);
assert.equal(allowLocalScope(true,'A','A'),true);
assert.equal(allowLocalScope(false,'A',''),true);
assert.deepEqual(resolveEpisodes(full,undefined,false,[11],[],e,e).ids,[11]);
console.log('Effective viewing state assertions passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
