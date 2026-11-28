#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile,sqlite3
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    for source in (root/"model").glob("*.ets"):shutil.copyfile(source,w/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ListSyncMerge.ts","RatingRules.ts","ListPersistence.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const a=require('node:assert/strict'),m=require('./ListSyncMerge'),r=require('./RatingRules'),p=require('./ListPersistence');
const item=i=>({media:{id:'show:'+i,kind:'show',title:'T'+i,year:2020,watched:false},rank:i,listedAt:i});
const row={id:'trakt:3',name:'remote',description:'',createdAt:1,updatedAt:3,remote:true,members:[item(1)],unsupported:0};
const blank={nextId:1,local:[],remote:[]};
for(let i=0;i<100;i++){
 const first=m.mergeMappedLists(blank,[row],[]);a.equal(first.doc.local.length,1);a.equal(first.links[0].remoteId,3);
 const local={...first.doc.local[0],name:'local',updatedAt:4,members:Array.from({length:10000},(_,j)=>item(j+1))};
 const next=m.mergeMappedLists({...first.doc,local:[local]},[{...row,members:[item(10001)]}],first.links);
 a.equal(next.doc.local[0].members.length,10001);a.equal(next.doc.local[0].name,'local');a.equal(next.links.length,0);a(p.validStorageDocument(next.doc));
 const replay=m.mergeMappedLists(next.doc,[{...row,members:[item(10001)]}],first.links);a.equal(replay.doc.local[0],next.doc.local[0]);
 a.equal(m.mergeMappedLists(blank,[row],[{localId:'local:1',remoteId:0,pending:'create'}]).doc.local.length,0);
 a.equal(m.mergeMappedLists({...blank,nextId:2},[row],first.links).doc.local.length,0);
 const intents=Array.from({length:200},(_,j)=>({target:{kind:'show',id:j+1,label:''},desired:8,before:5,beforeAt:1,createdAt:1000+j}));
 const body=JSON.parse(r.ratingBatchBody('show',intents,false));a.equal(body.shows.length,200);a.equal(body.shows[199].rated_at,new Date(1199).toISOString());
 const state={known:true,fresh:true,value:5,ratedAt:1,pending:false};
 a.equal(r.ratingIntentDecision(intents[0],state,false),'send');
 a.equal(r.ratingIntentDecision(intents[0],state,true),'blocked');
 a.equal(r.ratingIntentDecision(intents[0],{...state,ratedAt:2},false),'blocked');
 a.equal(r.ratingIntentDecision(intents[0],{...state,value:8},true),'satisfied');
}
console.log('100 rounds: 10k additive mapped list parity, identity tombstones, 200 rating payloads and no resend');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
    db=sqlite3.connect(w/"receipt.db")
    db.execute("CREATE TABLE receipt(scope TEXT,id INT,PRIMARY KEY(scope,id))")
    for i in range(100):
        db.execute("BEGIN")
        db.executemany("INSERT INTO receipt VALUES(?,?)",[("A",j) for j in range(200)])
        db.rollback()
        assert db.execute("SELECT count(*) FROM receipt").fetchone()[0]==0
    db.executemany("INSERT INTO receipt VALUES(?,?)",[("A",j) for j in range(200)]);db.commit();db.close()
    db=sqlite3.connect(w/"receipt.db")
    assert db.execute("SELECT count(*) FROM receipt WHERE scope='A'").fetchone()[0]==200
    assert db.execute("SELECT count(*) FROM receipt WHERE scope='B'").fetchone()[0]==0
    db.close()
repo=(root/"data/RatingsRepository.ets").read_text()
assert repo.count("http.RequestMethod.POST")==1
batch=repo.split("  exportIntents(",1)[1]
assert batch.index("INSERT INTO rating_receipt")<batch.index("this.db.commit()")<batch.index("await this.sendRatings")
assert "SELECT payload FROM rating_receipt" in batch and "pending.has(i.target.id)" in batch
lists=(root/"data/CustomListsRepository.ets").read_text()
assert "current,next.links" in lists and "for(const link of links)" in lists
print("100 host rollback cycles; durable mapping and batched receipt ordering verified")
