#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    shutil.copyfile(root/"model/ManualSync.ets",w/"ManualSync.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ManualSync.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{syncDirections}=require('./ManualSync');
for(let i=0;i<100;i++){
 assert.equal(syncDirections(false,false),undefined);
 assert.deepEqual(syncDirections(true,false),{importEnabled:true,exportEnabled:false});
 assert.deepEqual(syncDirections(false,true),{importEnabled:false,exportEnabled:true});
 assert.deepEqual(syncDirections(true,true),{importEnabled:true,exportEnabled:true});
}
console.log('100 direction selection cycles passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
page=(root/"pages/Index.ets").read_text()
run=page.split("  private async runManualSync(",1)[1].split("  private async changeQuickSync(",1)[0]
assert run.index("bound!==account.uuid")<run.index("if (direction.importEnabled)")<run.index("if (direction.exportEnabled)")
imp=run.split("if (direction.importEnabled)",1)[1].split("if (direction.exportEnabled)",1)[0]
exp=run.split("if (direction.exportEnabled)",1)[1]
assert all(s in imp for s in ("await this.confirmCloudImport()","await this.importCloud()","await lists.importMapped","await repo.refreshAllVerified"))
assert all(s not in imp for s in ("resumeQueued","resumeTitleQuick","recoverMediaPending"))
assert all(s in exp for s in ("resumeQueued(true)","resumeTitleQuick()","recoverMediaPending()"))
assert "this.manualRunning || this.quickChanging" in page
assert "finally" in run and "this.manualRunning=false" in run
assert "非完整双向同步" in page
assert "await lists.exportAdditive" in exp and "await ratings.exportIntents" in exp
assert "await uploadBatch" in exp and "await syncSelectedMedia" in exp
panel=(root/"pages/SyncStatusPanel.ets").read_text()
assert "SYNC_PERIODS.map" in panel and "showActionSheet" in panel
assert "SYNC_PERIODS.slice" not in panel
assert "[0,1,3,6,24,72,168]" in (root/"data/SyncSchedule.ets").read_text()
print("Manual direction isolation, four-domain import wiring, safe existing export, seven periods and explicit limitations passed")
