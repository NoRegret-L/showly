#!/usr/bin/env python3
"""Production policy, independent resource work, stale consumer and service gates."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation","PresentationPolicy","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","PresentationPolicy.ts","ReadFlight.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),p=require('./PresentationPolicy.js'),{ReadFlight}=require('./ReadFlight.js');
const now=Date.parse('2026-11-27T10:00:00Z');Date.now=()=>now;
assert.equal(p.retryAfter('120',now),now+120000);
assert.equal(p.retryAfter('Fri, 27 Nov 2026 10:02:00 GMT',now),now+120000);
assert.equal(p.retryAfter('',now),Number.MAX_SAFE_INTEGER);
assert.equal(p.httpPresentationFailure(404,'',now).category,'missing');
assert.equal(p.httpPresentationFailure(503,'',now).category,'temporary');
const gate=new p.PresentationGate();
gate.record('trakt:A',p.httpPresentationFailure(429,'120',now),true);
gate.manualProbe();assert.throws(()=>gate.check('trakt:A',now+119999),/limited/);
gate.check('poster:A',now);gate.check('trakt:B',now);gate.check('trakt:A',now+120000);
gate.record('trakt:A',p.httpPresentationFailure(403,'',now),true);
assert.throws(()=>gate.check('trakt:A',now),/authorization/);gate.manualProbe();gate.check('trakt:A',now);
gate.record('trakt:A',p.httpPresentationFailure(429,'',now),true);
assert.throws(()=>gate.check('trakt:A',now),/limited/);gate.manualProbe();gate.check('trakt:A',now);
const task=(i,artwork=true,season=1)=>({media:{id:'show:'+i,kind:'show',title:'x',year:2026,watched:false},artwork,season,posterUrls:[]});
const tasks=[task(4,false),task(1),task(2),task(1,true,2),task(3)];
const attempts=new p.PresentationAttempts();
(async()=>{
 let calls=[],published=0,reported=0;
 const work=async t=>{calls.push(t.media.id);if(t.media.id==='show:2')throw new p.PresentationFailure('temporary',503)};
 await p.runPresentationPass(tasks,'title',attempts,'A',()=>true,t=>t.artwork,work,()=>published++,()=>reported++);
 assert.deepEqual(calls,['show:1','show:2','show:3']);assert.equal(published,3);assert.equal(reported,1);
 calls=[];await p.runPresentationPass(tasks,'title',attempts,'A',()=>true,t=>t.artwork,work,()=>{},()=>{});
 assert.deepEqual(calls,['show:1','show:3']);
 calls=[];await p.runPresentationPass(tasks,'title',attempts,'B',()=>true,t=>t.artwork,work,()=>{},()=>{});
 assert.deepEqual(calls,['show:1','show:2','show:3']);
 attempts.retry();calls=[];
 await p.runPresentationPass(tasks,'artwork',attempts,'A',()=>true,()=>true,work,()=>{},()=>{});
 assert.deepEqual(calls,['show:1','show:2','show:3','show:4']);
 let resolve,active=true,stalePublishes=0,started=[];
 const slow=p.runPresentationPass(tasks,'season',attempts,'A',()=>active,t=>t.artwork,async t=>{started.push(t.media.id);await new Promise(r=>resolve=r)},()=>stalePublishes++,()=>{});
 await Promise.resolve();active=false;
 let titleDone=false;
 await p.runPresentationPass([task(9)],'title',attempts,'A',()=>true,()=>true,async()=>{titleDone=true},()=>{},()=>{});
 assert(titleDone);resolve();await slow;assert.deepEqual(started,['show:1']);assert.equal(stalePublishes,0);
 let reject,scroll=true,staleErrors=0;
 const scrolling=p.runPresentationPass([task(8)],'title',attempts,'A',()=>scroll,()=>true,async()=>{await new Promise((_,r)=>reject=r)},()=>{},()=>staleErrors++);
 await Promise.resolve();scroll=false;reject(new p.PresentationFailure('temporary',0));await scrolling;
 let retried=0;
 await p.runPresentationPass([task(8)],'title',attempts,'A',()=>true,()=>true,async()=>retried++,()=>{},()=>{});
 assert.equal(staleErrors,0);assert.equal(retried,0);
 attempts.retry();
 await p.runPresentationPass([task(8)],'title',attempts,'A',()=>true,()=>true,async()=>retried++,()=>{},()=>{});
 assert.equal(retried,1);
 const flights=new ReadFlight();let network=0;
 await Promise.all(Array.from({length:393},()=>flights.run('A:show:1:season:1',async()=>{network++;return 1})));
 assert.equal(network,1);
 console.log('Presentation policy: item failure isolation, viewport order, title/season independence, stale queue cancellation, account scope, Retry-After and 393-to-1 flight passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
repo=(root/"data"/"PresentationRepository.ets").read_text()
detail=(root/"data"/"TraktDetails.ets").read_text()
progress=(root/"data"/"TraktProgress.ets").read_text()
assert "presentationBlocked" not in page
assert "this.presentationLane('local')" in page and "this.presentationLane('title')" in page and "this.presentationLane('season')" in page
assert "queue.relevant(row)" in page and "account===this.currentProgressScope()" in page
assert "this.presentationAttempts.nextAttempt(key)" in page
assert "await repo.hydrateSeason(" in page and "await repo.translation(" in page and "await repo.season(" in page
assert "await repo.artwork(task.media,\'\',task.artwork,task.posterUrls,false,consumer)" in page
assert "this.summaryMissing.add(summaryKey)" in repo
assert "throw error;" not in repo
assert repo.count("const failure: PresentationFailure = presentationFailure(error as Error);")==2
assert repo.count("if (failure.category!=='missing') { throw failure; }")==2
assert "this.hydrateFlights.run(" in repo and "this.seasonFlights.run(JSON.stringify([clientId,key,language])" in repo
assert "checkPresentationService(service)" in detail and progress.count("checkPresentationService(service)")==2
assert "presentationHttpError(service,response.responseCode" in detail and progress.count("presentationHttpError(service,response.responseCode")==2
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Presentation transport, local-only offscreen translation, incremental publishing and sync safety wiring passed")
