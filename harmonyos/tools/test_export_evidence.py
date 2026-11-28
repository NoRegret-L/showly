#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    shutil.copyfile(root/"model/ExportEvidence.ets",w/"ExportEvidence.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ExportEvidence.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const a=require('node:assert/strict'),x=require('./ExportEvidence');
for(let i=0;i<100;i++){
 const t=new Date(1000+i).toISOString();
 a.equal(x.actualWatchTime(t),t);a.equal(x.actualWatchTime(undefined),'');
 a.equal(x.actualWatchTime('invalid'),'');a.equal(x.actualWatchTime('2999-01-01'),'');
 const local=Array.from({length:10000},(_,j)=>'show:'+(j+1));
 const remote=local.slice(0,5000);
 a.deepEqual(x.missingMemberIds(local,remote),local.slice(5000));
 a.equal(x.membersSatisfied(local,remote),false);a.equal(x.membersSatisfied(remote,local),true);
 a.throws(()=>x.missingMemberIds(['local:1'],[]));
}
console.log('100 actual-time and 10k member delta cycles passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
    db=sqlite3.connect(str(w/"receipt.db"))
    db.execute("CREATE TABLE list_export_link(scope TEXT NOT NULL,local_id TEXT NOT NULL,remote_id INTEGER NOT NULL,pending TEXT NOT NULL,PRIMARY KEY(scope,local_id))")
    db.execute("INSERT INTO list_export_link VALUES(?,?,?,?)",("account:A","local:1",0,"create"));db.commit();db.close()
    db=sqlite3.connect(str(w/"receipt.db"))
    assert db.execute("SELECT pending FROM list_export_link WHERE scope='account:A'").fetchone()==("create",)
    assert db.execute("SELECT count(*) FROM list_export_link WHERE scope='account:B'").fetchone()==(0,)
    try: db.execute("INSERT INTO list_export_link VALUES(?,?,?,?)",("account:A","local:1",0,"create"));raise AssertionError("duplicate create reservation")
    except sqlite3.IntegrityError: pass
    db.close()
batch=(root/"data/TraktSyncBatch.ets").read_text()
assert "prior.intentSeq!==row.intentSeq" in batch and "times.get(id)" in batch
assert "await store.reserveUpload(uuid, id)" in batch
lists=(root/"data/CustomListsRepository.ets").read_text()
assert lists.index("INSERT INTO list_export_link")<lists.index("await createPrivateList")
assert lists.index("JSON.stringify(missing)")<lists.index("await appendListMembers")
assert "link.remoteId<=0" in lists and "membersSatisfied" in lists
rating=(root/"data/RatingsRepository.ets").read_text()
assert rating.index("INSERT INTO rating_intent")<rating.index("INSERT INTO rating_receipt")<rating.index("http.RequestMethod.POST")
assert "actual.ratedAt!==receipt.beforeAt" in rating and "if(pending)" in rating
print("Timestamp, list create/member receipt, rating intent and account scope wiring passed; host only")
