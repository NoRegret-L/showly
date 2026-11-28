import pathlib, shutil, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=pathlib.Path(tmp)
    for source in (root/"model").glob("*.ets"):
        shutil.copyfile(source,work/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","StatisticsOwner.ts"],cwd=work,check=True)
    (work/"test.js").write_text("""
const assert=require('node:assert/strict'),m=require('./StatisticsOwner');
const media=(i,kind='show')=>({id:kind+':'+i,kind,title:'Title '+i,year:2020,watched:true});
const input=(i,kind='show')=>({media:media(i,kind),mine:true,sourceKey:'1',observed:0,meta:{genres:['drama','drama','action'],network:'',release:'',runtime:90},runtimes:[]});
const a=input(1);a.source={media:a.media,episodes:[{episode:{id:1,season:1,number:1,title:'one',firstAired:''},watched:true,watchedAt:0},{episode:{id:2,season:1,number:2,title:'two',firstAired:''},watched:true,watchedAt:0}],recentAt:0,randomOrder:0};a.runtimes=[{id:1,minutes:42}];a.observed=3;
const o=new m.StatisticsOwner();let s=o.update('a',[a,a]);assert.equal(s.titles,1);assert.equal(s.episodes,2);assert.equal(s.minutes,42);assert.equal(s.missing,2);assert.equal(s.genres[0].count,1);
assert.strictEqual(o.update('a',[a]),s);const n=o.computations();let b={...a,runtimes:[...a.runtimes,{id:2,minutes:21}]};s=o.update('a',[b]);assert.equal(s.minutes,63);assert.equal(o.computations(),n+1);assert.equal(s.missing,1);
assert.equal(o.ratings([{id:'show:1',value:9,ratedAt:1}])[0].value,9);assert.equal(o.update('b',[]).titles,0);
for(const size of [393,10000]){const rows=Array.from({length:size},(_,i)=>input(i+1,'movie'));const owner=new m.StatisticsOwner();let old=owner.update('a',rows);assert.equal(old.minutes,size*90);for(let i=0;i<100;i++)assert.strictEqual(owner.update('a',rows),old);assert.equal(owner.computations(),size);const changed=rows.slice();changed[0]={...changed[0],meta:{...changed[0].meta,runtime:100}};const next=owner.update('a',changed);const full=m.completeStatistics('a',changed);assert.equal(next.minutes,full.minutes);assert.deepEqual(next.genres,full.genres);assert.equal(owner.computations(),size+1);assert.equal(owner.update('other',[]).titles,0);}
console.log('Statistics: dedup, exact duration, unknowns, stable snapshots, incremental/full equivalence, 393/10000 rows, 100 cycles and scope reset passed');
""")
    subprocess.run(["node","test.js"],cwd=work,check=True)
