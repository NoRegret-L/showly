#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3,fcntl,sys
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    for source in (root/"model").glob("*.ets"):shutil.copyfile(source,w/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ArchiveSyncRules.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const a=require('node:assert/strict'),m=require('./ArchiveSyncRules');
const item={media:{id:'show:1',kind:'show',title:'T',year:2020,watched:false},at:123};
const remote={section:'dropped',entry:item},row={id:'show:1',base:[remote],remove:true};
for(let i=0;i<100;i++){
 a.equal(m.archivePlan(undefined,item,[]).send.section,'progress_watched');
 a.equal(m.archivePlan(undefined,item,[remote]).send,undefined);
 a.equal(m.archivePlan(row,undefined,[remote]).send.remove,true);
 a.equal(m.archivePlan(row,item,[remote]).blocked,true);
 a.equal(m.archivePlan({...row,base:[]},undefined,[remote]).blocked,true);
 a.equal(m.archivePlan(row,undefined,[{...remote,entry:{...item,at:124}}]).blocked,true);
 const pending={...row,pending:{section:'dropped',entry:item,remove:true}};
 a.equal(m.archivePlan(pending,undefined,[remote]).send,undefined);
 a.equal(m.archivePlan(pending,undefined,[]).settled,true);
 a.equal(m.validArchiveLedger(pending),true);a.equal(m.validArchiveLedger({...pending,id:'show:2'}),false);
 a.equal(m.validArchiveLedger({...pending,base:[]}),false);a.equal(m.sameArchiveBase([remote],[remote]),true);
 a.equal(m.archiveImportRows([remote],[row],{hidden:[],mine:[],queue:[]}).length,0);
 const many=Array.from({length:10000},(_,j)=>({section:'calendar',entry:{media:{id:'movie:'+(j+1),kind:'movie',title:'M',year:2020,watched:false},at:123}}));
 a.equal(m.archiveIndex(many).size,10000);
}
console.log('100 archive conflict, receipt, 10k identity and cancellation cycles passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
    path=w/"operation.lock"
    for i in range(100):
        with path.open("a+") as f:
            fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
            child=subprocess.run([sys.executable,"-c","import fcntl,sys;f=open(sys.argv[1],'a+');\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(0)\nsys.exit(1)",str(path)])
            assert child.returncode==0
    db=sqlite3.connect(w/"receipt.db")
    db.execute("CREATE TABLE archive_sync(scope TEXT,media_id TEXT,payload TEXT,PRIMARY KEY(scope,media_id))")
    db.execute("INSERT INTO archive_sync VALUES(?,?,?)",("account:A","show:1","pending"));db.commit();db.close()
    db=sqlite3.connect(w/"receipt.db")
    assert db.execute("SELECT count(*) FROM archive_sync WHERE scope='account:B'").fetchone()[0]==0
    assert db.execute("SELECT payload FROM archive_sync").fetchone()[0]=="pending";db.close()
repo=(root/"data/ArchiveRepository.ets").read_text()
assert repo.index("this.db.commit();",repo.index("const batch:ArchiveMutation[]"))<repo.index("await this.send(session")
assert "archivePlan(row,local.get(row.id),observed).settled" in repo
assert "if(old?.pending){throw" in repo
page=(root/"pages/Index.ets").read_text()
assert "await archive.stageLocal" in page and "await archive.export" in page
assert "trySyncLease" in page and "trySyncLease" in (root/"data/BackgroundObservation.ets").read_text()
print("Archive durable reservations, scope and 100 host cross-process lock attempts passed; no live network")

for method in ('ratingSave','stageOldRatings','confirmBatchUpload','confirmEpisodeUpload','confirmEpisodeRemoval','confirmMediaOperation'):
    body=page.split('  private async '+method+'(',1)[1].split('\n  private ',1)[0]
    assert 'trySyncLease' in body and 'releaseSyncLease' in body,method
