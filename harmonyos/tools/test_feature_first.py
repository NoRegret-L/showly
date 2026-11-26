#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaState","PersonalLibrary"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Media.ts","MediaState.ts","PersonalLibrary.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {buildPersonalLibrary,businessLibraryLabel,isPersonalMember}=require('./PersonalLibrary.js');
const media={id:'show:1',kind:'show',title:'Show',year:2025,watched:false};
const [row]=buildPersonalLibrary([],[],[],[{media,watchedEpisodes:5}],[{media,watchedEpisodes:-1,merged:true,sections:['watching'],effectiveWatched:4,effectiveTotal:8}]);
assert.equal(businessLibraryLabel(row),'正在追 · 已看 4 / 8 集');
assert.equal(isPersonalMember(row),true);
assert.equal(businessLibraryLabel({...row,effectiveWatched:undefined,effectiveTotal:undefined,sections:[]}), '追剧状态待核实');
assert.equal(isPersonalMember({...row,cloudEpisodes:-1,localEpisodes:0}),false);
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
source=(root/"pages"/"Index.ets").read_text()
def region(start,end):
    return source.split(start,1)[1].split(end,1)[0]
assert "seriesProgressView(item)" not in region("  detailPage(item: Media) {","  libraryRow(item: Media)")
assert "legacyProgressView()" not in region("  progressView() {","  legacyProgressView() {")
assert "headerAction('云端'" not in source
assert "businessLibraryLabel(row)" in region("  collectionView() {","  private async loadProgress")
assert "this.syncPreviewView()" in region("  syncSettingsView() {","  build() {")
assert "this.mediaPreviewView()" in region("  syncSettingsView() {","  build() {")
print("Feature-first presentation assertions passed")
