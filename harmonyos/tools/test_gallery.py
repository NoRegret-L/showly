import pathlib, shutil, subprocess, tempfile, sqlite3,re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for name in ("GalleryRules","Media","ReadFlight","ArtworkRules"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","GalleryRules.ts","ReadFlight.ts","ArtworkRules.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const a=require('node:assert/strict'),g=require('./GalleryRules'),{ConsumerReadFlight,ReadCancel}=require('./ReadFlight'),{artworkIdentity}=require('./ArtworkRules');
const t={item:{id:'movie:1',kind:'movie',title:'M',year:0,watched:false},type:'poster',hints:[],initialUri:''};
const raw=JSON.stringify({id:7,posters:Array.from({length:10000},(_,i)=>({file_path:'/img'+i+'.jpg'}))});
const rows=g.parseGallery(raw,7,'poster');a.equal(rows.length,10000);a.throws(()=>g.parseGallery(raw,8,'poster'));
for(let i=0;i<100;i++){let result=g.galleryRows(t,rows[i],rows,[]);a.equal(result.length,20);a.equal(result[0].url,rows[i].url);a.equal(new Set(result.map(r=>r.url)).size,20);a.equal(g.galleryIndex(result,result[3].url),3);}
const person={...t,item:{...t.item,id:'person:1',kind:'person'},type:'profile'};a.equal(g.galleryRows(person,undefined,rows,[]).length,10000);a.notEqual(g.galleryKey(t),g.galleryKey(person));a.throws(()=>g.galleryKey({...person,type:'poster'}));
a.equal(g.tmdbArtworkUrl('https://image.tmdb.org.evil.test/t/p/original/a.jpg'),'');a.equal(g.tmdbArtworkUrl('https://image.tmdb.org/t/p/original/../x.jpg'),'');a.equal(g.galleryTraktUrl('https://evil.test/a.jpg'),'');
a.notEqual(artworkIdentity('tmdb','poster','movie:1',rows[0].url),artworkIdentity('trakt','poster','movie:1',rows[0].url));
(async()=>{let n=0;const f=new ConsumerReadFlight();await Promise.all(Array.from({length:100},()=>f.run('movie:1:poster',async()=>{n++;return 'ok';},new ReadCancel())));a.equal(n,1);console.log('Gallery: 10k candidates x100 cycles, upstream cap/order, identity/URL isolation, selection restoration and 100 shared reads passed');})().catch(e=>{console.error(e);process.exitCode=1;});
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
repo=(root/"data/GalleryRepository.ets").read_text()
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp)/"gallery.db";db=sqlite3.connect(path)
    db.execute(re.search(r"CREATE TABLE IF NOT EXISTS gallery_candidates\([^']+\)",repo).group(0))
    db.execute("INSERT INTO gallery_candidates VALUES(?,?,?)",("movie:1:poster","[]",1));db.commit();db.close()
    db=sqlite3.connect(path);assert db.execute("SELECT payload FROM gallery_candidates WHERE identity=?",("movie:1:poster",)).fetchone()[0]=="[]";assert db.execute("SELECT payload FROM gallery_candidates WHERE identity=?",("person:1:profile",)).fetchone() is None;db.close()
assert "version!==tmdbCredentialVersion()" in repo and "signal.check()" in repo
print("Gallery candidate cache cold recovery, identity fence and previous artwork decoder regression retained")
