#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for path in (root/"model").glob("*.ets"):
        shutil.copyfile(path,work/(path.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","CollectionRules.ts","RemoteObservation.ts","TitleQuickState.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const c=require('./CollectionRules.js');
const {titleEdit}=require('./TitleQuickState.js');
const {buildPersonalLibrary}=require('./PersonalLibrary.js');
const {validateObservation}=require('./RemoteObservation.js');
const now=Date.parse('2026-01-10T12:00:00Z');
const mk=(id,kind,title,year,queued,watched,sections=[])=>({media:{id:kind+':'+id,kind,title,year,watched},queued,watched,localEpisodes:kind==='show'&&!queued?1:-1,cloudEpisodes:-1,sections,merged:true});
const a=mk(1,'show','The Zebra',2024,false,false,['watching']);
const b=mk(2,'show','Alpha',2025,false,false,['finished']);
const q=mk(3,'show','Beta',2026,true,false);
const m=mk(1,'movie','The Movie',2026,true,false);
const n=mk(2,'movie','Other',2025,false,true);
const unknown=mk(4,'movie','Unknown',2027,true,false);
const all=[a,b,q,m,n,unknown];
const ids=rows=>rows.map(x=>x.media.id);
let state=c.emptyCollectionState();
assert.deepEqual(c.defaultCollection(),{sort:'added',descending:true,genres:[],networks:[],upcoming:'all'});
assert.equal(c.validCollectionState(state),true);
assert.deepEqual(ids(c.collectionMembers(all,state,'show','mine','all')),['show:1','show:2']);
assert.deepEqual(ids(c.collectionMembers(all,state,'show','mine','watching')),['show:1']);
assert.deepEqual(ids(c.collectionMembers(all,state,'show','queue','all')),['show:3']);
const hidden=c.hideMedia(state,a.media,true,now);
assert.deepEqual(ids(c.collectionMembers(all,hidden,'show','mine','all')),['show:2']);
assert.deepEqual(ids(c.collectionMembers(all,hidden,'show','hidden','all')),['show:1']);
assert.deepEqual(ids(c.collectionMembers(all,hidden,'movie','queue','all')),['movie:1','movie:4']);
assert.deepEqual(c.hideMedia(hidden,a.media,true,now+1),hidden);
assert.deepEqual(c.hideMedia(hidden,a.media,false,now+1),state);
assert.equal(all[0].localEpisodes,1);
const other=c.hideMedia(hidden,{id:'show:9',kind:'show',title:'External',year:2026,watched:false},true,now+2);
assert.deepEqual(ids(c.collectionMembers(all,other,'show','hidden','all')),['show:1','show:9']);
assert.equal(c.validCollectionState(JSON.parse(JSON.stringify(other))),true);
assert.equal(c.validCollectionState({...other,hidden:[other.hidden[0],other.hidden[0]]}),false);
const ca=(row,genres,network,release,added,rating,extra={})=>({row,translation:'',meta:{genres,network,release,rating,runtime:90},added,randomOrder:row.media.year,...extra});
const x=ca(a,['drama'],'Netflix','2024-01-01',10,8,{recent:100,userRating:5,translation:'斑马'});
const y=ca(b,['comedy','drama'],'HBO','2025-01-01',20,7,{recent:200,userRating:9});
const z=ca(q,['comedy'],'Netflix','2026-01-11T12:00:00Z',undefined,9);
const opts=c.defaultCollection();
const out=(rows,options={},section='mine',query='')=>ids(c.projectCollection(rows,{...opts,...options},section,query,now).map(x=>x.row));
assert.deepEqual(out([x,y,z]),['show:2','show:1','show:3']);
assert.deepEqual(out([x,y,z],{sort:'added',descending:false}),['show:1','show:2','show:3']);
assert.deepEqual(out([x,y,z],{genres:['drama'],networks:['Netflix']}),['show:1']);
assert.deepEqual(out([x,y,z],{genres:['drama','comedy'],networks:['Netflix']}),['show:1','show:3']);
assert.deepEqual(out([x,y,z],{sort:'rating'}),['show:3','show:1','show:2']);
assert.deepEqual(out([x,y,z],{sort:'userRating'}),['show:2','show:1','show:3']);
assert.deepEqual(out([x,y,z],{sort:'userRating',descending:false}),['show:1','show:2','show:3']);
assert.deepEqual(out([x,y,z],{sort:'recent'}),['show:2','show:1','show:3']);
assert.deepEqual(out([x,y,z],{sort:'newest'}),['show:3','show:2','show:1']);
assert.deepEqual(out([x,y,z],{sort:'random'}),['show:1','show:2','show:3']);
assert.deepEqual(out([x,{...z,meta:undefined}],{genres:['drama']}),['show:1']);
assert.deepEqual(out([x,y,z],{},'mine','斑马'),['show:1']);
assert.deepEqual(out([x,y,z],{},'mine','zebra'),['show:1']);
assert.deepEqual(out([x,y,z],{upcoming:'upcoming'},'queue'),['show:3']);
assert.deepEqual(out([x,y,z],{upcoming:'released'},'queue'),['show:2','show:1']);
const same=ca(m,['drama'],'','2026-01-10',30,8);
const past=ca(n,['drama'],'','',40,7);
const future=ca(unknown,[],'','',undefined,6);
assert.deepEqual(out([same,past,future],{upcoming:'released'},'queue'),['movie:2']);
assert.deepEqual(out([same,past,future],{upcoming:'upcoming'},'queue'),['movie:4']);
assert.deepEqual(out([same,past,future],{networks:['Netflix']},'queue'),['movie:2','movie:1','movie:4']);
assert.deepEqual(ids(c.recentCollection([x,y,z],4)),['show:2','show:1']);
const rec={media:m.media,movieState:'unknown',watchlistState:'yes'};
const before=buildPersonalLibrary([rec],[],[],[],[]);
const edit=titleEdit([rec],m.media,'movie','yes');
const after=buildPersonalLibrary(edit.records,[],[],[],[]);
state=c.recordCollectionDate(state,m.media.id,'queue',true,now-100);
const dated=c.transitionCollectionDates(state,before,after,[m.media.id,m.media.id],now);
assert.deepEqual(dated.queue,[]);
assert.deepEqual(dated.mine,[{id:m.media.id,at:now}]);
assert.equal(c.transitionCollectionDates(dated,after,after,[m.media.id],now+10),dated);
assert.equal(edit.records[0].movieState,'yes');assert.equal(edit.records[0].watchlistState,'no');
const snapshot={generation:1,activity:'revision',observedAt:now,watchlist:[m.media],watchedMovies:[],shows:[],moviePlays:[],queueDates:[{id:m.media.id,at:now}]};
validateObservation(snapshot);
assert.throws(()=>validateObservation({...snapshot,queueDates:[{id:'movie:99',at:now}]}));
assert.throws(()=>validateObservation({...snapshot,queueDates:[{id:m.media.id,at:now},{id:m.media.id,at:now}]}));
console.log('Collection member, hidden isolation, real transition dates, filters, sort, release boundaries and observation fixtures passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages"/"Index.ets").read_text()
settings=(root/"data"/"ClientSettings.ets").read_text()
library=(root/"data"/"TraktLibrary.ets").read_text()
assert "LazyForEach(this.collectionRowsSource" in page
assert "this.collectionRowsSource.replace([], [], [])" in page
assert "this.collectionScope === this.currentProgressScope()" in page
assert "collectionMembers(this.personalLibrary()" in page
assert "if (!source || this.isHidden(source.media))" in page
assert "const items = this.visibleDiscover()" in page and "LazyForEach(this.discoverRows" in page
assert "this.isHidden(row.media) || !movie" in page
assert "await this.recordTitleDates(dateScope, beforeDates, changes)" in page
assert "transitionCollectionDates(this.collectionState" in page
assert "this.settings.loadCollectionOptions(this.mediaMode,this.collectionFilter)" in page
assert "'collection_state:' + scope" in settings
assert "'collection_options:' + kind + ':' + section" in settings
assert "Date.parse(row.listed_at" in library
hidden=page.split("  private async editHidden(",1)[1].split("  private async recordTitleDates(",1)[0]
assert "await settings.saveCollectionState(scope, next)" in hidden
assert "await settings.saveProgressFlags(scope, flags)" in hidden
assert "persistMedia(" not in hidden and "titleEdit(" not in hidden and "store.mark(" not in hidden
assert "Refresh({ refreshing: $$this.refreshing })" in page
print("Collection lazy list, account scope, hidden presentation-only and timestamp wiring assertions passed")
