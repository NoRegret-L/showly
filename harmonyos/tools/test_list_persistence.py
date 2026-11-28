import pathlib, shutil, subprocess, tempfile, sqlite3, re, json
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for source in (root/"model").glob("*.ets"):
        shutil.copyfile(source,work/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ListPersistence.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const assert=require('node:assert/strict'),m=require('./CustomLists'),p=require('./ListPersistence');
const media=i=>({id:'show:'+i,kind:'show',title:'Title '+i,year:2020,watched:false});
let doc=m.applyListCommand(m.emptyListDocument(),{kind:'create',name:'List'},1);
let row={...doc.local[0],members:Array.from({length:10000},(_,i)=>({media:media(i+1),rank:i+1,listedAt:1}))};
doc={...doc,local:[row]};
assert(p.validStorageDocument(doc));
let next=m.applyListCommand(doc,{kind:'add',id:row.id,media:media(10001)},2);
let d=p.listDelta(doc,next);assert.equal(d.members.length,1);assert.equal(d.lists.length,1);assert.equal(d.removedMembers.length,0);
next=m.applyListCommand(doc,{kind:'remove',id:row.id,mediaId:'show:5000'},2);d=p.listDelta(doc,next);assert.equal(d.members.length,0);assert.equal(d.removedMembers.length,1);
next=m.applyListCommand(doc,{kind:'reorder',id:row.id,mediaId:'show:10',targetId:'show:12'},2);d=p.listDelta(doc,next);assert.equal(d.members.length,3);assert.equal(next.local[0].members[11].media.id,'show:10');
assert(p.validStorageDocument(next));assert.strictEqual(p.mergeListBackup(doc,p.localListBackup(doc)),doc);
let merged=p.mergeListBackup(doc,p.localListBackup(next));assert.equal(merged.local.length,2);assert.strictEqual(p.mergeListBackup(merged,p.localListBackup(next)),merged);
let owner=new m.ListsOwner();for(let i=0;i<100;i++){let t=owner.begin();owner.publish(t,doc.local,false,'',true);owner.clear();owner.publish(t,next.local,false,'',true);assert.equal(owner.snapshot().rows.length,0);}
assert(p.validListPreference(p.defaultListPreference()));
console.log('List storage: 10k delta add/remove/reorder, canonical ranks, backup idempotence, 100 lifecycles passed');
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/CustomListsRepository.ets").read_text()
sql=re.findall(r"executeSql\('([^']+)'",repo)
ddl=[x for x in sql if x.startswith("CREATE ")]
expected={"list_document","list_scope_v2","list_header_v2","list_member_v2","list_preference_v2","list_export_link","list_metadata_base"}
assert {re.match(r"CREATE TABLE IF NOT EXISTS (\w+)",q).group(1) for q in ddl if q.startswith("CREATE TABLE")}==expected
assert any("list_member_reverse_v2" in q for q in ddl)
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp)/"lists.db"
    db=sqlite3.connect(path)
    for q in ddl:db.execute(q)
    db.execute("INSERT INTO list_document VALUES(?,?)",("account:A","legacy"));db.commit()
    db.execute("BEGIN")
    db.execute("INSERT INTO list_header_v2 VALUES(?,?,?,?,?)",("account:A","local:1",0,1,"header"))
    db.rollback();assert db.execute("SELECT count(*) FROM list_header_v2").fetchone()[0]==0
    assert db.execute("SELECT payload FROM list_document").fetchone()[0]=="legacy"
    for scope in ("account:A","account:B"):
        db.execute("BEGIN")
        db.execute("INSERT INTO list_header_v2 VALUES(?,?,?,?,?)",(scope,"local:1",0,1,"header"))
        db.execute("INSERT INTO list_member_v2 VALUES(?,?,?,?,?)",(scope,"local:1","show:1",1,scope))
        db.execute("INSERT INTO list_scope_v2 VALUES(?,?)",(scope,2))
        db.commit()
    db.execute("INSERT INTO list_export_link VALUES(?,?,?,?)",("account:A","local:1",0,"create"))
    db.commit()
    db.close();db=sqlite3.connect(path)
    assert db.execute("SELECT remote_id,pending FROM list_export_link WHERE scope=? AND local_id=?",("account:A","local:1")).fetchone()==(0,"create")
    assert db.execute("SELECT count(*) FROM list_export_link WHERE scope='account:B'").fetchone()==(0,)
    db.execute("UPDATE list_export_link SET remote_id=42,pending='' WHERE scope='account:A'");db.rollback()
    assert db.execute("SELECT remote_id,pending FROM list_export_link").fetchone()==(0,"create")
    assert db.execute("SELECT payload FROM list_member_v2 WHERE scope=? AND list_id=? AND media_id=?",("account:A","local:1","show:1")).fetchone()[0]=="account:A"
    assert db.execute("SELECT payload FROM list_member_v2 WHERE scope=?",("device",)).fetchone() is None
    db.execute("BEGIN");db.execute("DELETE FROM list_member_v2 WHERE scope=? AND list_id=? AND media_id=?",("account:A","local:1","show:1"));db.rollback()
    assert db.execute("SELECT count(*) FROM list_member_v2").fetchone()[0]==2
    db.close()
print("Native SQL schema, migration interruption, marker, cold recovery, rollback and scope isolation host fixture passed")
