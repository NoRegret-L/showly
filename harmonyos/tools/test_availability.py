import pathlib, shutil, subprocess, tempfile, sqlite3,re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for name in ("AvailabilityRules","Media","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","AvailabilityRules.ts","ReadFlight.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const a=require('node:assert/strict'),m=require('./AvailabilityRules'),{ConsumerReadFlight,ReadCancel}=require('./ReadFlight');
const p={provider_id:1,provider_name:'P',logo_path:'/x.png'};
const raw=JSON.stringify({id:7,results:{US:{flatrate:[p],buy:[p],link:'https://www.themoviedb.org/movie/7/watch?locale=US'},GB:{free:[p]}}});
a.deepEqual(m.parseProviders(raw,7,'us')[0].options,['订阅','购买']);a.deepEqual(m.parseProviders(raw,7,'uk')[0].options,['免费']);a.deepEqual(m.parseProviders(raw,7,'hk'),[]);a.throws(()=>m.parseProviders(raw,8,'us'));
a.equal(m.safeProviderLink('https://evil.example/movie/7/watch'),'');a.equal(m.fresh(1,m.STREAMING_AGE+1,m.STREAMING_AGE),false);
const series=m.parseSeries(JSON.stringify([{ids:{trakt:1},name:'S',privacy:'public',item_count:10000},{ids:{trakt:2},name:'private',privacy:'private',item_count:1}]))[0];
const rawItems=JSON.stringify(Array.from({length:10000},(_,i)=>({rank:10000-i,movie:{ids:{trakt:i+1},title:'M'+i}})));
for(let i=0;i<100;i++){const rows=m.parseSeriesMovies(rawItems);a.equal(rows[0].rank,1);m.verifySeriesMembers(series,rows,'movie:1');a.throws(()=>m.verifySeriesMembers(series,rows.slice(1),'movie:1'));}
(async()=>{const f=new ConsumerReadFlight();let n=0;const consumers=Array.from({length:100},()=>new ReadCancel());await Promise.all(consumers.map(c=>f.run('series:1',async()=>{n++;return 'ok';},c)));a.equal(n,1);await Promise.all(['US','GB'].map(k=>f.run(k,async()=>{n++;return k;},new ReadCancel())));a.equal(n,3);console.log('Availability: region/type isolation, provider merge, strict URLs, public rank, 10k x100 members and shared flights passed');})().catch(e=>{console.error(e);process.exitCode=1});
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/AvailabilityRepository.ets").read_text()
assert "http.RequestMethod.GET" in repo and "http.RequestMethod.POST" not in repo
assert "credentialVersion" in repo and "JSON.stringify([key,version])" in repo
with tempfile.TemporaryDirectory() as tmp:
    db=sqlite3.connect(pathlib.Path(tmp)/"cache.db");db.execute(re.search(r"CREATE TABLE IF NOT EXISTS availability_cache\([^']+\)",repo).group(0))
    for key in ("provider:movie:1:7:us","provider:movie:1:7:uk","provider:show:1:7:us","series:items:1"):
        db.execute("INSERT INTO availability_cache VALUES(?,?,?)",(key,"[]",1))
    db.commit();assert db.execute("SELECT count(*) FROM availability_cache").fetchone()[0]==4
    db.close()
print("Availability read-only transport and persistent region/type lanes passed (host)")
