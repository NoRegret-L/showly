#!/usr/bin/env python3
from pathlib import Path
import os,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","MediaPresentation","ShowCatalog","CalendarRules"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","CalendarRules.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict'),c=require('./CalendarRules.js');
const now=new Date(2026,4,31,12).getTime(), today=new Date(now);
const date=(y,m,d,h=10)=>new Date(y,m-1,d,h).toISOString();
const media=i=>({id:'show:'+i,kind:'show',title:'Show '+i,year:2026,watched:false});
const ep=(id,season,number,firstAired)=>({id,season,number,firstAired,title:'Episode '+id});
const source=(i,episodes,ids,queued=false)=>({media:media(i),full:{media:media(i),status:'returning series',fetchedAt:now,seasons:[{number:1,firstAired:date(2026,1,1),episodes}]},watchedIds:ids,queued});
const a=source(2,[ep(21,1,1,date(2026,5,31)),ep(22,1,2,date(2026,5,30)),ep(23,1,3,date(2026,2,28)),ep(24,1,4,date(2026,3,1)),ep(25,1,5,date(2026,6,1)),ep(26,0,1,date(2026,5,31))],[22]);
const b=source(10,[ep(101,1,1,date(2026,5,31)),ep(102,1,2,date(2026,5,30))],undefined);
const q={media:media(3),queued:true};
const inputs=[{source:a,release:''},{source:b,release:''},{source:q,release:date(2026,6,1)}];
const ix=new c.CalendarIndex();ix.begin('account-A');
const make=(plan,mode='future',extra={})=>c.calendarJob({plan,now,mode,premieres:false,query:'',hidden:[],members:['show:2','show:10','show:3'],titles:[],episodes:[],...extra});
let plan=ix.plan(inputs);assert.equal(plan.pending.length,3);
let out=make(plan);assert.deepEqual(out.entries.map(x=>x.key),['episode:101','episode:21','premiere:show:3','episode:25']);
assert.equal(out.entries[0].header,'今天');assert.equal(out.entries[2].header,'明天');
assert.equal(out.entries[2].episodeId,0);assert(out.entries[2].synthetic);assert.equal(out.entries[0].state,'unknown');
assert(c.calendarTitleHidden(out.entries[0],true));assert(!c.calendarTitleHidden(out.entries[0],false));
ix.commit(inputs,out.built);plan=ix.plan(inputs);assert.equal(plan.pending.length,0);assert.deepEqual(make(plan).entries,out.entries);
let recent=make(plan,'recent').entries;
assert.deepEqual(recent.map(x=>x.key),['episode:102','episode:22','episode:24']);
assert.equal(recent[1].state,'watched');assert(!c.calendarTitleHidden(recent[1],true));
assert.equal(c.calendarMonthBefore(today,3).getDate(),28);
assert.equal(make(plan,'future',{premieres:true}).entries.length,3);
assert.equal(make(plan,'future',{hidden:['show:10']}).entries.length,3);
assert.equal(make(plan,'future',{members:['show:10']}).entries.length,1);
assert.equal(make(plan,'future',{query:'中文',titles:[{key:'show:2',title:'中文'}]}).entries.length,2);
assert.equal(make(plan,'recent',{query:'分集',episodes:[{key:'show:2:1:22',title:'分集'}]}).entries[0].episodeId,22);
assert.equal(c.calendarPageRows(out.entries,2,1)[0].header,'今天');
assert.equal(ix.plan([{source:{...a,watchedIds:[21,22]},release:''},inputs[1],inputs[2]]).pending.length,1);
ix.begin('account-B');assert.equal(ix.plan(inputs).pending.length,3);
assert.equal(c.calendarAtoms({source:{...a,queued:true},release:date(2026,5,31)}).filter(x=>x.synthetic).length,0);
assert.equal(c.calendarAtoms({source:q,release:''}).length,0);
assert.deepEqual(make(new c.CalendarIndex().plan(inputs)).entries,out.entries);
const dst=new Date(2026,2,8,12).getTime();assert.equal(c.calendarDay(new Date(c.calendarExpiry(dst))), '2026-03-09');
assert.equal(c.calendarGroup(new Date(2027,0,20),new Date(2026,11,1),'future'),'下月');
assert.equal(c.calendarGroup(new Date(2028,0,20),new Date(2026,11,1),'future'),'以后');
console.log('Calendar: '+process.env.TZ+' date, sort, group, search, unknown/synthetic, one-show rebuild, account and cold reconstruction passed');
""",encoding="utf-8")
    for tz in ("UTC","Asia/Tokyo","America/New_York","Pacific/Auckland"):
        subprocess.run(["node","test.cjs"],cwd=work,check=True,env={**os.environ,"TZ":tz})
page=(root/"pages"/"Index.ets").read_text()
lib=(root/"data"/"LibraryProjection.ets").read_text()
task=(root/"data"/"CalendarTask.ets").read_text()
assert "readCalendar(" not in page and "calendarWindow(" not in page
assert "calendar.push({media:row.media,full:full,watchedIds:effective?.complete ? effective.ids : undefined,queued:row.queued})" in lib
assert "this.publishLocalCalendar(initial)" in page and page.count("this.publishLocalCalendar(result)")==2
assert "this.calendarSourceScope===this.calendarScopeKey()" in page
assert "this.sortJobs.current('calendar',token)" in page and "key===this.calendarKey()" in page
assert "executeDisplayTask(new taskpool.Task(calendarTask" in task
assert "row.synthetic ? 0 : row.season" in page
view=page.split("  calendarView() {",1)[1].split("  private movieSortKey(",1)[0]
assert "mark" not in view and "journal" not in view
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Calendar shared projection, no calendar API route, background scope gate and sync safety wiring passed")
