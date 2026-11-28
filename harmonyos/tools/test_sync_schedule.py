#!/usr/bin/env python3
"""Actual wiring checks; Linux advisory lock semantics are not a device test."""
from pathlib import Path
import fcntl,subprocess,sys,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main"
ets=root/"ets"
ext=(ets/"workability/SyncWorkAbility.ets").read_text()
assert '"type": "workScheduler"' in (root/"module.json5").read_text()
assert "recordScheduleWake(this.context.filesDir)" in ext
assert all(x not in ext for x in ("TraktAuth","TokenVault","http.request","EpisodeStore","MediaStore"))
schedule=(ets/"data/SyncSchedule.ets").read_text()
assert "workScheduler.startWork(workInfo(hours))" in schedule
assert "workScheduler.stopWork(work, true)" in schedule
assert "isPersisted: true" in schedule
auth=(ets/"data/TraktAuth.ets").read_text()
assert auth.count("const lease = tryVaultLock();")==3
assert auth.count("releaseVaultLock(lease)")==3
vault=(ets/"data/TokenVault.ets").read_text()
assert "file.tryLock(true)" in vault and "file.unlock()" in vault
with tempfile.TemporaryDirectory() as tmp:
    path=Path(tmp)/"oauth.lock"
    with path.open("w") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        code="import fcntl,sys; f=open(sys.argv[1],'r+'); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
        for _ in range(100):
            assert subprocess.run([sys.executable,"-c",code,str(path)],capture_output=True).returncode!=0
    assert subprocess.run([sys.executable,"-c",code,str(path)],capture_output=True).returncode==0
print("Native scheduler wiring, OAuth lock scope, 100 cross-process host lock attempts passed; device callback/locking not measured")
