#!/usr/bin/env python3
"""Compile actual background executor against deterministic SDK/network fakes."""
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
src=(root/"data/BackgroundObservation.ets").read_text()
worker=(root/"workability/SyncWorkAbility.ets").read_text()
assert "ticket===this.run" in worker and "this.run++" in worker
assert all(x not in src for x in ("RequestMethod.POST","loadRefresh(","saveRefresh(","EpisodeStore","MediaStore","uploadBatch","traktAuth.restore"))
stub=r"""
interface BackgroundGrant {uuid:string;clientId:string;token:string;expiresAt:number;id:string;}
interface CloudLibrary {generation:number;activity:string;observedAt:number;verifiedAt?:number;}
interface TraktSession {clientId:string;token:string;generation:number;}
let grant:BackgroundGrant|undefined;
let locked=false, account='a', reads=0, stopAfterRead=false, stopped=false, failRead=false;
let previous:CloudLibrary|undefined;
let storage=new Map<string,string>(), pendingPath='';
let releases=0;
export function setup(uuid='a',expiry=Date.now()+100000,id='grant-a'){
 grant={uuid,clientId:'client',token:'access-secret',expiresAt:expiry,id};
 account=uuid; reads=0; stopAfterRead=false;stopped=false;failRead=false;previous=undefined;
}
export function faults(kind:string){if(kind==='wrong')account='b';if(kind==='stop')stopAfterRead=true;if(kind==='failure')failRead=true;}
export function state(){return {reads,locked,releases,previous,stored:[...storage.values()]};}
export function setLocked(value:boolean){locked=value;}
export function active(){return !stopped;}
function configureVaultLock(_directory:string){}
function tryVaultLock(){if(locked)return undefined;locked=true;return 1;}
function releaseVaultLock(_lease:number){locked=false;releases++;}
function readBackgroundGrant(){return grant;}
function validateObservation(s:CloudLibrary){if(!s||!s.activity)throw Error('invalid');}
async function readSyncAccount(_session:TraktSession,permit:()=>boolean){if(!permit())throw Error('stopped');reads++;return {uuid:account};}
async function readCloudLibraryIncremental(_session:TraktSession,prior:CloudLibrary|undefined,permit:()=>boolean){
 if(!permit())throw Error('stopped');reads++;previous=prior;if(failRead)throw Error('offline');if(stopAfterRead)stopped=true;
 return {generation:1,activity:'rev',observedAt:Date.now()};
}
const fs={
 OpenMode:{WRITE_ONLY:1,CREATE:2,TRUNC:4},
 readTextSync:(p:string)=>{const v=storage.get(p);if(v===undefined)throw Error('missing');return v;},
 openSync:(p:string,_mode:number)=>{pendingPath=p;return {fd:1};},
 writeSync:(_fd:number,value:string)=>{storage.set(pendingPath,value);},
 fsyncSync:(_fd:number)=>{},
 closeSync:(_file:{fd:number})=>{},
 renameSync:(from:string,to:string)=>{const v=storage.get(from);if(v===undefined)throw Error('missing');storage.set(to,v);storage.delete(from);}
};
"""
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    (w/"Background.ts").write_text(stub+src[src.index("interface BackgroundSnapshot"):])
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Background.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const assert=require('node:assert/strict');const x=require('./Background');
(async()=>{
 x.setup();await x.runBackgroundObservation('/private',x.active);
 assert.equal(x.state().reads,3);assert(!x.state().locked);
 assert(x.backgroundReadInfo('/private','a','client').verifiedAt>0);
 assert.equal(x.readPreparedObservation('/private','a','client',42).generation,42);
 assert.equal(x.readPreparedObservation('/private','b','client',42),undefined);
 assert(x.state().stored.every(s=>!s.includes('access-secret')));
 x.setup();await x.runBackgroundObservation('/private',x.active);
 assert.equal(x.state().previous.activity,'rev');
 const original=x.state().stored[0];
 for(let i=0;i<100;i++){
  x.setup('a',Date.now()+100000,'new-'+i);x.faults('wrong');await x.runBackgroundObservation('/private',x.active);
  assert.equal(x.state().reads,1);assert.equal(x.readPreparedObservation('/private','a','client',1),undefined);assert(!x.state().locked);
  x.setup('a',Date.now()+100000,'stop-'+i);x.faults('stop');await assert.rejects(x.runBackgroundObservation('/private',x.active));
  assert(!x.state().locked);assert.equal(x.state().stored[0],original);
  x.setup('a',Date.now()+100000,'offline-'+i);x.faults('failure');await assert.rejects(x.runBackgroundObservation('/private',x.active));
  assert(!x.state().locked);assert.equal(x.state().stored[0],original);
 }
 x.setup('a',Date.now()-1);await x.runBackgroundObservation('/private',x.active);assert.equal(x.state().reads,0);
 x.setup();x.setLocked(true);await x.runBackgroundObservation('/private',x.active);assert.equal(x.state().reads,0);x.setLocked(false);
 console.log('Background observation executor: 100 rounds account mismatch, cancellation, offline recovery, expired/contended grant, no secret in persisted snapshot and generation remap passed');
})().catch(e=>{console.error(e);process.exit(1)});
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
