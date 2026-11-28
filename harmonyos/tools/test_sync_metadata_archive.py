#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    for source in (root/"model").glob("*.ets"):shutil.copyfile(source,w/(source.stem+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ListSyncMerge.ts","CollectionRules.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const a=require('node:assert/strict'),m=require('./ListSyncMerge'),c=require('./CollectionRules');
const local={id:'local:1',name:'local',description:'',createdAt:1,updatedAt:2,remote:false,members:[],unsupported:0};
const remote={...local,id:'trakt:3',name:'remote',remote:true,updatedAt:3};
const base={localId:'local:1',remoteId:3,name:'local',description:''};
for(let i=0;i<100;i++){
 a.equal(m.listMetadataDecision(local,remote),'conflict');
 a.equal(m.listMetadataDecision(local,remote,base),'import');
 a.equal(m.listMetadataDecision({...local,name:'changed'},remote,{...base,name:'remote'}),'export');
 a.equal(m.listMetadataDecision({...local,name:'changed'},remote,base),'conflict');
 a.equal(m.mergeMappedLists({nextId:2,local:[local],remote:[]},[remote],[{localId:'local:1',remoteId:3,pending:''}]).doc.local[0].name,'local');
 const media={id:'show:1',kind:'show',title:'T',year:2020,watched:false};
 const previous=c.emptyCollectionState(),next=c.mergeHiddenArchive(previous,[{media,at:123}]);
 a.equal(next.hidden[0].at,123);a.equal(c.mergeHiddenArchive(next,[{media,at:456}]),next);
}
console.log('100 metadata conflict and additive archive cycles passed');
""")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
lists=(root/"data/CustomListsRepository.ets").read_text()
assert lists.index("'meta:'+JSON.stringify(expected)")<lists.index("await updateListMetadata")
assert "link.pending.startsWith('meta:')" in lists and "this.settleMetadata" in lists
ratings=(root/"data/RatingsRepository.ets").read_text()
assert "stageDeviceRatings" in ratings and "rating_migration" in ratings
page=(root/"pages/Index.ets").read_text()
assert "确认旧评分归属" in page and "await readHiddenArchive" in page
print("Metadata receipt, archive import and explicit migration wiring passed; no live API calls")
