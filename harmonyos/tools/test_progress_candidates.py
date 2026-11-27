#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ProgressCandidates.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),p=require('./ProgressRules.js'),c=require('./ProgressCandidates.js');
const now=Date.parse('2026-11-27T00:00:00Z'),day=86400000;
const make=(i)=>({source:{media:{id:'show:'+i,title:'Title '+i,kind:'show',year:2026,watched:false},episodes:[{episode:{id:i*10+1,season:1,number:1,title:'One',firstAired:new Date(now-10*day).toISOString()},watched:false,watchedAt:0},{episode:{id:i*10+2,season:1,number:2,title:'Two',firstAired:new Date(now-9*day).toISOString()},watched:false,watchedAt:0}],recentAt:0,randomOrder:i},stateKey:'state:'+i,catalogKey:'catalog:'+i});
const inputs=Array.from({length:393},(_,i)=>make(i+1)),prefs=p.defaultProgress(),index=new c.ProgressCandidateIndex();
index.begin('A');let calls=0;
const run=(rows,pr=prefs,time=now)=>{const plan=index.plan(rows,pr,time);calls+=plan.pending.length;const built=c.computeCandidates({inputs:plan.pending,prefs:pr,now:time});const out=index.commit(plan,built);
assert.deepEqual(out.rows,rows.map(x=>p.selectProgress(x.source,pr,x.flag?[x.flag]:[],time)).filter(Boolean));return {plan,out};};
assert.equal(run(inputs).plan.pending.length,393);
assert.equal(run(inputs,{...prefs,sort:'title'}).plan.pending.length,0);
const changed=inputs.slice();changed[12]=JSON.parse(JSON.stringify(changed[12]));changed[12].source.episodes[0].watched=true;changed[12].source.episodes[0].watchedAt=now;changed[12].stateKey+=':watched';
assert.equal(run(changed).plan.pending.length,1);
changed[13]={...changed[13],flag:{id:'show:14',pinned:true,held:false}};assert.equal(run(changed).plan.pending.length,1);
changed[14]={...changed[14],flag:{id:'show:15',pinned:false,held:true}};assert.equal(run(changed).plan.pending.length,1);
assert.equal(run(changed.filter(x=>x.source.media.id!=='show:16')).plan.pending.length,0);
assert.equal(run(changed).plan.pending.length,0);
const future=make(999);future.source.episodes=[{episode:{id:9991,season:1,number:1,title:'Future',firstAired:new Date(now+day).toISOString()},watched:false,watchedAt:0}];
const timed=[...changed,future];const noUpcoming={...prefs,days:0};
assert.equal(run(timed,noUpcoming).plan.pending.length,394);
assert.equal(run(timed,noUpcoming,now+day-1).plan.pending.length,0);
const boundary=run(timed,noUpcoming,now+day);assert.equal(boundary.plan.pending.length,1);assert(boundary.out.rows.some(x=>x.media.id==='show:999'));
assert.equal(run(timed,noUpcoming,now+day+1).plan.pending.length,1);
assert.equal(run(timed,noUpcoming,now+day-1).plan.pending.length,1);
index.begin('B');assert.equal(run(changed).plan.pending.length,393);
for(const strategy of ['last','oldest'])for(const count of ['aired','all'])for(const days of [0,30]){run(changed,{...prefs,strategy,count,days});}
const base=p.selectProgress(make(1).source,prefs,[],now);
const rated=[{...base,media:{...base.media,id:'show:1',title:'The Zebra'},userRating:8},{...base,media:{...base.media,id:'show:2',title:'Alpha'},userRating:8},{...base,media:{...base.media,id:'show:3',title:'Beta'},userRating:4},{...base,media:{...base.media,id:'show:4',title:'A'}}];
assert.deepEqual(p.sortProgressCandidates(rated,{...prefs,sort:'userRating',descending:true},'all','').map(x=>x.media.id),['show:2','show:1','show:3','show:4']);
assert.deepEqual(p.sortProgressCandidates(rated,{...prefs,sort:'userRating',descending:false},'all','').map(x=>x.media.id),['show:3','show:2','show:1','show:4']);
assert(p.validProgress({...prefs,sort:'userRating'}));
console.log('Progress candidates: 393 cold, 1 changed watch, 1 pin, 1 hold, 0 hide/unhide, 0 display-only, exact time/rollback and scope, strategy/count/window parity and user-rating sort passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
projection=(root/"data"/"LibraryProjection.ets").read_text()
task=(root/"data"/"ProgressCandidateTask.ets").read_text()
assert "progressRow.sourceStateKey = work.key" in projection and "progressRow.sourceCatalogKey = work.catalogKey" in projection
assert "inputs:plan.pending" in page and "executeDisplayTask(new taskpool.Task(progressCandidateTask" in task
assert "this.candidateIndex.retain(" in page and "this.candidateIndex.remove(showId)" in page
assert "this.scheduleCandidateWake(output.expiry)" in page and "this.cancelCandidateWake()" in page
mark=page.split("  private async markNext(",1)[1].split("  private invalidateMovieCalendar",1)[0]
assert mark.count("this.validateNextTarget(row)") == 2
assert "await store.boundAccount()" in mark and "eligibleCatalog(" in mark and "await projectDetail(" in mark and "await store.mark(" in mark
assert "effective.complete" in mark and "effective.localAllowed" in mark and "if (!unwatched)" in mark
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
assert "this.currentShowRatingKey()" in page and "this.collectionRatingKey===key" in page
print("Incremental candidate scope, timer, target-only live validation, verified rating scope and sync safety wiring passed")
