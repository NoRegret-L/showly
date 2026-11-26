#!/usr/bin/env python3
"""Host-side tests for the pure personal-library projection (requires tsc and node)."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / "entry/src/main/ets/model"
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    for name in ("Media", "MediaState", "PersonalLibrary"):
        shutil.copyfile(root / (name + ".ets"), work / (name + ".ts"))
    subprocess.run(["tsc", "--strict", "--target", "ES2020", "--module", "commonjs",
                    "Media.ts", "MediaState.ts", "PersonalLibrary.ts"], cwd=work, check=True)
    (work / "test.cjs").write_text("""
const assert = require('node:assert/strict');
const {buildPersonalLibrary: build, filterPersonalLibrary: filter, personalLibraryLabel: label} = require('./PersonalLibrary.js');
const media = (id, watched=false) => ({id, kind: id.split(':')[0], title: id, year: 2025, watched});
const record = (m, movieState='unknown', watchlistState='unknown') => ({media:m, movieState, watchlistState});
const evidence = (id, watchedEpisodes) => ({media:media(id), watchedEpisodes});
const ids = rows => rows.map(r=>r.media.id).sort();
const records = [record(media('movie:1'), 'no', 'yes'), record(media('movie:2',true),'yes','no'),
                 record(media('show:3'),'unknown','no'), record(media('show:7'))];
const before = JSON.stringify(records);
const rows = build(records, [media('movie:1',true),media('movie:4',true)],
  [media('movie:2'),media('show:3'),media('show:5'),media('movie:5')],
  [evidence('show:3',12), evidence('show:6',7)],
  [evidence('show:3',2),evidence('show:8',0),evidence('show:9',1)]);
assert.equal(JSON.stringify(records),before);
assert.equal(new Set(ids(rows)).size,rows.length);
assert.deepEqual(ids(filter(rows,'queue')),['movie:1','movie:5','show:5','show:7']);
assert.deepEqual(ids(filter(rows,'watched')),['movie:2','movie:4']);
assert.deepEqual(ids(filter(rows,'tracking')),['show:3','show:6','show:9']);
assert.equal(rows.find(r=>r.media.id==='show:3').localEpisodes,2);
assert.equal(rows.find(r=>r.media.id==='show:3').cloudEpisodes,12);
assert.equal(rows.find(r=>r.media.id==='show:6').localEpisodes,-1);
assert.equal(rows.find(r=>r.media.id==='show:6').localRecord,undefined);
assert.ok(label(rows.find(r=>r.media.id==='show:6')).includes('追剧状态待核实'));
assert.ok(!ids(rows).includes('show:8'));
const offline = build(records,[],[],[],[evidence('show:9',1)]);
assert.ok(!ids(offline).includes('show:6'));
assert.ok(ids(offline).includes('show:9'));
const restored = {...record(media('movie:10')),restoredWatchlist:false};
assert.equal(build([restored],[],[],[],[])[0].queued,false);
assert.equal(build([restored],[],[media('movie:10')],[],[])[0].queued,true);
assert.equal(build([],[],[],[],[]).length,0);
console.log('Personal library projection: all assertions passed');
""", encoding="utf-8")
    subprocess.run(["node", "test.cjs"], cwd=work, check=True)
