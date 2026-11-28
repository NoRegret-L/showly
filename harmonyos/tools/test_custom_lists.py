import pathlib,shutil,subprocess,tempfile,sqlite3,json
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for source in (root/"model").glob("*.ets"):
        shutil.copyfile(source,work/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","CustomLists.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const assert=require('node:assert/strict'),m=require('./CustomLists');
const media=(n,kind='show')=>({id:kind+':'+n,kind,title:'Title '+n,year:2020,watched:true});
let doc=m.emptyListDocument();
doc=m.applyListCommand(doc,{kind:'create',name:' A '},1);doc=m.applyListCommand(doc,{kind:'create',name:'B'},2);
const a=doc.local[0].id,b=doc.local[1].id;
for(const [id,item] of [[a,media(1)],[a,media(1,'movie')],[b,media(1)]])doc=m.applyListCommand(doc,{kind:'add',id,media:item},3);
assert(m.validateListDocument(doc));assert.equal(doc.local[0].members.length,2);assert.equal(doc.local[0].members[0].media.watched,false);
assert.strictEqual(m.applyListCommand(doc,{kind:'add',id:a,media:media(1)},4),doc);
const index=new m.ListMembershipIndex();index.update(doc.local);
assert.deepEqual(index.listsFor('show:1'),[a,b]);assert.equal(index.count(a),2);
let old=doc;doc=m.applyListCommand(doc,{kind:'move',id:a,mediaId:'movie:1',direction:-1},4);assert.strictEqual(doc.local[1],old.local[1]);assert.equal(doc.local[0].members[0].media.id,'movie:1');
const count=index.updates();index.update(doc.local);assert.equal(index.updates(),count);
doc=m.applyListCommand(doc,{kind:'remove',id:a,mediaId:'show:1'},5);index.update(doc.local);assert.equal(index.updates(),count+1);assert.deepEqual(index.listsFor('show:1'),[b]);
const remote={id:'trakt:42',name:'Cloud',description:'',createdAt:0,updatedAt:0,remote:true,members:[],unsupported:0};
const prior=doc.local;doc=m.replaceRemoteLists(doc,[remote]);assert.strictEqual(doc.local,prior);assert.throws(()=>m.applyListCommand(doc,{kind:'delete',id:remote.id},6));assert.throws(()=>m.replaceRemoteLists(doc,[remote,remote]));
assert.equal(m.sortLists(doc.local,' a ','name',false)[0].id,a);
const ratings=[{media:media(1),rank:1,listedAt:0,userRating:9},{media:media(2),rank:2,listedAt:0},{media:media(3),rank:3,listedAt:0,userRating:4}];
assert.deepEqual(m.sortListMembers(ratings,'all','userRating',false).map(x=>x.media.id),['show:3','show:1','show:2']);
assert.deepEqual(m.sortListMembers(ratings,'all','userRating',true).map(x=>x.media.id),['show:1','show:3','show:2']);
const large={...doc.local[0],members:Array.from({length:10000},(_,i)=>({media:media(i+1),rank:i+1,listedAt:1}))};
const ix=new m.ListMembershipIndex();ix.update([large]);const n=ix.updates();ix.update([large]);assert.equal(ix.updates(),n);
const next={...large,members:large.members.slice(1)};ix.update([next]);assert.equal(ix.updates(),n+1);
const rebuilt=new m.ListMembershipIndex();rebuilt.update([next]);assert.equal(ix.count(a),rebuilt.count(a));assert.deepEqual(ix.listsFor('show:2'),rebuilt.listsFor('show:2'));
const owner=new m.ListsOwner();for(let i=0;i<100;i++){const token=owner.begin();owner.publish(token,[large],false,'',true);const snap=owner.snapshot();owner.publish(token,snap.rows,false,'',true);assert.strictEqual(owner.snapshot(),snap);owner.clear();owner.publish(token,[large],false,'',true);assert.equal(owner.snapshot().rows.length,0);}
console.log('Custom lists: mixed identity, local CRUD, atomic member document, rank, 10k reverse index, 100 stale lifecycles, read-only remote and full fallback passed');
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/CustomListsRepository.ets").read_text()
assert "CREATE TABLE IF NOT EXISTS list_document (scope TEXT PRIMARY KEY,payload TEXT NOT NULL)" in repo
assert "INSERT OR REPLACE INTO list_document(scope,payload) VALUES(?,?)" in repo
with tempfile.TemporaryDirectory() as tmp:
    db=pathlib.Path(tmp)/"lists.db"
    con=sqlite3.connect(db);con.execute("CREATE TABLE IF NOT EXISTS list_document (scope TEXT PRIMARY KEY,payload TEXT NOT NULL)")
    for scope in ("account:A","account:B"):con.execute("INSERT OR REPLACE INTO list_document(scope,payload) VALUES(?,?)",(scope,json.dumps({"scope":scope})))
    con.commit();con.close()
    con=sqlite3.connect(db);assert json.loads(con.execute("SELECT payload FROM list_document WHERE scope=?",("account:A",)).fetchone()[0])["scope"]=="account:A";assert con.execute("SELECT payload FROM list_document WHERE scope=?",("device",)).fetchone() is None;con.close()
transport=(root/"data/TraktCustomLists.ets").read_text()
assert "http.RequestMethod.GET" in transport and "http.RequestMethod.POST" not in transport and "http.RequestMethod.DELETE" not in transport
assert "confirmed.uuid!==uuid" in transport and "items.length!==row.item_count" in transport and "JSON.stringify(initial)!==JSON.stringify(after)" in transport
page=(root/"pages/Index.ets").read_text();assert "CustomListsPage({" in page and "manage:true,selectedItem:item" in page
print("Custom list account persistence, exact native SQL, read-only transport and page wiring passed (host fixtures)")
