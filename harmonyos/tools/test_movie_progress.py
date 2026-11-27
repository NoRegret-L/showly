#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","MovieProgressRules.ts","TitleQuickState.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const p=require('./MovieProgressRules.js');
const {titleEdit}=require('./TitleQuickState.js');
const {validFlags,toggleProgressFlag}=require('./ProgressRules.js');
const {buildPersonalLibrary}=require('./PersonalLibrary.js');
const mk=(id,title,date,year=2026,extra={})=>({row:{media:{id:'movie:'+id,kind:'movie',title,year,watched:false},queued:true,watched:false,localEpisodes:-1,cloudEpisodes:-1},metadata:{id:'movie:'+id,released:date,year,...extra},translation:''});
const a=mk(1,'The Zebra','2026-01-01',2026,{rating:8,runtime:100,addedAt:10,userRating:4});
const b=mk(2,'Alpha','',2027,{rating:7,runtime:80,addedAt:20,userRating:9});
const c=mk(3,'Beta','2026-01-02');
const d=mk(4,'No date','',0);
const e=mk(5,'Watched','2025-01-01');e.row.watched=true;
const f=mk(6,'Unknown rating','2025-01-01');
const g=mk(7,'Not queued','2025-01-01');g.row.queued=false;
const today='2026-01-01', opts=p.defaultMovieProgress();
const ids=(sources,sort='added',descending=true,flags=[],query='')=>p.movieProgressRows(sources,flags,{sort,descending},today,query,7).map(x=>x.media.id);
const all=[a,b,c,d,e,f,g];
assert.deepEqual(opts,{sort:'added',descending:true});
assert.equal(p.validMovieProgress(opts),true);
assert.deepEqual(ids(all),['movie:2','movie:1','movie:6']);
assert.deepEqual(ids(all,'added',false),['movie:1','movie:2','movie:6']);
assert.deepEqual(ids(all,'title',false),['movie:2','movie:6','movie:1']);
assert.deepEqual(ids(all,'title',true),['movie:1','movie:6','movie:2']);
assert.deepEqual(ids(all,'runtime',false),['movie:2','movie:1','movie:6']);
assert.deepEqual(ids(all,'runtime',true),['movie:1','movie:2','movie:6']);
assert.deepEqual(ids(all,'rating',false),['movie:2','movie:1','movie:6']);
assert.deepEqual(ids(all,'rating',true),['movie:1','movie:2','movie:6']);
assert.deepEqual(ids(all,'userRating',false),['movie:1','movie:2','movie:6']);
assert.deepEqual(ids(all,'userRating',true),['movie:2','movie:1','movie:6']);
assert.deepEqual(ids(all,'newest',false),['movie:2','movie:6','movie:1']);
assert.deepEqual(ids(all,'newest',true),['movie:1','movie:6','movie:2']);
assert.deepEqual(ids(all,'random'),ids(all,'random'));
assert.equal(new Set(ids(all,'random')).size,3);
a.translation='斑马';
assert.deepEqual(ids(all,'title',false,[],'斑马'),['movie:1']);
assert.deepEqual(ids(all,'title',false,[],'zebra'),['movie:1']);
const flags=toggleProgressFlag([],a.row.media.id,'pin');
assert.equal(validFlags(flags),true);
assert.equal(validFlags([{id:'movie:1',pinned:false,held:true}]),false);
assert.deepEqual(toggleProgressFlag(flags,a.row.media.id,'hold'),flags);
assert.deepEqual(ids(all,'added',true,flags),['movie:1','movie:2','movie:6']);
const mixed=toggleProgressFlag(flags,'show:1','hold');
assert.equal(validFlags(mixed),true);
const records=[{media:a.row.media,movieState:'no',watchlistState:'yes'},{media:b.row.media,movieState:'no',watchlistState:'yes'}];
const edit=titleEdit(records,a.row.media,'movie','yes');
assert.equal(edit.records[0].movieState,'yes');
assert.equal(edit.records[0].watchlistState,'no');
assert.deepEqual(edit.records[1],records[1]);
assert.deepEqual(edit.changes.map(x=>[x.domain,x.value]),[['movie','yes'],['watchlist','no']]);
assert.deepEqual(p.clearMoviePin(flags,a.row.media.id),[]);
assert.deepEqual(p.clearMoviePin(mixed,a.row.media.id),[{id:'show:1',pinned:false,held:true}]);
const projected=buildPersonalLibrary(edit.records,[],[],[],[]);
assert.equal(p.eligibleMovie({...a,row:projected[0]},today),false);
assert.equal(p.eligibleMovie({...b,row:projected[1]},today),true);
console.log('Movie progress candidate, sorter, pin and watched transition fixtures passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
source=(root/"pages"/"Index.ets").read_text()
# Both display and explicit mark validation use the same movie rules. The
# background result may enter the memo only after route/account/key checks.
movie_rows=source.split("  private movieProgressRows(",1)[1].split("  private async runMovieSort(",1)[0]
worker=source.split("  private async runMovieSort(",1)[1].split("  private async setMovieProgressSort(",1)[0]
guard=movie_rows.index("if (!this.movieCalendarCurrent()) { return []; }")
hit=movie_rows.index("memo.get(key,now)")
hit_return=movie_rows.index("if (cached) { return cached; }")
compute=movie_rows.index("const rows = projectMovieProgress(sources,flags,this.movieProgressOptions,utc,query,this.movieRandomSeed);")
cache=movie_rows.index("memo.put(key,rows,now,expiry);")
result=movie_rows.index("return rows;")
assert guard < hit < hit_return < compute < cache < result
assert "this.runMovieSort(input,key,now,expiry)" in movie_rows
assert worker.index("await movieDisplay(input,this.sortJobs.consumer(slot,token))") < worker.index("key !== this.movieSortKey(input.query,input.utc)") < worker.index("memo.put(key,rows,now,expiry)")
assert "this.sortJobs.current(slot,token)" in worker and "!this.movieCalendarCurrent()" in worker
assert "this.movieSortKey(query,utc)" in movie_rows and "this.currentProgressScope(),this.activeCloud()?.generation" in source
assert "includeBusiness ? this.displayRevisions.movie : 0" in source
assert "includeBusiness ? this.libraryRevision : 0" in source
assert "this.movieProgressRows('',true).find(" in source
assert "this.markMovieProgress(row.media)" in source
assert "await this.changeMediaIntent(row.media, 'movie', 'yes')" in source
assert "await this.clearWatchedMoviePin(item, pinScope)" in source
assert "await settings.saveMovieProgress(options)" in source
print("Movie progress wiring assertions passed")
