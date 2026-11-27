#!/usr/bin/env python3
"""Committed library deltas and stable display membership preserve full projection semantics."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs",
        "MediaInputVersion.ts","PersonalLibrary.ts","StableDisplayOrder.ts","SearchRules.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {MediaInputVersion}=require('./MediaInputVersion');
const {buildPersonalLibrary,PersonalLibraryIndex}=require('./PersonalLibrary');
const {StableDisplayOrder}=require('./StableDisplayOrder');
const {SearchCandidateTitles}=require('./SearchRules');
const media=(id,kind='movie',watched=false)=>({id,kind,title:'Title '+id,year:2026,watched});
const makeRecord=(i)=>({media:media('movie:'+i,'movie',false),movieState:'unknown',watchlistState:i%3===0?'yes':'unknown'});
const makeEvidence=(id,watchedEpisodes,merged)=>({media:media(id,'show'),watchedEpisodes,merged:merged,sections:['watching']});
for(const size of [393,10000]){
  let records=Array.from({length:size},(_,i)=>makeRecord(i+1));
  const cloudMovies=[media('movie:2'),media('movie:19'),media('movie:10001')];
  const cloudQueue=[media('movie:3'),media('movie:20'),media('movie:10002')];
  const cloudShows=[makeEvidence('show:1',2,true),makeEvidence('show:2',4,true)];
  const evidence=[makeEvidence('show:1',2,true),makeEvidence('show:2',4,true),makeEvidence('show:3',0,false)];
  const localShows=evidence.filter(x=>x.merged===true),cloud={account:'A',generation:1};
  const input=new MediaInputVersion();assert(input.replace(records));assert(input.canApplyIncremental());
  const index=new PersonalLibraryIndex(),full=()=>buildPersonalLibrary(records,cloudMovies,cloudQueue,cloudShows,localShows);
  index.seed(records,cloudMovies,cloudQueue,cloudShows,localShows,cloud,evidence,true,full());
  input.acknowledgeLibrary(input.version());
  for(let j=0;j<100;j++){
    const beforeId=records[(j*29+records.length-1)%records.length].media.id,oldUnchanged=index.get(beforeId);
    const next=records.slice();
    if(j%5===0){next.push({media:media('movie:added:'+size+':'+j),movieState:'unknown',watchlistState:'yes'});}
    else if(j%5===1&&next.length>4){next.splice((j*13)%next.length,1);}
    else if(next.length){
      const at=(j*17)%next.length,prior=next[at],watched=!prior.media.watched;
      next[at]={media:{...prior.media,watched:watched},movieState:watched?'yes':'no',
        watchlistState:prior.watchlistState==='yes'?'no':'yes'};
    }
    assert(input.replace(next));assert(input.canApplyIncremental());assert(!input.libraryOrderChanged());
    const changes=input.libraryChangedIds();
    const delta=index.updateRecords(input.recordsById(),changes,input.canApplyIncremental(),cloud,evidence,true);
    assert.notEqual(delta,undefined);
    records=next;assert.deepEqual(index.rowsView(),full());
    if(changes.indexOf(beforeId)<0){assert.equal(index.get(beforeId),oldUnchanged);}
    const version=input.version();input.acknowledgeLibrary(version);assert.deepEqual(input.libraryChangedIds(),[]);
  }
  const reordered=records.slice().reverse();assert(input.replace(reordered));assert.equal(input.canApplyIncremental(),false);
  assert(input.libraryOrderChanged());
  assert.equal(index.updateRecords(input.recordsById(),input.libraryChangedIds(),input.canApplyIncremental(),cloud,evidence,true),undefined);
  assert.deepEqual(index.rowsView(),full());
}
const row=(id)=>({media:{id:id,kind:'movie',title:id,year:2026,watched:false},localRecord:undefined,queued:false,watched:false,localEpisodes:-1,cloudEpisodes:-1});
const orderOf=new Map([['a',{segment:0,position:0}],['b',{segment:0,position:1}],['c',{segment:0,position:2}],['d',{segment:0,position:3}]]);
const compare=(a,b)=>a.sort-b.sort,eligible=()=>true,source=[{row:row('a'),sort:2},{row:row('b'),sort:1},{row:row('c'),sort:2}];
const full=()=>source.slice().sort((a,b)=>compare(a,b)||orderOf.get(a.row.media.id).position-orderOf.get(b.row.media.id).position).map(x=>x.row);
const display=new StableDisplayOrder(x=>x.row);
display.seed('s0',0,1000,source,full(),'basis',id=>orderOf.get(id));
let changed={...source[1],row:{...source[1].row,watched:true}};
source[1]=changed;
let delta=display.applyChanges('s0','s1','basis',1,1000,[{id:'b',item:changed,ordinal:orderOf.get('b')}],eligible,compare);
assert(delta);assert.equal(delta.structural,false);assert.equal(delta.patches[0].kind,'update');assert.deepEqual(delta.rows,full());
const added={row:row('d'),sort:2};
source.push(added);
delta=display.applyChanges('s1','s2','basis',2,1000,[{id:'d',item:added,ordinal:orderOf.get('d')}],eligible,compare);
assert(delta);assert(delta.structural);assert.deepEqual(delta.rows,full());
source.splice(0,1);
delta=display.applyChanges('s2','s3','basis',3,1000,[{id:'a'}],eligible,compare);
assert(delta);assert(delta.structural);assert.deepEqual(delta.rows,full());
const moved={...source[1],sort:0,row:{...source[1].row,watched:false}};
source[1]=moved;
delta=display.applyChanges('s3','s4','basis',4,1000,[{id:'c',item:moved,ordinal:orderOf.get('c')}],eligible,compare);
assert(delta);assert(delta.structural);assert.deepEqual(delta.rows,full());
console.log('393/10k personal-library: 100 commit-scoped add/remove/state updates, cloud fallback, stable identity and reorder fallback passed');
const candidates=new SearchCandidateTitles();
candidates.seed([{media:row('show:1').media,votes:0,localized:''}]);
const addedSearch={media:row('movie:1').media,votes:0,localized:''};candidates.upsert(addedSearch);
assert.equal(candidates.get('movie:1'),addedSearch);candidates.remove('movie:1');assert.equal(candidates.get('movie:1'),undefined);
console.log('StableDisplayOrder direct update/insert/remove/move and ID-scoped search upsert/remove passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
assert "this.personalLibraryIndex.updateRecords(" in page
assert "this.personalLibraryIndex.rowsView()" in page
assert "this.mediaInput.libraryChangedIds()" in page
assert "order.applyChanges(before,after,basis" in page
assert "[this.movieTitleOrder,pending.movieQueryScope" in page and "[this.movieAllTitleOrder,pending.movieAllScope" in page
assert "this.collectionTitleOrder.applyChanges(" in page
print("Production incremental member and sort wiring assertions passed")
