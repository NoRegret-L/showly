#!/usr/bin/env python3
"""Provider parity, native-source validation adapter and artwork lifecycle."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
detail=(root/"data/TraktDetails.ets").read_text()
repo=(root/"data/PresentationRepository.ets").read_text()
page=(root/"pages/Index.ets").read_text()
component=(root/"pages/ArtworkImage.ets").read_text()
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("ArtworkRules","Media","MediaPresentation","ViewportTasks","ReadFlight"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    # Compile the actual cache-validation function against a native API
    # adapter. It injects decoding failures; native decoder runs on device.
    actual=detail.split("async function validPosterFile(",1)[1].split("function canReadArtwork(",1)[0]
    guard=detail.split("function canReadArtwork(",1)[1].split("export async function cachedPoster(",1)[0]
    media_guard=detail.split("export function canReadDetails(",1)[1].split("export async function readDetails(",1)[0]
    (work/"CacheHarness.ts").write_text("""
import {ReadCancel} from './ReadFlight';
import {Media} from './Media';
interface Fixture {size:number; valid:boolean; width:number; height:number; }
export const files=new Map<string,Fixture>();
export const rejectedPosterUris=new Set<string>();
export const counts={open:0,close:0,release:0};
export let cancelAtInfo: ReadCancel|undefined;
export function setCancelAtInfo(scope: ReadCancel|undefined){cancelAtInfo=scope;}
const fileUri={getUriFromPath:(path:string)=>path};
const fileIo={
 OpenMode:{READ_ONLY:0},
 stat:async(path:string)=>{const value=files.get(path);if(!value)throw Error('missing');return {size:value.size}},
 open:async(path:string,_mode:number)=>{counts.open++;return {fd:path}},
 close:async(_file:{fd:string})=>{counts.close++}
};
const image={createImageSource:(fd:string)=>({
 getImageInfo:async()=>{const f=files.get(fd)!;cancelAtInfo?.cancel();if(!f.valid)throw Error('bad decoder');return {size:{width:f.width,height:f.height}}},
 release:async()=>{counts.release++}
})};
export async function validPosterFile("""+actual+"\nexport function canReadDetails("+media_guard+"\nexport function canReadArtwork("+guard,encoding="utf-8")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","ArtworkRules.ts","ViewportTasks.ts","ReadFlight.ts","CacheHarness.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const a=require('./ArtworkRules');
const {ViewportTasks,mergeViewportTasks}=require('./ViewportTasks');
const {ReadCancel,ConsumerReadFlight}=require('./ReadFlight');
const c=require('./CacheHarness');
const tick=()=>new Promise(r=>setImmediate(r));
const media=i=>({id:'show:'+i,title:'S'+i,year:2026,kind:'show',watched:false});
const img=(path,language,average,votes,type='poster',source='tmdb')=>({path,language,average,votes,type,source});
(async()=>{
 const zh=img('/zh.jpg','zh',1,2),en=img('/en.jpg','en',9,100),plain=img('/plain.jpg',null,10,500);
 assert.equal(a.bestArtwork([en,plain,zh],'zh','poster'),zh);
 assert.equal(a.bestArtwork([zh,en,plain],'zh','fanart'),plain);
 assert.equal(a.bestArtwork([img('/weak.jpg','zh',10,1),img('/strong.jpg','zh',9,100)],'zh','poster').path,'/strong.jpg');
 const aws=img('/aws.jpg','en',0,0,'poster','aws'),ep=img('/episode.jpg',null,0,0,'fanart');
 const custom=img('/custom.jpg','zh',0,0,'poster','custom');
 assert.equal(a.chooseArtwork('show','poster','zh',{posters:[en],backdrops:[plain],aws,custom}),custom);
 assert.equal(a.chooseArtwork('show','poster','zh',{posters:[],backdrops:[plain],aws}),plain);
 assert.equal(a.chooseArtwork('show','poster','zh',{posters:[],backdrops:[],aws}),aws);
 assert.equal(a.chooseArtwork('movie','poster','zh',{posters:[],backdrops:[plain],aws}),undefined);
 assert.equal(a.chooseArtwork('show','fanart','zh',{posters:[],backdrops:[],episode:ep}),ep);
 assert.deepEqual(a.episodeLookupNumbers(2,103),[2,103]);
 assert.deepEqual(a.episodeLookupNumbers(2,2),[2]);
 const url='https://media.trakt.tv/images/a/poster.jpg';
 const other='https://media.trakt.tv/images/b/poster.jpg';
 assert.equal(a.legacyPosterName(url),a.legacyPosterName(other));
 const keys=[a.artworkIdentity('trakt','poster','show:1',url),a.artworkIdentity('trakt','poster','show:1',other),a.artworkIdentity('tmdb','poster','show:1',url),a.artworkIdentity('trakt','fanart','show:1',url),a.artworkIdentity('trakt','poster','movie:1',url),a.artworkIdentity('trakt','poster','show:1',url+'?x=1')];
 assert.equal(new Set(keys).size,keys.length);
 assert.deepEqual(a.decodeSize(54,81),{width:54,height:81});
 assert.deepEqual(a.decodeSize(180,270),{width:180,height:270});
 assert.deepEqual(a.decodeSize(157.2,235.8),{width:158,height:236});
 assert.deepEqual(a.decodeSize(NaN,0),{width:0,height:0});
 const person={id:'person:1',title:'P',kind:'person',year:0,watched:false};
 assert(c.canReadArtwork(person,'fanart'));assert(!c.canReadArtwork(person,'poster'));assert(!c.canReadDetails(person));assert(!c.canReadArtwork({...person,id:'show:1'},'fanart'));assert(!c.canReadArtwork({...person,id:'person:0'},'fanart'));assert(c.canReadArtwork(media(1),'poster'));
 assert.notEqual(a.artworkIdentity('trakt','fanart','person:1',url),a.artworkIdentity('trakt','fanart','show:1',url));
 const repair=new a.ArtworkRecovery();
 assert(repair.reject('show:1','uri'));assert(!repair.reject('show:1','uri'));assert(!repair.allowed('show:1'));assert(repair.allowed('show:2'));repair.clear();assert(repair.allowed('show:1'));
 c.files.set('good',{size:128,valid:true,width:100,height:150});c.files.set('bad',{size:128,valid:false,width:0,height:0});c.files.set('empty',{size:0,valid:true,width:100,height:150});
 assert(await c.validPosterFile('good'));assert(!await c.validPosterFile('bad'));assert(!await c.validPosterFile('empty'));assert(!await c.validPosterFile('missing'));
 c.rejectedPosterUris.add('good');assert(!await c.validPosterFile('good'));c.rejectedPosterUris.delete('good');
 const stop=new ReadCancel();c.setCancelAtInfo(stop);await assert.rejects(c.validPosterFile('good',stop),/Read cancelled/);c.setCancelAtInfo(undefined);
 assert.equal(c.counts.open,c.counts.close);assert.equal(c.counts.open,c.counts.release);
 const flight=new ConsumerReadFlight();let starts=0,done;
 const work=scope=>{starts++;return new Promise((resolve,reject)=>{done=()=>resolve('disk');scope.subscribe(()=>reject(Error('cancelled')));})};
 const x=new ReadCancel(),y=new ReadCancel();
 const p=flight.run(keys[0],work,x).catch(e=>e.message),q=flight.run(keys[0],work,y);
 await tick();assert.equal(starts,1);x.cancel();assert.equal(await p,'Read cancelled');done();assert.equal(await q,'disk');
 const all=Array.from({length:10000},(_,i)=>media(i+1));
 const viewport=new ViewportTasks();
 for(let i=0;i<100;i++){
  for(let j=0;j<12;j++)viewport.update(all[j],0,[],true,'card');
  assert.equal(mergeViewportTasks(viewport,new Map()).length,12);
  viewport.clear();assert.equal(mergeViewportTasks(viewport,new Map()).length,0);
 }
 console.log('Artwork provider parity, source/size identity, 100 viewport cycles, shared cancellation, corrupt/offline cache adapter and balanced release passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
for operation in ("accessSync","statSync","openSync","closeSync","renameSync","unlinkSync"):
    assert "fileIo."+operation not in detail
assert "await fileIo.rename(temp, path)" in detail and "await validPosterFile(temp,scope)" in detail
assert "await source.getImageInfo()" in detail and "await source.release()" in detail
assert "cryptoFramework.createMd('SHA256')" in detail and "artworkIdentity('trakt','poster',item.id,url)" in detail
assert "await cachedPoster(this.dir,item,urls,scope)" in repo and "expectedPosterUri:uri" in repo
assert "this.repair.clear()" in repo and "this.repair.allowed(item.id)" in repo
assert ".sourceSize({width:this.targetWidth,height:this.targetHeight})" in component
assert ".syncLoad(false).autoResize(true)" in component and ".onAreaChange(" in component
assert "ArtworkImage({uri:this.artwork" in page and "Image(this.artwork(" not in page
assert "return this.mediaMode==='show' ? true :" in page
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in page
assert "await readSyncAccount(session)" in page and "await readActivity(session)" in page
print("Async artwork IO, validated legacy fallback, native measured decode, recovery and sync safety wiring passed")
