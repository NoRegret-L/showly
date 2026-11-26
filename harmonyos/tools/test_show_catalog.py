#!/usr/bin/env python3
"""Pure model checks; requires TypeScript and Node on PATH."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1] / "entry/src/main/ets/model"
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    for name in ("Media", "MediaState", "PersonalLibrary", "ShowCatalog"):
        shutil.copyfile(root / (name + ".ets"), work / (name + ".ts"))
    subprocess.run(["tsc", "--strict", "--target", "ES2020", "--module", "commonjs",
                    "Media.ts", "MediaState.ts", "PersonalLibrary.ts", "ShowCatalog.ts"], cwd=work, check=True)
    (work / "test.cjs").write_text("""
const assert = require('node:assert/strict');
const {airDate,aired,showSections,validateFullCatalog,scheduleEpisodes} = require('./ShowCatalog.js');
const {followShow,setMediaIntent,inLocalWatchlist,applyLegacyEdit} = require('./MediaState.js');
const {buildPersonalLibrary,filterPersonalLibrary} = require('./PersonalLibrary.js');
const media={id:'show:1',kind:'show',title:'Test',year:2025,watched:false};
const now=Date.parse('2026-01-01T00:00:00Z');
const old='2025-01-01T00:00:00Z', future='2027-01-01T00:00:00Z';
const episode=(id,number,firstAired)=>({id,season:1,number,title:'E'+number,firstAired});
const full={media,status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:old,episodes:[episode(1,1,old),episode(2,2,future),episode(3,3,'')]}]};
validateFullCatalog(full,media.id);
assert.equal(scheduleEpisodes(full).length,3);
assert.deepEqual(scheduleEpisodes(full).filter(e=>aired(e,now)).map(e=>e.id),[1]);
assert.equal(airDate('invalid'),'');
assert.deepEqual(showSections(full,[1],now),['watching']);
assert.deepEqual(showSections({...full,status:'ended'},[1,2,3],now),['finished']);
assert.deepEqual(showSections(full,[1,2,3],now),['upcoming']);
assert.deepEqual(showSections({...full,status:'ended',seasons:[]},[],now),[]);
assert.throws(()=>validateFullCatalog({...full,seasons:[...full.seasons,...full.seasons]},media.id));
const added=applyLegacyEdit([], [media], 'add');
assert.equal(added[0].followState,'no');
assert.equal(filterPersonalLibrary(buildPersonalLibrary(added,[],[],[],[{media,watchedEpisodes:1}]),'tracking').length,0);
const followed=followShow([],media);
assert.equal(followed[0].followState,'yes');
assert.equal(inLocalWatchlist(followed[0]),false);
assert.equal(filterPersonalLibrary(buildPersonalLibrary(followed,[],[media],[],[]),'tracking').length,1);
const queued=setMediaIntent(followed,media,'watchlist','yes');
assert.equal(queued[0].followState,'no');
assert.equal(filterPersonalLibrary(buildPersonalLibrary(queued,[],[],[{media,watchedEpisodes:5}],[]),'tracking').length,0);
assert.equal(inLocalWatchlist(queued[0]),true);
assert.equal(filterPersonalLibrary(buildPersonalLibrary(followed,[],[],[{media,watchedEpisodes:5}],[{media,watchedEpisodes:1,sections:['watching']}]),'watching').length,0);
console.log('Show catalog model assertions passed');
""", encoding="utf-8")
    subprocess.run(["node","test.cjs"], cwd=work, check=True)
