#!/usr/bin/env python3
"""Production read-model and in-flight request tests; no real account or network."""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
lib=(root/"data"/"TraktLibrary.ets").read_text()
page=(root/"pages"/"Index.ets").read_text()
repo=(root/"data"/"PresentationRepository.ets").read_text()
detail=(root/"data"/"TraktDetails.ets").read_text()
def section(text,start,end):
    return text[text.index(start):text.index(end,text.index(start)+len(start))]
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp)
    for name in ("Media","ShowCatalog","RemoteObservation","ReadFlight","MediaPresentation"):
        shutil.copyfile(root/"model"/(name+".ets"),work/(name+".ts"))
    harness="""import { Media, CollectionDate, PersonalMovie, validReleaseDate } from './Media';
import { RemoteLibraryObservation, RemoteMovieObservation, RemoteShowObservation, RemotePlayPosition, validateObservation, ObservationVersions, observationCollectionMask, mergeMovieSources, movieSourcesValid } from './RemoteObservation';
type ShowProgress=RemoteShowObservation;
type CloudLibrary=RemoteLibraryObservation;
interface TraktSession { clientId:string; generation:number; token:string; }
"""+section(lib,"interface Ids {","export type ShowProgress")+"""
let requests:string[]=[];
let activity='revision';
let movies='movie-revision',shows='show-revision';
let changed=false;
let stopped=false;
let active=0;
let maximum=0;
export function scenario(change:boolean=false,fail:boolean=false) { requests=[];activity='revision';changed=change;stopped=fail;active=0;maximum=0; }
let watchedShows:string|undefined,queuedShows:string|undefined,watchedMovies:string|undefined,queuedMovies:string|undefined;
export function setVersions(m:string,s:string,w?:string,q?:string,wm?:string,qm?:string){movies=m;shows=s;watchedShows=w;queuedShows=q;watchedMovies=wm;queuedMovies=qm;activity='changed-revision';}
async function readActivityVersions(session:TraktSession):Promise<ObservationVersions> { return {all:await readActivity(session),movies,shows,watchedShows,queuedShows,watchedMovies,queuedMovies}; }
export function stats(){return {requests,maximum,active};}
function ensureCurrent(session:TraktSession):void { if(session.generation!==1)throw Error('session'); }
async function readActivity(session:TraktSession):Promise<string> {
 ensureCurrent(session); requests.push('activity');
 return changed && requests.filter(x=>x==='activity').length>1?'new-revision':activity;
}
async function readAll(session:TraktSession,path:string,allowed?:()=>boolean):Promise<SyncItem[]> {
 ensureCurrent(session);if(allowed&&!allowed())throw Error('stopped');requests.push(path);active++;maximum=Math.max(maximum,active);
 try {
  await Promise.resolve();
  if(stopped&&path.includes('watched/shows'))throw Error('HTTP 429');
  if(allowed&&!allowed())throw Error('stopped');
  const movie={ids:{trakt:1},title:'One',year:2025,released:'2025-08-01',rating:8,runtime:91};
  if(path==='sync/watched/movies?extended=full')return [{movie,plays:2,last_watched_at:'2025-10-01'}];
  if(path==='sync/watchlist/movies?extended=full')return [{movie,listed_at:'2025-09-01'},{movie:{ids:{trakt:2},title:'Two',year:2026,released:'2026-02-29'},listed_at:'2025-10-01'}];
  if(path==='sync/watched/shows?extended=progress')return [{show:{ids:{trakt:1},title:'Series'},seasons:[{number:1,episodes:[{number:1,plays:1,last_watched_at:'2025-10-01'}]}]}];
  return [];
 } finally{active--;}
}
"""+section(lib,"function titleToMedia(","export interface CollectionRating")+section(lib,"async function readObservationCollections(","// Import only new titles")+section(lib,"function appendPersonalMovies(","export async function readPersonalMovies(")
    (work/"Harness.ts").write_text(harness,encoding="utf-8")
    subprocess.run(["tsc","--strict","--target","ES2020","--module","commonjs","Harness.ts","ReadFlight.ts","MediaPresentation.ts"],cwd=work,check=True)
    (work/"test.cjs").write_text("""
const assert=require('node:assert/strict');
const {ReadFlight}=require('./ReadFlight.js');
const h=require('./Harness.js');
const {validateObservation}=require('./RemoteObservation.js');
const {mergeText}=require('./MediaPresentation.js');
(async()=>{
 const group=new ReadFlight();
 let count=0;
 let release;
 const gate=new Promise(r=>{release=r});
 const run=()=>group.run('account-A:g1:movie:1',async()=>{count++;await gate;return 42});
 const list=Array.from({length:393},run);
 await Promise.resolve();
 assert.equal(count,1);assert.equal(group.started(),1);assert.equal(group.joined(),392);
 const other=group.run('account-B:g1:movie:1',async()=>{count++;return 99});
 release();
 assert.deepEqual(await Promise.all(list),Array(393).fill(42));
 assert.equal(await other,99);assert.equal(count,2);
 await run();assert.equal(count,3); // no completed response cache
 let attempts=0;
 const fail=()=>group.run('failure',async()=>{attempts++;throw Error('HTTP 429')});
 const failures=await Promise.allSettled([fail(),fail()]);assert.equal(attempts,1);
 assert(failures.every(x=>x.status==='rejected'));
 await assert.rejects(fail(),/429/);assert.equal(attempts,2);
 const session={clientId:'client',generation:1,token:'not-persisted'};
 h.scenario();
 const snap=await h.readCloudLibrary(session);
 assert.equal(h.stats().requests.length,6); // 2 activity fences, 4 independent domain reads
 assert.equal(h.stats().maximum,4);
 assert.equal(snap.movieDetails.length,2);
 assert.equal(snap.movieDetails[0].cloudWatched,true);
 assert.equal(snap.movieDetails[0].cloudWatchlist,true);
 assert.equal(snap.movieDetails[0].released,'2025-08-01');
 assert.equal(snap.movieDetails[0].rating,8);
 assert.equal(snap.movieDetails[1].released,'');
 assert.equal(snap.movieDetails[1].dateUncertain,true);
 validateObservation(JSON.parse(JSON.stringify(snap)));
 const bad=JSON.parse(JSON.stringify(snap));bad.movieDetails[0].cloudWatched=false;
 assert.throws(()=>validateObservation(bad),/Invalid movie details/);
 assert.throws(()=>validateObservation({...snap,movieDetails:[]}),/Incomplete movie details/);
 assert.throws(()=>validateObservation({...snap,movieDetails:[...snap.movieDetails,snap.movieDetails[0]]}),/Invalid movie details/);
 h.scenario();
 const baseline=await h.readCloudLibraryIncremental(session);
 h.scenario();h.setVersions('movie-revision','new-show');
 const delta=await h.readCloudLibraryIncremental(session,baseline);
 assert.equal(h.stats().requests.length,4);
 assert.equal(delta.movieDetails,baseline.movieDetails);
 assert.deepEqual(delta.watchlist,baseline.watchlist);
 assert.deepEqual(delta.queueDates,baseline.queueDates);
 assert.deepEqual(delta.shows,baseline.shows);
 console.log('Incremental observation fixture: 6 full requests -> 4 show-domain requests; retained movie details and collection equality passed');
 h.scenario();h.setVersions('new-movie','new-show');
 const moviesOnly=await h.readCloudLibraryIncremental(session,delta);
 assert.equal(h.stats().requests.length,6); // global revision identical but domain inconsistent -> full
 assert.deepEqual(moviesOnly.movieDetails,baseline.movieDetails);
 h.scenario();h.setVersions('m','s','w','q');
 const split=await h.readCloudLibraryIncremental(session);
 h.scenario();h.setVersions('m','s2','w2','q');
 const splitPrior={...split,activity:'prior',versions:{...split.versions,all:'prior'}};
 const showOnly=await h.readCloudLibraryIncremental(session,splitPrior);
 assert.equal(h.stats().requests.length,3);
 assert.deepEqual(showOnly.shows,split.shows);
 assert.deepEqual(showOnly.watchlist,split.watchlist);
 assert.deepEqual(showOnly.queueDates,split.queueDates);
 assert.deepEqual(showOnly.movieDetails,split.movieDetails);
 console.log('Split show endpoint fixture: 6 full requests -> 3; complete observation parity passed');
 h.scenario();h.setVersions('m','s','w','q','wm','qm');
 const movieBase=await h.readCloudLibraryIncremental(session);
 const moviePrior={...movieBase,activity:'prior',versions:{...movieBase.versions,all:'prior'}};
 h.scenario();h.setVersions('m2','s','w','q','wm','qm2');
 const queueOnly=await h.readCloudLibraryIncremental(session,moviePrior);
 assert.equal(h.stats().requests.length,3);
 assert.deepEqual(queueOnly.movieDetails,movieBase.movieDetails);
 assert.deepEqual(queueOnly.watchedMovies,movieBase.watchedMovies);
 assert.deepEqual(queueOnly.queueDates,movieBase.queueDates);
 h.scenario();h.setVersions('m2','s','w','q','wm2','qm');
 const watchedOnly=await h.readCloudLibraryIncremental(session,moviePrior);
 assert.equal(h.stats().requests.length,3);
 assert.deepEqual(watchedOnly.movieDetails,movieBase.movieDetails);
 assert.deepEqual(watchedOnly.watchlist,movieBase.watchlist);
 console.log('Split movie endpoints fixture: 6 full requests -> 3 each; normalized metadata provenance parity passed');
 const legacy={...snap};delete legacy.movieDetails;validateObservation(legacy);
 h.scenario(true);
 await assert.rejects(h.readCloudLibrary(session),/activity changed/);
 h.scenario(false,true);
 await assert.rejects(h.readCloudLibrary(session),/429/);
 assert.equal(h.stats().active,0);assert.equal(h.stats().requests.filter(x=>x==='activity').length,1);
 assert.deepEqual(mergeText({title:'old',overview:'overview'},{title:'new',overview:''}),{title:'new',overview:'overview'});
 console.log('Shared reads: 393 callers -> 1 in-flight request, scope separation and failure retry; 4 domains + 2 activity fences, movie metadata, invalidation and drain passed');
})().catch(e=>{console.error(e);process.exitCode=1});
""",encoding="utf-8")
    subprocess.run(["node","test.cjs"],cwd=work,check=True)
cloud=section(page,"  private async loadCloud(","  private async importCloud(")
calendar=section(page,"  private async loadCalendar(","  private async repairDeviceCalendar(")
assert "readCalendar(" not in calendar
assert "this.publishMovieSource(source)" in calendar and "const source=this.activeCloud()" in calendar
assert "this.requestProjection()" in calendar and "this.requestObservation()" in calendar
assert "movieDetails: cached.movieDetails" in cloud and "snapshot.movieDetails === undefined" in cloud
assert "this.publishMovieSource(restored)" in cloud and "this.publishMovieSource(snapshot)" in cloud
assert "await readSyncAccount(session)" in cloud and "await readActivity(session)" in cloud
assert "await store.saveReadCheckpoints(account.uuid, result.matches)" in cloud
assert "readPersonalMovies(session)" not in calendar and "await this.loadCalendar()" not in cloud
assert "this.movieCalendarData.activity === active.activity" in page
assert "this.movieRatingKey = ''" in page and "this.movieRatingRows = []" in page
assert "this.sharedTitleRatings('movie',scope)" in page
rating_repo=(root/"data/RatingsRepository.ets").read_text()
assert "await repo.list(scope,kind,session," in page
assert "readCollectionRatings(session,kind,activity)" in rating_repo
assert "old.known&&old.activity===activity" in rating_repo
assert "await this.verify(scope,session,current)" in rating_repo and "await readActivity(session)!==activity" in rating_repo
assert "SELECT show_id,season,payload FROM presentation_season" not in repo
assert "SELECT payload FROM presentation_season WHERE show_id=? AND season=?" in repo
assert "await repo.hydrateSeason(" in page
publish=section(page,"  private publishPresentation(","  private displayTitle(")
release=section(page,"  private releaseInactiveCaches(","  private scheduleLazyRows(")
assert "this.presentation.takeChanges()" in publish
assert "this.titleIndex.clear()" not in page
assert "this.episodeNameIndex.clear()" not in publish
assert "this.episodeNameIndex.clear()" in release and "this.presentation?.releaseTransient()" in release
assert page.count("this.episodeNameIndex.clear()")==1
assert "await Promise.all([" in section(page,"  private async loadPresentation(","  private ") 
patch=section(repo,"  private async saveTitlePatch(","  async hydrateSeason(")
assert "this.titleWrites.set(id,task)" in patch and "const old = await this.readTitle(id,version)" in patch
assert "const previous = this.titleWrites.get(id)" in patch and "version!==this.residency" in patch
assert patch.index("const old = await this.readTitle(id,version)") < patch.index("INSERT OR REPLACE INTO presentation_title")
assert "summaryFlights.run(" in detail and "posterFlights.run(" in detail
assert "if (epoch === summaryEpoch)" in detail
assert "ratingFlights.run(" in lib and "await readActivity(session)" in section(lib,"async function readRatingsVerified(","async function readObservationCollections(")
print("Shared movie source, lazy translation, independent presentation, incremental indexes, read-only request and sync guard wiring assertions passed")

# ArkTS requires imports before re-exports and other statements.
imports=lib.splitlines()
assert max(i for i,line in enumerate(imports) if line.startswith('import ')) < min(i for i,line in enumerate(imports) if line.startswith('export '))
