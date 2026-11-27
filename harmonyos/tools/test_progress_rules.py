#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    names=("Media","ShowCatalog","ThreeWay","RemoteObservation","EffectiveState","MediaPresentation","ProgressRules")
    for name in names: shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs",*[n+".ts" for n in names]],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {defaultProgress,selectProgress,progressRows,progressSource,toggleProgressFlag,validProgress,progressSections,progressEntries,progressPage,effectiveProgressFilter}=require('./ProgressRules.js');
const now=Date.parse('2026-01-10T12:00:00Z'), day=86400000;
const media={id:'show:1',kind:'show',title:'The Série',year:2025,watched:false};
const ep=(id,offset,watched=false,watchedAt=0,season=1)=>({episode:{id,season,number:id,title:'Episode '+id,firstAired:offset===null?'':new Date(now+offset*day).toISOString()},watched,watchedAt});
const source={media,episodes:[ep(1,-10,true,now-2*day),ep(2,-9),ep(3,-8,true,now-day),ep(4,-1),ep(5,1),ep(6,null),ep(7,-1,false,0,0)],recentAt:now,rating:8,randomOrder:0.1};
const p=defaultProgress();
assert.equal(p.days,30);
assert.equal(selectProgress(source,p,[],now).episode.id,4);
assert.equal(selectProgress(source,{...p,strategy:'oldest'},[],now).episode.id,2);
assert.equal(selectProgress({...source,episodes:source.episodes.map(x=>x.episode.id===1?{...x,watchedAt:now}:x)},p,[],now).episode.id,2);
assert.equal(selectProgress(source,p,[],now).total,4);
assert.equal(selectProgress(source,{...p,count:'all'},[],now).total,6);
assert.equal(selectProgress(source,p,[],now).fresh,true);
const future={...source,episodes:source.episodes.filter(x=>x.episode.id>=5)};
assert.equal(selectProgress(future,p,[],now).upcoming,true);
assert.equal(selectProgress(future,{...p,days:0},[],now),undefined);
assert.equal(selectProgress({...source,episodes:[ep(1,-1),ep(2,-2,true,now)]},p,[],now),undefined);
assert.equal(selectProgress({...source,episodes:[ep(1,-1,true),ep(2,-1)]},p,[],now).dateUnknown,true);
const pin=toggleProgressFlag([],media.id,'pin');
assert.equal(selectProgress(source,p,pin,now).group,'pinned');
const hold=toggleProgressFlag(pin,media.id,'hold');
assert.equal(selectProgress(source,p,hold,now).group,'hold');
assert.deepEqual(toggleProgressFlag(hold,media.id,'hold'),[]);
assert.equal(selectProgress(source,{...p,newAtTop:true},[],now).group,'new');
assert.equal(progressRows([source],p,[],now,'all','serie').length,1);
assert.equal(progressRows([source],p,[],now,'all','Episode 4').length,1);
assert.equal(progressRows([source],p,[],now,'hold','').length,0);
assert.equal(progressRows([source],p,hold,now,'hold','').length,1);
assert.equal(progressRows([source],p,hold,now,'both','').length,1);
const b={...source,media:{...media,id:'show:2',title:'Alpha'},rating:9,randomOrder:0.2};
assert.equal(progressRows([source,b],{...p,sort:'rating'},[],now,'all','')[0].media.id,'show:2');
assert.equal(progressRows([source,b],{...p,sort:'title',descending:false},[],now,'all','')[0].media.id,'show:2');
assert.equal(validProgress({...p,days:-1}),false);
const full={media,status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:source.episodes[0].episode.firstAired,episodes:source.episodes.slice(0,6).map(x=>x.episode)}]};
const remote={id:media.id,title:media.title,watchedEpisodes:1,positions:[{season:1,number:1,plays:1,lastWatchedAt:new Date(now-day).toISOString()}],updatedAt:new Date(now).toISOString()};
const observed=progressSource(full,[1],remote,[{episodeId:1,seq:4,watched:true,changedAt:now}],new Map([[1,{id:1,seq:4,watched:true}]]),true);
assert.equal(observed.episodes[0].watchedAt,now-day);
assert.equal(progressSource(full,[1],undefined,[],new Map(),false).episodes[0].watchedAt,0);
const heldSource={...source,media:{...media,id:'show:3'}};
const futureSource={...future,media:{...media,id:'show:4'}};
const pinnedSource={...source,media:{...media,id:'show:5'}};
const flags=[{id:'show:3',held:true,pinned:false},{id:'show:5',held:false,pinned:true}];
const mixed=progressRows([source,heldSource,futureSource,pinnedSource],p,flags,now,'all','');
assert.deepEqual(mixed.map(x=>x.group),['pinned','aired','upcoming','hold']);
const sections=progressSections(mixed,p);
assert.deepEqual(progressEntries(sections).map(x=>x.row?x.row.media.id:x.key),['show:5','show:1','header:upcoming','show:4','header:hold','show:3']);
assert.deepEqual(progressEntries(progressSections(mixed,{...p,holdCollapsed:true})).map(x=>x.row?x.row.media.id:x.key),['show:5','show:1','header:upcoming','show:4','header:hold']);
assert.equal(progressPage(progressEntries(sections),2,3)[0].key,'header:upcoming');
assert.deepEqual(progressRows([source,heldSource,futureSource,pinnedSource],p,flags,now,'both','').map(x=>x.group),['upcoming','hold']);
assert.equal(effectiveProgressFilter({...p,days:0,filter:'both'}),'hold');
assert.deepEqual(toggleProgressFlag([], 'show:999','hold'),[{id:'show:999',pinned:false,held:true}]);
console.log('Upstream progress behavior fixtures passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
source=(root/"pages"/"Index.ets").read_text()
mark=source.split("  private async markNext(",1)[1].split("  private invalidateMovieCalendar",1)[0]
assert "await store.mark(" in mark and "await store.boundAccount()" in mark
assert "row.upcoming" in mark and "eligibleCatalog(" in mark and "projectDetail(" in mark
assert "syncSelectedMedia(" not in mark and "uploadBatch(" not in mark
assert "progressRows(sources" in source
print("Progress wiring assertions passed")
