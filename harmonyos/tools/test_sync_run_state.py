#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    shutil.copyfile(root/"model/SyncRunState.ets",w/"SyncRunState.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","SyncRunState.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const a=require('node:assert/strict'),m=require('./SyncRunState');
for(let i=0;i<100;i++){
 const o=new m.ManualRunOwner();
 const start=o.begin('A','client',undefined,'import-library',100);
 a.throws(()=>o.begin('B','client',undefined,'recover',101));
 a.equal(m.validSyncRun(start,'B','client'),false);
 a.equal(m.validSyncRun(start,'A','other'),false);
 a.equal(o.transition('import-verified',101).lastImportAt,101);
 const saved=JSON.parse(JSON.stringify(o.transition('export-media',102)));
 a.equal(m.runPhaseLabel(saved.phase).includes('未完整'),true);
 o.end();
 const recovered=new m.ManualRunOwner();
 a.equal(recovered.begin('A','client',saved,'recover',103).lastImportAt,101);
 a.equal(recovered.transition('interrupted',104).lastImportAt,101);
}
console.log('100 sync status lifecycle and identity cycles passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
page=(root/"pages/Index.ets").read_text()
run=page.split("  private async runManualSync(",1)[1].split("  private async stageOldRatings(",1)[0]
assert run.count("await buildMediaPreview(")==1
assert "await syncSelectedMedia(media,store,session,preview,selected,at,current)" in run
assert "if(result.verified){titleChecked++;}" in run
assert run.index("bound!==account.uuid")<run.index("run.begin(")
assert "releaseSyncLease(operation)" in run and "phase('interrupted')" in run
sender=(root/"data/TraktMediaSync.ets").read_text()
assert "await buildMediaPreview(binding, session, records, uuid, store)" in sender
assert sender.index("await store.reserveOperation")<sender.index("await request.request")
assert "await readActivity(session) !== fresh.activity" in sender
assert "ManualSyncControls" in page
print("Single reviewed outer preview, verified receipt counts, persistent diagnostic status and original sender fences checked (host)")
