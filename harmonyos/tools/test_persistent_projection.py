#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    (work/"arkui.d.ts").write_text("interface IDataSource { totalCount(): number; getData(index: number): unknown; registerDataChangeListener(l: DataChangeListener): void; unregisterDataChangeListener(l: DataChangeListener): void; } interface DataChangeListener { onDataReloaded(): void; onDataChange(index: number): void; onDataAdd(index: number): void; onDataDelete(index: number): void; }")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ProjectionCompute.ts","LazyRows.ts","arkui.d.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const fs=require('node:fs');
const p=require('./ProjectionCompute.js');
const {LazyRows}=require('./LazyRows.js');
const now=Date.parse('2026-01-10T12:00:00Z'), day=86400000;
const scope=p.persistentProjectionScope('client','account-A',true,true);
const build=(id)=> {
 const media={id:'show:'+id,kind:'show',title:'Show '+id,year:2026,watched:false};
 const episodes=[{id:id*10+1,season:1,number:1,title:'One',firstAired:new Date(now-day).toISOString()},
 {id:id*10+2,season:1,number:2,title:'Two',firstAired:new Date(now+day).toISOString()}];
 const full={media,status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:episodes[0].firstAired,episodes}]};
 if(id%2===0) full.rating=8.5;
 const remote={id:media.id,title:media.title,watchedEpisodes:1,positions:[{season:1,number:1,plays:1,lastWatchedAt:new Date(now-day).toISOString()}],updatedAt:new Date(now).toISOString()};
 return {full,remote,cloudActive:true,localIds:[],decisions:[],timed:[],checkpoints:[],common:[],now};
};
const shows=Array.from({length:393},(_,i)=>build(i+1));
if(process.argv[2]==='write'){
 const rows=new Map();
 for(const input of shows) rows.set(input.full.media.id,p.persistShow(p.showProjectionKey(input),now,p.computeProjection(input)));
 fs.writeFileSync('disk.json',p.encodePersistedProjection(scope,rows));
 console.log('Process 1: 393 computed, serialized read cache');
}else{
 const raw=fs.readFileSync('disk.json','utf8'), disk=p.decodePersistedProjection(raw,scope);
 assert.equal(disk.size,393);
 let hits=0, computed=0;
 const read=(input)=>{const row=p.readPersistedShow(disk.get(input.full.media.id),input,p.showProjectionKey(input));if(row){hits++;return row}computed++;return p.computeProjection(input)};
 for(const input of shows){const old=p.computeProjection(input), value=read(input);assert.deepEqual({...value.source,randomOrder:0},JSON.parse(JSON.stringify({...old.source,randomOrder:0})));assert.equal(value.source.rating,input.full.rating);assert.deepEqual(value.effective,old.effective);assert.deepEqual(value.sections,old.sections)}
 assert.equal(hits,393);assert.equal(computed,0);
 const changed={...shows[0],remote:{...shows[0].remote,positions:[],watchedEpisodes:0}};
 read(changed);shows.slice(1).forEach(read);assert.equal(computed,1);
 const x=shows[0],entry=disk.get(x.full.media.id),key=p.showProjectionKey(x);
 assert.equal(p.readPersistedShow(entry,{...x,now:now+day},key),undefined);
 assert.equal(p.readPersistedShow(entry,{...x,now:now-1},key),undefined);
 assert.equal(p.readPersistedShow({...entry,output:{...entry.output,effective:{...entry.output.effective,ids:[999]}}},x,key),undefined);
 assert.equal(p.readPersistedShow({...entry,output:{...entry.output,effective:{...entry.output.effective,matches:[{id:11,seq:1,watched:true}]}}},x,key),undefined);
 const dirty={...x,decisions:[{episodeId:11,seq:1,watched:true}],timed:[{episodeId:11,seq:1,watched:true,changedAt:now}]};
 const d=p.computeProjection(dirty);assert.equal(d.effective.matches.length,1);
 assert.equal(p.diskProjectionAllowed(dirty),false);
 assert.equal(p.readPersistedShow(p.persistShow(p.showProjectionKey(dirty),now,d),dirty,p.showProjectionKey(dirty)),undefined);
 const ack={...dirty,checkpoints:[{id:11,seq:1,watched:true}]};
 assert.equal(p.diskProjectionAllowed(ack),true);
 const a=p.persistShow(p.showProjectionKey(ack),now,p.computeProjection(ack));
 assert.equal(a.output.effective.matches.length,0);
 assert.equal(p.readPersistedShow(a,ack,p.showProjectionKey(ack)).source.episodes[0].watchedAt,now-day);
 for(const other of [p.persistentProjectionScope('client','account-B',true,true),p.persistentProjectionScope('other','account-A',true,true),p.persistentProjectionScope('client','account-A',true,false),p.persistentProjectionScope('client','',false,true)]) assert.equal(p.decodePersistedProjection(raw,other).size,0);
 assert.equal(p.decodePersistedProjection('{broken',scope).size,0);
 assert.equal(p.decodePersistedProjection(JSON.stringify({...JSON.parse(raw),schema:2}),scope).size,0);
 const rows=new LazyRows(), events=[], listener={onDataReloaded:()=>events.push('reload'),onDataChange:i=>events.push(i),onDataAdd:i=>events.push('add:'+i),onDataDelete:i=>events.push('delete:'+i)};
 rows.registerDataChangeListener(listener);rows.registerDataChangeListener(listener);
 rows.replace(['a','b'],['1','2'],['a','b']);assert.deepEqual(events,['reload']);
 rows.replace(['a','b'],['1','2'],['a','b']);assert.deepEqual(events,['reload']);
 rows.replace(['a','c'],['1','2'],['a','c']);assert.deepEqual(events,['reload',1]);assert.equal(rows.getData(1),'c');
 rows.replace(['c','a'],['2','1'],['c','a']);assert.deepEqual(events,['reload',1,'reload']);
 rows.unregisterDataChangeListener(listener);rows.replace([],[],[]);assert.equal(rows.totalCount(),0);assert.deepEqual(events,['reload',1,'reload']);
 console.log('Process 2: 393 disk hits, 0 recomputations; 1 changed input recomputed; invalid cache, scopes, checkpoint safety and lazy row notifications passed');
}
""",encoding="utf-8")
    for phase in ("write","read"):
        subprocess.run(["node","test.cjs",phase],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
store=(root/"data"/"EpisodeStore.ets").read_text()
projection=(root/"data"/"LibraryProjection.ets").read_text()
cloud=page.split("  private async loadCloud(",1)[1].split("  private async importCloud(",1)[0]
repair=page.split("  private async repairCatalogs(",1)[1].split("  private titleQuickActive(",1)[0]
assert "await readSyncAccount(session)" in cloud and "await readActivity(session)" in cloud
assert "snapshot, account.uuid, clientId, false, force, current" in cloud
assert "if (this.cloudFresh) { this.repairTargets = result.repairTargets; }" in cloud
assert "const full = await fetchFullEpisodeCatalog(media, client)" in repair
assert repair.index("await fetchFullEpisodeCatalog") < repair.index("store.readModelRevision() !== revision") < repair.index("await store.saveObservedSchedule(full)")
assert "store.mark(" not in repair and "saveReadCheckpoints" not in repair
# The batch refactor reads each disk entry once and reuses the validated result.
lib=projection.split("export async function projectLibrary(",1)[1].split("export interface DetailProjection",1)[0]
lookup="const prior = disk.get(row.media.id)"
validate="const validDisk = readPersistedShow(prior, input, key)"
reuse="if (!calculated && validDisk)"
retain="if (validDisk && prior) { nextDisk.set(row.media.id,prior); }"
assert lib.index(lookup) < lib.index(validate) < lib.index(reuse) < lib.index(retain)
assert lib.count("readPersistedShow(") == 1
assert "calculated = validDisk" in lib.split(reuse,1)[1].split("if (calculated)",1)[0]
assert "calculated.effective.complete && diskProjectionAllowed(input)" in lib
assert lib.index("if (diskChanged || nextDisk.size !== disk.size)") < lib.index("await store.saveProjectionCache(diskScope,payload)")
assert "CREATE TABLE IF NOT EXISTS progress_projection_cache" in store
for builder,ds in [("nextShowsView","showRows"),("movieProgressView","movieRowsSource")]:
    region=page.split("  "+builder+"(",1)[1].split("\n  @Builder",1)[0]
    assert "List({ space:" in region and "LazyForEach(this."+ds in region and "ListItem()" in region
assert "this.markNext(row)" in page and "this.markMovieProgress(row.media)" in page
assert "this.cancelCatalogRepair()" in page and "this.showRows.replace([], [], [])" in page
print("Persistent cache, foreground repair and native lazy-list wiring assertions passed")

assert "Refresh({ refreshing: $$this.refreshing })" in page
assert "Refresh({ refreshing: $this.refreshing })" not in page
