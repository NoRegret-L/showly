#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Media.ts","MediaPresentation.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const p=require('./MediaPresentation.js');
const media={id:'show:12',kind:'show',title:'Original',year:2020,watched:false};
const text=p.chineseText([{language:'zh',country:'tw',title:'繁體'},{language:'zh',country:'CN',title:'简体',overview:'简介'}]);
assert.deepEqual(text,{title:'简体',overview:'简介'});
assert.equal(p.chineseText([{language:'zh',country:'tw',title:'繁體'}]).title,'');
assert.equal(p.chineseEpisodeText([{language:'zh',title:'第一集'}]).title,'第一集');
const now=Date.now();
const row={id:'show:12',text,translatedAt:now,posterUrls:[],posterUri:''};
assert.equal(p.validTitle(row),true);
assert.equal(p.localizedTitle(media,[row],'zh'),'简体');
assert.equal(p.localizedTitle(media,[row],'original'),'Original');
assert.equal(p.localizedTitle({...media,id:'movie:12'},[row],'zh'),'Original');
assert.equal(media.title,'Original');
assert.equal(p.matchesText('简体',media.title,'简体'),true);
assert.equal(p.matchesText('original',media.title,'简体'),true);
const season={showId:media.id,season:1,fetchedAt:now,episodes:[{id:77,number:1,text:{title:'第一集',overview:''}}]};
assert.equal(p.validSeason(season),true);
assert.equal(p.localizedEpisode(media.id,1,77,'Episode 1',[season],'zh'),'第一集');
assert.equal(p.localizedEpisode('show:99',1,77,'Episode 1',[season],'zh'),'Episode 1');
assert.equal(p.localizedEpisode(media.id,2,77,'Episode 1',[season],'zh'),'Episode 1');
assert.equal(p.validSeason({...season,episodes:[...season.episodes,...season.episodes]}),false);
assert.equal(p.titleNeedsTranslation(row,now+p.TITLE_RETRY),false);
assert.equal(p.titleNeedsTranslation({...row,text:{title:'',overview:''}},now+p.TITLE_RETRY-1),false);
assert.equal(p.titleNeedsTranslation({...row,text:{title:'',overview:''}},now+p.TITLE_RETRY),true);
assert.equal(p.seasonNeedsTranslation(season,now+p.SEASON_RETRY),true);
assert.equal(p.imageFormat(Uint8Array.from([255,216,255])),'jpeg');
assert.equal(p.imageFormat(Uint8Array.from([137,80,78,71,13,10,26,10])),'png');
assert.equal(p.imageFormat(Uint8Array.from([82,73,70,70,0,0,0,0,87,69,66,80])),'webp');
assert.equal(p.imageFormat(Uint8Array.from([60,104,116,109,108])),'');
console.log('Presentation identity, locale and image fixtures passed');
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
source=(root/"pages"/"Index.ets").read_text()
for builder in ("nextProgressCard", "movieProgressView", "calendarView", "personalMovieCalendarView", "collectionGroupView", "discoverCard", "detailPage"):
    region=source.split("  "+builder+"(",1)[1].split("\n  @Builder",1)[0]
    assert "this.displayTitle(" in region or "this.displayLabel(" in region,builder
    assert "this.posterImage(" in region or "this.artwork(" in region,builder
assert "readChineseSeason" in (root/"data"/"PresentationRepository.ets").read_text()
print("Presentation wiring assertions passed")
