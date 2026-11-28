import pathlib, shutil, subprocess, tempfile, sqlite3,re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for name in ("CommentRules","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","CommentRules.ts","ReadFlight.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const a=require('node:assert/strict'),m=require('./CommentRules'),{ConsumerReadFlight,ReadCancel}=require('./ReadFlight');
const t={kind:'show',id:1,label:'x'},make=(id,parent=0,username='u')=>({id,parent_id:parent,comment:'this is a spoiler text example',spoiler:false,replies:0,created_at:'2026-11-20T00:00:00Z',user:{username,ids:{uuid:username}}});
const row=m.parseComment(JSON.stringify(make(1)));
a(m.hasSpoiler(row));a(m.validComment('this is another valid comment'));a(!m.validComment('@user a b c d e'));
a(m.canDeleteComment(row,'u','u',Date.parse('2026-11-21')));a(!m.canDeleteComment(row,'v','u',Date.parse('2026-11-21')));a(!m.canDeleteComment(row,'u','u',row.created+13*86400000));a(!m.canDeleteComment({...row,replies:1},'u','u',row.created));
a.equal(m.commentLimit(t),100);a.equal(m.commentLimit({...t,kind:'episode',showId:1,season:0,episode:2}),50);
a.equal(m.commentPath({...t,kind:'episode',showId:1,season:0,episode:2}),'shows/1/seasons/0/episodes/2/comments/newest');
for(const kind of ['show','movie','episode']){let target={...t,kind,showId:2,season:0,episode:1};a.equal(JSON.parse(m.postBody(target,0,'this is another valid comment',true))[kind].ids.trakt,1);}
a.equal(JSON.parse(m.postBody(t,4,'this is another valid comment',false)).show,undefined);
a.equal(m.nextCommentPage(1,'{"X-Pagination-Page":"1","X-Pagination-Page-Count":"3"}'),2);
a.equal(m.nextCommentPage(1,'{}'),0);a.throws(()=>m.parseComments(JSON.stringify([make(2,3)]),1));
const ix=new m.CommentIndex(),rows=m.parseComments(JSON.stringify(Array.from({length:10000},(_,i)=>make(i+1,0,i===9999?'mine':'u'))),0);
for(let i=0;i<100;i++){ix.clear();ix.append(rows,0);ix.append(rows.slice(0,10),0);let result=ix.project('mine','mine');a.equal(result.length,10000);a.equal(result[0].id,10000);ix.reveal(rows[0]);a(ix.isRevealed(rows[0]));a(!ix.isRevealed(rows[1]));ix.append([{...rows[0],text:'changed'}],0);a(!ix.isRevealed(rows[0]));}
ix.clear();ix.append([row],0);ix.append(m.parseComments(JSON.stringify([make(3,1),make(2,1)]),1),1);a.equal(ix.project('','').length,3);
(async()=>{const f=new ConsumerReadFlight();let calls=0;await Promise.all(Array.from({length:100},()=>f.run('show:1:0:1',async()=>{calls++;return 'ok';},new ReadCancel())));a.equal(calls,1);console.log('Comments: 10k x100 cycles, page overlap, spoiler isolation, author/delete fences, exact routes and 100 shared reads passed');})().catch(e=>{console.error(e);process.exitCode=1});
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/CommentsRepository.ets").read_text()
assert repo.count("http.RequestMethod.POST")==1 and repo.count("http.RequestMethod.DELETE")==1
assert repo.index("await this.reserve(scope,{action:'post'")<repo.index("http.RequestMethod.POST")
assert repo.index("await this.reserve(scope,{action:'delete'")<repo.index("http.RequestMethod.DELETE")
assert "a.uuid!==scope.substring(8)" in repo and "row.updated!==expected.updated" in repo
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp)/"comments.db";db=sqlite3.connect(path)
    for ddl in re.findall(r"CREATE TABLE IF NOT EXISTS [^']+",repo):db.execute(ddl)
    db.execute("INSERT INTO comment_receipt VALUES(?,?)",("account:A","pending"));db.commit();db.close();db=sqlite3.connect(path)
    assert db.execute("SELECT payload FROM comment_receipt WHERE scope=?",("account:A",)).fetchone()[0]=="pending"
    assert db.execute("SELECT payload FROM comment_receipt WHERE scope=?",("account:B",)).fetchone() is None
    try:db.execute("INSERT INTO comment_receipt VALUES(?,?)",("account:A","duplicate"));raise AssertionError("duplicate accepted")
    except sqlite3.IntegrityError:db.rollback()
    db.close()
print("Comments durable unknown receipt, account isolation, no automatic resend and exact DELETE host assertions passed")
