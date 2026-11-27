#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    shutil.copyfile(root/"model/ScrollAnchor.ets",work/"ScrollAnchor.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ScrollAnchor.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),{captureAnchor,resolveAnchor,ScrollAnchors}=require('./ScrollAnchor');
const rows=ids=>({totalCount:()=>ids.length,idAt:i=>ids[i]??'',indexOfId:id=>ids.indexOf(id)});
const before=rows(['a','b','c','d']),a=captureAnchor('A:discover',before,3,19.5);
assert.deepEqual(a,{context:'A:discover',id:'c',index:3,offset:19.5});
assert.equal(resolveAnchor(a,'A:discover',rows([])),undefined);
assert.equal(resolveAnchor(a,'B:discover',before),undefined);
assert.deepEqual(resolveAnchor(a,'A:discover',rows(['x','a','b','c'])),{index:4,offset:19.5});
assert.deepEqual(resolveAnchor(a,'A:discover',rows(['a','b'])),{index:2,offset:19.5});
assert.deepEqual(resolveAnchor(captureAnchor('A',before,0,12),'A',rows([])),{index:0,offset:12});
const manager=new ScrollAnchors();
for(let i=0;i<100;i++){
 manager.save('discover',a);assert.equal(manager.pending('discover','A:discover'),a);
 assert.equal(manager.pending('search','A:search'),undefined);
 manager.consume('discover',a);assert.equal(manager.pending('discover','A:discover'),undefined);
 manager.save('discover',a);assert.equal(manager.pending('discover','B:discover'),undefined);
}
manager.save('discover',a);manager.clear();assert.equal(manager.pending('discover','A:discover'),undefined);
console.log('100 navigation cycles, stable identity, offset, empty rebuild, removed item and account isolation passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
page=(root/"pages/Index.ets").read_text()
for slot in ("discover","search","show","movie","calendar","movieCalendar","library"):
    assert "this.onListScroll('"+slot+"',start)" in page
    assert "this.restoreScroll('"+slot+"')" in page
assert "if (!this.selectedMedia) { this.rememberScroll(); }" in page
assert "this.getUIContext().postFrameCallback" in page and "scroller.scrollToIndex(target.index,false,ScrollAlign.START" in page
assert "this.scrollAnchors.clear()" in page
assert "this.presentation?.releaseTransient()" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Native restoration wiring, cache eviction and sync protection verified")
