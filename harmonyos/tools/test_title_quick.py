#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets/model"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    names=("Media","MediaState","ThreeWay","TitleQuickState")
    for name in names: shutil.copyfile(root/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs",*[n+".ts" for n in names]],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {titleEdit,quickDisposition,canAdoptTitle,autoEligible}=require('./TitleQuickState.js');
const movie={id:'movie:1',kind:'movie',title:'Movie',year:2025,watched:false};
const date='2026-01-01T00:00:00Z';
const queued=titleEdit([],movie,'watchlist','yes');
const watched=titleEdit(queued.records,movie,'movie','yes');
assert.equal(watched.records[0].movieState,'yes');
assert.equal(watched.records[0].watchlistState,'no');
assert.deepEqual(watched.changes.map(x=>x.domain),['movie','watchlist']);
const i={id:movie.id,domain:'movie',value:'yes',seq:1,epoch:2,operationSeq:0,watchedAt:date,state:'open'};
assert.equal(quickDisposition(i,'yes',false,'add',0,'','',2),'send');
assert.equal(quickDisposition(i,'yes',true,'',0,'','',2),'matched');
assert.equal(quickDisposition(i,'yes',false,'add',1,'pending','add',2),'readback');
assert.equal(quickDisposition(i,'yes',false,'add',1,'verified','add',2),'settled');
assert.equal(quickDisposition(i,'yes',false,'add',0,'','',3),'review');
assert.equal(quickDisposition(i,'no',false,'add',0,'','',2),'review');
assert.equal(quickDisposition({...i,value:'no'},'no',true,'remove',0,'','',2),'review');
assert.equal(autoEligible('watchlist','no'),true);
assert.equal(canAdoptTitle('yes',false,{id:movie.id,value:true,activity:date},i,false),false);
assert.equal(canAdoptTitle('yes',false,{id:movie.id,value:true,activity:date},{...i,state:'settled'},false),true);
assert.equal(canAdoptTitle('yes',false,{id:movie.id,value:true,activity:date},undefined,true),false);
console.log('Title quick state assertions passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
