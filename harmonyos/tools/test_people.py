import pathlib, shutil, subprocess, tempfile, sqlite3, re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for name in ("PeopleRules","Media","DetailSections","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","PeopleRules.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const a=require('node:assert/strict'),p=require('./PeopleRules'),d=require('./DetailSections');
const person={personId:42,tmdb:88,name:'A',department:'Acting',key:'Acting:42',roles:[]};
a.equal(p.personKey(person),'trakt:42');a.throws(()=>p.parsePerson(JSON.stringify({ids:{trakt:42,tmdb:89},name:'A'}),person));a.equal(p.parsePerson(JSON.stringify({ids:{trakt:42,tmdb:88},name:'A',birthday:'2000-01-01'}),person).birthday,'2000-01-01');
const credits=Array.from({length:100},(_,i)=>({person:{id:i+1,name:'P'+i},character:'role'}));a.equal(d.projectPeople({cast:credits}).length,30);a.equal(d.projectPeople({cast:credits},true).length,100);
const raw=JSON.stringify({cast:[{show:{ids:{trakt:1},title:'A',first_aired:'2025-01-01T00:00:00Z'},character:'x'},{show:{ids:{trakt:1},title:'A',first_aired:'2025-01-01T00:00:00Z'},character:'y'},{show:{ids:{trakt:2},title:'B',status:'planned'}},{show:{ids:{trakt:3},title:'C'}}]});
const rows=p.parsePersonCredits(raw,'show',true);a.equal(rows.length,3);a.deepEqual(rows[0].roles,['x','y']);let out=p.projectPersonCredits(rows,'all',false,new Set());a.equal(out[0].group,'待上映');a.equal(out[1].key,'show:2');a.equal(out[3].key,'show:1');a.equal(p.projectPersonCredits(rows,'all',true,new Set(['show:1'])).length,2);
const big=Array.from({length:10000},(_,i)=>({media:{id:'movie:'+(i+1),kind:'movie',title:'M'+i,year:2025,watched:false},release:'2025-01-01',upcoming:false,roles:[]}));
for(let i=0;i<100;i++){const r=p.projectPersonCredits(big,'movie',true,new Set(['movie:'+(i+1)]));a.equal(r.length,2);a.equal(r[1].key,'movie:'+(i+1));a.equal(p.projectPersonCredits(big,'show',false,new Set()).length,0);}
console.log('People: exact identities, full credits, role dedup, upcoming ordering, 10k x100 filters passed');
const {ConsumerReadFlight,ReadCancel}=require('./ReadFlight');
(async()=>{
 const f=new ConsumerReadFlight();let starts=0,finish;
 const job=()=>{starts++;return new Promise(resolve=>{finish=resolve;});};
 const signals=Array.from({length:100},()=>new ReadCancel());
 const jobs=signals.map(s=>f.run('client:trakt:42:profile',job,s).catch(e=>e.message));
 await Promise.resolve();a.equal(starts,1);signals[0].cancel();a.equal(await jobs[0],'Read cancelled');finish('profile');
 a((await Promise.all(jobs.slice(1))).every(x=>x==='profile'));
 const keys=['client:trakt:42:profile','client:trakt:43:profile','client:trakt:42:show:cast','other:trakt:42:profile'];
 let distinct=0;await Promise.all(keys.map(k=>f.run(k,async()=>{distinct++;return k;},new ReadCancel())));a.equal(distinct,4);
 console.log('People shared read: 100 consumers, one flight, independent cancellation and client/person/lane isolation passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/PeopleRepository.ets").read_text()
assert "ConsumerReadFlight" in repo and "signal.check()" in repo and "parsePerson(raw,person)" in repo
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp)/"people.db";db=sqlite3.connect(path)
    ddl=re.search(r"CREATE TABLE IF NOT EXISTS person_section\([^']+\)",repo).group(0);db.execute(ddl)
    for ident in ("trakt:1","trakt:2"):
        for lane in ("profile","show:cast","movie:cast","show:crew"):
            db.execute("INSERT INTO person_section VALUES(?,?,?)",(ident,lane,ident+lane))
    db.commit();db.close();db=sqlite3.connect(path)
    assert db.execute("SELECT payload FROM person_section WHERE identity=? AND lane=?",("trakt:1","profile")).fetchone()[0]=="trakt:1profile"
    assert db.execute("SELECT count(*) FROM person_section").fetchone()[0]==8;db.close()
print("People cache cold recovery, source-lane and person identity isolation passed (host)")
