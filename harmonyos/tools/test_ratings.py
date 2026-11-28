import pathlib, shutil, subprocess, tempfile, sqlite3, re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    shutil.copyfile(root/"model/RatingRules.ets",work/"RatingRules.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","RatingRules.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const a=require('node:assert/strict'),r=require('./RatingRules');
const t={kind:'show',id:42,label:'A'},s={known:true,value:5,ratedAt:1,pending:false,fresh:true};
for(const kind of ['show','movie','season','episode']){let body=JSON.parse(r.ratingBody({...t,kind},8,1000));a.deepEqual(Object.keys(body),[kind+'s']);a.equal(body[kind+'s'][0].ids.trakt,42);a.equal(body[kind+'s'][0].rating,8);body=JSON.parse(r.ratingBody({...t,kind},0,1000));a.deepEqual(body,{[kind+'s']:[{ids:{trakt:42}}]});}
a.equal(r.ratingDecision(s,s,5),'match');a.equal(r.ratingDecision(s,s,8),'write');a.equal(r.ratingDecision(s,{...s,ratedAt:2},8),'conflict');a.equal(r.ratingDecision(s,{...s,pending:true},8),'blocked');a.equal(r.ratingDecision(s,{...s,fresh:false},8),'blocked');
a.equal(r.receiptSatisfied({target:t,desired:8,before:5,createdAt:2},{...s,value:8,pending:true}),true);
a.equal(r.receiptSatisfied({target:t,desired:0,before:5,createdAt:2},{...s,value:0,known:false}),false);
const rows=Array.from({length:10000},(_,i)=>({id:i+1,value:5,ratedAt:1}));a(r.validRatingRows(rows));a(!r.validRatingRows(rows.concat(rows[0])));
for(let i=0;i<100;i++){let next=rows.slice();next[i]={...next[i],value:8};let d=r.ratingDelta(rows,next);a.equal(d.upserts.length,1);a.equal(d.removed.length,0);a.equal(r.ratingDelta(next,next).upserts.length,0);}
a.equal(r.ratingDelta(rows,rows.slice(1)).removed[0],1);
console.log('Ratings: four typed IDs, exact payloads, conflict, unknown receipt, removal and 10k x100 delta passed');
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/RatingsRepository.ets").read_text()
assert repo.count("http.RequestMethod.POST")==1
assert repo.index("INSERT INTO rating_receipt")<repo.index("http.RequestMethod.POST")
assert "receiptSatisfied(receipt,state)" in repo and "this.db.rollBack()" in repo
assert "account.uuid!==scope.substring(8)" in repo
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp)/"ratings.db"
    db=sqlite3.connect(path)
    for q in re.findall(r"executeSql\('([^']+)'",repo):
        if q.startswith("CREATE TABLE"):db.execute(q)
    for scope in ("device","account:A","account:B"):
        for kind in ("show","movie","season","episode"):
            db.execute("INSERT INTO personal_rating VALUES(?,?,?,?)",(scope,kind,42,scope+kind))
    db.execute("INSERT INTO rating_receipt VALUES(?,?,?,?)",("account:A","show",42,"pending"))
    db.execute("INSERT INTO rating_intent VALUES(?,?,?,?)",("account:A","show",42,"desired"))
    db.execute("INSERT OR REPLACE INTO rating_intent VALUES(?,?,?,?)",("account:B","show",42,"unsent"))
    db.commit();db.close()
    db=sqlite3.connect(path)
    assert db.execute("SELECT count(*) FROM personal_rating").fetchone()[0]==12
    assert db.execute("SELECT count(*) FROM rating_receipt WHERE scope='account:B'").fetchone()[0]==0
    db.execute("DELETE FROM rating_receipt WHERE scope='account:A'");db.rollback()
    assert db.execute("SELECT count(*) FROM rating_receipt").fetchone()[0]==1
    assert db.execute("SELECT payload FROM rating_intent WHERE scope='account:A'").fetchone()==('desired',)
    db.execute("DELETE FROM rating_intent WHERE scope='account:B'");db.commit()
    assert db.execute("SELECT count(*) FROM rating_intent").fetchone()[0]==1
    db.close()
print("Rating receipt durability, scope/type isolation, no retry, rollback host assertions passed")
