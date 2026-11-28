#!/usr/bin/env python3
"""Production SQL exact guard parity, isolated accounts, transaction failure."""
from pathlib import Path
import re, sqlite3, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
store=(root/"data/EpisodeStore.ets").read_text()
sql=re.search(r"queryRead\('(SELECT g\.episode_id,r\.history_id,r\.watched_at,r\.removal_state FROM sync_upload_guard[^']+)'",store).group(1)
with tempfile.TemporaryDirectory() as tmp:
    db=sqlite3.connect(str(Path(tmp)/"guard.db"))
    db.executescript("CREATE TABLE sync_upload_guard(account_uuid TEXT,episode_id INT,PRIMARY KEY(account_uuid,episode_id));CREATE TABLE sync_play_receipt(account_uuid TEXT,episode_id INT,history_id INT,watched_at TEXT,removal_state INT,PRIMARY KEY(account_uuid,episode_id));")
    db.executemany("INSERT INTO sync_upload_guard VALUES(?,?)",[(a,i) for a in ('a','b') for i in range(1,10001)])
    db.executemany("INSERT INTO sync_play_receipt VALUES(?,?,?,?,?)",[(a,i,i,'2026-01-01',i%3) for a in ('a','b') for i in range(1,10001) if i%5])
    db.commit()
    for account in ('a','b'):
        actual={i for i,h,at,state in db.execute(sql,(account,)) if h is None or state!=2}
        expected={i for i in range(1,10001) if i%5==0 or i%3!=2}
        assert actual==expected
    # Independent connection cannot take a competing write reservation.
    other=sqlite3.connect(str(Path(tmp)/"guard.db"),timeout=0)
    db.execute("BEGIN IMMEDIATE")
    try:
        other.execute("BEGIN IMMEDIATE")
        raise AssertionError("concurrent reservation")
    except sqlite3.OperationalError as error:
        assert "locked" in str(error)
    finally:
        db.rollback()
    other.execute("BEGIN IMMEDIATE");other.rollback();other.close();db.close()
assert "const guard = protectedIds.has(intent.episodeId)" in store
assert "async hasUploadAttempt(" in store
batch=(root/"data/TraktSyncBatch.ets").read_text()
assert "accepted && present === send.length && receipts === send.length && readErrors === 0" in batch
assert "'episode-upload-confirmed'" in batch
assert "await store.hasUploadAttempt(uuid, id)" in batch
print("10k account guard join parity, two SQLite connections exclusive transaction and confirmed upload log wiring passed")
