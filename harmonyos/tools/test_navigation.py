#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    names=("Media","MediaState","PersonalLibrary","NavigationModel")
    for name in names: shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs",*[n+".ts" for n in names]],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {normalizeMode,progressTabs,collectionRows,collectionGroups,groupEntries,pageGroups,releasedWatchlist}=require('./NavigationModel.js');
const mk=(id,kind,queued,watched,sections=[])=>({media:{id,kind,title:id,year:2025,watched},queued,watched,localEpisodes:-1,cloudEpisodes:kind==='show'&&!queued?2:-1,sections,merged:true});
const show=mk('show:1','show',false,false,['watching']);
const queued=mk('show:2','show',true,false);
const movie=mk('movie:1','movie',true,false);
const seen=mk('movie:2','movie',false,true);
const manual=mk('local:1','manual',false,false);
const rows=[show,queued,movie,seen,manual];
assert.equal(normalizeMode('bad'),'show');
assert.deepEqual(progressTabs('show'),['next','calendar','history']);
assert.deepEqual(progressTabs('movie'),['next','calendar']);
assert.deepEqual(collectionRows(rows,'show','mine'),[show]);
assert.deepEqual(collectionRows(rows,'movie','mine'),[seen]);
assert.deepEqual(collectionRows(rows,'show','queue'),[queued]);
assert.deepEqual(collectionRows(rows,'movie','queue'),[movie]);
assert.deepEqual(collectionRows(rows,'movie','other'),[manual]);
assert.deepEqual(collectionRows(rows,'show','hidden'),[]);
const groups=collectionGroups(rows,'show','mine');
assert.deepEqual(groups.map(g=>g.key),['all']);
assert.deepEqual(pageGroups(groupEntries(groups),1,1).map(g=>g.key),['all']);
assert.deepEqual(collectionGroups(rows,'show','mine','watching')[0].rows,[show]);
assert.equal(collectionGroups(rows,'show','mine','finished').length,0);
assert.equal(groupEntries(groups).length,1);
assert.deepEqual(releasedWatchlist(rows,[{id:'movie:1',released:'2026-01-01'}],'2026-01-01'),[movie]);
assert.deepEqual(releasedWatchlist(rows,[{id:'movie:1',released:'2026-01-02'}],'2026-01-01'),[]);
assert.deepEqual(releasedWatchlist(rows,[],'2026-01-01'),[]);
console.log('Navigation model assertions passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
source=(root/"pages"/"Index.ets").read_text()
assert "@State discoverKind" not in source
assert "@State calendarKind" not in source
assert "this.mediaModeTabs()" in source
assert "discoverRequest(kind,options,this.discoverCollectionSize())" in source
assert "repo.load(clientId,request,force,publish,consumer)" in source
assert "const kind = this.mediaMode;" in source
assert "this.collectionPageGroups()" in source
assert "this.movieProgressView()" in source
assert "this.markMovieProgress(row.media,at)" in source
assert "await this.changeMediaIntent(row.media, 'movie', 'yes')" in source
print("Navigation wiring assertions passed")

assert "this.chooseWatchTime(this.movieMetadataIndex().get(row.media.id)?.released??''" in source
assert "this.chooseWatchTime(row.episode.firstAired" in source
