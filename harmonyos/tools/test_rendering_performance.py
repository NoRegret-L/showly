#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    (work/"reference.ts").write_text("import { ProgressEpisode, ProgressSource, ProgressPreferences, ProgressFlag, ProgressRow } from './ProgressRules';\nconst DAY=86400000; const NEW_DURATION=3*DAY;\nfunction position(a: ProgressEpisode, b: ProgressEpisode): number {\n  return a.episode.season - b.episode.season || a.episode.number - b.episode.number;\n}\nexport function referenceSelect(source: ProgressSource, prefs: ProgressPreferences, flags: ProgressFlag[],\n  now: number): ProgressRow | undefined {\n  const ordered = source.episodes.filter((item: ProgressEpisode) => item.episode.season > 0).sort(position);\n  const watched = ordered.filter((item: ProgressEpisode) => item.watched);\n  const dated = watched.filter((item: ProgressEpisode) => item.watchedAt > 0)\n    .sort((a: ProgressEpisode, b: ProgressEpisode) => b.watchedAt - a.watchedAt || position(a,b));\n  const last = prefs.strategy === 'last' ? dated[0] : undefined;\n  const limit = now + prefs.days * DAY;\n  const next = ordered.find((item: ProgressEpisode) => !item.watched && !!item.episode.firstAired &&\n    Number.isFinite(Date.parse(item.episode.firstAired)) && Date.parse(item.episode.firstAired) <= limit &&\n    (!last || position(item, last) > 0));\n  if (!next) { return undefined; }\n  const aired = Date.parse(next.episode.firstAired);\n  const upcoming = aired > now;\n  if (upcoming && !prefs.days) { return undefined; }\n  // Upstream SQL counts first_aired < now, while the candidate limit is <=.\n  const counted = prefs.count === 'all' ? ordered : ordered.filter((item: ProgressEpisode) =>\n    !!item.episode.firstAired && Date.parse(item.episode.firstAired) < now);\n  const flag = flags.find((item: ProgressFlag) => item.id === source.media.id);\n  const pinned = flag?.pinned ?? false;\n  const held = flag?.held ?? false;\n  const fresh = aired < now && now - aired < NEW_DURATION;\n  const group = pinned ? 'pinned' : held ? 'hold' : prefs.newAtTop && fresh ? 'new' : upcoming ? 'upcoming' : 'aired';\n  return { media: source.media, episode: next.episode, total: counted.length,\n    completed: counted.filter((item: ProgressEpisode) => item.watched).length, upcoming: upcoming,\n    fresh: fresh, pinned: pinned, held: held, group: group, recentAt: source.recentAt, rating: source.rating,\n    randomOrder: source.randomOrder, dateUnknown: prefs.strategy === 'last' && watched.length > dated.length,\n    localizedTitle: source.localizedTitle, localizedEpisode: source.episodeNames?.get(next.episode.id) };\n}\n",encoding="utf-8")
    (work/"arkui.d.ts").write_text("interface IDataSource { totalCount(): number; getData(index:number): unknown; registerDataChangeListener(l:DataChangeListener): void; unregisterDataChangeListener(l:DataChangeListener): void; } interface DataChangeListener { onDataReloaded():void; onDataChange(i:number):void; onDataAdd(i:number):void; onDataDelete(i:number):void; onDataMove(from:number,to:number):void; }")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","arkui.d.ts","reference.ts","ProgressRules.ts","ViewportTasks.ts","LazyRows.ts","ReadModelCache.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {referenceSelect}=require('./reference.js');
const {selectProgress,sortProgressCandidates,progressRows,defaultProgress}=require('./ProgressRules.js');
const {RevisionMemo,progressExpiry}=require('./ReadModelCache.js');
const {ViewportTasks,addPresentationTask}=require('./ViewportTasks.js');
const {LazyRows}=require('./LazyRows.js');
const now=Date.parse('2026-01-10T12:00:00Z');
const media={id:'show:1',kind:'show',title:'Series',year:2025,watched:false};
const episode=(id,season,number,air,watched,watchedAt)=>({episode:{id,season,number,firstAired:air,title:'Episode '+id},watched,watchedAt});
const dates=['',new Date(now-1).toISOString(),new Date(now).toISOString(),new Date(now+1).toISOString(),new Date(now+86400000).toISOString(),'invalid'];
let seed=17;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;};
let comparisons=0;
for(let n=0;n<393;n++){
 const episodes=Array.from({length:24},(_,i)=>episode(i+1,i%6,i%4+1,dates[rand()%dates.length],(rand()>>>8)%2===0,[0,now-1,now][(rand()>>>8)%3]));
 // deterministic shuffling; equal timestamp/position ties remain stable
 for(let i=episodes.length-1;i>0;i--){const j=rand()%(i+1);[episodes[i],episodes[j]]=[episodes[j],episodes[i]];}
 const source={media:{...media,id:'show:'+(n+1)},episodes,recentAt:now,randomOrder:n,localizedTitle:'剧集',episodeNames:new Map([[1,'第一集']])};
 for(const strategy of ['last','oldest'])for(const count of ['aired','all'])for(const days of [0,1,30])for(const flags of [[],[{id:source.media.id,pinned:true,held:false}],[{id:source.media.id,pinned:false,held:true}]]){
  const prefs={...defaultProgress(),strategy,count,days,newAtTop:n%2===0};
  assert.deepEqual(selectProgress(source,prefs,flags,now),referenceSelect(source,prefs,flags,now));comparisons++;
 }
}
const source={media,episodes:[episode(1,1,1,dates[1],false,0),episode(2,1,2,dates[2],true,now)],recentAt:now,randomOrder:1};
const prefs={...defaultProgress(),strategy:'oldest'};
const base=[selectProgress(source,prefs,[],now)];
assert.deepEqual(sortProgressCandidates(base,prefs,'all','episode'),progressRows([source],prefs,[],now,'all','episode'));
const memo=new RevisionMemo();let selections=0;
const get=(business,clock)=>{let rows=memo.get(business,clock);if(!rows){selections++;rows=[selectProgress(source,prefs,[],clock)];memo.put(business,rows,clock,progressExpiry([source],prefs,clock));}return rows;};
const initial=get('account-A:revision1',now);
for(let i=0;i<393;i++)assert.equal(get('account-A:revision1',now),initial);
assert.equal(selections,1);
get('account-A:revision2',now);assert.equal(selections,2);
get('account-B:revision2',now);assert.equal(selections,3);
get('account-B:revision2',now+1);assert.equal(selections,4);
const vp=new ViewportTasks(), tasks=new Map();
const other={...media,id:'show:2'};
assert.equal(vp.has(media,1),false);
assert.equal(vp.update(media,1,['url'],true,'episode1'),true);
assert.equal(vp.update(media,1,['url'],true,'episode1'),false);
assert.equal(vp.update(media,1,[],true,'episode2'),true);
assert.equal(vp.update(media,1,[],false,'episode1'),true);
assert.equal(vp.has(media,1),true);
assert.equal(vp.has(other,1),false);
for(const item of [media,other])if(vp.has(item,1))addPresentationTask(tasks,item,true,1,[]);
assert.equal(tasks.size,1);
addPresentationTask(tasks,media,false,1,['hint']);
assert.equal(tasks.size,1);assert.equal(tasks.values().next().value.artwork,true);
assert.deepEqual(tasks.values().next().value.posterUrls,['hint']);
vp.update(media,1,[],false,'episode2');assert.equal(vp.has(media,1),false);
vp.update(other,1,[],true);vp.clear();assert.equal(vp.has(other,1),false);
const data=new LazyRows(), events=[];
data.registerDataChangeListener({onDataReloaded:()=>events.push('reload'),onDataChange:i=>events.push('change:'+i),onDataAdd:i=>events.push('add:'+i),onDataDelete:i=>events.push('delete:'+i),onDataMove:(a,b)=>events.push('move:'+a+':'+b)});
data.replace(['a','b'],['a','b'],['1','1']);
data.replace(['a','b'],['a','b'],['1','1']);
data.replace(['a','B'],['a','b'],['1','2']);
data.replace(['a','x','B'],['a','x','b'],['1','1','2']);
data.replace(['x','B'],['x','b'],['1','2']);
data.replace(['B','x'],['b','x'],['2','1']);
assert.deepEqual(events,['reload','change:1','add:1','delete:0','move:1:0']);
assert.equal(data.getData(0),'B');
console.log('Rendering model: '+comparisons+' old/new candidate comparisons; 393 display-only memo reads -> 0 additional selections; visible dedup, account/clock invalidation and list delta passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
publish=page.split("  private publishPresentation()",1)[1].split("  private displayTitle(",1)[0]
assert "this.listRevision++" not in publish
assert "this.titleSortRevision++" in publish and "this.episodeSearchRevision++" in publish and "this.collectionMetaRevision++" in publish
assert "this.candidateMemo.get(businessKey,now)" in page
assert "this.candidateMemo.put(businessKey,candidates,now,this.candidateExpiry)" in page
assert "this.candidateRuns++" in page
assert "const tasks = new Map<string,PresentationTask>()" in page
assert "if (artwork && !this.selectedMedia && !this.viewport.has(item,season))" in page
assert "if (task.artwork && !this.selectedMedia && !this.viewport.has(task.media,task.season))" in page
for name in ("discoverRows","searchRows","calendarRows","movieCalendarRows","showRows","movieRowsSource","collectionRowsSource"):
    assert "LazyForEach(this."+name in page
assert page.count(".onVisibleAreaChange([0]")>=7
assert "JSON.stringify(entry)" not in page and "JSON.stringify(row) + ':'" not in page
assert "Refresh({ refreshing: $$this.refreshing })" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Rendering virtualization, viewport dispatch, business/display separation and sync guard wiring passed")
