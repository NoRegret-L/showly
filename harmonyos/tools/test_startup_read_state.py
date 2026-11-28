#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    w=Path(tmp)
    shutil.copyfile(root/"model/StartupReadState.ets",w/"StartupReadState.ts")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","StartupReadState.ts"],cwd=w,check=True)
    (w/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {cacheReadable,startupNotice}=require('./StartupReadState');
for(let i=0;i<100;i++){
  assert(cacheReadable('A','A',1+i));
  assert(!cacheReadable('A','B',1+i));
  assert(!cacheReadable('A','',1+i));
  assert(!cacheReadable('A','A',0));
  assert(!cacheReadable(' A',' A',1+i));
  assert(!cacheReadable('A','A',NaN));
  assert(startupNotice(true,true).includes('显示'));
  assert(startupNotice(true,false).includes('显示'));
  assert(startupNotice(false,false).includes('重试'));
}
console.log('100 identity/terminal-state cycles passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=w,check=True)
page=(root/"pages/Index.ets").read_text()
auth=(root/"data/TraktAuth.ets").read_text()
vault=(root/"data/TokenVault.ets").read_text()
assert "this.activeCloud() && this.cloudLocalAllowed" in page
assert "cacheReadable(this.cloudUuid,traktAuth.cachedAccount(this.clientId)" in page
assert "generation:-1" in page
assert "this.nextStatus='进度读取已结束，请刷新核对。'" in page
assert "this.projectionPending=false; this.loadNextShows(); return;" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "saveRefresh(clientId,record.refreshToken,uuid)" in auth
assert "saveRefresh(clientId, token, uuid)" in auth
assert "uuid?: string" in vault
print("Startup read-state wiring: secure identity, offline projection and online write gate checked")
