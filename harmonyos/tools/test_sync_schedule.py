#!/usr/bin/env python3
"""Actual wiring checks; Linux advisory lock semantics are not a device test."""
from pathlib import Path
import fcntl,re,subprocess,sys,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main"
ets=root/"ets"
ext=(ets/"workability/SyncWorkAbility.ets").read_text()
assert '"type": "workScheduler"' in (root/"module.json5").read_text()
assert "recordScheduleWake(this.context.filesDir)" in ext
assert "runBackgroundObservation(this.context.filesDir" in ext
assert all(x not in ext for x in ("TraktAuth","TokenVault","http.request","EpisodeStore","MediaStore"))
schedule=(ets/"data/SyncSchedule.ets").read_text()
assert "workScheduler.startWork(workInfo(hours))" in schedule
assert "workScheduler.stopWork(work, true)" in schedule
assert "isPersisted: true" in schedule
auth=(ets/"data/TraktAuth.ets").read_text()
# Check each production owner rather than assuming the number of call sites.
owners = {
    "rememberAccount": "lease",
    "setBackgroundRead": "lease",
    "begin": "revokeLease",
    "receive": "lease",
    "restore": "lease",
    "disconnect": "lease",
}
for method, lease in owners.items():
    start = re.search(r"(?m)^  (?:async )?" + method + r"\(", auth)
    assert start, method
    body = re.split(r"(?m)^  (?:private )?(?:async )?\w+\(", auth[start.end():], maxsplit=1)[0]
    acquire = re.search(r"const " + lease + r"\s*=\s*tryVaultLock\(\);", body)
    release = re.search(r"finally\s*\{[\s\S]*?releaseVaultLock\(" + lease + r"\)", body)
    assert acquire and release and acquire.start() < release.start(), method
    assert re.search(r"if\s*\(!" + lease + r"\)", body), method
assert len(re.findall(r"=\s*tryVaultLock\(\);", auth)) == len(owners)
assert len(re.findall(r"releaseVaultLock\((?:lease|revokeLease)\)", auth)) == len(owners)
vault=(ets/"data/TokenVault.ets").read_text()
assert "file.tryLock(true)" in vault and "file.unlock()" in vault
with tempfile.TemporaryDirectory() as tmp:
    path=Path(tmp)/"oauth.lock"
    with path.open("w") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        code="import fcntl,sys; f=open(sys.argv[1],'r+'); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
        competing="import fcntl,sys; f=open(sys.argv[1],'r+'); exec('for i in range(100):\\n try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\\n except BlockingIOError: continue\\n raise AssertionError(\"concurrent lock acquired\")')"
        assert subprocess.run([sys.executable,"-c",competing,str(path)],capture_output=True).returncode==0
    assert subprocess.run([sys.executable,"-c",code,str(path)],capture_output=True).returncode==0
    child=subprocess.Popen([sys.executable,"-u","-c",code+"; print('locked',flush=True); sys.stdin.read()",str(path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    assert child.stdout.readline().strip()=="locked"
    child.kill(); child.wait()
    assert subprocess.run([sys.executable,"-c",code,str(path)],capture_output=True).returncode==0
print("Native scheduler wiring, OAuth lock scope, 100 cross-process host lock attempts passed; device callback/locking not measured")
